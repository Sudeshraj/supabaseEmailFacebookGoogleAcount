import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

// The web implementation needs dart:js_interop / package:web, which only
// compile for the browser. Every other platform gets the stub instead.
import 'payhere_web_service_stub.dart'
    if (dart.library.js_interop) 'payhere_web_service.dart';

/// ============================================================
/// PayHere payments — WEB ONLY
/// ------------------------------------------------------------
/// On Android the subscription is bought with Google Play Billing
/// (PlayBillingService). Google Play requires that for digital features, so
/// the app must never open a PayHere payment on Android.
///
/// Web: returns the order id when the iframe popup payment completes,
/// [redirectSentinel] if it had to fall back to a same-tab redirect
/// (the result then comes back via returnUrl / cancelUrl), or null on
/// cancel / failure. The plan is activated by the payhere-webhook function.
/// ============================================================
class PaymentService {
  final PayHereWebService _web = PayHereWebService();

  /// Returned when the tab is being redirected to PayHere's hosted checkout.
  static const String redirectSentinel = PayHereWebService.redirectSentinel;

  bool get isWeb => kIsWeb;

  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    String? returnUrl,
    String? cancelUrl,
  }) async {
    if (!kIsWeb) {
      debugPrint('PayHere is web-only. Use Google Play Billing on Android.');
      return null;
    }

    try {
      return await _web.startSubscriptionPayment(
        salonId: salonId,
        planName: planName,
        customerEmail: customerEmail,
        customerName: customerName,
        customerPhone: customerPhone,
        returnUrl: returnUrl ?? Uri.base.origin,
        cancelUrl: cancelUrl ?? Uri.base.origin,
        onError: (error) => debugPrint('❌ [Web] Payment error: $error'),
      );
    } catch (e, stack) {
      debugPrint('❌ PaymentService error: $e\n$stack');
      return null;
    }
  }
}