import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ============================================
// NAVIGATION HELPER FUNCTIONS
// Use these functions instead of direct context.push
// ============================================

/// Navigate to Service Management Screen
Future<dynamic> goToServiceManagement(
  BuildContext context, {
  required int salonId,
  required String salonName,
}) async {
  final encodedSalonName = Uri.encodeComponent(salonName);
  return context.push('/owner/services?salonId=$salonId&salonName=$encodedSalonName');
}

/// Navigate to Add Service Screen
Future<dynamic> goToAddService(
  BuildContext context, {
  required int salonId,
  int? salonBarberId,
  String? barberName,
  bool isEditing = false,
  int? serviceId,
}) async {
  String path = '/owner/services/add?salonId=$salonId';
  if (salonBarberId != null) {
    path += '&salonBarberId=$salonBarberId';
  }
  if (barberName != null && barberName.isNotEmpty) {
    path += '&barberName=${Uri.encodeComponent(barberName)}';
  }
  if (isEditing) {
    path += '&isEditing=true';
  }
  if (serviceId != null && isEditing) {
    path += '&serviceId=$serviceId';
  }
  return context.push(path);
}

/// Navigate to Edit Service Screen
Future<dynamic> goToEditService(
  BuildContext context, {
  required int serviceId,
  required int salonId,
}) async {
  return context.push('/owner/services/edit?serviceId=$serviceId&salonId=$salonId');
}

/// Navigate to Edit Salon Screen
Future<dynamic> goToEditSalon(
  BuildContext context, {
  required int salonId,
}) async {
  return context.push('/owner/salon/edit?salonId=$salonId');
}

/// Navigate to Create Salon Screen
Future<dynamic> goToCreateSalon(BuildContext context) async {
  return context.push('/owner/salon/create');
}

/// Navigate to Add Barber Screen
Future<dynamic> goToAddBarber(
  BuildContext context, {
  bool refresh = false,
}) async {
  return context.push('/owner/add-barber?refresh=$refresh');
}

/// Navigate to Barber List Screen
Future<dynamic> goToBarberList(
  BuildContext context, {
  String? salonId,
}) async {
  if (salonId != null && salonId.isNotEmpty) {
    return context.push('/owner/barbers?salonId=$salonId');
  }
  return context.push('/owner/barbers');
}

/// Navigate to Barber Schedule Screen
Future<dynamic> goToBarberSchedule(
  BuildContext context, {
  String? salonId,
}) async {
  if (salonId != null && salonId.isNotEmpty) {
    return context.push('/owner/barber-schedule?salonId=$salonId');
  }
  return context.push('/owner/barber-schedule');
}

/// Navigate to Barber Leaves Screen
Future<dynamic> goToBarberLeaves(
  BuildContext context, {
  String? salonId,
}) async {
  if (salonId != null && salonId.isNotEmpty) {
    return context.push('/owner/barber-leaves?salonId=$salonId');
  }
  return context.push('/owner/barber-leaves');
}

/// Navigate to VIP Requests Screen
Future<dynamic> goToVIPRequests(
  BuildContext context, {
  required String salonId,
}) async {
  return context.push('/owner/vip-requests?salonId=$salonId');
}

/// Navigate to Salon Holidays Screen
Future<dynamic> goToSalonHolidays(
  BuildContext context, {
  required int salonId,
  required String salonName,
}) async {
  final encodedSalonName = Uri.encodeComponent(salonName);
  return context.push('/owner/salon/holidays?salonId=$salonId&salonName=$encodedSalonName');
}

/// Navigate to Add Category Screen
Future<dynamic> goToAddCategory(BuildContext context) async {
  return context.push('/owner/categories/add');
}

/// Navigate to Add Gender Screen
Future<dynamic> goToAddGender(BuildContext context) async {
  return context.push('/owner/genders/add');
}

/// Navigate to Add Age Category Screen
Future<dynamic> goToAddAgeCategory(BuildContext context) async {
  return context.push('/owner/age-categories/add');
}

// ============================================
// LIST VIEW NAVIGATION METHODS
// ============================================

/// Navigate to Category List Screen
Future<dynamic> goToCategoryList(BuildContext context) async {
  return context.push('/owner/categories');
}

/// Navigate to Gender List Screen
Future<dynamic> goToGenderList(BuildContext context) async {
  return context.push('/owner/genders');
}

/// Navigate to Age Category List Screen
Future<dynamic> goToAgeCategoryList(BuildContext context) async {
  return context.push('/owner/age-categories');
}

// ============================================
// APPOINTMENT & CUSTOMER NAVIGATION
// ============================================

/// Navigate to Appointments Screen
Future<dynamic> goToAppointments(
  BuildContext context, {
  String? salonId,
}) async {
  if (salonId != null && salonId.isNotEmpty) {
    return context.push('/owner/appointments?salonId=$salonId');
  }
  return context.push('/owner/appointments');
}

/// Navigate to Customers Screen
Future<dynamic> goToCustomers(
  BuildContext context, {
  String? salonId,
}) async {
  if (salonId != null && salonId.isNotEmpty) {
    return context.push('/owner/customers?salonId=$salonId');
  }
  return context.push('/owner/customers');
}

/// Navigate to Revenue Screen
Future<dynamic> goToRevenue(
  BuildContext context, {
  String? salonId,
}) async {
  if (salonId != null && salonId.isNotEmpty) {
    return context.push('/owner/revenue?salonId=$salonId');
  }
  return context.push('/owner/revenue');
}

// ============================================
// REPORTS & ANALYTICS NAVIGATION
// ============================================

/// Navigate to Reports Screen
Future<dynamic> goToReports(BuildContext context) async {
  return context.push('/owner/reports');
}

/// Navigate to Analytics Screen
Future<dynamic> goToAnalytics(BuildContext context) async {
  return context.push('/owner/analytics');
}

/// Navigate to Settings Screen
Future<dynamic> goToSettings(BuildContext context) async {
  return context.push('/owner/settings');
}

// ============================================
// HELPER: Get current salon ID from state
// ============================================

/// Get current salon ID from dashboard state (helper function)
String? getCurrentSalonId() {
  // This is a helper - actual implementation should get from your state management
  // For now, you'll need to pass salonId from the dashboard
  return null;
}