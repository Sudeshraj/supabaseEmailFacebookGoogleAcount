import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/alertBox/reset_password.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class SignInScreen extends StatefulWidget {
  final String? prefilledEmail;

  const SignInScreen({super.key, this.prefilledEmail});

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

      debugPrint('\n' + '='*50);
  debugPrint('🚀 SIGNINSCREEN INITSTATE CALLED');
  debugPrint('='*50);
  debugPrint('📧 widget.prefilledEmail: ${widget.prefilledEmail}');
  debugPrint('🔑 widget.key: ${widget.key}');
  
  // Initialize controllers with debug
  if (widget.prefilledEmail != null) {
    _emailController = TextEditingController(text: widget.prefilledEmail);
    debugPrint('✅ Controller initialized with: ${widget.prefilledEmail}');
  } else {
    _emailController = TextEditingController();
    debugPrint('⚠️ Controller initialized EMPTY');
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
print(widget.prefilledEmail);
print(  'Checking prefilled email in SignInScreen');
     // ✅ Check for email from multiple sources
   WidgetsBinding.instance.addPostFrameCallback((_) {
    print(  'Checking prefilled email in SignInScreen');
    _checkForPrefilledEmail();
  });


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

  void _checkForPrefilledEmail() async {
  // 1. Check widget parameter first
  if (widget.prefilledEmail != null && widget.prefilledEmail!.isNotEmpty) {
    _emailController.text = widget.prefilledEmail!;
  } 
  // 2. Check from SessionManager
  else {
    // final lastEmail = await SessionManager.getLastEmail();
    // if (lastEmail != null && lastEmail.isNotEmpty) {
    //   _emailController.text = lastEmail;
    //   // Clear after use
    //   await SessionManager.clearLastEmail();
    // }
  }
  
  // Validate after setting email
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      _validateForm();
      setState(() {});
    }
  });
}

  // ======================================================================
  // ✅ UPDATED: LOGIN FUNCTION WITH SESSION MANAGER PROFILE SAVING
  // ======================================================================
  Future<void> loginUser() async {
    try {
      setState(() => _loading = true);

      // 1️⃣ SIGN IN WITH SUPABASE
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      // ✅ SAVE USER PROFILE TO SESSION MANAGER FOR CONTINUE SCREEN
      await SessionManager.saveUserProfile(
        email: user.email!,
        userId: user.id,
        name: user.userMetadata?['full_name'] ?? user.email!.split('@').first,
      );
      print('✅ Profile saved to SessionManager: ${user.email}');

      // 2️⃣ FETCH PROFILE FROM DATABASE (FOR VALIDATION AND ROLE)
      // try {

      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      // 3️⃣ PROFILE NOT CREATED IN DATABASE → router will redirect to /reg
      print('✅ Profile fetched: $profile');
      if (profile == null) {
        // await appState.restore();
        appState.refreshState();
        if (!mounted) return;
        context.go('/'); // 🔥 let main.dart decide
        return;
      }

      // 4️⃣ CHECK IF ACCOUNT IS BLOCKED
      if (profile['is_blocked'] == true) {
        await supabase.auth.signOut();
        // Remove from SessionManager too
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

      // 5️⃣ CHECK IF ACCOUNT IS INACTIVE
      if (profile['is_active'] == false) {
        await supabase.auth.signOut();
        // Remove from SessionManager too
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

      // 6️⃣ SAVE ROLE TO SESSION MANAGER
      final String role = profile['role'] ?? 'customer';
      await SessionManager.saveUserRole(role);
      print('✅ Role saved: $role');

      // 7️⃣ UPDATE APP STATE AND NAVIGATE
      // await appState.restore();
      appState.refreshState();
      if (!mounted) return;

      // Let router handle the redirection based on role
      context.go('/'); // Router will redirect to appropriate screen

      // }catch (_) {
      //     appState.refreshState();
      //   if (!mounted) return;
      //   context.go('/');
      // }
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
          // Save profile even if email not confirmed
          final email = _emailController.text.trim();
          final user = supabase.auth.currentUser;

          if (user != null) {
            await SessionManager.saveUserProfile(
              email: email,
              userId: user.id,
              name: email.split('@').first,
            );
          }
          // await appState.restore();
          appState.refreshState();
          if (!mounted) return;
          context.go('/'); // 🔥 router → /verify-email
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

  // ======================================================================
  // ✅ NEW: AUTO LOGIN FROM CONTINUE SCREEN
  // ======================================================================
  Future<void> tryAutoLogin(String email) async {
    try {
      setState(() => _loading = true);

      // Try auto login using SessionManager
      final success = await SessionManager.tryAutoLogin(email);

      if (success) {
        // Auto login successful
        // await appState.restore();
        appState.refreshState();
        if (!mounted) return;
        context.go('/'); // Router will handle redirection
      } else {
        // Auto login failed, pre-fill email and show message
        _emailController.text = email;
        _validateForm();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter password for $email'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Auto login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ======================================================================
  // ✅ UI SECTION WITH CONTINUE SCREEN OPTION
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
                                onPressed: () async {
                                  // Go to continue screen
                                  context.push('/continue');
                                },
                              ),
                              // Optional: Add text label
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

                              // ✅ EMAIL FIELD - Updated for prefilled email
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
                                  // ✅ Prefix icon එකතු කරන්න
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
                                // ✅ Auto focus password field if email is prefilled
                                onEditingComplete: () {
                                  if (_emailController.text.isNotEmpty &&
                                      widget.prefilledEmail != null) {
                                    // ✅ Use widget.prefilledEmail
                                    FocusScope.of(context).nextFocus();
                                  }
                                },
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
                              const SizedBox(height: 24),

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

                      // ✅ CREATE ACCOUNT BUTTON
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
