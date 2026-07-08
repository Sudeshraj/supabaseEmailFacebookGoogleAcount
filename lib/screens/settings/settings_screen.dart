import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/services/auth_provider_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthProviderService _authService = AuthProviderService();
  bool _hasEmailPassword = false;
  bool _hasOAuth = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthProviders();
  }

  Future<void> _checkAuthProviders() async {
    setState(() => _isLoading = true);
    try {
      final providers = await _authService.getUserAuthProviders();
      _hasEmailPassword = providers.any((p) => p['is_email_password'] == true);
      _hasOAuth = providers.any((p) => p['is_oauth'] == true);
    } catch (e) {
      debugPrint('❌ Error checking auth providers: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkAuthProviders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF6B8B),
              ),
            )
          : ListView(
              children: [
                // ============================================================
                // ✅ PROFILE MANAGEMENT SECTION
                // ============================================================
                _buildSectionHeader('Profile Management'),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B8B).withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.people_outline,
                      color: Color(0xFFFF6B8B),
                    ),
                  ),
                  title: const Text('Manage Profiles'),
                  subtitle: const Text('Switch, deactivate, or delete profiles'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/settings/profiles');
                  },
                ),

                const Divider(),

                // ============================================================
                // ✅ ACCOUNT SECTION
                // ============================================================
                _buildSectionHeader('Account'),

                // ✅ Personal Information
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline, color: Colors.blue),
                  ),
                  title: const Text('Personal Information'),
                  subtitle: const Text('Edit your profile details'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/profile');
                  },
                ),

                // ✅ Change Password - Only for Email/Password users
                if (_hasEmailPassword)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha:0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline, color: Colors.purple),
                    ),
                    title: const Text('Change Password'),
                    subtitle: const Text('Update your account password'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      context.push('/settings/change-password');
                    },
                  ),

                // ✅ Authentication Settings - OAuth Management
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_outlined, color: Colors.green),
                  ),
                  title: const Text('Authentication Settings'),
                  subtitle: _hasOAuth
                      ? const Text('Manage connected accounts (Google, Facebook, Apple)')
                      : const Text('Manage your authentication methods'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasOAuth)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha:0.3),
                            ),
                          ),
                          child: Text(
                            '${_getOAuthCount()}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                  onTap: () {
                    context.push('/settings/auth');
                  },
                ),

                const Divider(),

                // ============================================================
                // ✅ PREFERENCES SECTION
                // ============================================================
                _buildSectionHeader('Preferences'),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_outlined, color: Colors.orange),
                  ),
                  title: const Text('Notifications'),
                  subtitle: const Text('Manage your notification preferences'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // Get current role for notifications
                    final role = 'customer'; // You can get from SessionManager
                    context.push('/notifications?role=$role');
                  },
                ),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.language_outlined, color: Colors.purple),
                  ),
                  title: const Text('Language'),
                  subtitle: const Text('Select your preferred language'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // Navigate to language
                  },
                ),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.palette_outlined, color: Colors.teal),
                  ),
                  title: const Text('Theme'),
                  subtitle: const Text('Choose light or dark theme'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    // Navigate to theme
                  },
                ),

                const Divider(),

                // ============================================================
                // ✅ SUPPORT SECTION
                // ============================================================
                _buildSectionHeader('Support'),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.help_outline, color: Colors.grey),
                  ),
                  title: const Text('Help & Support'),
                  subtitle: const Text('Get help or contact support'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/help');
                  },
                ),

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.info_outline, color: Colors.grey),
                  ),
                  title: const Text('About'),
                  subtitle: const Text('App version and information'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/about');
                  },
                ),

                const SizedBox(height: 20)
              ],
            ),
    );
  }

  int _getOAuthCount() {
    // This would come from AuthProviderService
    // For now, return a placeholder
    return 0;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}