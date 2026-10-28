import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One way to buy Pro (monthly / yearly). The list comes from the database
/// (customer_plans), so a new plan = a new row there + a Google Play product.
class CustomerProPlanOption {
  /// 'pro_monthly' | 'pro_yearly'
  final String name;
  final String displayName;
  final double price;
  final String currencyCode;

  /// 'monthly' | 'yearly'
  final String billingPeriod;
  final String? playProductId;

  /// "Save N%" badge. Set in the database (customer_plans.discount_percent);
  /// null / 0 = no badge.
  final int? discountPercent;

  const CustomerProPlanOption({
    required this.name,
    required this.displayName,
    required this.price,
    required this.currencyCode,
    required this.billingPeriod,
    required this.playProductId,
    this.discountPercent,
  });

  bool get isMonthly => billingPeriod == 'monthly';
  String get periodWord => isMonthly ? 'month' : 'year';
  String get periodAdjective => isMonthly ? 'monthly' : 'yearly';

  /// "Rs. 500" (database price; on Android the Google Play price is shown)
  String get priceText {
    final symbol = currencyCode == 'LKR' ? 'Rs.' : currencyCode;
    return '$symbol ${price.toStringAsFixed(0)}';
  }

  factory CustomerProPlanOption.fromJson(Map<String, dynamic> json) {
    return CustomerProPlanOption(
      name: (json['name'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? 'Pro',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      currencyCode: (json['currency_code'] as String?) ?? 'LKR',
      billingPeriod: (json['billing_period'] as String?) ?? 'yearly',
      playProductId: json['play_product_id'] as String?,
      discountPercent: (json['discount_percent'] as num?)?.toInt(),
    );
  }
}

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

  /// the plan the customer has right now ('pro_monthly' / 'pro_yearly')
  final String? currentPlanName;
  final String? currentBillingPeriod;

  /// every plan that can be bought
  final List<CustomerProPlanOption> plans;

  /// Google Play could not charge the card: 'grace' (access still on) |
  /// 'on_hold' (access off) | null
  final String? paymentIssue;

  const CustomerProStatus({
    required this.isPro,
    required this.source,
    required this.expiresAt,
    required this.autoRenew,
    required this.cancelAtPeriodEnd,
    required this.currentPlanName,
    required this.currentBillingPeriod,
    required this.plans,
    this.paymentIssue,
  });

  bool get isGooglePlay => source == 'google_play';
  bool get isPayHere => source == 'payhere';

  int? get daysRemaining {
    if (!isPro || expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  CustomerProPlanOption? planByName(String? name) {
    for (final p in plans) {
      if (p.name == name) return p;
    }
    return null;
  }

  CustomerProPlanOption? get currentPlan => planByName(currentPlanName);

  /// The other billing period (to "switch to")
  List<CustomerProPlanOption> get otherPlans =>
      plans.where((p) => p.name != currentPlanName).toList();

  Set<String> get playProductIds =>
      plans.map((p) => p.playProductId).whereType<String>().toSet();

  /// The "Save N%" badge of a plan: the number stored in the database
  /// (customer_plans.discount_percent). null = no badge.
  int? savingPercent(CustomerProPlanOption plan) {
    final percent = plan.discountPercent;
    return (percent != null && percent > 0) ? percent : null;
  }

  factory CustomerProStatus.fromJson(Map<String, dynamic> json) {
    final expires = json['expires_at'];
    final current = json['current_plan'];
    final plansRaw = (json['plans'] as List?) ?? const [];

    return CustomerProStatus(
      isPro: json['is_pro'] == true,
      source: json['source'] as String?,
      expiresAt: expires is String ? DateTime.tryParse(expires)?.toLocal() : null,
      autoRenew: json['auto_renew'] == true,
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
      currentPlanName: current is Map ? current['name'] as String? : null,
      currentBillingPeriod:
          current is Map ? current['billing_period'] as String? : null,
      plans: plansRaw
          .map((e) => CustomerProPlanOption.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      paymentIssue: json['payment_issue'] as String?,
    );
  }
}

/// One line of the Pro payment history
class CustomerProPayment {
  /// 'payhere' | 'google_play'
  final String source;
  final String planName; // display name, e.g. "Pro Yearly"
  final String reference;
  final double? amount; // null for Google Play (Google keeps the receipts)
  final String? currencyCode;
  final DateTime? paidAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// 'completed' | 'refunded' | 'active' | 'expired'
  final String status;

  const CustomerProPayment({
    required this.source,
    required this.planName,
    required this.reference,
    required this.amount,
    required this.currencyCode,
    required this.paidAt,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
  });

  bool get isGooglePlay => source == 'google_play';

  static DateTime? _date(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory CustomerProPayment.fromJson(Map<String, dynamic> json) {
    return CustomerProPayment(
      source: (json['source'] as String?) ?? 'payhere',
      planName: (json['plan_name'] as String?) ?? 'Pro membership',
      reference: (json['reference'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      currencyCode: json['currency_code'] as String?,
      paidAt: _date(json['paid_at']),
      periodStart: _date(json['period_start']),
      periodEnd: _date(json['period_end']),
      status: (json['status'] as String?) ?? 'completed',
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

  /// Pro payment history of the logged-in customer (newest first)
  Future<List<CustomerProPayment>> getMyPayments() async {
    final result = await _supabase.rpc('get_my_customer_pro_payments');
    final data = Map<String, dynamic>.from(result as Map);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Could not load payment history');
    }
    final list = (data['payments'] as List?) ?? const [];
    return list
        .map((e) => CustomerProPayment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}