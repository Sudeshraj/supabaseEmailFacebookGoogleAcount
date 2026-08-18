import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/auth_provider_service.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthProviderService _authService = AuthProviderService();
  bool _hasEmailPassword = false;
  bool _hasOAuth = false;
  int _oauthCount = 0;
  bool _isLoading = true;

  // ✅ Theme state
  ThemeMode _currentTheme = ThemeMode.system;

  // ✅ GlobalKey for Scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _checkAuthProviders();
    _loadThemeMode();
    themeNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    setState(() {
      _currentTheme = themeNotifier.currentTheme;
    });
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    final themeMode = await SessionManager.getThemeMode();
    setState(() {
      _currentTheme = themeMode == 'light' 
          ? ThemeMode.light 
          : themeMode == 'dark' 
              ? ThemeMode.dark 
              : ThemeMode.system;
    });
  }

  void _changeTheme(ThemeMode mode) {
    themeNotifier.setTheme(mode);
    setState(() {
      _currentTheme = mode;
    });
  }

  Future<void> _checkAuthProviders() async {
    setState(() => _isLoading = true);
    try {
      final providers = await _authService.getUserAuthProviders();
      _hasEmailPassword = providers.any((p) => p['is_email_password'] == true);
      _hasOAuth = providers.any((p) => p['is_oauth'] == true);
      _oauthCount = providers.where((p) => p['is_oauth'] == true).length;
    } catch (e) {
      debugPrint('❌ Error checking auth providers: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final isTablet = screenWidth > 600 && screenWidth <= 800;
    final contentWidth = isWeb ? 1000.0 : double.infinity;

    return Scaffold(
      key: _scaffoldKey,
      drawer: SideMenu(
        userRole: appState.currentRole ?? 'customer',
        userName: appState.currentUser?.userMetadata?['full_name'] ?? 'User',
        userEmail: appState.currentEmail,
        profileImageUrl: appState.currentUser?.userMetadata?['avatar_url'],
        selectedSalonId: null,
        onMenuItemSelected: () {},
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
          tooltip: 'Menu',
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: context.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _checkAuthProviders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: context.primaryColor,
              ),
            )
          : Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWeb ? 24 : 16,
                    vertical: 8,
                  ),
                  children: [
                    // ============================================================
                    // ✅ THEME SECTION - Dashboard Card Style
                    // ============================================================
                    _buildSectionHeader('Appearance'),

                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isTablet ? 20 : 16),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
                        border: Border.all(
                          color: context.dividerColor,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(isTablet ? 12 : 10),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                                ),
                                child: Icon(
                                  Icons.palette_outlined,
                                  color: Colors.purple[400],
                                  size: isTablet ? 24 : 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Theme',
                                      style: context.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: context.textColor,
                                        fontSize: isTablet ? 18 : 16,
                                      ),
                                    ),
                                    Text(
                                      _getThemeModeText(),
                                      style: context.bodySmall.copyWith(
                                        color: context.secondaryTextColor,
                                        fontSize: isTablet ? 14 : 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // ✅ Responsive Theme Options
                          isWeb || isTablet
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildThemeOption(
                                      icon: Icons.brightness_auto,
                                      label: 'System',
                                      mode: ThemeMode.system,
                                      isSelected: _currentTheme == ThemeMode.system,
                                      isTablet: isTablet,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildThemeOption(
                                      icon: Icons.brightness_5,
                                      label: 'Light',
                                      mode: ThemeMode.light,
                                      isSelected: _currentTheme == ThemeMode.light,
                                      isTablet: isTablet,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildThemeOption(
                                      icon: Icons.brightness_2,
                                      label: 'Dark',
                                      mode: ThemeMode.dark,
                                      isSelected: _currentTheme == ThemeMode.dark,
                                      isTablet: isTablet,
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildThemeOption(
                                      icon: Icons.brightness_auto,
                                      label: 'System',
                                      mode: ThemeMode.system,
                                      isSelected: _currentTheme == ThemeMode.system,
                                      isTablet: false,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildThemeOption(
                                      icon: Icons.brightness_5,
                                      label: 'Light',
                                      mode: ThemeMode.light,
                                      isSelected: _currentTheme == ThemeMode.light,
                                      isTablet: false,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildThemeOption(
                                      icon: Icons.brightness_2,
                                      label: 'Dark',
                                      mode: ThemeMode.dark,
                                      isSelected: _currentTheme == ThemeMode.dark,
                                      isTablet: false,
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    Divider(
                      color: context.dividerColor,
                      height: 1,
                    ),
                    const SizedBox(height: 8),

                    // ============================================================
                    // ✅ PROFILE MANAGEMENT SECTION
                    // ============================================================
                    _buildSectionHeader('Profile Management'),

                    _buildSettingsTile(
                      icon: Icons.people_outline,
                      iconColor: context.primaryColor,
                      title: 'Manage Profiles',
                      subtitle: 'Switch between your owner, barber, or customer roles',
                      onTap: () => context.push('/settings/profiles'),
                      isTablet: isTablet,
                    ),

                    const SizedBox(height: 8),
                    Divider(
                      color: context.dividerColor,
                      height: 1,
                    ),
                    const SizedBox(height: 8),

                    // ============================================================
                    // ✅ ACCOUNT SECTION
                    // ============================================================
                    _buildSectionHeader('Account'),

                    _buildSettingsTile(
                      icon: Icons.person_outline,
                      iconColor: Colors.blue,
                      title: 'Personal Information',
                      subtitle: 'Edit your profile details',
                      onTap: () => context.push('/profile'),
                      isTablet: isTablet,
                    ),

                    if (_hasEmailPassword)
                      _buildSettingsTile(
                        icon: Icons.lock_outline,
                        iconColor: Colors.purple,
                        title: 'Change Password',
                        subtitle: 'Update your account password',
                        onTap: () => context.push('/settings/change-password'),
                        isTablet: isTablet,
                      ),

                    _buildSettingsTile(
                      icon: Icons.security_outlined,
                      iconColor: Colors.green,
                      title: 'Authentication Settings',
                      subtitle: _hasOAuth
                          ? 'Manage connected accounts (Google, Facebook, Apple)'
                          : 'Manage your authentication methods',
                      onTap: () => context.push('/settings/auth'),
                      isTablet: isTablet,
                      badge: _hasOAuth ? '$_oauthCount' : null,
                    ),

                    _buildSettingsTile(
                      icon: Icons.delete_forever_outlined,
                      iconColor: Colors.red,
                      title: 'Delete Account',
                      subtitle: 'Permanently delete your account and data',
                      onTap: () => context.push('/settings/delete-account'),
                      isTablet: isTablet,
                    ),

                    const SizedBox(height: 8),
                    Divider(
                      color: context.dividerColor,
                      height: 1,
                    ),
                    const SizedBox(height: 8),

                    // ============================================================
                    // ✅ PREFERENCES SECTION
                    // ============================================================
                    _buildSectionHeader('Preferences'),

                    _buildSettingsTile(
                      icon: Icons.notifications_outlined,
                      iconColor: Colors.orange,
                      title: 'Notifications',
                      subtitle: 'Manage your notification preferences',
                      onTap: () {
                        final role = appState.currentRole ?? 'customer';
                        context.push('/notifications?role=$role');
                      },
                      isTablet: isTablet,
                    ),

                    _buildSettingsTile(
                      icon: Icons.language_outlined,
                      iconColor: Colors.purple,
                      title: 'Language',
                      subtitle: 'Select your preferred language',
                      onTap: () {},
                      isTablet: isTablet,
                    ),

                    const SizedBox(height: 8),
                    Divider(
                      color: context.dividerColor,
                      height: 1,
                    ),
                    const SizedBox(height: 8),

                    // ============================================================
                    // ✅ SUPPORT SECTION
                    // ============================================================
                    _buildSectionHeader('Support'),

                    _buildSettingsTile(
                      icon: Icons.help_outline,
                      iconColor: Colors.grey,
                      title: 'Help & Support',
                      subtitle: 'Get help or contact support',
                      onTap: () => context.push('/help'),
                      isTablet: isTablet,
                    ),

                    _buildSettingsTile(
                      icon: Icons.info_outline,
                      iconColor: Colors.grey,
                      title: 'About',
                      subtitle: 'App version and information',
                      onTap: () => context.push('/about'),
                      isTablet: isTablet,
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  // ============================================================
  // ✅ SETTINGS TILE WIDGET (Reusable)
  // ============================================================
  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isTablet,
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
      ),
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(isTablet ? 10 : 8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: isTablet ? 24 : 22,
          ),
        ),
        title: Text(
          title,
          style: context.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: context.textColor,
            fontSize: isTablet ? 16 : 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: context.bodySmall.copyWith(
            color: context.secondaryTextColor,
            fontSize: isTablet ? 14 : 13,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null)
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
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: isTablet ? 12 : 10,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios,
              size: isTablet ? 18 : 16,
              color: context.secondaryTextColor,
            ),
          ],
        ),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isTablet ? 20 : 16,
          vertical: isTablet ? 8 : 4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
        ),
        splashColor: iconColor.withValues(alpha: 0.1),
        hoverColor: iconColor.withValues(alpha: 0.05),
      ),
    );
  }

  // ============================================================
  // ✅ THEME OPTION WIDGET
  // ============================================================
  Widget _buildThemeOption({
    required IconData icon,
    required String label,
    required ThemeMode mode,
    required bool isSelected,
    required bool isTablet,
  }) {
    final isDark = context.isDarkMode;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTheme(mode),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: isTablet ? 16 : 12,
            horizontal: isTablet ? 12 : 8,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFFF6B8B).withValues(alpha: 0.1))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFFF6B8B)
                  : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFFFF6B8B)
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                size: isTablet ? 32 : 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: context.bodySmall.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? const Color(0xFFFF6B8B)
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  fontSize: isTablet ? 14 : 12,
                ),
              ),
              if (isSelected)
                const SizedBox(height: 2),
              if (isSelected)
                Container(
                  width: isTablet ? 20 : 16,
                  height: isTablet ? 4 : 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getThemeModeText() {
    switch (_currentTheme) {
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
      default:
        return 'System Default';
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Text(
        title,
        style: context.bodySmall.copyWith(
          fontWeight: FontWeight.w600,
          color: context.secondaryTextColor,
          letterSpacing: 0.5,
          fontSize: context.isTablet ? 14 : 13,
        ),
      ),
    );
  }
}