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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final supabase = Supabase.instance.client;

  bool canResend = true;
  int remainingSeconds = 0;
  Timer? resendTimer;

  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  StreamSubscription<AuthState>? _authSub;

  // ============================================================
  // ✅ FIX: this screen previously never actually checked whether
  // the email got verified. `_authSub` was declared but never
  // assigned, so nothing was listening for auth changes at all.
  //
  // Email confirmation happens in the BROWSER (Supabase's hosted
  // confirm page), not inside the app, so Supabase's in-app auth
  // client has no way of knowing the email was confirmed unless:
  //   (a) a deep link brings the new session back into the app, OR
  //   (b) we explicitly ask the server "has this user verified yet?"
  //
  // Deep links can silently fail to fire (wrong scheme registration,
  // platform quirks, user manually switching back to the app instead
  // of tapping a link), so we can't rely on that alone. This adds:
  //   1. A real onAuthStateChange listener (in case a deep link OR
  //      background token refresh DOES bring in a fresh session).
  //   2. A lifecycle observer — the moment the user comes back to
  //      the app after tapping the email link (app resumed), we
  //      immediately ask the server for a fresh session.
  //   3. A periodic poll (every 4s) as a last-resort safety net for
  //      platforms/situations where lifecycle resume doesn't fire
  //      reliably (e.g. some web/desktop flows).
  // Whichever path detects verification first wins; the others are
  // cancelled once verified.
  // ============================================================
  Timer? _pollTimer;
  bool _verifiedHandled = false;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  // ------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _setupAnimation();
    _restoreCooldown();
    _startAuthListener();
    _startPolling();

    // Check once immediately too, in case the user already
    // verified before this screen even finished building
    // (e.g. re-entering the app after a while).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
      _checkEmailVerified();
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
  // ✅ NEW: LIFECYCLE — check the moment the app comes back to
  // foreground (user just tapped the email link in their mail
  // app / browser, then switched back).
  // ------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📲 App resumed — checking email verification status');
      _checkEmailVerified();
    }
  }

  // ------------------------------------------------------------
  // ✅ NEW: AUTH STATE LISTENER — catches the case where a deep
  // link (or a background token refresh) brings a fresh, already-
  // verified session into the app directly.
  // ------------------------------------------------------------
  void _startAuthListener() {
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      debugPrint('🔔 Auth event on verify screen: ${data.event}');

      if (data.event == AuthChangeEvent.userUpdated ||
          data.event == AuthChangeEvent.tokenRefreshed ||
          data.event == AuthChangeEvent.signedIn) {
        _checkEmailVerified();
      }
    });
  }

  // ------------------------------------------------------------
  // ✅ NEW: PERIODIC POLL — last-resort safety net. Runs every 4s
  // while this screen is visible, stops itself once verified or
  // once the screen is disposed.
  // ------------------------------------------------------------
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkEmailVerified();
    });
  }

  // ------------------------------------------------------------
  // ✅ NEW: THE ACTUAL CHECK
  // ------------------------------------------------------------
  Future<void> _checkEmailVerified() async {
    if (_verifiedHandled || !mounted) return;

    try {
      // Ask the server directly rather than trusting the locally
      // cached user object, since that cache won't reflect a
      // confirmation that happened in the browser.
      final response = await supabase.auth.refreshSession();
      final user = response.user ?? supabase.auth.currentUser;

      if (user?.emailConfirmedAt != null) {
        debugPrint('✅ Email verified! Redirecting to /reg');
        _verifiedHandled = true;

        _pollTimer?.cancel();
        _authSub?.cancel();

        // ✅ Refresh global app state so router's redirect logic
        // (which reads appState.emailVerified) picks this up too.
        appState.refreshState();

        if (!mounted) return;
        context.go('/reg');
      }
    } catch (e) {
      // No active session yet / network hiccup / not verified yet —
      // this is expected while the user hasn't clicked the link,
      // so we just silently retry on the next poll/resume.
      debugPrint('ℹ️ Verification check: not verified yet ($e)');
    }
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
      await appState.logoutForContinue();
      if (!mounted) return;
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
        child: SingleChildScrollView(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: size.height - 40,
                    ),
                    child: Container(
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

                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 12),
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
                              const SizedBox(height: 12),
                            ],
                          ),
                        ],
                      ),
                    ),
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
    WidgetsBinding.instance.removeObserver(this);
    resendTimer?.cancel();
    _pollTimer?.cancel();
    _authSub?.cancel();
    _controller.dispose();
    super.dispose();
  }
}