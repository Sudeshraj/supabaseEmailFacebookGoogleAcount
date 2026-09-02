import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class ResetPasswordRequestScreen extends StatefulWidget {
  const ResetPasswordRequestScreen({super.key});

  @override
  State<ResetPasswordRequestScreen> createState() =>
      _ResetPasswordRequestScreenState();
}

class _ResetPasswordRequestScreenState
    extends State<ResetPasswordRequestScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _loading = false;
  bool _isValidEmail = false;
  String? _emailError;
  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

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

  bool _isValidEmailFormat(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value);
  }

  void _validateEmail() {
    final email = _emailController.text.trim();
    
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
    });
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isValidEmail) return;

    setState(() => _loading = true);

    try {
      final email = _emailController.text.trim();
      
      debugPrint('Sending password reset email to: $email');
      
      String redirectUrl;
      
      if (kIsWeb) {
        final currentOrigin = Uri.base.origin;
        redirectUrl = '$currentOrigin/auth/callback';
        
        if (kDebugMode) {
          print('Web mode detected');
          print('   Origin: $currentOrigin');
          print('   Full URL: $redirectUrl');
        }
      } else {
        redirectUrl = 'myapp://auth/callback';
        
        if (kDebugMode) {
          print('Mobile mode detected');
          print('   Deep link: $redirectUrl');
        }
      }
      
      debugPrint('Using redirect URL: $redirectUrl');
      
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl,
      );
      
      debugPrint('Reset email sent successfully');

      if (mounted) {
        context.go(
          '/reset-password-confirm',
          extra: {'email': email},
        );
      }
    } on AuthException catch (e) {
      debugPrint('Auth error: ${e.message}');
      
      String errorMessage = 'Failed to send reset email';
      
      if (e.message.toLowerCase().contains('user not found')) {
        errorMessage = 'No account found with this email';
      } else if (e.message.toLowerCase().contains('rate limit')) {
        errorMessage = 'Too many attempts. Please try again later.';
      } else if (e.message.toLowerCase().contains('email')) {
        errorMessage = 'Invalid email address';
      }
      
      if (mounted) {
        context.showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        context.showErrorSnackBar('An unexpected error occurred');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final errorColor = context.errorColor;
    final successColor = context.successColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                margin: const EdgeInsets.all(24),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Back button
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: textColor,
                          size: 22,
                        ),
                        onPressed: () => context.pop(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor.withValues(alpha: 0.1),
                        border: Border.all(
                          color: primaryColor,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        color: primaryColor,
                        size: 40,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      'Reset Password',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Enter your email address and we\'ll send you a password reset link',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Email field
                    Form(
                      key: _formKey,
                      child: TextField(
                        controller: _emailController,
                        onChanged: (value) => _validateEmail(),
                        style: TextStyle(color: textColor),
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(color: secondaryTextColor),
                          hintText: 'you@example.com',
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _isValidEmail
                                  ? primaryColor
                                  : errorColor,
                              width: 2,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade400,
                          ),
                          suffixIcon: _emailController.text.isEmpty
                              ? null
                              : _isValidEmail
                                  ? Icon(
                                      Icons.check_circle,
                                      color: successColor,
                                    )
                                  : Icon(
                                      Icons.error_outline,
                                      color: errorColor,
                                    ),
                          errorText: _emailError,
                          errorStyle: TextStyle(color: errorColor),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Check your spam folder if you don\'t see the email',
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Send button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_isValidEmail && !_loading)
                            ? _sendResetEmail
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          disabledBackgroundColor: isDark
                              ? Colors.white12
                              : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Send Reset Link',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Back to login
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back_rounded,
                          color: secondaryTextColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Back to Login',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
    super.dispose();
  }
}