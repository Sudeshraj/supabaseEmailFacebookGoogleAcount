import 'package:flutter/material.dart';
import 'package:flutter_application_1/router/auth_gate.dart';
import 'package:flutter_application_1/screens/authantication/services/session_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _decideRoute();
  }

  // ------------------------------------------------------------
  // 🔑 ROUTE DECISION (PRODUCTION SAFE)
  // ------------------------------------------------------------
  Future<void> _decideRoute() async {
    // 0️⃣ Small delay (UI polish + engine settle)
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // 1️⃣ Check LOCAL profiles first (KEY REQUIREMENT)
    final hasLocalProfile = await SessionManager.hasProfile();
    if (!mounted) return;

    if (hasLocalProfile) {
      context.go('/continue');
      return;
    }

    // 2️⃣ Wait for deep-link session restore
    await SessionManager.waitForSession();
    if (!mounted) return;

    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;

    print(session);
    print(user);

    // 3️⃣ No session → login
    if (session == null || user == null) {
      context.go('/login');
      return;
    }

    // 4️⃣ Refresh session safely
    try {
      await _supabase.auth.refreshSession();
    } catch (_) {
      if (!mounted) return;
      context.go('/login');
      return;
    }

    if (!mounted) return;

    // 5️⃣ Email not verified → verify screen
    if (user.emailConfirmedAt == null) {
      context.go('/verify-email');
      return;
    }

    // 6️⃣ Resolve role
    String? role = await SessionManager.getUserRole();
    if (!mounted) return;

    if (role == null) {
      final res = await _supabase
          .from('profiles')
          .select('role, roles')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      role = AuthGate.pickRole(res?['role'] ?? res?['roles']);
      await SessionManager.saveUserRole(role);
    }

    if (!mounted) return;

    // 7️⃣ Final navigation
    switch (role) {
      case 'business':
        context.go('/owner');
        break;
      case 'employee':
        context.go('/employee');
        break;
      default:
        context.go('/customer');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🔹 App logo (optional)
            // Image.asset(
            //   'assets/logo.png',
            //   height: 120,
            // ),
            SizedBox(height: 24),

            CircularProgressIndicator(),

            SizedBox(height: 16),

            Text(
              'LOADING',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
