import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/main.dart';
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
      print('🧹 Clearing all data...');

      // 1. Clear SessionManager (local profiles)
      await SessionManager.clearAll();
      print('✅ SessionManager cleared');

      // 2. Sign out from Supabase
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();
      print('✅ Supabase sign out');

      // 3. Refresh app state
      await appState.refreshState();
      print('✅ AppState refreshed');

      // 4. Navigate directly to login (not splash)
      if (mounted) {
        // Close any open dialogs
        Navigator.popUntil(context, (route) => route.isFirst);

        // Go directly to login
        context.go('/login');
      }
    } catch (e) {
      print('❌ Error clearing data: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;
    final bool isMobile = size.width < 600;

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
                  // ✅ FIXED: Use withOpacity instead of withValues
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      // Back Button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: _isLoading ? null : _handleBackButton,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Main Content
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ✅ FIXED: Changed from Icons.salon to Icons.security
                              Icon(
                                Icons.security,
                                size: isMobile ? 50.0 : 60.0,
                                color: Colors.blue.withOpacity(0.8),
                              ),
                              SizedBox(height: isMobile ? 16.0 : 20.0),
                              const Text(
                                'Data Management',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: isMobile ? 12.0 : 16.0),

                              // Data Collection Info
                              Container(
                                padding: const EdgeInsets.all(16),
                                // ✅ FIXED: Use withOpacity
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'What Data We Store:',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '• Email address (for account login)',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Text(
                                      '• App preferences and settings',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Text(
                                      '• Login session information',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'This data is stored locally on your device and can be cleared at any time.',
                                      style: TextStyle(
                                        color: Colors.white70,
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
                                      : () {
                                          _showConfirmDialog();
                                        },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16.0,
                                    ),
                                    backgroundColor: Colors.red,
                                    disabledBackgroundColor: Colors.grey,
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

                              SizedBox(height: isMobile ? 16.0 : 20.0),

                              // Manage Preferences Button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          context.pop();
                                        },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16.0,
                                    ),
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                  ),
                                  child: Text(
                                    'Manage Preferences',
                                    style: TextStyle(
                                      color: Colors.white,
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
                                child: const Text(
                                  'View Privacy Policy',
                                  style: TextStyle(
                                    color: Colors.blue,
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

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Confirm Clear Data',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove all saved accounts, preferences, and login information from this device. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _clearAllData(); // Call clear function
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
