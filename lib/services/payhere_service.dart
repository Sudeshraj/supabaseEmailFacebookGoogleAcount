import 'package:flutter/material.dart';
import 'package:payhere_mobilesdk_flutter/payhere_mobilesdk_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PayHereService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ⚠️ CHANGE THESE for production
  static const String merchantId = 'YOUR_MERCHANT_ID';
  static const bool isSandbox = true; // false for production

  /// Start payment flow
  /// Returns: payment success (true), fail (false), cancel (null)
  Future<String?> startSubscriptionPayment({
    required int salonId,
    required String planName,
    required double amount,
    required String customerEmail,
    required String customerName,
    required String customerPhone,
  }) async {
    try {
      // 1. Generate order ID
      final orderId = 'SUB-$salonId-${DateTime.now().millisecondsSinceEpoch}';

      // 2. Get hash from Supabase Edge Function
      final hashResponse = await _supabase.functions.invoke(
        'generate-payhere-hash',
        body: {
          'order_id': orderId,
          'amount': amount,
          'currency': 'LKR',
        },
      );

      if (hashResponse.status != 200) {
        throw Exception('Failed to generate hash');
      }

      final hash = hashResponse.data['hash'] as String;

      // 3. Build payment object
      final paymentObject = {
        "sandbox": isSandbox,
        "merchant_id": merchantId,
        "notify_url": "https://your-project.supabase.co/functions/v1/payhere-webhook",
        "order_id": orderId,
        "items": "$planName Subscription",
        "amount": amount.toStringAsFixed(2),
        "currency": "LKR",
        "hash": hash,
        "first_name": customerName.split(' ').first,
        "last_name": customerName.split(' ').length > 1 
            ? customerName.split(' ').last : '',
        "email": customerEmail,
        "phone": customerPhone,
        "address": "Colombo",
        "city": "Colombo",
        "country": "Sri Lanka",
        "custom_1": salonId.toString(),
        "custom_2": planName,
      };

      // 4. Start payment
      String? result;
      PayHere.startPayment(
        paymentObject,
        (paymentId) {
          // Success
          result = paymentId;
        },
        (error) {
          // Failed
          result = null;
          debugPrint('Payment failed: $error');
        },
        () {
          // Dismissed
          result = null;
        },
      );

      return result;
    } catch (e) {
      debugPrint('PayHere error: $e');
      return null;
    }
  }
}