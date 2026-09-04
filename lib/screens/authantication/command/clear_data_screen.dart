import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClearDataScreen extends StatefulWidget {
  const ClearDataScreen({super.key});

  @override
  State<ClearDataScreen> createState() => _ClearDataScreenState();
}

class _ClearDataScreenState extends State<ClearDataScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _isLoading = false;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
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

  void _handleBackButton() {
    if (!_isLoading) {
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/continue');
      }
    }
  }

  Future<void> _clearAllData() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      await SessionManager.clearAll();

      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();

      await appState.refreshState();

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
        context.go('/login');
      }
    } catch (e) {
      debugPrint('❌ Error clearing data: $e');

      if (mounted) {
        final errorColor = context.errorColor;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

void _showConfirmDialog() {
  final isDark = context.isDarkMode;
  final textColor = context.textColor;
  final secondaryTextColor = context.secondaryTextColor;
  final errorColor = context.errorColor;

  final screenWidth = MediaQuery.of(context).size.width;
  final isWeb = screenWidth > 700;
  final dialogWidth = isWeb ? 420.0 : screenWidth * 0.9;

  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.8, // ✅ give it real room
        ),
        child: SingleChildScrollView( // ✅ scroll instead of overflow
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm Clear Data',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This will remove all saved accounts, preferences, and login information from this device. This action cannot be undone.',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: secondaryTextColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _clearAllData();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: errorColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final errorColor = context.errorColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;
    final bool isMobile = size.width < 600;

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
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cardColor,
                        isDark
                            ? Colors.white.withValues(alpha: 0.03)
                            : Colors.grey.shade50,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Back Button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: textColor,
                            size: 22,
                          ),
                          onPressed: _isLoading ? null : _handleBackButton,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Main Content
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon
                              Icon(
                                Icons.security,
                                size: isMobile ? 50.0 : 60.0,
                                color: primaryColor.withValues(alpha: 0.8),
                              ),
                              SizedBox(height: isMobile ? 16.0 : 20.0),
                              Text(
                                'Data Management',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 22.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: isMobile ? 12.0 : 16.0),

                              // ✅ FIXED: Data Collection Info - Added mainAxisSize: MainAxisSize.min
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: primaryColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min, // ✅ FIX: Prevents overflow
                                  children: [
                                    Text(
                                      'What Data We Store:',
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '• Email address (for account login)',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '• App preferences and settings',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '• Login session information',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'This data is stored locally on your device and can be cleared at any time.',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: isMobile ? 24.0 : 32.0),

                              // Clear Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _showConfirmDialog,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16.0,
                                    ),
                                    backgroundColor: errorColor,
                                    disabledBackgroundColor: isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[300],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : Text(
                                          'Clear All Data',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: isMobile ? 15.0 : 16.0,
                                          ),
                                        ),
                                ),
                              ),

                              SizedBox(height: isMobile ? 8.0 : 12.0),

                              // Privacy Policy Link
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        context.push(
                                          '/privacy?from=${Uri.encodeComponent('/clear-data')}',
                                        );
                                      },
                                child: Text(
                                  'View Privacy Policy',
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
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