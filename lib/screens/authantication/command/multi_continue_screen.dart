import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/router/auth_gate.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:cached_network_image/cached_network_image.dart';

final supabase = Supabase.instance.client;

class ContinueScreen extends StatefulWidget {
  const ContinueScreen({super.key});

  @override
  State<ContinueScreen> createState() => _ContinueScreenState();
}

class _ContinueScreenState extends State<ContinueScreen> {
  List<Map<String, dynamic>> profiles = [];
  bool _loading = false;
  String? _selectedEmail;
  bool _showComplianceDialog = false;
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
          photoUrl.contains('?sz=') ||
          photoUrl.contains('/s96-c/');

      if (hasSizeParam) {
        return photoUrl; // Already optimized
      }

      // Add size parameter if missing
      if (!photoUrl.contains('=s') && !photoUrl.contains('?sz=')) {
        if (photoUrl.contains('?')) {
          return '$photoUrl&sz=96';
        } else {
          return '$photoUrl?sz=96';
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

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkCompliance() async {
    final rememberMe = await SessionManager.isRememberMeEnabled();
    if (!rememberMe) {
      setState(() {
        _showComplianceDialog = true;
      });
    }
  }

  // Get provider icon with color
  Widget _getProviderIcon(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'google':
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFDB4437),
          ),
          child: Center(
            child: Text(
              'G',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        );
      case 'facebook':
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1877F2),
          ),
          child: Center(
            child: Text(
              'f',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        );
      case 'apple':
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: const Center(
            child: Icon(Icons.apple, color: Colors.white, size: 22),
          ),
        );
      default:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blueAccent,
          ),
          child: const Center(
            child: Icon(Icons.email, color: Colors.white, size: 20),
          ),
        );
    }
  }

  // Get provider icon small (for list)
  Widget _getProviderIconSmall(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'google':
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFDB4437),
          ),
          child: Center(
            child: Text(
              'G',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        );
      case 'facebook':
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1877F2),
          ),
          child: Center(
            child: Text(
              'f',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        );
      case 'apple':
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: const Center(
            child: Icon(Icons.apple, color: Colors.white, size: 12),
          ),
        );
      default:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blueAccent,
          ),
          child: const Center(
            child: Icon(Icons.email, color: Colors.white, size: 10),
          ),
        );
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

      // ✅ Check for specific code verifier error
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

      // ✅ Force reload after error
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
      // Check if already logged in
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) {
        await _processSuccessfulLogin(email);
        return;
      }

      // Try auto-login first
      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) {
        await _processSuccessfulLogin(email);
        return;
      }

      // Initialize OAuth flow with proper parameters
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _getRedirectUrl(),
        scopes: 'email profile',
      );

      // Listen for auth state changes
      final completer = Completer<void>();
      final subscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          final user = supabase.auth.currentUser;
          if (user?.email == email) {
            await _processSuccessfulLogin(email);
            completer.complete();
          }
        }
      });

      // Wait for login with timeout
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
        redirectTo: _getRedirectUrl(),
        scopes: 'email',
      );

      final completer = Completer<void>();
      final subscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          final user = supabase.auth.currentUser;
          if (user?.email == email) {
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
        redirectTo: _getRedirectUrl(),
        scopes: 'email name',
      );

      final completer = Completer<void>();
      final subscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          final user = supabase.auth.currentUser;
          if (user?.email == email) {
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

  // Handle email login (existing password dialog)
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

      // 1 Try auto-login
      final autoLoginSuccess = await SessionManager.tryAutoLogin(email);
      if (autoLoginSuccess) {
        await _processSuccessfulLogin(email);
        return;
      }

      // 2️ Show password dialog
      final password = await _showPasswordDialog(email);
      if (password == null || password.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // 3️ Manual login
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception("Login failed.");

      await _processSuccessfulLogin(email);
    } on AuthException catch (e) {
      if (!mounted) return;

      switch (e.code) {
        case 'invalid_login_credentials':
          await showCustomAlert(
            context: context,
            title: "Login Failed",
            message: "Email or password is incorrect.",
            isError: true,
          );
          break;

        case 'email_not_confirmed':
          appState.emailVerifyerError();
          appState.refreshState();
          if (!mounted) return;
          context.go('/verify-email');
          break;

        case 'too_many_requests':
          await showCustomAlert(
            context: context,
            title: "Too Many Attempts ⏳",
            message: "Please wait a few minutes and try again.",
            isError: true,
          );
          break;

        default:
          await showCustomAlert(
            context: context,
            title: "Login Error",
            message: e.message,
            isError: true,
          );
      }
      await _loadProfiles();
    } catch (e) {
      debugPrint('Login error: $e');
      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "Connection Error",
        message: "Please check your internet connection.",
        isError: false,
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

  // Process successful login
  Future<void> _processSuccessfulLogin(String email) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Get profile from database
      final dbProfile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      if (dbProfile == null) {
        if (!mounted) return;
        context.go('/reg');
        return;
      }

      // Get role
      final role = AuthGate.pickRole(dbProfile['role'] ?? dbProfile['roles']);

      // Save role
      await SessionManager.saveUserRole(role);
      await SessionManager.updateLastLogin(email);

      // Update app state
      appState.refreshState();

      if (!mounted) return;

      // Navigate based on role
      switch (role) {
        case 'business':
          context.go('/owner');
          break;
        case 'employee':
          context.go('/employee');
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
    }
  }

  // Redirect URL for OAuth
  String _getRedirectUrl() {
    // return 'com.yourcompany.mysalon://auth-callback';
    return 'http://localhost:5000/auth/callback';
  }

  // ✅ Password dialog (existing)
  Future<String?> _showPasswordDialog(String email) async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SecurityCompliantPasswordDialog(email: email),
    );
  }

  // Get provider color
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

  // Format last login time
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

  // Build profile image with error handling
  Widget _buildProfileImage(
    Map<String, dynamic> profile,
    String? provider,
    String? photoUrl,
    bool hasPhoto,
  ) {
    final email = profile['email'] as String? ?? 'Unknown';
    final name = profile['name'] as String? ?? email.split('@').first;
    final isOAuth = provider != 'email';
    final isGoogle = provider == 'google';

    // Check if we should use fallback due to rate limiting
    if (isGoogle && _isGoogleImageRateLimited && hasPhoto) {
      return _getFallbackAvatar(profile, provider);
    }

    if (hasPhoto) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: Container(
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
          ),
          errorWidget: (context, url, error) {
            // Handle Google rate limiting errors
            if (url.contains('googleusercontent.com')) {
              _handleGoogleImageError();
              return _getFallbackAvatar(profile, provider);
            }
            return _getFallbackAvatar(profile, provider);
          },
        ),
      );
    } else {
      return Center(
        child: isOAuth
            ? _getProviderIcon(provider)
            : Container(
                width: 56,
                height: 56,
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
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
      );
    }
  }

  // Get fallback avatar
  Widget _getFallbackAvatar(Map<String, dynamic> profile, String? provider) {
    final email = profile['email'] as String? ?? 'Unknown';
    final name = profile['name'] as String? ?? email.split('@').first;
    final isOAuth = provider != 'email';
    final isGoogle = provider == 'google';

    if (isGoogle) {
      return Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4285F4),
              Color(0xFF34A853),
              Color(0xFFFBBC05),
              Color(0xFFEA4335),
            ],
          ),
        ),
        child: Center(
          child: Text(
            name[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Roboto',
            ),
          ),
        ),
      );
    }

    if (isOAuth) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _getProviderColor(provider),
        ),
        child: Center(
          child: isGoogle
              ? Text(
                  'G',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                )
              : provider == 'facebook'
              ? Text(
                  'f',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                )
              : provider == 'apple'
              ? const Icon(Icons.apple, color: Colors.white, size: 22)
              : const Icon(Icons.email, color: Colors.white, size: 20),
        ),
      );
    }

    return Container(
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
            fontSize: 20,
          ),
        ),
      ),
    );
  }

  //Toggle profile selection
  void _toggleProfileSelection(Map<String, dynamic> profile) {
    final email = profile['email'] as String? ?? '';
    setState(() {
      if (_selectedProfiles.contains(email)) {
        _selectedProfiles.remove(email);
      } else {
        _selectedProfiles.add(email);
      }
      _selectedCount = _selectedProfiles.length;

      // Exit selection mode if nothing selected
      if (_selectedCount == 0) {
        _selectionMode = false;
      }
    });
  }

  // Select all profiles
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

  // Deselect all profiles
  void _deselectAllProfiles() {
    setState(() {
      _selectedProfiles.clear();
      _selectedCount = 0;
      _selectionMode = false;
    });
  }

  // Remove selected profiles
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

  // Start selection mode
  void _startSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedProfiles.clear();
      _selectedCount = 0;
    });
  }

  //Build profile item for selection mode
  Widget _buildProfileItem(Map<String, dynamic> profile, int index) {
    final email = profile['email'] as String? ?? 'Unknown';
    final provider = profile['provider'] as String? ?? 'email';
    final isOAuth = provider != 'email';
    final isSelected = _selectedProfiles.contains(email);
    final isLoading = _oauthLoadingStates[email] == true;
    final rememberMe = profile['rememberMe'] == true;

    // Get name properly
    final name = profile['name'] as String? ?? email.split('@').first;

    // Get photo URL
    final photoUrl = profile['photo'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleProfileSelection(profile);
        } else if (isLoading) {
          return;
        } else if (isOAuth) {
          _handleOAuthLogin(profile);
        } else {
          _handleEmailLogin(profile);
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          _startSelectionMode();
          _toggleProfileSelection(profile);
        }
      },
      child: Card(
        color: isSelected
            ? Colors.blue.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? Colors.blueAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Selection Checkbox
              if (_selectionMode)
                Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    _toggleProfileSelection(profile);
                  },
                  activeColor: Colors.blueAccent,
                  checkColor: Colors.white,
                ),

              SizedBox(width: _selectionMode ? 8 : 0),

              // Profile Image
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOAuth
                          ? _getProviderColor(provider).withValues(alpha: 0.2)
                          : Colors.blueAccent.withValues(alpha: 0.2),
                    ),
                    child: _buildProfileImage(
                      profile,
                      provider,
                      photoUrl,
                      hasPhoto,
                    ),
                  ),

                  // Provider icon badge
                  if (isOAuth && !_selectionMode)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getProviderColor(provider),
                          border: Border.all(
                            color: const Color(0xFF0F1820),
                            width: 2,
                          ),
                        ),
                        child: Center(child: _getProviderIconSmall(provider)),
                      ),
                    ),

                  // Selection check badge
                  if (isSelected && _selectionMode)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueAccent,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),

                  // Remember me badge
                  if (rememberMe && !isOAuth && !_selectionMode)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 12),

              // Profile Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blueAccent,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      email,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Provider and last login info
                    if (!_selectionMode)
                      Row(
                        children: [
                          // Provider indicator
                          // if (isOAuth)
                          //   Container(
                          //     margin: const EdgeInsets.only(right: 8),
                          //     padding: const EdgeInsets.symmetric(
                          //       horizontal: 8,
                          //       vertical: 2,
                          //     ),
                          //     decoration: BoxDecoration(
                          //       color: _getProviderColor(provider).withOpacity(0.2),
                          //       borderRadius: BorderRadius.circular(12),
                          //       border: Border.all(
                          //         color: _getProviderColor(provider).withOpacity(0.5),
                          //       ),
                          //     ),
                          //     child: Row(
                          //       mainAxisSize: MainAxisSize.min,
                          //       children: [
                          //         _getProviderIconSmall(provider),
                          //         const SizedBox(width: 4),
                          //         Text(
                          //           provider.toUpperCase(),
                          //           style: TextStyle(
                          //             color: _getProviderColor(provider),
                          //             fontSize: 10,
                          //             fontWeight: FontWeight.bold,
                          //           ),
                          //         ),
                          //       ],
                          //     ),
                          //   ),

                          // Last login time
                          if (profile['lastLogin'] != null)
                            Text(
                              _formatLastLogin(profile['lastLogin'] as String?),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),

                    // Role indicator
                    if (profile['roles'] != null &&
                        (profile['roles'] as List).isNotEmpty &&
                        !_selectionMode)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (profile['roles'] as List).first.toString(),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Arrow indicator (only when not in selection mode)
              if (!_selectionMode && !isLoading)
                Icon(
                  isOAuth ? Icons.login : Icons.arrow_forward_ios_rounded,
                  color: isOAuth ? Colors.greenAccent : Colors.white38,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Clear all profiles (original function)
  // Future<void> _clearAllProfiles() async {
  //   if (profiles.isEmpty) return;

  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       backgroundColor: const Color(0xFF1C1F26),
  //       title: const Text(
  //         "Clear All Profiles?",
  //         style: TextStyle(color: Colors.white),
  //       ),
  //       content: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(
  //             "Remove all ${profiles.length} saved profiles from this device?",
  //             style: const TextStyle(color: Colors.white70),
  //           ),
  //           const SizedBox(height: 8),
  //           const Text(
  //             "This will clear all saved login information and preferences.",
  //             style: TextStyle(color: Colors.grey, fontSize: 12),
  //           ),
  //           const SizedBox(height: 8),
  //           const Text(
  //             "Your accounts will not be deleted, only removed from this device.",
  //             style: TextStyle(color: Colors.grey, fontSize: 12),
  //           ),
  //         ],
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: const Text(
  //             "Cancel",
  //             style: TextStyle(color: Colors.white70),
  //           ),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: TextButton.styleFrom(foregroundColor: Colors.red),
  //           child: const Text("Clear All"),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed == true) {
  //     for (final profile in profiles) {
  //       await SessionManager.removeProfile(profile['email'] as String);
  //     }

  //     await SessionManager.clearContinueScreen();
  //     await SessionManager.setRememberMe(false);
  //     await _loadProfiles();

  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('All profiles cleared'),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //   }
  // }

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
                  // Header with selection mode
                  if (_selectionMode)
                    _buildSelectionModeHeader()
                  else
                    _buildNormalHeader(),

                  const SizedBox(height: 20),

                  // Compliance Notice
                  if (_showComplianceDialog && !_selectionMode)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Remember Me Disabled',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enable "Remember Me" during login to save profiles',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Rate limiting notice
                  if (_isGoogleImageRateLimited && !_selectionMode)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: Colors.orangeAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Google Profile Images Limited',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Using fallback images to prevent rate limiting',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Selection instructions
                  if (_selectionMode)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_selectedCount profile${_selectedCount == 1 ? '' : 's'} selected',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap profiles to select/deselect',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Profiles List
                  Expanded(
                    child: _loading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blueAccent,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                const Text(
                                  'Logging in...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_selectedEmail != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      _selectedEmail!,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : profiles.isEmpty
                        ? Center(
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
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: profiles.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildProfileItem(
                                  profiles[index],
                                  index,
                                ),
                              );
                            },
                          ),
                  ),

                  // Footer Buttons (only when not in selection mode)
                  if (!_selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        children: [
                          // Login with another account
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                context.go('/login');
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Login with another account',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Clear all data button
                          TextButton(
                            onPressed: () => context.go('/clear-data'),
                            child: const Text(
                              'Clear All Data',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Privacy links
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => context.go('/privacy'),
                                child: const Text(
                                  'Privacy Policy',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 1,
                                height: 12,
                                color: Colors.white30,
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => context.go('/terms'),
                                child: const Text(
                                  'Terms of Service',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Create new account
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                context.go('/signup');
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF1877F3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: const Text(
                                'Create new account',
                                style: TextStyle(
                                  color: Color(0xFF1877F3),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
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

  // Build normal header
  Widget _buildNormalHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
         // Empty space on left to balance the row
      Container(width: 48), // Same width as the button area on right
      
      // Logo in center
      Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.asset(
              'logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),

        // Column(
        // crossAxisAlignment: CrossAxisAlignment.start,
        // children: [
        //   const Text(
        //     'Continue',
        //     style: TextStyle(
        //       color: Colors.white,
        //       fontSize: 24,
        //       fontWeight: FontWeight.bold,
        //     ),
        //   ),
        //   const SizedBox(height: 4),
        //   Text(
        //     profiles.isEmpty
        //         ? 'No saved profiles'
        //         : '${profiles.length} profile${profiles.length == 1 ? '' : 's'}',
        //     style: TextStyle(
        //       color: Colors.white.withOpacity(0.7),
        //       fontSize: 12,
        //     ),
        //   ),
        // ],
        // ),
        if (profiles.isNotEmpty)
          Row(
            children: [
              // Selection mode button
              // IconButton(
              //   icon: const Icon(
              //     Icons.check_circle_outline,
              //     color: Colors.blueAccent,
              //     size: 24,
              //   ),
              //   onPressed: _startSelectionMode,
              //   tooltip: 'Select Profiles',
              // ),
              // Delete all button
              IconButton(
                icon: const Icon(
                  Icons.delete_sweep,
                  color: Colors.redAccent,
                  size: 24,
                ),
                // onPressed: _clearAllProfiles,
                onPressed: _startSelectionMode,
                tooltip: 'Clear All Profiles',
              ),
            ],
          ),
      ],
    );
  }

  // ✅ Build selection mode header
  Widget _buildSelectionModeHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Back button
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: _deselectAllProfiles,
          tooltip: 'Cancel Selection',
        ),

        // Selection count
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

        // Action buttons
        Row(
          children: [
            // Select all button
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
            // Delete selected button
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
}

// Security Compliant Password Dialog (Remains the same)
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

    // Update typed characters count
    if (newLength > _typedCharacters) {
      _typedCharacters = newLength;
    }

    // Validate password
    setState(() {
      _isValid = newLength >= 6;
    });

    // Handle auto-submit
    _handleAutoSubmit();
  }

  void _handleAutoSubmit() {
    // Cancel previous timer
    _typingTimer?.cancel();

    // Start auto-submit timer if conditions met
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

    // Clear any active timer
    _typingTimer?.cancel();

    // Add small delay for smooth UX
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
            // Header
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

                // Clear button
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

            // Password Field with Progress
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
                            // Visibility toggle
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

                            // Auto-submit indicator
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

                    // Loading overlay
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

                // Password strength indicator
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

            // Auto-login info
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
                          // Text(
                          //   'Login will proceed automatically',
                          //   style: TextStyle(
                          //     color: Colors.white.withOpacity(0.7),
                          //     fontSize: 10,
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Action Buttons
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
