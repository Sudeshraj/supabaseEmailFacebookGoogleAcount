import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/authantication/command/email_verify_checker.dart';
import 'package:flutter_application_1/screens/authantication/command/multi_continue_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/not_you.dart';
import 'package:flutter_application_1/screens/authantication/command/registration_flow.dart';
import 'package:flutter_application_1/screens/authantication/services/session_manager.dart';
import 'package:flutter_application_1/screens/commands/alertBox/reset_password.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/home/customer_home.dart';
import 'package:flutter_application_1/screens/home/employee_dashboard.dart';
import 'package:flutter_application_1/screens/home/owner_dashboard.dart';
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

      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user == null) throw Exception("Login failed. Please try again.");
      final safeEmail = user.email ?? '';
      final userId = user.id;
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // 🔹 Check Email Verification
      if (user.emailConfirmedAt == null) {
        if (!mounted) return;

        // Fetch profile from Supabase

        if (profile == null) {
          // ❌ profile එක නැහැ
          final displayName = profile?['name'] ?? "Unknown User";
          final photoUrl = "";

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => NotYouScreen(
                email: safeEmail,
                name: displayName,
                photoUrl: photoUrl,
                roles: [],
                buttonText: "Not You?",
                page: 'splash',
                // ================== NOT YOU ==================
                onNotYou: () async {
                  final nav = navigatorKey.currentState;
                  if (nav == null) return;
                  final dialogCtx = nav.overlay!.context;

                  await showCustomAlert(
                    dialogCtx,
                    title: "Delete Account?",
                    message: "Are you sure you want to delete this profile?",
                    isError: true,
                    buttonText: "Delete",
                    onOk: () async {
                      try {
                        await supabase.auth.admin.deleteUser(userId);
                        nav.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const RegistrationFlow(),
                          ),
                        );
                      } catch (e) {
                        messengerKey.currentState?.showSnackBar(
                          const SnackBar(
                            content: Text("Delete failed. Try again."),
                          ),
                        );
                      }
                    },
                    onClose: () {
                      supabase.auth.signOut();
                    },
                  );
                },
                // ================== CONTINUE ==================
                onContinue: () async {
                  context.go('/verify-email');
                },
              ),
            ),
          );
        } else {
          // ✅ profile එක තියෙනවා
          final displayName = profile['name'] ?? "Unknown User";
          final photoUrl = profile['photo'] ?? "";
          final roles = (profile['roles'] as List?)?.cast<String>() ?? [];

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => NotYouScreen(
                email: safeEmail,
                name: displayName,
                photoUrl: photoUrl,
                roles: roles,
                buttonText: "Not You?",
                page: 'splash',
                // ================== NOT YOU ==================
                onNotYou: () async {
                  final nav = navigatorKey.currentState;
                  if (nav == null) return;
                  final dialogCtx = nav.overlay!.context;

                  await showCustomAlert(
                    dialogCtx,
                    title: "Delete Account?",
                    message: "Are you sure you want to delete this profile?",
                    isError: true,
                    buttonText: "Delete",
                    onOk: () async {
                      try {
                        await supabase.auth.admin.deleteUser(userId);
                        nav.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const RegistrationFlow(),
                          ),
                        );
                      } catch (e) {
                        messengerKey.currentState?.showSnackBar(
                          const SnackBar(
                            content: Text("Delete failed. Try again."),
                          ),
                        );
                      }
                    },
                    onClose: () {
                      supabase.auth.signOut();
                    },
                  );
                },
                // ================== CONTINUE ==================
                onContinue: () async {
                  final nav = navigatorKey.currentState;
                  if (nav == null) return;
                  nav.pushReplacement(
                    MaterialPageRoute(builder: (_) => EmailVerifyChecker()),
                  );
                },
              ),
            ),
          );
        }

        setState(() => _loading = false);
        return;
      }

      print(profile);
      // 🔹 Fetch verified profile
      if (profile == null) {
        if (!mounted) return;
        context.push('/reg');
      } else {
        String savedName =
            profile['name'] ?? user.userMetadata?['full_name'] ?? user.email!;
        String savedPhoto = profile['photo'] ?? "";
        List<String> savedRoles =
            (profile['roles'] as List?)?.cast<String>() ?? [];

        if (savedRoles.isEmpty) savedRoles = ["customer"];

        // 🔹 Save locally (secure)
        await SessionManager.saveProfile(
          email: user.email!,
          name: savedName,
          password: _passwordController.text.trim(),
          roles: savedRoles,
          photo: savedPhoto,
        );

        // 🔹 Redirect to proper dashboard
        final redirectRole = savedRoles.first;
        if (!mounted) return;

        if (redirectRole == "customer") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CustomerHome()),
          );
        } else if (redirectRole == "business") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const OwnerDashboard()),
          );
        } else if (redirectRole == "employee") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EmployeeDashboard()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CustomerHome()),
          );
        }
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      await showCustomAlert(
        context,
        title: "Login Error ❌",
        message: e.message,
        isError: true,
      );
    } catch (e) {
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
                    color: Colors.white.withOpacity(0.03),
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
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ContinueScreen(),
                                ),
                              );
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
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isValid && !_loading
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
}
