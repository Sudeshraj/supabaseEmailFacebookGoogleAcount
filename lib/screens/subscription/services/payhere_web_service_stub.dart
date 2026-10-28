/// Stand-in for PayHereWebService on NON-web platforms (Android, iOS,
/// Windows...). The real one (payhere_web_service.dart) uses dart:js_interop
/// and package:web, which do not compile outside the browser.
///
/// payment_service.dart picks the right file with a conditional import.
/// Keep this API identical to the web version.
class PayHereWebService {
  static const bool preferPopup = true;
  static const String redirectSentinel = 'REDIRECT';

  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required String returnUrl,
    required String cancelUrl,
    required void Function(String error) onError,
  }) async {
    onError('Web payments are only available in the web app');
    return null;
  }

  Future<String?> startCustomerProPayment({
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
    required String returnUrl,
    required String cancelUrl,
    required void Function(String error) onError,
  }) async {
    onError('Web payments are only available in the web app');
    return null;
  }
}