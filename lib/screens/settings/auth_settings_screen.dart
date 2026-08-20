// screens/settings/auth_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_provider_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
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

  // ✅ Scroll Controller for web
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      case 'email':
        return 'Email & Password';
      case 'google':
        return 'Google';
      case 'facebook':
        return 'Facebook';
      case 'apple':
        return 'Apple';
      default:
        return provider;
    }
  }

  // ✅ Inline provider icon getter
  IconData _getProviderIcon(String provider) {
    switch (provider) {
      case 'email':
        return Icons.email_outlined;
      case 'google':
        return Icons.g_mobiledata;
      case 'facebook':
        return Icons.facebook;
      case 'apple':
        return Icons.apple;
      default:
        return Icons.person_outline;
    }
  }

  // ✅ Inline provider color getter
  Color _getProviderColor(String provider) {
    switch (provider) {
      case 'email':
        return Colors.blue;
      case 'google':
        return const Color(0xFFDB4437);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'apple':
        return Colors.black;
      default:
        return Colors.grey;
    }
  }

  Future<void> _unlinkProvider(String provider) async {
    final hasEmailPassword = _providers.any(
      (p) => p['is_email_password'] == true,
    );
    final oauthProviders = _providers
        .where((p) => p['is_oauth'] == true)
        .toList();

    if (oauthProviders.length <= 1 && !hasEmailPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ You cannot unlink your only authentication method.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Unlink ${_getProviderDisplayName(provider)}?',
          style: context.titleLarge.copyWith(color: context.textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to unlink your ${_getProviderDisplayName(provider)} account?',
              style: context.bodyMedium.copyWith(color: context.textColor),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will not be able to sign in with this provider until you link it again.',
                      style: context.bodySmall.copyWith(color: Colors.orange),
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
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ This is your only authentication method. You may lose access to your account.',
                        style: context.bodySmall.copyWith(color: Colors.red),
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
                content: Text(
                  '✅ ${_getProviderDisplayName(provider)} unlinked successfully',
                ),
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
              content: Text(
                'Error: ${e.toString().replaceFirst('Exception: ', '')}',
              ),
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
              content: Text(
                '✅ ${_getProviderDisplayName(provider)} linked successfully',
              ),
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
            content: Text(
              'Error linking provider: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
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
    final isDark = context.isDarkMode;
    final isEmailPassword = provider['is_email_password'] == true;
    final isOAuth = provider['is_oauth'] == true;
    final providerName = provider['display_name'] as String;
    final providerKey = provider['provider'] as String;
    final icon = _getProviderIcon(providerKey);
    final color = _getProviderColor(providerKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isEmailPassword
              ? Colors.blue.withValues(alpha: 0.3)
              : (isDark
                    ? Colors.grey[700]!
                    : Colors.grey.withValues(alpha: 0.2)),
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
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
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // ✅ Actions - Responsive Wrap
            if (isEmailPassword || isOAuth)
              Container(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    if (isEmailPassword)
                      _buildActionButton(
                        icon: Icons.lock_outline,
                        label: 'Change Password',
                        color: Colors.purple,
                        onPressed: () =>
                            context.push('/settings/change-password'),
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
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : color,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: isDark ? Colors.white : color,
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
    final isDark = context.isDarkMode;

    return OutlinedButton.icon(
      onPressed: () => _linkProvider(provider),
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        'Link $label',
        style: TextStyle(color: isDark ? Colors.white : color),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: isDark
              ? color.withValues(alpha: 0.5)
              : color.withValues(alpha: 0.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        foregroundColor: isDark ? Colors.white : color,
      ),
    );
  }

  // ✅ Info Card
  Widget _buildInfoCard() {
    final isDark = context.isDarkMode;
    final hasEmailPassword = _providers.any(
      (p) => p['is_email_password'] == true,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.blue.withValues(alpha: 0.2)
              : Colors.blue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: isDark ? Colors.blue[300] : Colors.blue[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Authentication Methods',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasEmailPassword
                      ? 'Email & Password is your primary authentication method.'
                      : 'You are using OAuth to sign in.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Link New Provider Section
  Widget _buildLinkNewProviderSection() {
    final isDark = context.isDarkMode;
    final oauthProviders = _providers
        .where((p) => p['is_oauth'] == true)
        .toList();
    final linkedOAuth = oauthProviders
        .map((p) => p['provider'] as String)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E1E)
            : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.grey[700]!
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Link New Account',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
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
              color: isDark
                  ? Colors.orange.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: isDark ? Colors.orange[300] : Colors.orange[700],
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can link multiple OAuth accounts to your profile.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ CONTENT - FIXED
  // ============================================================
  Widget _buildContent() {
    final isDark = context.isDarkMode;
    final hasEmailPassword = _providers.any(
      (p) => p['is_email_password'] == true,
    );
    final oauthProviders = _providers
        .where((p) => p['is_oauth'] == true)
        .toList();
    final linkedOAuth = oauthProviders
        .map((p) => p['provider'] as String)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoCard(),
        const SizedBox(height: 16),

        // ✅ Provider count badge
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_providers.length} authentication method${_providers.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ✅ Show email/password status (uses hasEmailPassword)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          decoration: BoxDecoration(
            color: hasEmailPassword
                ? (isDark
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.05))
                : (isDark
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasEmailPassword
                  ? Colors.blue.withValues(alpha: 0.2)
                  : Colors.orange.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasEmailPassword
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_outlined,
                size: 14,
                color: hasEmailPassword ? Colors.blue[700] : Colors.orange[700],
              ),
              const SizedBox(width: 4),
              Text(
                hasEmailPassword
                    ? 'Email & Password available'
                    : 'No Email & Password set',
                style: TextStyle(
                  fontSize: 11,
                  color: hasEmailPassword
                      ? Colors.blue[700]
                      : Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ✅ Provider List
        ..._providers.map((p) => _buildProviderCard(p)),

        const SizedBox(height: 20),

        // ✅ Show linked OAuth summary (uses linkedOAuth)
        if (oauthProviders.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.green.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  size: 18,
                  color: isDark ? Colors.green[300] : Colors.green[700],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${oauthProviders.length} OAuth account${oauthProviders.length != 1 ? 's' : ''} linked: ${linkedOAuth.join(', ')}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.green[300] : Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // ✅ Link New Provider Section
        if (_providers.length < 4) _buildLinkNewProviderSection(),
      ],
    );
  }

  // ✅ WEB LAYOUT - Centered with Scrollbar
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.right,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildContent(),
    );
  }

  // ============================================================
  // ✅ BUILD METHOD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Authentication Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadProviders,
          ),
        ],
      ),
      // ✅ EDGE-TO-EDGE: SafeArea with Web Frame
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
    );
  }
}
