import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/router/auth_gate.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

final supabase = Supabase.instance.client;

class ContinueScreen extends StatefulWidget {
  const ContinueScreen({super.key});

  @override
  State<ContinueScreen> createState() => _ContinueScreenState();
}

class _ContinueScreenState extends State<ContinueScreen> {
  final EnvironmentManager _env = EnvironmentManager();
  List<Map<String, dynamic>> profiles = [];
  bool _loading = false;
  String? _selectedEmail;
  final Map<String, bool> _oauthLoadingStates = {};
  bool _isGoogleImageRateLimited = false;
  DateTime? _lastGoogleImageError;

  // Selection mode variables
  bool _selectionMode = false;
  Set<String> _selectedProfiles = {};
  int _selectedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _checkCompliance();
  }

  Future<void> _loadProfiles() async {
    try {
      // Load all profiles with remember me enabled
      final allProfiles = await SessionManager.getProfiles();
      final rememberMeProfiles = allProfiles
          .where((p) => p['rememberMe'] == true)
          .toList();

      // Sort profiles: OAuth first, then email
      rememberMeProfiles.sort((a, b) {
        final aProvider = a['provider'] as String? ?? 'email';
        final bProvider = b['provider'] as String? ?? 'email';

        if (aProvider != 'email' && bProvider == 'email') return -1;
        if (aProvider == 'email' && bProvider != 'email') return 1;
        return 0;
      });

      // Process and optimize profile images
      for (var profile in rememberMeProfiles) {
        await _optimizeProfileImage(profile);
      }

      if (!mounted) return;
      setState(() => profiles = rememberMeProfiles);

      if (kDebugMode) {
        debugPrint('Loaded ${profiles.length} profiles for continue screen');
      }
    } catch (e) {
      debugPrint('Error loading profiles: $e');
    }
  }

  Future<void> _optimizeProfileImage(Map<String, dynamic> profile) async {
    try {
      // Try different possible photo keys
      String? photoUrl;

      if (profile['photo'] != null && (profile['photo'] as String).isNotEmpty) {
        photoUrl = profile['photo'] as String;
      } else if (profile['avatar_url'] != null &&
          (profile['avatar_url'] as String).isNotEmpty) {
        photoUrl = profile['avatar_url'] as String;
      } else if (profile['picture'] != null &&
          (profile['picture'] as String).isNotEmpty) {
        photoUrl = profile['picture'] as String;
      } else if (profile['image'] != null &&
          (profile['image'] as String).isNotEmpty) {
        photoUrl = profile['image'] as String;
      }

      if (photoUrl != null && photoUrl.isNotEmpty) {
        // Clean up URL
        photoUrl = photoUrl.replaceAll('"', '').trim();

        // Ensure proper protocol
        if (!photoUrl.startsWith('http')) {
          photoUrl = 'https:$photoUrl';
        }

        // Optimize Google URLs
        if (photoUrl.contains('googleusercontent.com')) {
          photoUrl = _optimizeGoogleProfileUrl(photoUrl) ?? photoUrl;
        }

        // Update profile with optimized URL
        profile['photo'] = photoUrl;
      }
    } catch (e) {
      debugPrint('Error optimizing profile image: $e');
    }
  }

  String? _optimizeGoogleProfileUrl(String? photoUrl) {
    if (photoUrl == null || !photoUrl.contains('googleusercontent.com')) {
      return photoUrl;
    }

    try {
      // Simple optimization for Google URLs
      if (photoUrl.startsWith('//')) {
        photoUrl = 'https:$photoUrl';
      }

      // Check if already has size parameter
      final hasSizeParam =
          photoUrl.contains('=s96') ||
          photoUrl.contains('=s') ||
          photoUrl.contains('?sz=') ||
          photoUrl.contains('/s96-c/');

      if (hasSizeParam) {
        // Replace with larger size if needed
        if (photoUrl.contains('=s96')) {
          photoUrl = photoUrl.replaceAll('=s96', '=s200');
        }
        return photoUrl;
      }

      // Add size parameter if missing
      if (!photoUrl.contains('=s') && !photoUrl.contains('?sz=')) {
        if (photoUrl.contains('?')) {
          return '$photoUrl&sz=200';
        } else {
          return '$photoUrl?sz=200';
        }
      }

      return photoUrl;
    } catch (e) {
      debugPrint('Error optimizing Google URL: $e');
      return photoUrl;
    }
  }

  void _handleGoogleImageError() {
    final now = DateTime.now();

    if (_lastGoogleImageError != null) {
      final difference = now.difference(_lastGoogleImageError!);
      if (difference.inMinutes < 5) {
        _isGoogleImageRateLimited = true;

        // Schedule reset
        Future.delayed(const Duration(minutes: 5), () {
          if (mounted) {
            setState(() {
              _isGoogleImageRateLimited = false;
            });
          }
        });
      }
    }

    _lastGoogleImageError = now;
  }

  Future<void> _checkCompliance() async {
    final rememberMe = await SessionManager.isRememberMeEnabled();
    if (!rememberMe) {
      setState(() {});
    }
  }

  // Handle OAuth login with improved error handling
  Future<void> _handleOAuthLogin(Map<String, dynamic> profile) async {
    if (_selectionMode) {
      _toggleProfileSelection(profile);
      return;
    }

    final email = profile['email'] as String?;
    final provider = profile['provider'] as String?;

    if (email == null || provider == null || provider == 'email') {
      await _handleEmailLogin(profile);
      return;
    }

    if (_oauthLoadingStates[email] == true) return;

    setState(() {
      _oauthLoadingStates[email] = true;
      _selectedEmail = email;
    });

    try {
      if (kDebugMode) {
        print(' Attempting OAuth login for: $email ($provider)');
      }

      // Clear any existing session before starting new OAuth flow
      await supabase.auth.signOut();

      // Add delay to ensure storage is cleared
      await Future.delayed(const Duration(milliseconds: 500));

      // Different handling for each provider
      switch (provider) {
        case 'google':
          await _signInWithGoogle(email);
          break;
        case 'facebook':
          await _signInWithFacebook(email);
          break;
        case 'apple':
          await _signInWithApple(email);
          break;
        default:
          await _handleEmailLogin(profile);
          break;
      }
    } catch (e) {
      debugPrint('OAuth login error: $e');
      if (!mounted) return;

      if (e.toString().contains('Code verifier could not be found')) {
        await showCustomAlert(
          context: context,
          title: "Authentication Error",
          message:
              "Please try signing in again. Clearing browser cache may help.",
          isError: true,
        );
      } else {
        await showCustomAlert(
          context: context,
          title: "Login Failed",
          message: "Unable to sign in with $provider. Please try again.",
          isError: true,
        );
      }

      await _loadProfiles();
    } finally {
      if (mounted) {
        setState(() {
          _oauthLoadingStates[email] = false;
          _selectedEmail = null;
        });
      }
    }
  }

  // Google OAuth login with improved handling
  Future<void> _signInWithGoogle(String email) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) {
        await _processSuccessfulLogin(email);
        return;
      }

      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) {
        await _processSuccessfulLogin(email);
        return;
      }

      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // redirectTo: _getRedirectUrl(),
        redirectTo:_env.getRedirectUrl(),

        scopes: 'email profile',
      );

      final completer = Completer<void>();
      final subscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          final user = supabase.auth.currentUser;
          if (user?.email == email) {
            await _updateUserMetadataAfterOAuth(user!);
            await _processSuccessfulLogin(email);
            completer.complete();
          }
        }
      });

      await completer.future.timeout(const Duration(seconds: 30));
      subscription.cancel();
    } on TimeoutException {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Timeout",
        message: "Google sign in took too long. Please try again.",
        isError: true,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Helper function to update metadata after OAuth
  Future<void> _updateUserMetadataAfterOAuth(User user) async {
    try {
      // ✅ FIXED: Get ALL profiles with role names
      final profiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('id', user.id)
          .eq('is_active', true)
          .eq('is_blocked', false);

      if (profiles.isNotEmpty) {
        // Extract all role names
        final List<String> roleNames = [];
        for (var profile in profiles) {
          final role = profile['roles'] as Map?;
          if (role != null && role['name'] != null) {
            roleNames.add(role['name'].toString());
          }
        }

        // Save to SessionManager
        await SessionManager.saveUserRoles(
          email: user.email!,
          roles: roleNames,
        );

        // Get current role (first one or saved)
        String? currentRole = await SessionManager.getCurrentRole();
        if (currentRole == null || !roleNames.contains(currentRole)) {
          currentRole = roleNames.isNotEmpty ? roleNames.first : 'customer';
          await SessionManager.saveCurrentRole(currentRole);
        }

        // Update metadata
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              ...user.userMetadata ?? {},
              'roles': roleNames,
              'current_role': currentRole,
              'last_login': DateTime.now().toIso8601String(),
            },
          ),
        );

        print(
          '✅ OAuth user metadata updated with roles: $roleNames, current: $currentRole',
        );
      }
    } catch (e) {
      print('❌ Error updating OAuth metadata: $e');
    }
  }

  // Facebook OAuth login with improved handling
  Future<void> _signInWithFacebook(String email) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) {
        await _processSuccessfulLogin(email);
        return;
      }

      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) {
        await _processSuccessfulLogin(email);
        return;
      }

      await supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        // redirectTo: _getRedirectUrl(),
         redirectTo:_env.getRedirectUrl(),
        scopes: 'email',
      );

      final completer = Completer<void>();
      final subscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          final user = supabase.auth.currentUser;
          if (user?.email == email) {
            await _updateUserMetadataAfterOAuth(user!);
            await _processSuccessfulLogin(email);
            completer.complete();
          }
        }
      });

      await completer.future.timeout(const Duration(seconds: 30));
      subscription.cancel();
    } on TimeoutException {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Timeout",
        message: "Facebook sign in took too long. Please try again.",
        isError: true,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Apple OAuth login with improved handling
  Future<void> _signInWithApple(String email) async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) {
        await _processSuccessfulLogin(email);
        return;
      }

      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) {
        await _processSuccessfulLogin(email);
        return;
      }

      await supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        // redirectTo: _getRedirectUrl(),
         redirectTo:_env.getRedirectUrl(),
        scopes: 'email name',
      );

      final completer = Completer<void>();
      final subscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          final user = supabase.auth.currentUser;
          if (user?.email == email) {
            await _updateUserMetadataAfterOAuth(user!);
            await _processSuccessfulLogin(email);
            completer.complete();
          }
        }
      });

      await completer.future.timeout(const Duration(seconds: 30));
      subscription.cancel();
    } on TimeoutException {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Timeout",
        message: "Apple sign in took too long. Please try again.",
        isError: true,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Handle email login
  Future<void> _handleEmailLogin(Map<String, dynamic> profile) async {
    if (_selectionMode) {
      _toggleProfileSelection(profile);
      return;
    }

    if (_loading) return;

    setState(() {
      _loading = true;
      _selectedEmail = profile['email'] as String?;
    });

    try {
      final email = profile['email'] as String?;
      if (email == null) {
        setState(() => _loading = false);
        return;
      }

      final autoLoginSuccess = await SessionManager.tryAutoLogin(email);
      if (autoLoginSuccess) {
        final user = supabase.auth.currentUser;
        if (user != null) {
          // ✅ FIXED: Get ALL profiles with role names
          final dbProfiles = await supabase
              .from('profiles')
              .select('''
                role_id,
                roles!inner (
                  name
                )
              ''')
              .eq('id', user.id)
              .eq('is_active', true)
              .eq('is_blocked', false);

          if (dbProfiles.isNotEmpty) {
            final List<String> roleNames = [];
            for (var profile in dbProfiles) {
              final role = profile['roles'] as Map?;
              if (role != null && role['name'] != null) {
                roleNames.add(role['name'].toString());
              }
            }

            await SessionManager.saveUserRoles(email: email, roles: roleNames);

            String? currentRole = await SessionManager.getCurrentRole();
            if (currentRole == null || !roleNames.contains(currentRole)) {
              currentRole = roleNames.isNotEmpty ? roleNames.first : 'customer';
              await SessionManager.saveCurrentRole(currentRole);
            }

            await supabase.auth.updateUser(
              UserAttributes(
                data: {
                  ...user.userMetadata ?? {},
                  'roles': roleNames,
                  'current_role': currentRole,
                  'last_login': DateTime.now().toIso8601String(),
                },
              ),
            );
          }
        }

        await _processSuccessfulLogin(email);
        return;
      }

      final password = await _showPasswordDialog(email);
      if (password == null || password.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception("Login failed.");

      // ✅ FIXED: Get ALL profiles with role names
      final dbProfiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('id', user.id)
          .eq('is_active', true)
          .eq('is_blocked', false);

      if (dbProfiles.isNotEmpty) {
        final List<String> roleNames = [];
        for (var profile in dbProfiles) {
          final role = profile['roles'] as Map?;
          if (role != null && role['name'] != null) {
            roleNames.add(role['name'].toString());
          }
        }

        await SessionManager.saveUserRoles(email: email, roles: roleNames);

        String? currentRole = await SessionManager.getCurrentRole();
        if (currentRole == null || !roleNames.contains(currentRole)) {
          currentRole = roleNames.isNotEmpty ? roleNames.first : 'customer';
          await SessionManager.saveCurrentRole(currentRole);
        }

        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              ...user.userMetadata ?? {},
              'roles': roleNames,
              'current_role': currentRole,
              'last_login': DateTime.now().toIso8601String(),
            },
          ),
        );

        print(
          '✅ Email login metadata updated with roles: $roleNames, current: $currentRole',
        );
      }

      await _processSuccessfulLogin(email);
    } on AuthException catch (e) {
      if (!mounted) return;

      String errorMessage = e.message;
      if (e.code == 'invalid_credentials') {
        errorMessage = "Invalid email or password. Please try again.";
      }

      await showCustomAlert(
        context: context,
        title: "Login Failed",
        message: errorMessage,
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "Error",
        message: "Unable to login. Please try again.",
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _selectedEmail = null;
        });
      }
    }
  }

  // ✅ FIXED: Process successful login with role-based redirect
  Future<void> _processSuccessfulLogin(String email) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      // Get ALL profiles with roles
      final dbProfiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            is_active,
            is_blocked,
            roles!inner (
              name
            )
          ''')
          .eq('id', user.id)
          .eq('is_active', true)
          .eq('is_blocked', false);

      if (dbProfiles.isEmpty) {
        if (!mounted) return;
        context.go('/reg');
        return;
      }

      // Extract ALL role names
      final List<String> roleNames = [];
      for (var profile in dbProfiles) {
        final role = profile['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }

      // Save to SessionManager
      await SessionManager.saveUserRoles(email: email, roles: roleNames);

      // Get saved current role or use first
      String? savedRole = await SessionManager.getCurrentRole();
      String redirectRole;

      if (savedRole != null && roleNames.contains(savedRole)) {
        redirectRole = savedRole;
        print('📌 Using saved role: $redirectRole');
      } else {
        redirectRole = roleNames.isNotEmpty ? roleNames.first : 'customer';
        await SessionManager.saveCurrentRole(redirectRole);
        print('📌 Using first role: $redirectRole');
      }

      // Update metadata
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            ...user.userMetadata ?? {},
            'roles': roleNames,
            'current_role': redirectRole,
            'last_login': DateTime.now().toIso8601String(),
          },
        ),
      );

      await SessionManager.updateLastLogin(email);
      await appState.refreshState();

      if (!mounted) return;

      // ✅ Role-based redirect
      if (roleNames.length > 1 && savedRole == null) {
        // Multiple roles and no saved preference - show selector
        context.go(
          '/role-selector',
          extra: {'roles': roleNames, 'email': email, 'userId': user.id},
        );
        return;
      }

      // Single role or saved preference - direct redirect
      switch (redirectRole) {
        case 'owner':
          context.go('/owner');
          break;
        case 'barber':
          context.go('/barber');
          break;
        default:
          context.go('/customer');
      }
    } catch (e) {
      debugPrint('Error processing successful login: $e');
      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "Error",
        message: "Unable to complete login. Please try again.",
        isError: true,
      );

      context.go('/login');
    }
  }

  // Redirect URL for OAuth
  String _getRedirectUrl() {
    return 'http://localhost:5000/auth/callback';
  }

  Future<String?> _showPasswordDialog(String email) async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SecurityCompliantPasswordDialog(email: email),
    );
  }

  Color _getProviderColor(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'google':
        return const Color(0xFFDB4437);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'apple':
        return Colors.black;
      default:
        return Colors.blueAccent;
    }
  }

  String _formatLastLogin(String? lastLogin) {
    if (lastLogin == null || lastLogin.isEmpty) return 'Never';

    try {
      final loginTime = DateTime.parse(lastLogin);
      final now = DateTime.now();
      final difference = now.difference(loginTime);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';

      return '${difference.inDays ~/ 7}w ago';
    } catch (e) {
      return 'Recently';
    }
  }

  // Build large profile image
  Widget _buildLargeProfileImage(
    Map<String, dynamic> profile,
    String? provider,
    String? photoUrl,
    bool hasPhoto,
  ) {
    final email = profile['email'] as String? ?? 'Unknown';
    final name = profile['name'] as String? ?? email.split('@').first;
    final isGoogle = provider == 'google';

    if (isGoogle && _isGoogleImageRateLimited && hasPhoto) {
      return _getFallbackAvatar(profile, provider);
    }

    if (hasPhoto) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: Image.network(
            photoUrl!,
            width: 70,
            height: 70,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getProviderColor(provider).withValues(alpha: 0.2),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _getProviderColor(provider),
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Image error: $error');
              if (photoUrl.contains('googleusercontent.com')) {
                _handleGoogleImageError();
              }
              return _getFallbackAvatar(profile, provider);
            },
          ),
        );
      } catch (e) {
        debugPrint('Error loading image: $e');
        return _getFallbackAvatar(profile, provider);
      }
    } else {
      return _getFallbackAvatar(profile, provider);
    }
  }

  // Get fallback avatar
  Widget _getFallbackAvatar(Map<String, dynamic> profile, String? provider) {
    final email = profile['email'] as String? ?? 'Unknown';
    final name = profile['name'] as String? ?? email.split('@').first;
    final isOAuth = provider != 'email';

    if (isOAuth) {
      return Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _getProviderColor(provider),
        ),
        child: Center(
          child: provider == 'google'
              ? Text(
                  'G',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                )
              : provider == 'facebook'
              ? Text(
                  'f',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                )
              : provider == 'apple'
              ? const Icon(Icons.apple, color: Colors.white, size: 28)
              : const Icon(Icons.email, color: Colors.white, size: 24),
        ),
      );
    }

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blueAccent.withValues(alpha: 0.2),
      ),
      child: Center(
        child: Text(
          name[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
    );
  }

  void _toggleProfileSelection(Map<String, dynamic> profile) {
    final email = profile['email'] as String? ?? '';
    setState(() {
      if (_selectedProfiles.contains(email)) {
        _selectedProfiles.remove(email);
      } else {
        _selectedProfiles.add(email);
      }
      _selectedCount = _selectedProfiles.length;

      if (_selectedCount == 0) {
        _selectionMode = false;
      }
    });
  }

  void _selectAllProfiles() {
    setState(() {
      _selectedProfiles = Set<String>.from(
        profiles
            .map((p) => p['email'] as String? ?? '')
            .where((e) => e.isNotEmpty),
      );
      _selectedCount = _selectedProfiles.length;
    });
  }

  void _deselectAllProfiles() {
    setState(() {
      _selectedProfiles.clear();
      _selectedCount = 0;
      _selectionMode = false;
    });
  }

  Future<void> _removeSelectedProfiles() async {
    if (_selectedProfiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Remove Selected Profiles?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove $_selectedCount profile${_selectedCount == 1 ? '' : 's'} from this device?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will not delete your accounts, only remove them from this device.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final email in _selectedProfiles) {
        await SessionManager.removeProfile(email);
      }

      await _loadProfiles();
      _deselectAllProfiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_selectedCount profile${_selectedCount == 1 ? '' : 's'} removed',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _removeSingleProfile(String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Remove Profile?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove $email from this device?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will not delete your account, only remove it from this device.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SessionManager.removeProfile(email);
      await _loadProfiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$email removed'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _startSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedProfiles.clear();
      _selectedCount = 0;
    });
  }

  // Profile card for main list
  Widget _buildProfileCard(Map<String, dynamic> profile, int index) {
    final email = profile['email'] as String? ?? 'Unknown';
    final provider = profile['provider'] as String? ?? 'email';
    final isSelected = _selectedProfiles.contains(email);
    final isLoading = _oauthLoadingStates[email] == true;
    final photoUrl = profile['photo'] as String?;
    final name = profile['name'] as String? ?? email.split('@').first;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    // ✅ Get roles for display
    final List<String> roles =
        (profile['roles'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleProfileSelection(profile);
        } else if (isLoading) {
          return;
        } else if (provider == 'email') {
          _handleEmailLogin(profile);
        } else {
          _handleOAuthLogin(profile);
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          _startSelectionMode();
          _toggleProfileSelection(profile);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1877F2).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLoading
                ? Colors.blueAccent
                : isSelected
                ? const Color(0xFF1877F2)
                : Colors.white.withValues(alpha: 0.1),
            width: isLoading ? 2 : 1.5,
          ),
          boxShadow: isLoading
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Profile Image
              Stack(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getProviderColor(provider).withValues(alpha: 0.2),
                    ),
                    child: _buildLargeProfileImage(
                      profile,
                      provider,
                      photoUrl,
                      hasPhoto,
                    ),
                  ),

                  // Provider icon badge
                  if (provider != 'email' && !_selectionMode && !isLoading)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getProviderColor(provider),
                          border: Border.all(
                            color: const Color(0xFF0F1820),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: provider == 'google'
                              ? Text(
                                  'G',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto',
                                  ),
                                )
                              : provider == 'facebook'
                              ? Text(
                                  'f',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto',
                                  ),
                                )
                              : provider == 'apple'
                              ? const Icon(
                                  Icons.apple,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : const Icon(
                                  Icons.email,
                                  color: Colors.white,
                                  size: 12,
                                ),
                        ),
                      ),
                    ),

                  // Selection check badge
                  if (isSelected && _selectionMode)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueAccent,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 16),

              // Profile Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row for name and loading indicator
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Simple loading text
                        if (isLoading)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Logging in...',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Email
                    Text(
                      email,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // Last login and roles
                    // Provider type, last login and role in the same row
                    Row(
                      children: [
                        // Last login time
                        if (profile['lastLogin'] != null && !isLoading)
                          Text(
                            _formatLastLogin(profile['lastLogin'] as String?),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),

                        // 👇 Conditionally add space only if both elements exist
                        if (profile['lastLogin'] != null &&
                            !isLoading &&
                            profile['roles'] != null &&
                            (profile['roles'] as List).isNotEmpty &&
                            !_selectionMode)
                          const SizedBox(width: 10),

                        // Role indicator
                        if (profile['roles'] != null &&
                            (profile['roles'] as List).isNotEmpty &&
                            !_selectionMode &&
                            !isLoading)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (profile['roles'] as List).first
                                  .toString()
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow indicator
              if (!_selectionMode && !isLoading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.white38,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    final double maxWidth = isWeb ? 450 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              height: screenSize.height,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  // Logo at the top
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
                                  borderRadius: BorderRadius.circular(40),
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
                            ],
                          ),
                        ),
                      ),

                      // 3-dot menu at top right corner
                      if (profiles.isNotEmpty && !_selectionMode)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            child: PopupMenuButton<String>(
                              color: const Color(0xFF1C1F26),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Manage Profiles',
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'select',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Remove Selected',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.manage_accounts,
                                        color: Colors.blueAccent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Manage Account Data',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'select') {
                                  _startSelectionMode();
                                } else if (value == 'remove') {
                                  context.go('/clear-data');
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Card for profiles
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          // Header with selection mode
                          if (_selectionMode)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                                border: const Border(
                                  bottom: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: _buildSelectionModeHeader(),
                            ),

                          // Profiles List
                          Expanded(
                            child: _loading && _selectedEmail != null
                                ? _buildLoadingState()
                                : profiles.isEmpty
                                ? _buildEmptyState()
                                : _buildProfilesList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer
                  if (!_selectionMode) _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
          ),
          const SizedBox(height: 15),
          const Text(
            'Logging in...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (_selectedEmail != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _selectedEmail!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_add_disabled,
            size: 60,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 15),
          const Text(
            'No Saved Profiles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enable "Remember Me" during login\nto save your profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilesList() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildProfileCard(profiles[index], index),
        );
      },
    );
  }

  Widget _buildSelectionModeHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: _deselectAllProfiles,
          tooltip: 'Cancel Selection',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$_selectedCount selected',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Tap to select/deselect',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                _selectedCount == profiles.length
                    ? Icons.deselect
                    : Icons.select_all,
                color: Colors.blueAccent,
                size: 24,
              ),
              onPressed: _selectedCount == profiles.length
                  ? _deselectAllProfiles
                  : _selectAllProfiles,
              tooltip: _selectedCount == profiles.length
                  ? 'Deselect All'
                  : 'Select All',
            ),
            if (_selectedCount > 0)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 24,
                ),
                onPressed: _removeSelectedProfiles,
                tooltip: 'Remove Selected',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Add Another Account',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/signup'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF1877F2)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Create New Account',
                style: TextStyle(
                  color: Color(0xFF1877F2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.go('/privacy'),
                child: const Text(
                  'Privacy',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Container(width: 1, height: 12, color: Colors.white30),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/terms'),
                child: const Text(
                  'Terms',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Container(width: 1, height: 12, color: Colors.white30),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/help'),
                child: const Text(
                  'Help',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Security Compliant Password Dialog (unchanged)
class SecurityCompliantPasswordDialog extends StatefulWidget {
  final String email;
  const SecurityCompliantPasswordDialog({super.key, required this.email});
  @override
  State<SecurityCompliantPasswordDialog> createState() =>
      _SecurityCompliantPasswordDialogState();
}

class _SecurityCompliantPasswordDialogState
    extends State<SecurityCompliantPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscurePassword = true;
  bool _isValid = false;
  bool _isSubmitting = false;
  Timer? _typingTimer;
  int _typedCharacters = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final newLength = _controller.text.length;

    if (newLength > _typedCharacters) {
      _typedCharacters = newLength;
    }

    setState(() {
      _isValid = newLength >= 6;
    });

    _handleAutoSubmit();
  }

  void _handleAutoSubmit() {
    _typingTimer?.cancel();

    if (_controller.text.length >= 6 && !_isSubmitting && mounted) {
      _typingTimer = Timer(const Duration(milliseconds: 2000), () {
        if (!_isSubmitting && mounted) {
          _submitPassword();
        }
      });
    }
  }

  Future<void> _submitPassword() async {
    if (_isSubmitting || !_isValid) return;

    setState(() => _isSubmitting = true);

    _typingTimer?.cancel();

    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;

    final enteredPassword = _controller.text.trim();
    Navigator.pop(context, enteredPassword);
  }

  void _clearPassword() {
    _controller.clear();
    _typedCharacters = 0;
    setState(() {
      _isValid = false;
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;

    double dialogWidth = isWeb
        ? screenSize.width * 0.25
        : screenSize.width * 0.85;
    final double calculatedWidth = dialogWidth.clamp(300.0, 400.0).toDouble();

    return Dialog(
      backgroundColor: const Color(0xFF1C1F26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWeb ? (screenSize.width - calculatedWidth) / 2 : 20,
        vertical: isWeb ? 100 : 20,
      ),
      child: Container(
        width: calculatedWidth,
        padding: EdgeInsets.all(isWeb ? 24 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.email,
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_controller.text.isNotEmpty && !_isSubmitting)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    color: Colors.white70,
                    onPressed: _clearPassword,
                    tooltip: 'Clear',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    TextField(
                      controller: _controller,
                      obscureText: _obscurePassword,
                      autofocus: true,
                      enabled: !_isSubmitting,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'Type at least 6 characters',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_controller.text.isNotEmpty)
                              IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: _isSubmitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                              ),
                            if (_isValid && !_isSubmitting)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.greenAccent,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.black,
                                  size: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (value) => _submitPassword(),
                    ),
                    if (_isSubmitting)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_controller.text.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _controller.text.length / 6,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _controller.text.length >= 6
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_controller.text.length}/6',
                          style: TextStyle(
                            color: _controller.text.length >= 6
                                ? Colors.greenAccent
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (_isValid && !_isSubmitting)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.flash_auto,
                      color: Colors.greenAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Auto-login enabled',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isValid && !_isSubmitting
                      ? _submitPassword
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.blueAccent.withValues(
                      alpha: 0.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
