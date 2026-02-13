import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EmailPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  final String? initialPassword;
  final void Function(String email, String password) onNext;
  final VoidCallback? onBack;
  final bool isLoading;

  const EmailPasswordScreen({
    super.key,
    this.initialEmail,
    this.initialPassword,
    required this.onNext,
    this.onBack,
    this.isLoading = false,
  });

  @override
  State<EmailPasswordScreen> createState() => _EmailPasswordScreenState();
}

class _EmailPasswordScreenState extends State<EmailPasswordScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _obscurePassword = true;
  bool _isValid = false;
  bool _isProcessing = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize with previous values if available
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
    if (widget.initialPassword != null) {
      _passwordController.text = widget.initialPassword!;
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();

    // Add listeners to both controllers
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);

    // Initial validation
    _validateForm();
  }

  bool _isValidEmail(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value);
  }

  void _validateForm() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      // Validate email
      if (email.isEmpty) {
        _emailError = 'Enter your email address';
      } else if (!_isValidEmail(email)) {
        _emailError = 'Invalid email format';
      } else {
        _emailError = null;
      }

      // Validate password
      if (password.isEmpty) {
        _passwordError = 'Enter your password';
      } else if (password.length < 6) {
        _passwordError = 'Password must be at least 6 characters';
      } else {
        _passwordError = null;
      }

      // Enable next button only when both fields are valid
      _isValid = _emailError == null && _passwordError == null;
    });
  }

  // email_password_screen.dart
  void _handleNextPressed() {
    if (!_isValid || _isProcessing || widget.isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _isProcessing = true;
    });

    // Call the onNext callback
    widget.onNext(email, password);
  }

  void _handleBackPressed() {
    if (_isProcessing || widget.isLoading) return;

    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      // Default back navigation
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/login');
      }
    }
  }

  // email_password_screen.dart
  // email_password_screen.dart
  @override
  void didUpdateWidget(covariant EmailPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    debugPrint(
      'EmailPasswordScreen: isLoading changed from ${oldWidget.isLoading} to ${widget.isLoading}',
    );

    // Sync with parent's loading state
    if (widget.isLoading != _isProcessing) {
      setState(() {
        _isProcessing = widget.isLoading;
      });
    }

    // If parent just finished loading (true → false), also reset our state
    if (oldWidget.isLoading == true && widget.isLoading == false) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _isProcessing) {
          setState(() {
            _isProcessing = false;
            debugPrint('EmailPasswordScreen: Auto-reset processing state');
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    final bool showLoading = _isProcessing || widget.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔙 Back Button
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: showLoading ? Colors.white30 : Colors.white,
                            size: 22,
                          ),
                          onPressed: showLoading ? null : _handleBackPressed,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        "Create Your Account",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        "Enter your email and create a password to get started.",
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ✉ Email Field
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          color: showLoading ? Colors.white54 : Colors.white,
                        ),
                        enabled: !showLoading,
                        decoration: InputDecoration(
                          hintText: "Email address",
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _emailError != null
                                  ? Colors.redAccent
                                  : Colors.white24,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _emailError != null
                                  ? Colors.redAccent
                                  : const Color(0xFF1877F3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          errorText: _emailError,
                          errorStyle: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 🔒 Password Field
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: TextStyle(
                          color: showLoading ? Colors.white54 : Colors.white,
                        ),
                        enabled: !showLoading,
                        decoration: InputDecoration(
                          hintText: "Create a password",
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _passwordError != null
                                  ? Colors.redAccent
                                  : Colors.white24,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _passwordError != null
                                  ? Colors.redAccent
                                  : const Color(0xFF1877F3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: showLoading
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                          errorText: _passwordError,
                          errorStyle: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Password requirements
                      const Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: Text(
                          "• At least 6 characters",
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Loading indicator or Next Button
                      if (showLoading) ...[
                        Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  "Processing...",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        // Next Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isValid ? _handleNextPressed : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isValid
                                  ? const Color(0xFF1877F3)
                                  : Colors.white12,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Continue",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_isValid) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Info Text at Bottom
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: showLoading ? 0.5 : 1.0,
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "We'll use this email for:",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "• Account verification\n• Password recovery\n• Important updates",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                height: 1.6,
                              ),
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
}
