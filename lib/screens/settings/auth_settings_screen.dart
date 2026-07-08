// screens/settings/auth_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_provider_service.dart';
import 'package:go_router/go_router.dart';

class AuthSettingsScreen extends StatefulWidget {
  const AuthSettingsScreen({super.key});

  @override
  State<AuthSettingsScreen> createState() => _AuthSettingsScreenState();
}

class _AuthSettingsScreenState extends State<AuthSettingsScreen> {
  final AuthProviderService _authService = AuthProviderService();
  List<Map<String, dynamic>> _providers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() => _isLoading = true);
    try {
      final providers = await _authService.getUserAuthProviders();
      setState(() {
        _providers = providers;
        _isLoading = false;
      });
      debugPrint('📋 Loaded providers: $providers');
    } catch (e) {
      debugPrint('❌ Error loading providers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ✅ Helper method to get provider display name
  String _getProviderDisplayName(String provider) {
    switch (provider) {
      case 'email': return 'Email & Password';
      case 'google': return 'Google';
      case 'facebook': return 'Facebook';
      case 'apple': return 'Apple';
      default: return provider;
    }
  }

  // ✅ Inline provider icon getter (used directly in _buildProviderCard)
  IconData _getProviderIcon(String provider) {
    switch (provider) {
      case 'email': return Icons.email_outlined;
      case 'google': return Icons.g_mobiledata;
      case 'facebook': return Icons.facebook;
      case 'apple': return Icons.apple;
      default: return Icons.person_outline;
    }
  }

  // ✅ Inline provider color getter (used directly in _buildProviderCard)
  Color _getProviderColor(String provider) {
    switch (provider) {
      case 'email': return Colors.blue;
      case 'google': return const Color(0xFFDB4437);
      case 'facebook': return const Color(0xFF1877F2);
      case 'apple': return Colors.black;
      default: return Colors.grey;
    }
  }

  Future<void> _unlinkProvider(String provider) async {
    // ✅ Check if this is the only auth method
    final hasEmailPassword = _providers.any((p) => p['is_email_password'] == true);
    final oauthProviders = _providers.where((p) => p['is_oauth'] == true).toList();

    // ✅ If only one OAuth and no email/password, cannot unlink
    if (oauthProviders.length <= 1 && !hasEmailPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ You cannot unlink your only authentication method.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // ✅ Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Unlink ${_getProviderDisplayName(provider)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to unlink your ${_getProviderDisplayName(provider)} account?',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will not be able to sign in with this provider until you link it again.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            if (oauthProviders.length <= 1 && !hasEmailPassword)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ This is your only authentication method. You may lose access to your account.',
                        style: TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final success = await _authService.unlinkProvider(provider);
        if (success) {
          await _loadProviders();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ ${_getProviderDisplayName(provider)} unlinked successfully'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception('Failed to unlink provider');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _linkProvider(String provider) async {
    setState(() => _isLoading = true);
    try {
      final success = await _authService.linkProvider(provider);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${_getProviderDisplayName(provider)} linked successfully'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        await _loadProviders();
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error linking provider: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ✅ UI BUILDERS
  // ============================================================

  Widget _buildProviderCard(Map<String, dynamic> provider) {
    final isEmailPassword = provider['is_email_password'] == true;
    final isOAuth = provider['is_oauth'] == true;
    final providerName = provider['display_name'] as String;
    final providerKey = provider['provider'] as String;
    final icon = _getProviderIcon(providerKey);
    final color = _getProviderColor(providerKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isEmailPassword 
              ? Colors.blue.withValues(alpha: 0.3) 
              : Colors.grey.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        providerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isEmailPassword)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'Primary',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (isOAuth)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'Connected',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEmailPassword
                        ? 'Sign in with email and password'
                        : 'Sign in with $providerName account',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // ✅ Actions
            if (isEmailPassword)
              _buildActionButton(
                icon: Icons.lock_outline,
                label: 'Change Password',
                color: Colors.purple,
                onPressed: () => context.push('/settings/change-password'),
              ),
            if (isOAuth)
              _buildActionButton(
                icon: Icons.link_off,
                label: 'Unlink',
                color: Colors.red,
                onPressed: () => _unlinkProvider(providerKey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildLinkButton({
    required String provider,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _linkProvider(provider),
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        'Link $label',
        style: TextStyle(color: color),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEmailPassword = _providers.any((p) => p['is_email_password'] == true);
    final oauthProviders = _providers.where((p) => p['is_oauth'] == true).toList();
    final linkedOAuth = oauthProviders.map((p) => p['provider'] as String).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Authentication Settings'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProviders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF6B8B),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue[700],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Authentication Methods',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hasEmailPassword
                                    ? 'Email & Password is your primary authentication method.'
                                    : 'You are using OAuth to sign in.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ✅ Provider List
                  ..._providers.map((p) => _buildProviderCard(p)),

                  const SizedBox(height: 20),

                  // ✅ Link New Provider Section
                  if (_providers.length < 4)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Link New Account',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (!linkedOAuth.contains('google'))
                                _buildLinkButton(
                                  provider: 'google',
                                  label: 'Google',
                                  color: const Color(0xFFDB4437),
                                  icon: Icons.g_mobiledata,
                                ),
                              if (!linkedOAuth.contains('facebook'))
                                _buildLinkButton(
                                  provider: 'facebook',
                                  label: 'Facebook',
                                  color: const Color(0xFF1877F2),
                                  icon: Icons.facebook,
                                ),
                              if (!linkedOAuth.contains('apple'))
                                _buildLinkButton(
                                  provider: 'apple',
                                  label: 'Apple',
                                  color: Colors.black,
                                  icon: Icons.apple,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.orange[700],
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'You can link multiple OAuth accounts to your profile.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}