import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
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

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _restoreCooldown();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  // ✅ API 36: Check screen size for responsive layout
  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
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
      context.showErrorSnackBar("Session expired. Please login again.");
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
      context.showWarningSnackBar("Please wait before resending verification.");
    }
  }

  // ------------------------------------------------------------
  // LOGOUT
  // ------------------------------------------------------------
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastVerificationSent');

      await SessionManager.logoutForContinue();

      if (!mounted) return;

      appState.refreshState();
      context.go('/');
    } catch (e) {
      debugPrint('Logout error: $e');

      if (!mounted) return;

      context.go('/');
    }
  }

  // ------------------------------------------------------------
  // OPEN EMAIL APP
  // ------------------------------------------------------------
  Future<void> _openEmailApp() async {
    final email = await _resolveEmail();

    if (!mounted) return;

    openEmailApp(context, email);
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
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          disabledBackgroundColor: isDark
              ? Colors.white12
              : Colors.grey.shade300,
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
    Color? color,
  }) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final buttonColor = color ?? primaryColor;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: buttonColor),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isDark
                ? buttonColor.withValues(alpha: 0.5)
                : buttonColor,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: isDark
              ? buttonColor.withValues(alpha: 0.1)
              : buttonColor.withValues(alpha: 0.05),
          foregroundColor: buttonColor,
        ),
        label: Text(
          text,
          style: TextStyle(
            color: buttonColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: backgroundColor,
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 🔙 Back Button
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: textColor,
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
                            Icon(
                              Icons.mark_email_read_rounded,
                              size: 70,
                              color: primaryColor,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              "Verify your email",
                              style: TextStyle(
                                color: textColor,
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
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      emailText,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Open it to continue.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "Waiting for verification…",
                                  style: TextStyle(
                                    color: secondaryTextColor,
                                  ),
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

  @override
  void dispose() {
    resendTimer?.cancel();
    _authSub?.cancel();
    _controller.dispose();
    super.dispose();
  }
}