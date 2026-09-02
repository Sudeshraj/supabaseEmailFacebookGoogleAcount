import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class VerifyInvalidScreen extends StatefulWidget {
  const VerifyInvalidScreen({super.key});

  @override
  State<VerifyInvalidScreen> createState() => _VerifyInvalidScreenState();
}

class _VerifyInvalidScreenState extends State<VerifyInvalidScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
      _checkScreenSize();
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

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: backgroundColor,
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Error Icon with gradient background
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              errorColor.withValues(alpha: 0.1),
                              errorColor.withValues(alpha: 0.05),
                            ],
                          ),
                          border: Border.all(
                            color: errorColor.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.error_outline_rounded,
                          color: errorColor,
                          size: 50,
                        ),
                      ),
                      
                      const SizedBox(height: 24),

                      // Title
                      Text(
                        'Invalid or Expired Link',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      
                      const SizedBox(height: 12),

                      // Description
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'The verification link you used is invalid or has expired. Please request a new one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: secondaryTextColor,
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Back to Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            context.go('/login');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Back to Login',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Resend Link Option
                      TextButton(
                        onPressed: () {
                          context.push('/reset-password');
                        },
                        child: Text(
                          'Request new verification link',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
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