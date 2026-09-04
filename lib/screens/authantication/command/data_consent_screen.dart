import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/services/signup_serivce.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class DataConsentScreen extends StatefulWidget {
  final String email;
  final String password;
  final String? source;

  const DataConsentScreen({
    super.key,
    required this.email,
    required this.password,
    this.source,
  });

  @override
  State<DataConsentScreen> createState() => _DataConsentScreenState();
}

class _DataConsentScreenState extends State<DataConsentScreen>
    with SingleTickerProviderStateMixin {
  bool _rememberMe = true;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _acceptedMarketing = false;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final AuthService _authService = AuthService();

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();

    _rememberMe = true;
    _acceptedMarketing = false;

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

  bool get _isContinueEnabled {
    return _acceptedTerms && _acceptedPrivacy && !_isLoading;
  }

  Future<void> _handleContinue() async {
    if (!_isContinueEnabled || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Starting registration for: ${widget.email}');

      await _authService.registerUser(
        context: context,
        email: widget.email,
        password: widget.password,
        rememberMe: _rememberMe,
        marketingConsent: _acceptedMarketing,
      );

      debugPrint('Registration completed');
    } catch (e) {
      debugPrint('Registration error: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleBackButton() {
    if (_isLoading) return;

    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
    } else {
      GoRouter.of(context).go('/signup');
    }
  }

  void _showPolicyDetails(bool isPrivacyPolicy) {
    final route = isPrivacyPolicy ? '/privacy' : '/terms';

    GoRouter.of(context).push(
      route,
      extra: {
        'email': widget.email,
        'password': widget.password,
        'returnRoute': '/data-consent',
        'from': 'data-consent',
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    if (_isLoading) {
      debugPrint('DataConsentScreen disposing while still loading');
    }
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
    final successColor = context.successColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: backgroundColor,
      // ✅ FIX: LayoutBuilder + SingleChildScrollView so the whole card can
      // scroll and never overflow, regardless of screen height or content size.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                // keeps the card vertically centered when content is shorter
                // than the screen, but allows it to grow + scroll when taller.
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Container(
                          // ❌ REMOVED: fixed `height: size.height - 40`
                          // That forced an exact height, and once padding +
                          // header + banner + buttons were added, there
                          // wasn't enough room left → overflow.
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
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with Back Button
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: textColor,
                                      size: 22,
                                    ),
                                    onPressed:
                                        _isLoading ? null : _handleBackButton,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Complete Registration',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // Account Info Banner
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        primaryColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.email_outlined,
                                      color: primaryColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Registering email:',
                                            style: TextStyle(
                                              color: secondaryTextColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            widget.email,
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Main scrollable content
                              // ❌ REMOVED: Expanded(SingleChildScrollView(...))
                              // Not needed anymore since the whole card scrolls.
                              Text(
                                'Final Step: Review & Accept',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),

                              const SizedBox(height: 12),

                              Text(
                                'Please review and accept the following to create your account. All fields marked with * are required.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: secondaryTextColor,
                                  height: 1.5,
                                ),
                              ),

                              const SizedBox(height: 32),

                              Text(
                                'Required Consents *',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Terms of Service Consent
                              _buildConsentCard(
                                title: 'Terms of Service',
                                description:
                                    'You must accept our Terms of Service to use this app.',
                                value: _acceptedTerms,
                                isRequired: true,
                                onChanged: (value) {
                                  setState(() {
                                    _acceptedTerms = value ?? false;
                                  });
                                },
                                onViewPressed: () => _showPolicyDetails(false),
                                isLoading: _isLoading,
                              ),

                              const SizedBox(height: 16),

                              // Privacy Policy Consent
                              _buildConsentCard(
                                title: 'Privacy Policy',
                                description:
                                    'You must accept our Privacy Policy to use this app.',
                                value: _acceptedPrivacy,
                                isRequired: true,
                                onChanged: (value) {
                                  setState(() {
                                    _acceptedPrivacy = value ?? false;
                                  });
                                },
                                onViewPressed: () => _showPolicyDetails(true),
                                isLoading: _isLoading,
                              ),

                              const SizedBox(height: 32),

                              Text(
                                'Optional Preferences',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Remember Me Preference
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _rememberMe,
                                      onChanged: _isLoading
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _rememberMe = value ?? true;
                                              });
                                            },
                                      activeColor: primaryColor,
                                      checkColor: Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Keep me signed in',
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Recommended for faster access. Uncheck if using a shared device.',
                                            style: TextStyle(
                                              color: secondaryTextColor,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Marketing Communications Preference
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _acceptedMarketing,
                                      onChanged: _isLoading
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _acceptedMarketing =
                                                    value ?? false;
                                              });
                                            },
                                      activeColor: primaryColor,
                                      checkColor: Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Marketing communications',
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Receive updates, promotions, and news about our services. You can unsubscribe anytime.',
                                            style: TextStyle(
                                              color: secondaryTextColor,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Data Usage Information
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: successColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        successColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.security,
                                          color: successColor,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Your Data Rights',
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'You have the right to:',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    _buildBulletPoint(
                                      'Access your personal data',
                                      successColor,
                                    ),
                                    _buildBulletPoint(
                                      'Correct inaccurate data',
                                      successColor,
                                    ),
                                    _buildBulletPoint(
                                      'Delete your data anytime',
                                      successColor,
                                    ),
                                    _buildBulletPoint(
                                      'Opt-out of communications',
                                      successColor,
                                    ),
                                    _buildBulletPoint(
                                      'Export your data',
                                      successColor,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Important Notice
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        Colors.orange.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.info_outline,
                                          color: Colors.orange,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Important Notice',
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'By creating an account, you acknowledge that you have read, understood, and agree to be bound by our Terms of Service and Privacy Policy.',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Error Message (if any)
                              if (_errorMessage != null) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: errorColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          errorColor.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: errorColor,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                            color: errorColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Continue Button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isContinueEnabled
                                      ? _handleContinue
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isContinueEnabled
                                        ? primaryColor
                                        : (isDark
                                            ? Colors.white12
                                            : Colors.grey.shade300),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.check_circle,
                                                size: 20),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Create Account',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Cancel Button
                              Center(
                                child: TextButton(
                                  onPressed:
                                      _isLoading ? null : _handleBackButton,
                                  child: Text(
                                    'Cancel Registration',
                                    style: TextStyle(
                                      color: secondaryTextColor,
                                      fontSize: 14,
                                    ),
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
          },
        ),
      ),
    );
  }

  Widget _buildConsentCard({
    required String title,
    required String description,
    required bool value,
    required bool isRequired,
    required ValueChanged<bool?> onChanged,
    required VoidCallback onViewPressed,
    required bool isLoading,
  }) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? Colors.green.withValues(alpha: 0.3)
              : (isDark ? Colors.white24 : Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: value,
                onChanged: isLoading
                    ? null
                    : (newValue) {
                        onChanged(newValue);
                      },
                activeColor: primaryColor,
                checkColor: Colors.white,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isRequired) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '*',
                            style: TextStyle(color: Colors.red, fontSize: 16),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: isLoading ? null : onViewPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                side: BorderSide(
                  color: primaryColor.withValues(alpha: 0.5),
                ),
                foregroundColor: primaryColor,
              ),
              child: const Text(
                'View Details',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text, Color color) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: color, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}