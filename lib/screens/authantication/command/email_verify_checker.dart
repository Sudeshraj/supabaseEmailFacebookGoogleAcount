import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../functions/open_email.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class EmailVerifyChecker extends StatefulWidget {
  const EmailVerifyChecker({super.key});

  @override
  State<EmailVerifyChecker> createState() => _EmailVerifyCheckerState();
}

class _EmailVerifyCheckerState extends State<EmailVerifyChecker>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool canResend = true;
  int remainingSeconds = 0;
  Timer? resendTimer;

  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  StreamSubscription<AuthState>? _authSub;

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _restoreCooldown();
  }

  // ------------------------------------------------------------
  // ANIMATION
  // ------------------------------------------------------------
  void _setupAnimation() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _scaleAnim = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  // ------------------------------------------------------------
  // RESTORE COOLDOWN
  // ------------------------------------------------------------
  Future<void> _restoreCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSent = prefs.getInt('lastVerificationSent') ?? 0;

    if (lastSent == 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    const cooldownMs = 30 * 1000;

    final diff = now - lastSent;
    if (diff < cooldownMs) {
      final remaining = ((cooldownMs - diff) / 1000).ceil();
      startCooldown(remaining);
    }
  }

  // ------------------------------------------------------------
  // RESOLVE EMAIL
  // ------------------------------------------------------------
  Future<String?> _resolveEmail() async {
    final user = supabase.auth.currentUser;
    if (user?.email != null) return user!.email;

    // Try to get from SessionManager
    final recentUser = await SessionManager.getMostRecentUser();
    if (recentUser != null && recentUser['email'] != null) {
      return recentUser['email'] as String?;
    }

    final lastUser = await SessionManager.getLastUser();
    if (lastUser != null && lastUser['email'] != null) {
      return lastUser['email'] as String?;
    }

    return null;
  }

  // ------------------------------------------------------------
  // COOLDOWN TIMER
  // ------------------------------------------------------------
  void startCooldown(int seconds) {
    resendTimer?.cancel();

    setState(() {
      canResend = false;
      remainingSeconds = seconds;
    });

    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();

      if (remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          canResend = true;
          remainingSeconds = 0;
        });
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  // ------------------------------------------------------------
  // RESEND EMAIL
  // ------------------------------------------------------------
  Future<void> resendVerification() async {
    if (!canResend) return;

    final email = await _resolveEmail();
    if (email == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please login again.")),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);

      await prefs.setInt('lastVerificationSent', now);
      startCooldown(30);
    } catch (e) {
      await prefs.setInt('lastVerificationSent', now);
      startCooldown(30);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please wait before resending verification."),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // LOGOUT - FIXED WITH MOUNTED CHECK
  // ------------------------------------------------------------
  Future<void> logout() async {
    try {
      // Clear any saved verification timer
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastVerificationSent');

      // Logout but keep profile for continue screen
      await SessionManager.logoutForContinue();

      // Check if widget is still mounted before using context
      if (!mounted) return;

      // Navigate to home
      // appState.refreshState();
      context.go('/');
    } catch (e) {
      print('❌ Logout error: $e');

      // Check if widget is still mounted before using context
      if (!mounted) return;

      // Navigate to home even on error
      context.go('/');
    }
  }

  // ------------------------------------------------------------
  // OPEN EMAIL APP - FIXED WITH MOUNTED CHECK
  // ------------------------------------------------------------
  Future<void> _openEmailApp() async {
    final email = await _resolveEmail();

    // Check if widget is still mounted before using context
    if (!mounted) return;

    openEmailApp(context, email);
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF0F1820);
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  height: size.height - 40,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 🔙 Back Button (SignIn style)
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () {
                            if (mounted) {
                              context.go('/');
                            }
                          },
                        ),
                      ),

                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.mark_email_read_rounded,
                              size: 70,
                              color: Color(0xFF1877F3),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              "Verify your email",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FutureBuilder<String?>(
                              future: _resolveEmail(),
                              builder: (context, snapshot) {
                                String emailText = 'your email';
                                if (snapshot.hasData && snapshot.data != null) {
                                  emailText = snapshot.data!;
                                }

                                return Column(
                                  children: [
                                    Text(
                                      "We've sent a verification link to:",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      emailText,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Open it to continue.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  "Waiting for verification…",
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),

                            _primaryButton(
                              text: canResend
                                  ? "Resend Verification Email"
                                  : "Wait $remainingSeconds s",
                              icon: Icons.refresh,
                              enabled: canResend,
                              onPressed: canResend ? resendVerification : null,
                            ),
                            const SizedBox(height: 12),

                            _outlineButton(
                              text: "Open Email App",
                              icon: Icons.open_in_new,
                              onPressed: () => _openEmailApp(),
                            ),
                            const SizedBox(height: 12),

                            _outlineButton(
                              text: "Logout",
                              icon: Icons.logout,
                              color: Colors.redAccent,
                              onPressed: () => logout(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUTTONS
  // ------------------------------------------------------------
  Widget _primaryButton({
    required String text,
    required IconData icon,
    required VoidCallback? onPressed,
    bool enabled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1877F3),
          disabledBackgroundColor: Colors.white12,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        label: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    Color color = const Color(0xFF1877F3),
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: color.withValues(alpha: 0.1),
        ),
        label: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    _authSub?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
