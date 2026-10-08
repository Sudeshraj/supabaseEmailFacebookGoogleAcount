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

  // Convenience getters for UI
  String get currentPlanName => 
      _currentCapabilities?['plan']?['name'] ?? 'bronze';
  String get currentPlanDisplay => 
      _currentCapabilities?['plan']?['display_name'] ?? 'Bronze';
  int get currentPlanRank => 
      _currentCapabilities?['plan']?['rank'] ?? 1;
  int get maxSalons => 
      _currentCapabilities?['limits']?['max_salons'] ?? 1;
  int get currentSalons => 
      _currentCapabilities?['limits']?['current_salons'] ?? 0;
  bool get canCreateMoreSalons => 
      _currentCapabilities?['limits']?['can_create_more_salons'] ?? false;

  // Feature checks
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
    _currentSalonId = salonId;
    _loading = true;
    notifyListeners();

    try {
      _currentCapabilities = await _service.getSalonCapabilities(salonId);
    } catch (e) {
      _error = e.toString();
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

  /// Request plan change
  Future<Map<String, dynamic>> requestPlanChange({
    required String newPlanName,
    required String ownerId,
  }) async {
    if (_currentSalonId == null) {
      return {'success': false, 'message': 'No salon selected'};
    }

    final result = await _service.requestPlanChange(
      salonId: _currentSalonId!,
      newPlanName: newPlanName,
      ownerId: ownerId,
    );

    if (result['success'] == true) {
      await refresh();
    }

    return result;
  }

  /// Cancel subscription
  Future<Map<String, dynamic>> cancelSubscription({
    required String ownerId,
    String? reason,
  }) async {
    if (_currentSalonId == null) {
      return {'success': false, 'message': 'No salon selected'};
    }

    return await _service.cancelSubscription(
      salonId: _currentSalonId!,
      ownerId: ownerId,
      reason: reason,
    );
  }
}