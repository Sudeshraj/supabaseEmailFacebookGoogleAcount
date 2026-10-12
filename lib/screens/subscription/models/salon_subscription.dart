class SalonSubscription {
  final int? id;
  final int salonId;
  final int planId;
  final String planName;
  final String status;         // active, cancelled, expired
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;
  final double? lastPaymentAmount;
  final DateTime? lastPaymentAt;

  SalonSubscription({
    this.id,
    required this.salonId,
    required this.planId,
    required this.planName,
    required this.status,
    this.startedAt,
    this.expiresAt,
    this.autoRenew = false,
    this.lastPaymentAmount,
    this.lastPaymentAt,
  });

  bool get isActive => status == 'active';
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  
  int? get daysRemaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory SalonSubscription.fromJson(Map<String, dynamic> json) {
    return SalonSubscription(
      id: json['id'] as int?,
      salonId: json['salon_id'] as int,
      planId: json['plan_id'] as int,
      planName: json['plan_name'] as String? ?? 'bronze',
      status: json['status'] as String? ?? 'active',
      startedAt: json['started_at'] != null 
        ? DateTime.parse(json['started_at']) : null,
      expiresAt: json['expires_at'] != null 
        ? DateTime.parse(json['expires_at']) : null,
      autoRenew: json['auto_renew'] as bool? ?? false,
      lastPaymentAmount: json['last_payment_amount'] != null
        ? (json['last_payment_amount'] as num).toDouble() : null,
      lastPaymentAt: json['last_payment_at'] != null
        ? DateTime.parse(json['last_payment_at']) : null,
    );
  }
}