import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate {
  static final _supabase = Supabase.instance.client;

  // ------------------------------------------------------------
  // ROLE PICKER (priority: business > employee > customer)
  // ------------------------------------------------------------
  static String pickRole(dynamic data) {
    if (data == null) return 'customer';

    if (data is String) {
      return data.toLowerCase();
    }

    if (data is List) {
      final roles = data.map((e) => e.toString().toLowerCase()).toList();

      if (roles.contains('business')) return 'business';
      if (roles.contains('employee')) return 'employee';
      if (roles.contains('customer')) return 'customer';
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
