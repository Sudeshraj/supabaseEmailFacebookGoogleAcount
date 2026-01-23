import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/alertBox/reset_password.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/supabase_persistence.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/session_manager.dart';

import '../../../utils/simple_toast.dart';

class SignInScreen extends StatefulWidget {
  final String? prefilledEmail;
  final bool showMessage; // ✅ Add this parameter
  final String? message; // ✅ Custom message

  const SignInScreen({
    super.key,
    this.prefilledEmail,
    this.showMessage = false,
    this.message,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;
  bool _coolDown = false;
  bool _rememberMe = false;
  final bool _showPrivacyLinks = true;

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
    _loadRememberMeSetting();
    if (widget.prefilledEmail != null) {
      _emailController = TextEditingController(text: widget.prefilledEmail);
      print('📧 Prefilled email: ${widget.prefilledEmail}');
    } else {
      _emailController = TextEditingController();
    }

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForPrefilledEmail();

      // ✅ Show custom message if provided
      if (widget.showMessage && widget.message != null) {
        _showCustomMessage(widget.message!);
      }
    });

    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  void _showCustomMessage(String message) {
    // ✅ Pass both required parameters
    SimpleToast.info(
      context, // First parameter: BuildContext
      message, // Second parameter: String message
    );

    // Or with named duration parameter:
    // SimpleToast.info(
    //   context,
    //   message,
    //   duration: const Duration(seconds: 5),
    // );
  }

  Future<void> _loadRememberMeSetting() async {
    final rememberMe = await SessionManager.isRememberMeEnabled();
    setState(() {
      _rememberMe = rememberMe;
    });
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

  void _checkForPrefilledEmail() async {
    if (widget.prefilledEmail != null && widget.prefilledEmail!.isNotEmpty) {
      _emailController.text = widget.prefilledEmail!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _validateForm();
        setState(() {});
      }
    });
  }

  Future<void> loginUser() async {
    try {
      setState(() => _loading = true);

      // 1️⃣ SIGN IN WITH SUPABASE
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      final session = response.session;

      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      // After successful login in loginUser() method:
      print('🎉 LOGIN SUCCESS - VERIFYING PERSISTENCE');
      print('   - User: ${user.email}');
      print('   - Session valid: ${session != null}');

      // Force session to persist
      await Future.delayed(const Duration(milliseconds: 500));

      // Debug persistence
      await SupabasePersistenceHelper.debugSessionPersistence();

      // Save to shared preferences for backup
      await SessionManager.setCurrentUser(user.email!);
      print('✅ User email saved to preferences: ${user.email}');

      // ✅ SAVE REFRESH TOKEN PROPERLY AFTER LOGIN
      final refreshToken = session?.refreshToken;

      // ✅ SAVE USER PROFILE WITH REMEMBER ME SETTING AND TOKEN
      await SessionManager.saveUserProfile(
        email: user.email!,
        userId: user.id,
        name: user.userMetadata?['full_name'] ?? user.email!.split('@').first,
        rememberMe: _rememberMe,
        refreshToken: refreshToken,
      );

      // Also save the token separately for easier access
      if (refreshToken != null) {
        await SessionManager.saveRefreshToken(user.email!, refreshToken);
      }

      print(
        '✅ Profile saved: ${user.email} (Remember Me: $_rememberMe, Token: ${refreshToken != null ? "Saved" : "Not saved"})',
      );

      // Update app state remember me setting
      await appState.setRememberMe(_rememberMe);

      // 2️⃣ FETCH PROFILE FROM DATABASE
      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      print('✅ Profile fetched: $profile');

      if (profile == null) {
        appState.refreshState();
        if (!mounted) return;
        context.go('/');
        return;
      }

      // 3️⃣ CHECK IF ACCOUNT IS BLOCKED
      if (profile['is_blocked'] == true) {
        await supabase.auth.signOut();
        await SessionManager.removeProfile(user.email!);

        if (!mounted) return;

        await showCustomAlert(
          context: context,
          title: "Account Blocked 🚫",
          message: "Your account has been blocked. Please contact support.",
          isError: true,
        );
        return;
      }

      // 4️⃣ CHECK IF ACCOUNT IS INACTIVE
      if (profile['is_active'] == false) {
        await supabase.auth.signOut();
        await SessionManager.removeProfile(user.email!);

        if (!mounted) return;

        await showCustomAlert(
          context: context,
          title: "Account Inactive ⚠️",
          message: "Your account is deactivated.",
          isError: true,
        );
        return;
      }

      // 5️⃣ SAVE ROLE TO SESSION MANAGER
      final String role = profile['role'] ?? 'customer';
      await SessionManager.saveUserRole(role);
      print('✅ Role saved: $role');

      // 6️⃣ UPDATE APP STATE AND NAVIGATE
      appState.refreshState();
      if (!mounted) return;

      // Let router handle the redirection based on role
      context.go('/');
    }
    // 🔐 AUTH ERRORS HANDLING
    on AuthException catch (e) {
      if (!mounted) return;

      switch (e.code) {
        case 'invalid_login_credentials':
          await showCustomAlert(
            context: context,
            title: "Login Failed ❌",
            message: "Email or password is incorrect.",
            isError: true,
          );
          break;

        case 'email_not_confirmed':
          // Save profile with remember me setting even if email not confirmed
          final email = _emailController.text.trim();
          final user = supabase.auth.currentUser;

          if (user != null) {
            final session = supabase.auth.currentSession;
            final refreshToken = session?.refreshToken;

            await SessionManager.saveUserProfile(
              email: email,
              userId: user.id,
              name: email.split('@').first,
              rememberMe: _rememberMe,
              refreshToken: refreshToken,
            );
          }
          appState.emailVerifyerError();
          appState.refreshState();
          if (!mounted) return;
          context.go('/');
          break;

        case 'too_many_requests':
          await showCustomAlert(
            context: context,
            title: "Too Many Attempts ⏳",
            message: "Please wait a few minutes and try again.",
            isError: true,
          );

          setState(() => _coolDown = true);
          Future.delayed(const Duration(seconds: 60), () {
            if (mounted) setState(() => _coolDown = false);
          });
          break;

        default:
          await showCustomAlert(
            context: context,
            title: "Login Error ❌",
            message: e.message,
            isError: true,
          );
      }
    }
    // ❌ UNEXPECTED ERRORS
    catch (e) {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Unexpected Error",
        message: e.toString(),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleBackButton() {
    // Try to pop first
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
    } else {
      // If nothing to pop, navigate to splash
      GoRouter.of(context).go('/');
    }
  }

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
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ✅ CONTINUE SCREEN BACK BUTTON
                      if (_hasSavedProfile)
                        Align(
                          alignment: Alignment.topLeft,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed:
                                    _handleBackButton, // ✅ Use the handler
                              ),
                              if (_hasSavedProfile)
                                GestureDetector(
                                  onTap: () {
                                    context.push('/continue');
                                  },
                                  child: const Text(
                                    'Use another account',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                            ],
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

                              // ✅ EMAIL FIELD
                              TextField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Email address',
                                  hintStyle: const TextStyle(
                                    color: Colors.white54,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
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
                                  prefixIcon: const Icon(
                                    Icons.email_outlined,
                                    color: Colors.white54,
                                    size: 20,
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

                              // ✅ PASSWORD FIELD
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
                                  fillColor: Colors.white.withOpacity(0.05),
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
                              const SizedBox(height: 16),

                              // ✅ REMEMBER ME CHECKBOX
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
                                    activeColor: const Color(0xFF1877F3),
                                    checkColor: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Remember Me',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // ✅ LOGIN BUTTON
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

                              // ✅ FORGOT PASSWORD
                              GestureDetector(
                                onTap: () {
                                  context.push('/reset-password');
                                },
                                child: const Text(
                                  'Forgotten password?',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ✅ PRIVACY LINKS AND CREATE ACCOUNT
                      // sign_in_screen.dart - build method තුළ privacy links section
                      Column(
                        children: [
                          // Privacy Policy Links - ALWAYS VISIBLE
                          if (_showPrivacyLinks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      // ✅ Navigate to privacy policy with return route
                                      context.push(
                                        '/privacy?from=${Uri.encodeComponent('/login')}',
                                      );
                                    },
                                    child: const Text(
                                      'Privacy Policy',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 1,
                                    height: 12,
                                    color: Colors.white30,
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () {
                                      // ✅ Navigate to terms with return route
                                      context.push(
                                        '/terms?from=${Uri.encodeComponent('/login')}',
                                      );
                                    },
                                    child: const Text(
                                      'Terms of Service',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Data Management Option
                          TextButton(
                            onPressed: () => context.go('/clear-data'),
                            child: const Text(
                              'Clear All Data',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Create Account Button with explicit consent notice
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'New to MySalon?',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      context.go('/signup');
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
                                      ).withOpacity(0.1),
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
                                const SizedBox(height: 8),
                                const Text(
                                  'By creating an account, you agree to our Terms and Privacy Policy',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }
}
