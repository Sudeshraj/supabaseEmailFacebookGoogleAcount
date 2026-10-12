import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:payhere_mobilesdk_flutter/payhere_mobilesdk_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PayHere Mobile (Android / iOS) service.
///
/// The price is NEVER sent from the app. `generate-payhere-hash` checks that
/// the user owns the salon, reads the plan price from the database, creates a
/// pending payment and returns order_id + amount + hash + merchant_id
/// (signed with the PayHere *App* merchant secret for platform = 'mobile').
/// The subscription is activated by the `payhere-webhook` function.
class PayHereService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Returns the PayHere order id on success, or null on cancel / failure.
  /// Never throws.
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
  }) async {
    try {
      final env = EnvironmentManager();

      // 1. Signed quote from the server
      final Map<String, dynamic> quote;
      try {
        final response = await _supabase.functions.invoke(
          'generate-payhere-hash',
          body: {
            'salon_id': salonId,
            'plan_name': planName,
            'platform': 'mobile',
          },
        );
        quote = Map<String, dynamic>.from(response.data as Map);
      } on FunctionException catch (e) {
        debugPrint(
          '❌ generate-payhere-hash failed: status=${e.status}, details=${e.details}',
        );
        return null;
      }

      // 2. Payment object
      final nameParts = customerName.trim().split(' ');
      final paymentObject = <String, dynamic>{
        'sandbox': env.payhereSandbox,
        'merchant_id': quote['merchant_id'].toString(),
        'notify_url': '${env.supabaseUrl}/functions/v1/payhere-webhook',
        'order_id': quote['order_id'].toString(),
        'items': '$planName Subscription',
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
        'custom_1': salonId.toString(),
        'custom_2': planName,
      };

      // 3. Start payment. The SDK is callback-based, so wait with a Completer.
      final completer = Completer<String?>();

      PayHere.startPayment(
        paymentObject,
        (paymentId) {
          debugPrint('✅ PayHere completed: $paymentId');
          if (!completer.isCompleted) completer.complete(paymentId.toString());
        },
        (error) {
          debugPrint('❌ PayHere error: $error');
          if (!completer.isCompleted) completer.complete(null);
        },
        () {
          debugPrint('⏹️ PayHere dismissed');
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          debugPrint('⏱️ PayHere timed out waiting for callback');
          return null;
        },
      );
    } catch (e) {
      debugPrint('PayHere error: $e');
      return null;
    }
  }
}
