import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'payhere_service.dart';
// The web implementation needs dart:js_interop / package:web, which only
// compile for the browser. Every other platform gets the stub instead.
import 'payhere_web_service_stub.dart'
    if (dart.library.js_interop) 'payhere_web_service.dart';

/// ============================================================
/// Unified Payment Service — platform-aware wrapper
/// ------------------------------------------------------------
///   • Web    → PayHereWebService (iframe popup, redirect fallback)
///   • Mobile → PayHereService    (native PayHere SDK)
///
/// The app never sends a price. The server decides it from the plan.
///
/// Mobile: returns the order id on success, null on cancel / failure.
/// Web:    returns the order id when the iframe popup payment completes,
///         [redirectSentinel] if it had to fall back to a same-tab redirect
///         (the result then comes back via returnUrl / cancelUrl),
///         or null on cancel / failure.
///
/// Subscription activation always happens on the server via the PayHere
/// webhook, so callers must poll / refresh afterwards.
/// ============================================================
class PaymentService {
  final PayHereService _mobile = PayHereService();
  final PayHereWebService _web = PayHereWebService();

  /// Returned on web when the tab is being redirected to PayHere's hosted
  /// checkout. The caller should just stop; see PaymentReturnScreen.
  static const String redirectSentinel = PayHereWebService.redirectSentinel;

  bool get isSupported => true;
  bool get isWeb => kIsWeb;
  bool get isMobile => !kIsWeb;

  /// [returnUrl] / [cancelUrl] are used on web only.
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    String? returnUrl,
    String? cancelUrl,
  }) async {
    debugPrint(
      '💳 PaymentService.startSubscriptionPayment — '
      'platform=${kIsWeb ? "web" : "mobile"}, plan=$planName, salonId=$salonId',
    );

    try {
      if (kIsWeb) {
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
      } else {
        return await _mobile.startSubscriptionPayment(
          salonId: salonId,
          planName: planName,
          customerEmail: customerEmail,
          customerName: customerName,
          customerPhone: customerPhone,
        );
      }
    } catch (e, stack) {
      debugPrint('❌ PaymentService error: $e\n$stack');
      return null;
    }
  }
}
