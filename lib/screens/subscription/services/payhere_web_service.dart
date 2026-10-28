import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// PayHere Web service — Flutter Web only.
///
/// The price is NEVER sent from the app. The app only says what it wants to
/// buy (an owner plan for a salon, or customer Pro); the
/// `generate-payhere-hash` Edge Function checks the caller, reads the price
/// from the database, creates a pending payment and returns
/// order_id + amount + hash + merchant_id.
///
/// Two ways to take the payment:
///  1. POPUP (preferred): PayHere JS SDK opens an iframe over the app.
///  2. REDIRECT (fallback): hosted checkout, same tab. Used automatically
///     when the popup cannot start. The user comes back to [returnUrl].
///
/// The subscription itself is activated by the `payhere-webhook` function.
class PayHereWebService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Try the iframe popup first. Set to false to always use the redirect.
  static const bool preferPopup = true;

  /// Returned when the tab is being redirected to PayHere (hosted checkout).
  static const String redirectSentinel = 'REDIRECT';

  static const String _sdkUrl = 'https://www.payhere.lk/lib/payhere.js';

  /// OWNER plan payment (Silver / Gold / Platinum for one salon).
  /// Returns: order id (popup done) | [redirectSentinel] | null (cancelled/failed)
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required String returnUrl,
    required String cancelUrl,
    required void Function(String error) onError,
  }) {
    return _startPayment(
      quoteBody: {'salon_id': salonId, 'plan_name': planName, 'platform': 'web'},
      itemLabel: '$planName Subscription',
      custom1: salonId.toString(),
      custom2: planName,
      customerEmail: customerEmail,
      customerName: customerName,
      customerPhone: customerPhone,
      returnUrl: returnUrl,
      cancelUrl: cancelUrl,
      onError: onError,
    );
  }

  /// CUSTOMER Pro membership. [planName] = 'pro_monthly' | 'pro_yearly'.
  /// The price comes from the server.
  Future<String?> startCustomerProPayment({
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required String returnUrl,
    required String cancelUrl,
    required void Function(String error) onError,
  }) {
    return _startPayment(
      quoteBody: {
        'kind': 'customer_pro',
        'plan_name': planName,
        'platform': 'web',
      },
      itemLabel: planName == 'pro_monthly'
          ? 'Pro Membership (1 month)'
          : 'Pro Membership (1 year)',
      custom1: 'customer_pro',
      custom2: planName,
      customerEmail: customerEmail,
      customerName: customerName,
      customerPhone: customerPhone,
      returnUrl: returnUrl,
      cancelUrl: cancelUrl,
      onError: onError,
    );
  }

  Future<String?> _startPayment({
    required Map<String, dynamic> quoteBody,
    required String itemLabel,
    required String custom1,
    required String custom2,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required String returnUrl,
    required String cancelUrl,
    required void Function(String error) onError,
  }) async {
    final env = EnvironmentManager();

    // 1. Ask the server for a signed quote
    final Map<String, dynamic> quote;
    try {
      final response = await _supabase.functions.invoke(
        'generate-payhere-hash',
        body: quoteBody,
      );
      quote = Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      debugPrint(
        '❌ generate-payhere-hash failed: status=${e.status}, details=${e.details}',
      );
      onError('Could not start the payment (${e.status})');
      return null;
    } catch (e) {
      debugPrint('❌ generate-payhere-hash error: $e');
      onError('Could not start the payment');
      return null;
    }

    final orderId = quote['order_id'] as String;

    // 2. Payment fields (same for popup and redirect)
    final nameParts = customerName.trim().split(' ');
    final fields = <String, String>{
      'merchant_id': quote['merchant_id'].toString(),
      'return_url': returnUrl,
      'cancel_url': cancelUrl,
      'notify_url': '${env.supabaseUrl}/functions/v1/payhere-webhook',
      'order_id': orderId,
      'items': itemLabel,
      'amount': quote['amount'].toString(),
      'currency': quote['currency'].toString(),
      'hash': quote['hash'].toString(),
      'first_name': nameParts.first,
      'last_name': nameParts.length > 1 ? nameParts.last : '',
      'email': customerEmail,
      'phone': customerPhone,
      'address': 'Colombo',
      'city': 'Colombo',
      'country': 'Sri Lanka',
      'custom_1': custom1,
      'custom_2': custom2,
    };

    // 3. Popup first, redirect as fallback
    if (preferPopup) {
      final popup = await _tryPopup(fields, env.payhereSandbox, orderId);
      switch (popup.outcome) {
        case _PopupOutcome.completed:
          return popup.orderId ?? orderId;
        case _PopupOutcome.dismissed:
          return null;
        case _PopupOutcome.failed:
          debugPrint('⚠️ PayHere popup unavailable, using redirect fallback');
          break;
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