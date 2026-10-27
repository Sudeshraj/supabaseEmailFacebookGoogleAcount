import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What `get_my_customer_pro` returns for the logged-in account.
/// This is the CUSTOMER role's membership only: it has nothing to do with the
/// owner subscription (Bronze / Silver / Gold / Platinum) of the same account.
class CustomerProStatus {
  final bool isPro;

  /// 'payhere' | 'google_play' | null
  final String? source;
  final DateTime? expiresAt;
  final bool autoRenew;
  final bool cancelAtPeriodEnd;

  // plan (price comes from the database)
  final String displayName;
  final double price;
  final String currencyCode;
  final String billingPeriod;
  final String? playProductId;

  const CustomerProStatus({
    required this.isPro,
    required this.source,
    required this.expiresAt,
    required this.autoRenew,
    required this.cancelAtPeriodEnd,
    required this.displayName,
    required this.price,
    required this.currencyCode,
    required this.billingPeriod,
    required this.playProductId,
  });

  bool get isGooglePlay => source == 'google_play';
  bool get isPayHere => source == 'payhere';

  int? get daysRemaining {
    if (!isPro || expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  factory CustomerProStatus.fromJson(Map<String, dynamic> json) {
    final plan = Map<String, dynamic>.from((json['plan'] ?? {}) as Map);
    final expires = json['expires_at'];
    return CustomerProStatus(
      isPro: json['is_pro'] == true,
      source: json['source'] as String?,
      expiresAt: expires is String ? DateTime.tryParse(expires)?.toLocal() : null,
      autoRenew: json['auto_renew'] == true,
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
      displayName: (plan['display_name'] as String?) ?? 'Pro',
      price: (plan['price'] as num?)?.toDouble() ?? 0,
      currencyCode: (plan['currency_code'] as String?) ?? 'LKR',
      billingPeriod: (plan['billing_period'] as String?) ?? 'yearly',
      playProductId: plan['play_product_id'] as String?,
    );
  }
}

class CustomerProService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// null when it could not be loaded
  Future<CustomerProStatus?> getMyStatus() async {
    try {
      final result = await _supabase.rpc('get_my_customer_pro');
      final data = Map<String, dynamic>.from(result as Map);
      if (data['success'] != true) return null;
      return CustomerProStatus.fromJson(data);
    } catch (e) {
      debugPrint('❌ get_my_customer_pro failed: $e');
      return null;
    }
  }
}