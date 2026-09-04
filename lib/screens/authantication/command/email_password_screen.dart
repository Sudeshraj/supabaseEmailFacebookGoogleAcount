import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();

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

    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);

    _validateForm();

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

  bool _isValidEmail(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value);
  }

  void _validateForm() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      if (email.isEmpty) {
        _emailError = 'Enter your email address';
      } else if (!_isValidEmail(email)) {
        _emailError = 'Invalid email format';
      } else {
        _emailError = null;
      }

      if (password.isEmpty) {
        _passwordError = 'Enter your password';
      } else if (password.length < 6) {
        _passwordError = 'Password must be at least 6 characters';
      } else {
        _passwordError = null;
      }

      _isValid = _emailError == null && _passwordError == null;
    });
  }

  void _handleNextPressed() {
    if (!_isValid || _isProcessing || widget.isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _isProcessing = true;
    });

    widget.onNext(email, password);
  }

  void _handleBackPressed() {
    if (_isProcessing || widget.isLoading) return;

    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/login');
      }
    }
  }

  @override
  void didUpdateWidget(covariant EmailPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    debugPrint(
      'EmailPasswordScreen: isLoading changed from ${oldWidget.isLoading} to ${widget.isLoading}',
    );

    if (widget.isLoading != _isProcessing) {
      setState(() {
        _isProcessing = widget.isLoading;
      });
    }

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
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final errorColor = context.errorColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    final bool showLoading = _isProcessing || widget.isLoading;

    return Scaffold(
      backgroundColor: backgroundColor,
      // ✅ FIX: resizeToAvoidBottomInset ensures keyboard doesn't cause
      // extra overflow issues when a text field is focused.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  // ✅ FIX: removed the fixed `height: size.height - 40`.
                  // A fixed height forced the Column to fit into an exact
                  // box, so any extra content (validation errors showing,
                  // keyboard insets, small screens, etc.) had nowhere to go
                  // and overflowed. We let the container size itself to its
                  // content instead, and make that content scrollable.
                  constraints: BoxConstraints(
                    minHeight: size.height - 40,
                  ),
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
                  // ✅ FIX: SingleChildScrollView wraps the Column so that
                  // if the content is taller than the available space
                  // (small phones, error text pushing things down, keyboard
                  // open) it scrolls instead of overflowing.
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🔙 Back Button
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color:
                                  showLoading ? secondaryTextColor : textColor,
                              size: 22,
                            ),
                            onPressed: showLoading ? null : _handleBackPressed,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          "Create Your Account",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          "Enter your email and create a password to get started.",
                          style: TextStyle(
                            fontSize: 15,
                            color: secondaryTextColor,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ✉ Email Field
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            color:
                                showLoading ? secondaryTextColor : textColor,
                          ),
                          enabled: !showLoading,
                          decoration: InputDecoration(
                            hintText: "Email address",
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey.shade600,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade50,
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: _emailError != null
                                    ? errorColor
                                    : (isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: _emailError != null
                                    ? errorColor
                                    : primaryColor,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            errorText: _emailError,
                            errorStyle: TextStyle(
                              color: errorColor,
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
                            color:
                                showLoading ? secondaryTextColor : textColor,
                          ),
                          enabled: !showLoading,
                          decoration: InputDecoration(
                            hintText: "Create a password",
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey.shade600,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade50,
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: _passwordError != null
                                    ? errorColor
                                    : (isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: _passwordError != null
                                    ? errorColor
                                    : primaryColor,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: showLoading
                                ? const SizedBox.shrink()
                                : IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey.shade600,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                            errorText: _passwordError,
                            errorStyle: TextStyle(
                              color: errorColor,
                              fontSize: 13,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Password requirements
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            "• At least 6 characters",
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Loading indicator or Next Button
                        if (showLoading) ...[
                          Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
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
                                    ? primaryColor
                                    : (isDark
                                        ? Colors.white12
                                        : Colors.grey.shade300),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Continue",
                                    style: TextStyle(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "We'll use this email for:",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "• Account verification\n• Password recovery\n• Important updates",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: secondaryTextColor,
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
      ),
    );
  }
}