import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// PayHere Web service — Flutter Web only.
///
/// Two ways to take a payment on web:
///
///  1. POPUP (preferred, user-friendly): PayHere JS SDK opens the payment
///     form in an iframe overlay on top of the app. The user never leaves
///     the app. Result arrives via callbacks.
///
///  2. REDIRECT (fallback): hosted checkout, a normal form POST in the same
///     tab. Used automatically when the popup cannot start (SDK blocked,
///     or PayHere rejects the SDK request, e.g. some localhost setups).
///     The user returns to [returnUrl] / [cancelUrl] afterwards.
///
/// In both cases the subscription is activated by the `payhere-webhook`
/// Edge Function (server-to-server).
///
/// The PayHere JS SDK is loaded on demand, so web/index.html does not
/// need a <script> tag for it.
class PayHereWebService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Try the iframe popup first. Set to false to always use the redirect.
  static const bool preferPopup = true;

  /// Returned when the tab is being redirected to PayHere (hosted
  /// checkout). The caller should stop and wait for the return URL.
  static const String redirectSentinel = 'REDIRECT';

  static const String _sdkUrl = 'https://www.payhere.lk/lib/payhere.js';

  /// Returns:
  ///  • order id        → popup payment completed
  ///  • [redirectSentinel] → redirecting to PayHere (page is unloading)
  ///  • null            → cancelled / failed
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required double amount,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required String returnUrl,
    required String cancelUrl,
    required void Function(String error) onError,
  }) async {
    final env = EnvironmentManager();

    // 1. Order ID
    final orderId = 'SUB-$salonId-${DateTime.now().millisecondsSinceEpoch}';

    // 2. Fetch hash (web uses the PayHere *Domain* merchant secret)
    final String hash;
    try {
      final hashResponse = await _supabase.functions.invoke(
        'generate-payhere-hash',
        body: {
          'order_id': orderId,
          'amount': amount,
          'currency': 'LKR',
          'platform': 'web',
        },
      );
      hash = hashResponse.data['hash'] as String;
    } on FunctionException catch (e) {
      debugPrint(
        '❌ generate-payhere-hash failed: status=${e.status}, details=${e.details}',
      );
      onError('Failed to generate payment hash (${e.status})');
      return null;
    } catch (e) {
      debugPrint('❌ generate-payhere-hash error: $e');
      onError('Failed to generate payment hash');
      return null;
    }

    // 3. Payment fields (same for popup and redirect)
    final nameParts = customerName.trim().split(' ');
    final fields = <String, String>{
      'merchant_id': env.payhereMerchantId,
      'return_url': returnUrl,
      'cancel_url': cancelUrl,
      'notify_url': '${env.supabaseUrl}/functions/v1/payhere-webhook',
      'order_id': orderId,
      'items': '$planName Subscription',
      'amount': amount.toStringAsFixed(2),
      'currency': 'LKR',
      'hash': hash,
      'first_name': nameParts.first,
      'last_name': nameParts.length > 1 ? nameParts.last : '',
      'email': customerEmail,
      'phone': customerPhone,
      'address': 'Colombo',
      'city': 'Colombo',
      'country': 'Sri Lanka',
      'custom_1': salonId.toString(),
      'custom_2': planName,
    };

    // 4. Popup first, redirect as fallback
    if (preferPopup) {
      final popup = await _tryPopup(fields, env.payhereSandbox, orderId);
      switch (popup.outcome) {
        case _PopupOutcome.completed:
          return popup.orderId ?? orderId;
        case _PopupOutcome.dismissed:
          return null; // user closed the popup
        case _PopupOutcome.failed:
          debugPrint('⚠️ PayHere popup unavailable, using redirect fallback');
          break; // fall through to redirect
      }
    }

    return _redirectToCheckout(fields, env.payhereSandbox, orderId, onError);
  }

  // ------------------------------------------------------------
  // POPUP (JS SDK, iframe overlay)
  // ------------------------------------------------------------

  Future<_PopupResult> _tryPopup(
    Map<String, String> fields,
    bool sandbox,
    String orderId,
  ) async {
    if (!await _ensureSdk()) {
      return const _PopupResult(_PopupOutcome.failed);
    }
    final payhere = _getWindowPayHere();
    if (payhere == null) return const _PopupResult(_PopupOutcome.failed);

    final completer = Completer<_PopupResult>();

    payhere.setProperty(
      'onCompleted'.toJS,
      ((JSAny? completedOrderId) {
        final id = (completedOrderId as JSString?)?.toDart;
        debugPrint('✅ PayHere popup completed: $id');
        if (!completer.isCompleted) {
          completer.complete(_PopupResult(_PopupOutcome.completed, id));
        }
      }).toJS,
    );

    payhere.setProperty(
      'onDismissed'.toJS,
      (() {
        debugPrint('⏹️ PayHere popup dismissed');
        if (!completer.isCompleted) {
          completer.complete(const _PopupResult(_PopupOutcome.dismissed));
        }
      }).toJS,
    );

    payhere.setProperty(
      'onError'.toJS,
      ((JSAny? error) {
        debugPrint('❌ PayHere popup error: $error');
        if (!completer.isCompleted) {
          completer.complete(const _PopupResult(_PopupOutcome.failed));
        }
      }).toJS,
    );

    try {
      debugPrint('🚀 Starting PayHere popup for order $orderId');
      final paymentObject = <String, dynamic>{'sandbox': sandbox, ...fields};
      final startPaymentFn = payhere.getProperty<JSFunction?>(
        'startPayment'.toJS,
      );
      if (startPaymentFn == null) {
        return const _PopupResult(_PopupOutcome.failed);
      }
      startPaymentFn.callAsFunction(payhere, paymentObject.jsify());

      return await completer.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => const _PopupResult(_PopupOutcome.dismissed),
      );
    } catch (e) {
      debugPrint('❌ PayHere popup start failed: $e');
      return const _PopupResult(_PopupOutcome.failed);
    }
  }

  /// Loads payhere.js on demand if it isn't on the page already.
  Future<bool> _ensureSdk() async {
    if (_getWindowPayHere() != null) return true;

    final loaded = Completer<bool>();
    final script = web.HTMLScriptElement()
      ..src = _sdkUrl
      ..onload = ((web.Event _) {
        if (!loaded.isCompleted) loaded.complete(true);
      }).toJS
      ..onerror = ((web.Event _) {
        if (!loaded.isCompleted) loaded.complete(false);
      }).toJS;
    web.document.head!.append(script);

    return loaded.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    );
  }

  JSObject? _getWindowPayHere() {
    try {
      final window = web.window as JSObject;
      final payhere = window.getProperty<JSAny?>('payhere'.toJS);
      if (payhere == null || payhere.isUndefinedOrNull) return null;
      return payhere as JSObject;
    } catch (e) {
      debugPrint('❌ Error reading window.payhere: $e');
      return null;
    }
  }

  // ------------------------------------------------------------
  // REDIRECT (hosted checkout, same tab)
  // ------------------------------------------------------------

  String? _redirectToCheckout(
    Map<String, String> fields,
    bool sandbox,
    String orderId,
    void Function(String error) onError,
  ) {
    try {
      debugPrint('🚀 Redirecting to PayHere checkout, order $orderId');
      final form = web.HTMLFormElement()
        ..method = 'post'
        ..action = sandbox
            ? 'https://sandbox.payhere.lk/pay/checkout'
            : 'https://www.payhere.lk/pay/checkout'
        ..target = '_self';

      fields.forEach((key, value) {
        final input = web.HTMLInputElement()
          ..type = 'hidden'
          ..name = key
          ..value = value;
        form.append(input);
      });

      web.document.body!.append(form);
      form.submit();
      return redirectSentinel;
    } catch (e) {
      debugPrint('❌ PayHere redirect failed: $e');
      onError(e.toString());
      return null;
    }
  }
}

enum _PopupOutcome { completed, dismissed, failed }

class _PopupResult {
  final _PopupOutcome outcome;
  final String? orderId;
  const _PopupResult(this.outcome, [this.orderId]);
}