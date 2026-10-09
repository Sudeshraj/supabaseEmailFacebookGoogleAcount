import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'payhere_service.dart';
import 'payhere_web_service.dart';

/// ============================================================
/// Unified Payment Service — platform-aware wrapper
/// ------------------------------------------------------------
///   • Web    → PayHereWebService (iframe popup, redirect fallback)
///   • Mobile → PayHereService    (native PayHere SDK)
///
/// Mobile: returns the payment id on success, null on cancel/failure.
/// Web:    returns the order id when the iframe popup payment completes,
///         [redirectSentinel] if it had to fall back to a same-tab
///         redirect (result then comes back via returnUrl / cancelUrl),
///         or null on cancel / failure.
///
/// Subscription activation always happens on the server via the
/// PayHere webhook (Edge Function).
/// ============================================================
class PaymentService {
  final PayHereService _mobile = PayHereService();
  final PayHereWebService _web = PayHereWebService();

  bool get isSupported => true;

  /// Returned on web when the tab is being redirected to PayHere's hosted
  /// checkout (popup unavailable). The caller should just stop; the result
  /// is handled when PayHere sends the user back to returnUrl.
  static const String redirectSentinel = PayHereWebService.redirectSentinel;

  /// Whether we're currently running on web.
  bool get isWeb => kIsWeb;

  /// Whether we're currently running on mobile (Android/iOS).
  bool get isMobile => !kIsWeb;

  /// [returnUrl] / [cancelUrl] are used on web only.
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required double amount,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    String? returnUrl,
    String? cancelUrl,
  }) async {
    debugPrint(
      '💳 PaymentService.startSubscriptionPayment — '
      'platform=${kIsWeb ? "web" : "mobile"}, '
      'plan=$planName, amount=$amount, salonId=$salonId',
    );

    try {
      if (kIsWeb) {
        return await _web.startSubscriptionPayment(
          salonId: salonId,
          planName: planName,
          amount: amount,
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
          amount: amount,
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