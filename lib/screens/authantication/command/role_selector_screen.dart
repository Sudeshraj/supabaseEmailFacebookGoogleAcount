import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

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
        context.showErrorSnackBar('Error selecting role: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Get role config using context extensions
  Map<String, dynamic> _getRoleConfig(BuildContext context) {
    final successColor = context.successColor;
    final warningColor = context.warningColor;
    final infoColor = context.infoColor;

    return {
      'owner': {
        'title': 'Business Owner',
        'icon': Icons.business_center_rounded,
        'color': infoColor,
        'gradient': [infoColor, infoColor.withValues(alpha: 0.7)],
        'badge': '👑',
      },
      'barber': {
        'title': 'Barber',
        'icon': Icons.content_cut_rounded,
        'color': warningColor,
        'gradient': [warningColor, warningColor.withValues(alpha: 0.7)],
        'badge': '✂️',
      },
      'customer': {
        'title': 'Customer',
        'icon': Icons.people_rounded,
        'color': successColor,
        'gradient': [successColor, successColor.withValues(alpha: 0.7)],
        'badge': '👤',
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final isWeb = context.isWeb;

    // ✅ Get role config from context
    final roleConfig = _getRoleConfig(context);

    final List<String> safeRoles = widget.roles
        .map((e) => e.toString())
        .toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF1A2A3A),
                        const Color(0xFF0F1820),
                      ]
                    : [
                        Colors.grey.shade100,
                        Colors.white,
                      ],
              ),
            ),
          ),

          // Decorative circles - using context colors
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
                    context.warningColor.withValues(alpha: 0.1),
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
                    context.infoColor.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

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
                    context.successColor.withValues(alpha: 0.1),
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
                          // Header with logo/icon
                          Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  context.warningColor,
                                  context.infoColor,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: context.warningColor.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.account_circle_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),

                          Text(
                            'Choose Your Role',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 52),

                          // Role cards
                          ..._buildRoleCards(safeRoles, roleConfig),

                          if (_isLoading)
                            Container(
                              margin: const EdgeInsets.only(top: 40),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(
                                    color: primaryColor,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Setting up your dashboard...',
                                    style: TextStyle(
                                      color: secondaryTextColor,
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
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500,
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

  List<Widget> _buildRoleCards(
    List<String> safeRoles,
    Map<String, dynamic> roleConfig,
  ) {
    final List<Widget> cards = [];

    for (int i = 0; i < safeRoles.length; i++) {
      final role = safeRoles[i];
      final config = roleConfig[role];

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
    required VoidCallback onTap,
  }) {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
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
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.02),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.8),
                      Colors.white.withValues(alpha: 0.6),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
            ),
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
              // Icon with gradient background
              Container(
                width: isSmallScreen ? 50 : 70,
                height: isSmallScreen ? 50 : 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
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
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: isSmallScreen ? 25 : 35,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textColor,
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
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade100,
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