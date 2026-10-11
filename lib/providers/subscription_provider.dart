import 'package:flutter/foundation.dart';
import '../models/subscription_plan.dart';
import '../services/subscription_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final SubscriptionService _service = SubscriptionService();

  List<SubscriptionPlan> _plans = [];
  Map<String, dynamic>? _currentCapabilities;
  int? _currentSalonId;
  bool _loading = false;
  String? _error;

  List<SubscriptionPlan> get plans => _plans;
  Map<String, dynamic>? get capabilities => _currentCapabilities;
  bool get loading => _loading;
  String? get error => _error;
  int? get currentSalonId => _currentSalonId;

  /// true once capabilities for the current salon have really been loaded.
  /// Until then the UI must NOT treat the user as "Bronze".
  bool get isReady => _currentCapabilities != null;

  // ---------- plan info ----------
  String get currentPlanName =>
      _currentCapabilities?['plan']?['name'] ?? 'bronze';
  String get currentPlanDisplay =>
      _currentCapabilities?['plan']?['display_name'] ?? 'Bronze';
  int get currentPlanRank => _currentCapabilities?['plan']?['rank'] ?? 1;
  int get maxSalons => _currentCapabilities?['limits']?['max_salons'] ?? 1;
  int get currentSalons =>
      _currentCapabilities?['limits']?['current_salons'] ?? 0;
  bool get canCreateMoreSalons =>
      _currentCapabilities?['limits']?['can_create_more_salons'] ?? false;

  bool get isPaidPlan => currentPlanName != 'bronze';

  DateTime? get expiresAt {
    final raw = _currentCapabilities?['plan']?['expires_at'];
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  bool get autoRenew => _currentCapabilities?['plan']?['auto_renew'] == true;

  /// Cancelled, but still active until [expiresAt]
  bool get cancelAtPeriodEnd =>
      _currentCapabilities?['plan']?['cancel_at_period_end'] == true;

  int? get daysRemaining {
    if (!isPaidPlan || expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  /// A paid plan can be renewed during its last 7 days
  bool get canRenew => isPaidPlan && (daysRemaining ?? 999) <= 7;

  // ---------- feature checks ----------
  bool get canViewHistory =>
      _currentCapabilities?['capabilities']?['appointment_history'] ?? false;
  bool get canManageOffers =>
      _currentCapabilities?['capabilities']?['manage_offers'] ?? false;
  bool get canViewReports =>
      _currentCapabilities?['capabilities']?['reports'] ?? false;
  bool get canViewAnalytics =>
      _currentCapabilities?['capabilities']?['analytics'] ?? false;
  bool get canViewRevenue =>
      _currentCapabilities?['capabilities']?['revenue'] ?? false;
  bool get canViewCustomers =>
      _currentCapabilities?['capabilities']?['customers_screen'] ?? false;
  bool get canExportData =>
      _currentCapabilities?['capabilities']?['export_data'] ?? false;

  /// Load plans list
  Future<void> loadPlans() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _plans = await _service.getAllPlans();
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  /// Load capabilities for a salon
  Future<void> loadCapabilities(int salonId) async {
    // switching salon: never show the previous salon's plan
    if (_currentSalonId != salonId) _currentCapabilities = null;
    _currentSalonId = salonId;
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await _service.getSalonCapabilities(salonId);

    if (result == null) {
      _error = 'Could not load subscription details';
    } else if (result['success'] == false) {
      _error = result['message']?.toString() ?? 'Could not load subscription';
    } else {
      _currentCapabilities = result;
    }

    _loading = false;
    notifyListeners();
  }

  /// Refresh current capabilities
  Future<void> refresh() async {
    if (_currentSalonId != null) {
      await loadCapabilities(_currentSalonId!);
    }
  }

  /// Forget everything (call on logout)
  void clear() {
    _plans = [];
    _currentCapabilities = null;
    _currentSalonId = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  /// Request plan change. Pass [salonId] explicitly from screens that know it.
  Future<Map<String, dynamic>> requestPlanChange({
    required String newPlanName,
    required String ownerId,
    int? salonId,
  }) async {
    final targetSalon = salonId ?? _currentSalonId;
    if (targetSalon == null) {
      return {'success': false, 'message': 'No salon selected'};
    }

    final result = await _service.requestPlanChange(
      salonId: targetSalon,
      newPlanName: newPlanName,
      ownerId: ownerId,
    );

    if (result['success'] == true) {
      await loadCapabilities(targetSalon);
    }

    return result;
  }

  /// Cancel subscription (access continues until the period end)
  Future<Map<String, dynamic>> cancelSubscription({
    required String ownerId,
    String? reason,
  }) async {
    if (_currentSalonId == null) {
      return {'success': false, 'message': 'No salon selected'};
    }

    final result = await _service.cancelSubscription(
      salonId: _currentSalonId!,
      ownerId: ownerId,
      reason: reason,
    );

    if (result['success'] == true) {
      await refresh();
    }

    return result;
  }
}
