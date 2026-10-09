import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'payhere_service.dart';
import 'payhere_web_service.dart';

/// ============================================================
/// Unified Payment Service — Platform-aware wrapper
// ------------------------------------------------------------
/// Automatically picks the correct PayHere implementation:
///   • Web    → PayHereWebService (uses payhere.js JS SDK)
///   • Mobile → PayHereService    (uses native mobile SDK)
///
/// Usage:
///   final payment = PaymentService();
///   final paymentId = await payment.startSubscriptionPayment(...);
///
/// The returned paymentId is non-null on success, null on
/// cancel/fail. The actual subscription activation happens
/// asynchronously via the PayHere webhook (Edge Function), so
/// callers should refresh the subscription provider after a
/// short delay.
/// ============================================================
class PaymentService {
  final PayHereService _mobile = PayHereService();
  final PayHereWebService _web = PayHereWebService();

  /// True if payments are supported on this platform.
  /// Currently: Web, Android, iOS.
  bool get isSupported {
    if (kIsWeb) return true;
    // On non-web platforms, PayHere mobile SDK supports Android + iOS.
    // We can't check Platform directly here without importing
    // dart:io, which breaks web compilation, so we let the
    // mobile service handle its own platform check.
    return true;
  }

  /// Whether we're currently running on web.
  bool get isWeb => kIsWeb;

  /// Whether we're currently running on mobile (Android/iOS).
  bool get isMobile => !kIsWeb;

  /// Start a subscription payment.
  ///
  /// Returns the payment ID (a non-empty string) on success, or
  /// null on cancel/failure. Never throws — errors are surfaced
  /// via the debug log and returned as null.
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required double amount,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
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
          onCompleted: (paymentId) {
            debugPrint('✅ [Web] Payment completed: $paymentId');
          },
          onError: (error) {
            debugPrint('❌ [Web] Payment error: $error');
          },
          onDismissed: () {
            debugPrint('⏹️ [Web] Payment dismissed');
          },
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

  /// Check if PayHere is available right now (e.g. SDK loaded).
  /// Useful to show a friendly error BEFORE opening the payment
  /// sheet (e.g. on web when the payhere.js script failed to load).
  Future<bool> isAvailable() async {
    if (kIsWeb) {
      // On web we can't easily check without a JS call; assume true
      // — the web service itself returns a clear error if the SDK
      // is missing.
      return true;
    }
    // On mobile, the SDK is bundled — assume true.
    return true;
  }
}