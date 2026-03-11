
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class RoleSelectorScreen extends StatefulWidget {
  final List<String> roles;
  final String email;
  final String userId;

  const RoleSelectorScreen({
    super.key,
    required this.roles,
    required this.email,
    required this.userId,
  });

  @override
  State<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends State<RoleSelectorScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Your colors from the design
  final Color _customerGreen = Color(0xFF43A047);
  final Color _businessBlue = Color(0xFF1E88E5);
  final Color _employeeOrange = Color(0xFFFF9800); // Barber color

  // Role icons and colors mapping - updated with your colors
  final Map<String, dynamic> _roleConfig = {
    'owner': {
      'title': 'Business Owner',
      'icon': Icons.business_center_rounded,
      'color': const Color(0xFF1E88E5), // Your business blue
      'gradient': [const Color(0xFF1E88E5), const Color(0xFF1E88E5)],
      'badge': '👑',
    },
    'barber': {
      'title': 'Barber',
      'icon': Icons.content_cut_rounded,
      'color': const Color(0xFFFF9800), // Your employee orange/pink
      'gradient': [const Color(0xFFFF9800), const Color(0xFFFF9800)],
      'badge': '✂️',
    },
    'customer': {
      'title': 'Customer',
      'icon': Icons.people_rounded,
      'color': const Color(0xFF43A047), // Your customer green
      'gradient': [const Color(0xFF43A047), const Color(0xFF43A047)],
      'badge': '👤',
    },
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _selectRole(String role) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      await SessionManager.saveCurrentRole(role);
      await appState.refreshState();

      if (!mounted) return;

      switch (role) {
        case 'owner':
          context.go('/owner');
          break;
        case 'barber':
          context.go('/barber');
          break;
        case 'customer':
          context.go('/customer');
          break;
        default:
          context.go('/');
          break;
      }
    } catch (e) {     
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting role: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

    final List<String> safeRoles = widget.roles
        .map((e) => e.toString())
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: Stack(
        children: [
          // Background gradient - updated with your colors
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFF1A2A3A), const Color(0xFF0F1820)],
              ),
            ),
          ),

          // Decorative circles - updated with your colors
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _employeeOrange.withValues(alpha: 0.1), // Your barber color
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _businessBlue.withValues(alpha: 0.1), // Your owner color
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Add third decorative circle for customer
          Positioned(
            top: 50,
            left: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _customerGreen.withValues(
                      alpha: 0.1,
                    ), // Your customer color
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isWeb ? 40 : 24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: isWeb ? 600 : double.infinity,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header with logo/icon - updated with your colors gradient
                          Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _employeeOrange, // Your barber color
                                  _businessBlue, // Your owner color
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _employeeOrange.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.account_circle_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),

                          const Text(
                            'Choose Your Role',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 52),

                          // Role cards
                          ..._buildRoleCards(safeRoles),

                          if (_isLoading)
                            Container(
                              margin: const EdgeInsets.only(top: 40),
                              child: Column(
                                children: [
                                  const CircularProgressIndicator(
                                    color: Color(0xFFFF6B8B),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Setting up your dashboard...',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 30),

                          // Footer
                          Text(
                            'You can switch roles anytime from settings',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRoleCards(List<String> safeRoles) {
    final List<Widget> cards = [];

    for (int i = 0; i < safeRoles.length; i++) {
      final role = safeRoles[i];
      final config = _roleConfig[role];

      if (config != null) {
        cards.add(
          TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 500 + (i * 100)),
            curve: Curves.easeOutBack,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: _buildRoleCard(
              title: config['title'],

              icon: config['icon'],
              gradient: config['gradient'],
              color: config['color'],
              badge: config['badge'],
              onTap: () => _selectRole(role),
            ),
          ),
        );

        if (i < safeRoles.length - 1) {
          cards.add(const SizedBox(height: 16));
        }
      }
    }

    return cards;
  }

  Widget _buildRoleCard({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required Color color,
    required String badge,
    required VoidCallback onTap,
  }) {
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon with gradient background - updated with your role colors
              Container(
                width: isSmallScreen ? 50 : 70,
                height: isSmallScreen ? 50 : 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient, // This already has your colors
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 15,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Center(
                  child: Stack(
                    children: [
                      Icon(
                        icon,
                        color: Colors.white,
                        size: isSmallScreen ? 25 : 35,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: isSmallScreen ? 10 : 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmallScreen ? 16 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),

              // Arrow with glow effect
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: color,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
