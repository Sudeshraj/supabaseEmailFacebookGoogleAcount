import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:go_router/go_router.dart';

import '../../../services/session_manager.dart';

class WelcomeScreen extends StatefulWidget {
  final void Function(String) onNext;

  const WelcomeScreen({super.key, required this.onNext});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Pre-cached colors for better performance
  static const Color _primaryBg = Color(0xFF0F1820);
  static const Color _customerGreen = Color(0xFF43A047);
  static const Color _businessBlue = Color(0xFF1E88E5);
  static const Color _employeeOrange = Color(0xFFFF9800);

  @override
  void initState() {
    super.initState();
    
    // Optimized animation duration
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Logout function
  Future<void> _handleLogout() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      ),
    );

    try {
      await SessionManager.logoutForContinue();
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        appState.refreshState();
        context.go('/');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  /// Optimized role card with better image handling
  Widget _roleCard({
    required String image,
    required String title,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: accentColor.withValues(alpha: 0.2),
        highlightColor: accentColor.withValues(alpha: 0.1),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Optimized image loading
                  Image.asset(
                    image,
                    fit: BoxFit.cover,
                    cacheWidth: 300, // Optimize image size
                    cacheHeight: 400,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[900],
                        child: Icon(
                          title == 'Customer' ? Icons.person : 
                          title == 'Business' ? Icons.business : 
                          Icons.work,
                          color: accentColor.withValues(alpha: 0.3),
                          size: 50,
                        ),
                      );
                    },
                  ),
                  
                  // Semi-transparent overlay with gradient
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            accentColor.withValues(alpha: 0.5),
                            accentColor.withValues(alpha: 0.8),
                          ],
                          stops: const [0.4, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                  
                  // Title with better visibility
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
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
    );
  }

  /// Optimized action button with better tap area
  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(color: color.withValues(alpha: 0.5), width: 1),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

@override
Widget build(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final bool isWeb = size.width > 700;
  final bool isTablet = size.width > 600 && size.width <= 700;
  final double maxWidth = isWeb ? 560 : (isTablet ? 600 : double.infinity);
  final double horizontalPadding = isWeb ? 32.0 : 20.0;

  return Scaffold(
    backgroundColor: _primaryBg,
    body: SafeArea(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: isWeb ? 32 : 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ NEW HEADER - Matches ContinueScreen style
                    Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 25),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 2,
                                    ),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF1877F2),
                                        Color(0xFF0A58CA),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF1877F2,
                                        ).withValues(alpha: 0.4),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.asset(
                                      'logo.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Center(
                                          child: Icon(
                                            Icons.account_circle,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                const Text(
                                  'Welcome to MySaloon',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Choose your role to continue',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Role Cards
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _roleCard(
                            image: 'saloncus.png',
                            title: 'Customer',
                            accentColor: _customerGreen,
                            onTap: () => widget.onNext('customer'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _roleCard(
                            image: 'salon.png',
                            title: 'Salon',
                            accentColor: _businessBlue,
                            onTap: () => widget.onNext('owner'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _roleCard(
                            image: 'barber.png', // Change to employee image
                            title: 'Barber',
                            accentColor: _employeeOrange,
                            onTap: () => widget.onNext('employee'),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Description
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: const Text(
                        'Create an account to connect with trusted salons, discover new styles, and grow your business — all in one place.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Action Buttons
                    _actionButton(
                      label: 'Create customer account',
                      color: _customerGreen,
                      icon: Icons.person_add_alt_1,
                      onPressed: () => widget.onNext('customer'),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    _actionButton(
                      label: ' Create salon account',
                      color: _businessBlue,
                      icon: Icons.storefront,
                      onPressed: () => widget.onNext('owner'),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    _actionButton(
                      label: 'Create Barber account',
                      color: _employeeOrange,
                      icon: Icons.person_add,
                      onPressed: () => widget.onNext('employee'),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Logout link (replaced Login text)
                    Center(
                      child: TextButton(
                        onPressed: _handleLogout,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.logout,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Sign Out', // Changed to "Sign Out" for better UX
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
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