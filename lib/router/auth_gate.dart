import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/common_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate {
  static final _supabase = Supabase.instance.client;

  // ------------------------------------------------------------
  // ROLE PICKER (priority: business > employee > customer)
  // ------------------------------------------------------------
  static Future<String> pickRole(dynamic data) async {
    if (data == null) return 'customer';

    // If it's already a string role name
    if (data is String) {
      // Check if it's a UUID (role_id) or actual role name
      final isUuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(data);

      if (isUuid) {
        // It's a UUID, fetch from roles table
        try {
          final roleData = await supabase
              .from('roles')
              .select('name')
              .eq('id', data)
              .maybeSingle();

          return roleData?['name']?.toString().toLowerCase() ?? 'customer';
        } catch (e) {
          debugPrint('Error fetching role by UUID: $e');
          return 'customer';
        }
      } else {
        // It's a regular role name
        return data.toLowerCase();
      }
    }

    // If it's a list (old format)
    if (data is List) {
      final roles = data.map((e) => e.toString().toLowerCase()).toList();

      if (roles.contains('business')) return 'business';
      if (roles.contains('employee')) return 'employee';
      if (roles.contains('customer')) return 'customer';
    }

    // If it's a Map (like when joining tables)
    if (data is Map) {
      if (data.containsKey('name')) {
        return data['name'].toString().toLowerCase();
      }
    }

    return 'customer';
  }

  // ------------------------------------------------------------
  // PURE REDIRECT LOGIC (ASYNC but NO await)
  // ------------------------------------------------------------
  static Future<String?> redirect(String location) async {
    const allowed = {
      '/',
      '/login',
      '/verify-email',
      '/continue',
      '/signup',
    }; //refresh karama ethanama thiyenawa
    if (allowed.contains(location)) return null;

    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;
    print(session);
    if (session == null) {
      return '/login';
    }

    if (user?.emailConfirmedAt == null) {
      return '/verify-email';
    }

    return null;
  }
}
