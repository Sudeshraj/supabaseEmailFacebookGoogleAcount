import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// PayHere Web Checkout Service — Flutter Web only.
///
/// Requires this script in web/index.html (head):
///   <script src="https://www.payhere.lk/lib/payhere.js"></script>
///   (same script for sandbox & live; mode is set via the 'sandbox' flag)
///
/// Uses dart:js_interop + dart:js_interop_unsafe (Flutter 3.10+)
class PayHereWebService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ⚠️ CHANGE THESE for production
  static const bool isSandbox = true;

  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required double amount,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required void Function(String orderId) onCompleted,
    required void Function(String error) onError,
    required void Function() onDismissed,
  }) async {
    // 1. Check the PayHere JS SDK first (before any network call)
    final payhere = _getWindowPayHere();
    if (payhere == null) {
      debugPrint(
        '❌ PayHere JS SDK not loaded. Add <script src="https://www.payhere.lk/lib/payhere.js"> to index.html',
      );
      onError('PayHere SDK not loaded. Please refresh.');
      return null;
    }

    // 2. Order ID
    final orderId = 'SUB-$salonId-${DateTime.now().millisecondsSinceEpoch}';

    // 3. Fetch hash from Edge Function
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
      // invoke() throws on non-2xx responses
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

    // 4. Payment object
    final env = EnvironmentManager();
    final nameParts = customerName.trim().split(' ');
    final paymentObject = <String, dynamic>{
      'sandbox': env.payhereSandbox,
      'merchant_id': env.payhereMerchantId,
      'return_url': Uri.base.origin,
      'cancel_url': Uri.base.origin,
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

    final completer = Completer<String?>();

    // 5. Register callbacks
    payhere.setProperty(
      'onCompleted'.toJS,
      ((JSString completedOrderId) {
        debugPrint('✅ PayHere completed: ${completedOrderId.toDart}');
        if (!completer.isCompleted) completer.complete(completedOrderId.toDart);
        onCompleted(completedOrderId.toDart);
      }).toJS,
    );

    payhere.setProperty(
      'onDismissed'.toJS,
      (() {
        debugPrint('⏹️ PayHere dismissed');
        if (!completer.isCompleted) completer.complete(null);
        onDismissed();
      }).toJS,
    );

    payhere.setProperty(
      'onError'.toJS,
      ((JSString error) {
        debugPrint('❌ PayHere error: ${error.toDart}');
        if (!completer.isCompleted) completer.complete(null);
        onError(error.toDart);
      }).toJS,
    );
    // 6. Start payment
    try {
      debugPrint('🚀 Starting PayHere for order $orderId');
      final jsPaymentObject = paymentObject.jsify() as JSObject;
      final startPaymentFn = payhere.getProperty<JSFunction?>(
        'startPayment'.toJS,
      );
      if (startPaymentFn == null) {
        throw Exception('payhere.startPayment not found');
      }
      startPaymentFn.callAsFunction(payhere, jsPaymentObject);

      // Timeout so the UI spinner never hangs forever if no callback fires
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          debugPrint('⏱️ PayHere timed out waiting for callback');
          return null;
        },
      );
    } catch (e) {
      debugPrint('❌ startPayment failed: $e');
      if (!completer.isCompleted) completer.complete(null);
      onError(e.toString());
      return null;
    }
  }

  /// Fetch `window.payhere` object.
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
}
