import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/session_manager.dart';
import '../functions/open_email.dart';

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
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();
  }
  


  // ------------------------------------------------------------
  // RESTORE COOLDOWN
  // ------------------------------------------------------------
  Future<void> _restoreCooldown() async {
    final prefs = await SessionManager.getPrefs();
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

    final local = await SessionManager.getLastUser();
    print(local?['email']);
    if (local != null && local['email'] != null) {
      return local['email'];
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Session expired. Please login again."),
        ),
      );
      return;
    }

    final prefs = await SessionManager.getPrefs();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );

      await prefs.setInt('lastVerificationSent', now);
      startCooldown(30);
    } catch (e) {
      await prefs.setInt('lastVerificationSent', now);
      startCooldown(30);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("waiting... for resend verification.")),
      );
    }
  }

  // ------------------------------------------------------------
  // LOGOUT (GoRouter)
  // ------------------------------------------------------------
  Future<void> logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    context.go('/splash');
  }

  double _cardWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w > 900) return 720;
    if (w > 600) return 520;
    return w - 40;
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEEF3FF), Color(0xFFDDE7FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ScaleTransition(
                scale: _scaleAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    width: _cardWidth(context),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 30,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.mark_email_read_rounded,
                            size: 80, color: Colors.deepPurple),
                        const SizedBox(height: 24),
                        Text(
                          "Verify your email",
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "We’ve sent a verification link to your email.\n"
                          "Open it to continue.",
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 26),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text("Waiting for verification…"),
                          ],
                        ),
                        const SizedBox(height: 30),

                        PrimaryOutlineButton(
                          text: canResend
                              ? "Resend Verification Email"
                              : "Wait $remainingSeconds s",
                          onPressed:
                              canResend ? resendVerification : null,
                          color: const Color(0xFF1E88E5),
                          icon: Icons.refresh,
                          disabled: !canResend,
                        ),
                        const SizedBox(height: 14),

                        PrimaryOutlineButton(
                          text: "Open Email App",
                          onPressed: () => openEmailApp(
                            context,
                            supabase.auth.currentUser?.email,
                          ),
                          color: const Color(0xFF6A1B9A),
                          icon: Icons.open_in_new,
                        ),
                        const SizedBox(height: 14),

                        PrimaryOutlineButton(
                          text: "Verify Later",
                          onPressed: logout,
                          color: Colors.redAccent,
                          icon: Icons.logout,
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
    );
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    _authSub?.cancel(); // ✅ important
    _controller.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------
// REUSABLE BUTTON
// ------------------------------------------------------------
class PrimaryOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final IconData icon;
  final bool disabled;

  const PrimaryOutlineButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.color,
    required this.icon,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: OutlinedButton.icon(
          icon: Icon(icon, color: color),
          label: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
        ),
      ),
    );
  }
}
