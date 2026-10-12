class SubscriptionPlan {
  final int id;
  final String name;           // 'bronze', 'silver', 'gold', 'platinum'
  final String displayName;    // 'Bronze', 'Silver', 'Gold', 'Platinum'
  final double price;
  final String currencyCode;
  final int maxSalons;         // -1 = unlimited
  final int planRank;          // 1, 2, 3, 4
  
  // Features
  final bool canViewAppointmentHistory;
  final bool canManageOffers;
  final bool canViewReports;
  final bool canViewAnalytics;
  final bool canViewRevenue;
  final bool canViewCustomersScreen;
  final bool canExportData;
  
  final String? description;
  final String? badgeColor;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.displayName,
    required this.price,
    required this.currencyCode,
    required this.maxSalons,
    required this.planRank,
    required this.canViewAppointmentHistory,
    required this.canManageOffers,
    required this.canViewReports,
    required this.canViewAnalytics,
    required this.canViewRevenue,
    required this.canViewCustomersScreen,
    required this.canExportData,
    this.description,
    this.badgeColor,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as int,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      price: (json['price'] as num).toDouble(),
      currencyCode: json['currency_code'] as String,
      maxSalons: json['max_salons'] as int,
      planRank: json['plan_rank'] as int,
      canViewAppointmentHistory: json['can_view_appointment_history'] as bool? ?? false,
      canManageOffers: json['can_manage_offers'] as bool? ?? false,
      canViewReports: json['can_view_reports'] as bool? ?? false,
      canViewAnalytics: json['can_view_analytics'] as bool? ?? false,
      canViewRevenue: json['can_view_revenue'] as bool? ?? false,
      canViewCustomersScreen: json['can_view_customers_screen'] as bool? ?? false,
      canExportData: json['can_export_data'] as bool? ?? false,
      description: json['description'] as String?,
      badgeColor: json['badge_color'] as String?,
    );
  }
}