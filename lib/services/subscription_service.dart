import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subscription_plan.dart';

class SubscriptionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all available plans
  Future<List<SubscriptionPlan>> getAllPlans() async {
    try {
      final response = await _supabase
          .from('subscription_plans')
          .select()
          .eq('is_active', true)
          .order('plan_rank', ascending: true);

      return (response as List)
          .map((e) => SubscriptionPlan.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error loading plans: $e');
      return [];
    }
  }

  /// Get salon capabilities (cached per salon)
  Future<Map<String, dynamic>?> getSalonCapabilities(int salonId) async {
    try {
      final response = await _supabase.rpc(
        'get_salon_capabilities',
        params: {'p_salon_id': salonId},
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error loading capabilities: $e');
      return null;
    }
  }

  /// Get salon plan
  Future<Map<String, dynamic>?> getSalonPlan(int salonId) async {
    try {
      final response = await _supabase.rpc(
        'get_salon_plan',
        params: {'p_salon_id': salonId},
      );
      final list = response as List;
      return list.isNotEmpty ? list.first as Map<String, dynamic> : null;
    } catch (e) {
      debugPrint('Error loading plan: $e');
      return null;
    }
  }

  /// Get owner salon usage
  Future<Map<String, dynamic>?> getOwnerSalonUsage(String ownerId) async {
    try {
      final response = await _supabase.rpc(
        'get_owner_salon_usage',
        params: {'p_owner_id': ownerId},
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error loading usage: $e');
      return null;
    }
  }

  /// Request plan change (returns action_required if payment/action needed)
  Future<Map<String, dynamic>> requestPlanChange({
    required int salonId,
    required String newPlanName,
    required String ownerId,
  }) async {
    try {
      final response = await _supabase.rpc(
        'request_plan_change',
        params: {
          'p_salon_id': salonId,
          'p_new_plan_name': newPlanName,
          'p_owner_id': ownerId,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Activate subscription after payment success
  Future<Map<String, dynamic>> activateSubscription({
    required int salonId,
    required String planName,
    required String ownerId,
    String? paymentReference,
    double? paymentAmount,
    String? paymentMethod,
  }) async {
    try {
      final response = await _supabase.rpc(
        'activate_salon_subscription',
        params: {
          'p_salon_id': salonId,
          'p_plan_name': planName,
          'p_owner_id': ownerId,
          'p_payment_reference': paymentReference,
          'p_payment_amount': paymentAmount,
          'p_payment_method': paymentMethod,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Cancel subscription
  Future<Map<String, dynamic>> cancelSubscription({
    required int salonId,
    required String ownerId,
    String? reason,
  }) async {
    try {
      final response = await _supabase.rpc(
        'cancel_salon_subscription',
        params: {
          'p_salon_id': salonId,
          'p_owner_id': ownerId,
          'p_reason': reason,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Get payment history
  Future<List<Map<String, dynamic>>> getPaymentHistory(String ownerId) async {
    try {
      final response = await _supabase
          .from('subscription_payments')
          .select('*, subscription_plans(name, display_name)')
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading payments: $e');
      return [];
    }
  }

  /// Get subscription history
  Future<List<Map<String, dynamic>>> getSubscriptionHistory(int salonId) async {
    try {
      final response = await _supabase
          .from('subscription_history')
          .select()
          .eq('salon_id', salonId)
          .order('changed_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading history: $e');
      return [];
    }
  }
}
