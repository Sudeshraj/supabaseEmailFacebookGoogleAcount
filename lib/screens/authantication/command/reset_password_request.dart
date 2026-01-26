import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    
    print('📧 Sending password reset email to: $email');
    
    // Determine redirect URL based on platform
    String redirectUrl;
    
    if (kIsWeb) {
      // For web - use current origin
      final currentOrigin = Uri.base.origin;
      redirectUrl = '$currentOrigin/auth/callback';
      
      // Local development check
      if (kDebugMode) {
        print('🌐 Web mode detected');
        print('   Origin: $currentOrigin');
        print('   Full URL: $redirectUrl');
      }
    } else {
      // For mobile - use deep link
      // IMPORTANT: Make sure this matches your app's URL scheme
      redirectUrl = 'myapp://auth/callback';
      
      if (kDebugMode) {
        print('📱 Mobile mode detected');
        print('   Deep link: $redirectUrl');
      }
    }
    
    print('🔗 Using redirect URL: $redirectUrl');
    
    // Send reset email
    await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectUrl,
    );
    
    print('✅ Reset email sent successfully');

    // Navigate to confirmation screen
    if (mounted) {
      context.go(
        '/reset-password-confirm',
        extra: {'email': email},
      );
    }
  } on AuthException catch (e) {
    print('❌ Auth error: ${e.message}');
    
    String errorMessage = 'Failed to send reset email';
    
    if (e.message.toLowerCase().contains('user not found')) {
      errorMessage = 'No account found with this email';
    } else if (e.message.toLowerCase().contains('rate limit')) {
      errorMessage = 'Too many attempts. Please try again later.';
    } else if (e.message.toLowerCase().contains('email')) {
      errorMessage = 'Invalid email address';
    }
    
    if (mounted) {
      _showErrorSnackBar(errorMessage);
    }
  } catch (e) {
    print('❌ Error: $e');
    if (mounted) {
      _showErrorSnackBar('An unexpected error occurred');
    }
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Back button
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
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
                        color: const Color(0xFF1877F3).withOpacity(0.1),
                        border: Border.all(
                          color: const Color(0xFF1877F3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: Color(0xFF1877F3),
                        size: 40,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      'Reset Password',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Enter your email address and we\'ll send you a password reset link',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
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
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'you@example.com',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _isValidEmail
                                  ? const Color(0xFF1877F3)
                                  : Colors.redAccent,
                              width: 2,
                            ),
                          ),
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            color: Colors.white54,
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
                          errorStyle: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF1877F3).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFF1877F3),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Check your spam folder if you don\'t see the email',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
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
                          backgroundColor: const Color(0xFF1877F3),
                          disabledBackgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 20),
                                  SizedBox(width: 8),
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
                        const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white70,
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
                          child: const Text(
                            'Back to Login',
                            style: TextStyle(
                              color: Colors.white70,
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