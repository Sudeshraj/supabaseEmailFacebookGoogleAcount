import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/services/session_manager.dart';
import 'package:flutter_application_1/screens/authantication/services/singup_session.dart';
import 'package:flutter_application_1/screens/commands/alertBox/reset_password.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;
  bool _coolDown = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String? _emailError;
  String? _passwordError;
  bool _isValid = false;
  bool _isValidEmail = false;
  bool _hasSavedProfile = false;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkSavedProfile();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();

    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  bool _isValidEmailFormat(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value);
  }

  void _validateForm() {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    setState(() {
      if (email.isEmpty) {
        _emailError = 'Enter your email address';
        _isValidEmail = false;
      } else if (!_isValidEmailFormat(email)) {
        _emailError = 'Enter a valid email address';
        _isValidEmail = false;
      } else {
        _emailError = null;
        _isValidEmail = true;
      }

      if (password.isEmpty) {
        _passwordError = 'Enter your password';
      } else {
        _passwordError = null;
      }

      _isValid = _emailError == null && _passwordError == null;
    });
  }

  Future<void> _checkSavedProfile() async {
    final profiles = await SessionManager.getProfiles();
    setState(() {
      _hasSavedProfile = profiles.isNotEmpty;
    });
  }

  // ======================================================================
  // ✅ LOGIN FUNCTION WITH SUPABASE + LOCAL SESSION SAVE + NOTYOUSCREEN
  // ======================================================================
  Future<void> loginUser() async {
    try {
      setState(() => _loading = true);

      // 1️⃣ Sign in
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      final userId = user.id;
      final safeEmail = user.email ?? '';

      // 2️⃣ Fetch profile
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // 3️⃣ Profile NOT exists → Register
      if (profile == null) {
        await SessionManagerto.saveEmailAndPassword(
          email: safeEmail,
          password: _passwordController.text.trim(),
        );

        if (!mounted) return;
        context.go('/reg');
        return;
      }

      // 4️⃣ Blocked
      if (profile['is_blocked'] == true) {
        await supabase.auth.signOut();
        if (!mounted) return;

        await showCustomAlert(
          context,
          title: "Account Blocked 🚫",
          message: "Your account has been blocked.",
          isError: true,
        );
        return;
      }

      // 5️⃣ Inactive
      if (profile['is_active'] == false) {
        await supabase.auth.signOut();
        if (!mounted) return;

        await showCustomAlert(
          context,
          title: "Account Inactive ⚠️",
          message: "Your account is deactivated.",
          isError: true,
        );
        return;
      }

      // 6️⃣ Onboarding not completed
      // if (profile['onboarding_completed'] != true) {
      //   if (!mounted) return;
      //   context.go('/onboarding');
      //   return;
      // }

      // 7️⃣ Role based routing
      final role = profile['role'] ?? 'customer';

      if (!mounted) return;

      switch (role) {
        case 'customer':
          context.go('/customer-home');
          break;

        case 'business':
          context.go('/owner-dashboard');
          break;

        case 'employee':
          context.go('/employee-dashboard');
          break;

        default:
          context.go('/customer-home');
      }
    }
    // 🔐 Auth errors
    on AuthException catch (e) {
      switch (e.code) {
        case 'invalid_login_credentials':
          if (!mounted) return;
          context.go('/verify-email');
          break;

        case 'email_not_confirmed':
          await SessionManagerto.saveEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

          if (!mounted) return;
          context.go('/verify-email');
          break;

        case 'too_many_requests':
          if (!mounted) return;

          await showCustomAlert(
            context,
            title: "Too Many Attempts ⏳",
            message:
                "You’ve tried too many times. Please wait a few minutes before trying again.",
            isError: true,
          );

          // Optional: disable button for 30–60 seconds
          setState(() => _coolDown = true);
          Future.delayed(const Duration(seconds: 60), () {
            if (mounted) setState(() => _coolDown = false);
          });
          break;

        case 'user_banned':
          if (!mounted) return;
          await showCustomAlert(
            context,
            title: "Login Error ❌",
            message: e.message,
            isError: true,
          );
          break;

        default:
          if (!mounted) return;
          await showCustomAlert(
            context,
            title: "Login Error ❌",
            message: e.message,
            isError: true,
          );
      }
    }
    // ❌ Unexpected
    catch (e) {
      if (!mounted) return;
      await showCustomAlert(
        context,
        title: "Unexpected Error",
        message: e.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ======================================================================
  // ✅ UI SECTION
  // ======================================================================
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
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
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
                      if (_hasSavedProfile)
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: () {
                              context.push('/continue');
                            },
                          ),
                        ),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 10),
                              Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF1877F3),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Log in to MySalon',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Email address',
                                  hintStyle: const TextStyle(
                                    color: Colors.white54,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: _isValidEmail
                                          ? const Color(0xFF1877F3)
                                          : Colors.redAccent,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  suffixIcon: _emailController.text.isEmpty
                                      ? null
                                      : _isValidEmail
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF4CAF50),
                                        )
                                      : const Icon(
                                          Icons.error_outline,
                                          color: Colors.redAccent,
                                        ),
                                  errorText: _emailError,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  hintStyle: const TextStyle(
                                    color: Colors.white54,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Color(0xFF1877F3),
                                    ),
                                  ),
                                  errorText: _passwordError,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white70,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      (_isValid && !_loading && !_coolDown)
                                      ? loginUser
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1877F3),
                                    disabledBackgroundColor: Colors.white12,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: _loading
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : _coolDown
                                      ? const Text(
                                          'Please wait...',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      : const Text(
                                          'Log in',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () {
                                  showResetPasswordDialog(context);
                                },
                                child: const Text(
                                  'Forgotten password?',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                context.push('/signup');
                              },

                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF1877F3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                backgroundColor: const Color(
                                  0xFF1877F3,
                                ).withValues(alpha: 0.1),
                              ),
                              child: const Text(
                                'Create new account',
                                style: TextStyle(
                                  color: Color(0xFF1877F3),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
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
    );
  }
}
