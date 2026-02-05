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
  Map<String, bool> _oauthLoadingStates = {};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _checkCompliance();
    
    // Debug profiles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _debugProfiles();
    });
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
      
      if (!mounted) return;
      setState(() => profiles = rememberMeProfiles);
      
      if (kDebugMode) {
        print('📊 Loaded ${profiles.length} profiles for continue screen');
        for (var profile in profiles) {
          print('   - ${profile['email']} (${profile['provider']}) - Remember Me: ${profile['rememberMe']}');
        }
      }
    } catch (e) {
      print('❌ Error loading profiles: $e');
    }
  }

  Future<void> _debugProfiles() async {
    if (kDebugMode) {
      print('🔍 === DEBUG PROFILES ===');
      for (int i = 0; i < profiles.length; i++) {
        final profile = profiles[i];
        final email = profile['email'] as String? ?? 'Unknown';
        final photo = profile['photo'] as String?;
        final hasPhoto = photo != null && photo.isNotEmpty;
        
        print('Profile #${i + 1}: $email');
        print('   - Has photo: $hasPhoto');
        print('   - Photo URL: ${hasPhoto ? photo : "None"}');
        print('   - Provider: ${profile['provider']}');
        print('   - All keys: ${profile.keys.toList()}');
        print('---');
      }
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

  // ✅ Get provider icon
  Widget _getProviderIcon(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'google':
        return Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            'G',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Roboto',
            ),
          ),
        );
      case 'facebook':
        return Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            'f',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Roboto',
            ),
          ),
        );
      case 'apple':
        return const Icon(
          Icons.apple,
          color: Colors.white,
          size: 20,
        );
      default:
        return const Icon(
          Icons.email,
          color: Colors.white,
          size: 18,
        );
    }
  }

  // ✅ Handle OAuth login
  Future<void> _handleOAuthLogin(Map<String, dynamic> profile) async {
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
        print('🔄 Attempting OAuth login for: $email ($provider)');
      }

      // ✅ Different handling for each provider
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
      print('❌ OAuth login error: $e');
      if (!mounted) return;
      
      await showCustomAlert(
        context: context,
        title: "Login Failed",
        message: "Unable to sign in with $provider. Please try again.",
        isError: true,
      );
    } finally {
      setState(() {
        _oauthLoadingStates[email] = false;
        _selectedEmail = null;
      });
    }
  }

  // ✅ Google OAuth login
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

      // Show loading indicator
      if (!mounted) return;
      
      // Start OAuth flow
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

  // ✅ Facebook OAuth login
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

  // ✅ Apple OAuth login
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

  // ✅ Handle email login (existing password dialog)
  Future<void> _handleEmailLogin(Map<String, dynamic> profile) async {
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

      // 1️⃣ Try auto-login
      final autoLoginSuccess = await SessionManager.tryAutoLogin(email);
      if (autoLoginSuccess) {
        await _processSuccessfulLogin(email);
        return;
      }

      // 2️⃣ Show password dialog
      final password = await _showPasswordDialog(email);
      if (password == null || password.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // 3️⃣ Manual login
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
            title: "Login Failed ❌",
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
            title: "Login Error ❌",
            message: e.message,
            isError: true,
          );
      }
      await _loadProfiles();
    } catch (e) {
      print('❌ Login error: $e');
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

  // ✅ Process successful login
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
      print('❌ Error processing successful login: $e');
      if (!mounted) return;
      
      await showCustomAlert(
        context: context,
        title: "Error",
        message: "Unable to complete login. Please try again.",
        isError: true,
      );
    }
  }

  // ✅ Redirect URL for OAuth
  String _getRedirectUrl() {
    return 'com.yourcompany.mysalon://auth-callback';
  }

  // ✅ Password dialog (existing)
  Future<String?> _showPasswordDialog(String email) async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SecurityCompliantPasswordDialog(email: email),
    );
  }

  // ✅ Get provider color
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

  // ✅ NEW: Format last login time
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

  // ✅ FIXED: Build profile item with proper photo handling
  Widget _buildProfileItem(Map<String, dynamic> profile, int index) {
    final email = profile['email'] as String? ?? 'Unknown';
    final provider = profile['provider'] as String? ?? 'email';
    final isOAuth = provider != 'email';
    final isSelected = _selectedEmail == email;
    final isLoading = _oauthLoadingStates[email] == true;
    final rememberMe = profile['rememberMe'] == true;
    
    // ✅ FIXED: Get name properly
    final name = profile['name'] as String? ?? email.split('@').first;
    
    // ✅ FIXED: Get photo properly - check all possibilities
    String? photoUrl;
    
    // Try different possible photo keys
    if (profile['photo'] != null && (profile['photo'] as String).isNotEmpty) {
      photoUrl = profile['photo'] as String;
    } else if (profile['avatar_url'] != null && (profile['avatar_url'] as String).isNotEmpty) {
      photoUrl = profile['avatar_url'] as String;
    } else if (profile['picture'] != null && (profile['picture'] as String).isNotEmpty) {
      photoUrl = profile['picture'] as String;
    } else if (profile['image'] != null && (profile['image'] as String).isNotEmpty) {
      photoUrl = profile['image'] as String;
    }
    
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return GestureDetector(
      onTap: isLoading ? null : () {
        if (isOAuth) {
          _handleOAuthLogin(profile);
        } else {
          _handleEmailLogin(profile);
        }
      },
      child: Card(
        color: isSelected
            ? Colors.blue.withOpacity(0.15)
            : Colors.white.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected
                ? Colors.blueAccent.withOpacity(0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: ListTile(
          leading: Stack(
            children: [
              // ✅ FIXED: Profile image with proper loading and error handling
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOAuth
                      ? _getProviderColor(provider)
                      : Colors.blueAccent.withOpacity(0.2),
                ),
                child: hasPhoto
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: CachedNetworkImage(
                          imageUrl: photoUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _getProviderColor(provider),
                            ),
                          ),
                          errorWidget: (context, url, error) => Center(
                            child: isOAuth
                                ? _getProviderIcon(provider)
                                : Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      )
                    : Center(
                        child: isOAuth
                            ? _getProviderIcon(provider)
                            : Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
              ),
              
              // Remember me badge
              if (rememberMe)
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
          title: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isOAuth)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getProviderColor(provider).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getProviderColor(provider).withOpacity(0.5),
                    ),
                  ),
                  child: Text(
                    provider.toUpperCase(),
                    style: TextStyle(
                      color: _getProviderColor(provider),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Last login time
              if (profile['lastLogin'] != null)
                Text(
                  'Last login: ${_formatLastLogin(profile['lastLogin'] as String?)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                  ),
                ),
              if (isOAuth && isLoading)
                const SizedBox(height: 4),
              if (isOAuth && isLoading)
                const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  minHeight: 2,
                ),
            ],
          ),
          trailing: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (profile['roles'] != null &&
                        (profile['roles'] as List).isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
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
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      onPressed: () async {
                        await _showDeleteConfirmation(profile);
                      },
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isOAuth ? Icons.login : Icons.arrow_forward_ios_rounded,
                      color: isOAuth ? Colors.greenAccent : Colors.white38,
                      size: 16,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ✅ Delete confirmation
  Future<void> _showDeleteConfirmation(Map<String, dynamic> profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Remove Account?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove ${profile['email']} from this device?",
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
      await SessionManager.removeProfile(profile['email'] as String);
      await _loadProfiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${profile['email']} removed'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ✅ Clear all profiles
  Future<void> clearAllProfiles() async {
    if (profiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Clear All Profiles?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove all ${profiles.length} saved profiles from this device?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will clear all saved login information and preferences.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your accounts will not be deleted, only removed from this device.",
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
            child: const Text("Clear All"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final profile in profiles) {
        await SessionManager.removeProfile(profile['email'] as String);
      }

      await SessionManager.clearContinueScreen();
      await SessionManager.setRememberMe(false);
      await _loadProfiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All profiles cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
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
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Continue',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profiles.isEmpty
                                ? 'No saved profiles'
                                : '${profiles.length} profile${profiles.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (profiles.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_sweep,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          onPressed: clearAllProfiles,
                          tooltip: 'Clear All Profiles',
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // OAuth Info Banner
                  if (profiles.any((p) => (p['provider'] as String? ?? 'email') != 'email'))
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.greenAccent.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: Colors.greenAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Quick Sign In Available',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap on OAuth profiles for one-click sign in',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Compliance Notice
                  if (_showComplianceDialog)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.3),
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
                                    color: Colors.white.withOpacity(0.7),
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
                                        color: Colors.white.withOpacity(0.6),
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
                                  color: Colors.white.withOpacity(0.3),
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
                                    color: Colors.white.withOpacity(0.6),
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

                  // Footer Buttons
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                              side: const BorderSide(color: Color(0xFF1877F3)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
}

// ✅ Security Compliant Password Dialog
class SecurityCompliantPasswordDialog extends StatefulWidget {
  final String email;
  const SecurityCompliantPasswordDialog({super.key, required this.email});
  @override
  State<SecurityCompliantPasswordDialog> createState() => _SecurityCompliantPasswordDialogState();
}

class _SecurityCompliantPasswordDialogState extends State<SecurityCompliantPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscurePassword = true;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_validatePassword);
  }

  void _validatePassword() {
    setState(() {
      _isValid = _controller.text.length >= 6;
    });
  }

  @override
  void dispose() {
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
            const Text(
              'Enter Password',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'For:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            Text(
              widget.email,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              obscureText: _obscurePassword,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.security,
                    color: Colors.greenAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your password is securely encrypted',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
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
                  onPressed: () => Navigator.pop(context, null),
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
                  onPressed: _isValid
                      ? () {
                          final enteredPassword = _controller.text.trim();
                          if (enteredPassword.isNotEmpty) {
                            Navigator.pop(context, enteredPassword);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.blueAccent.withOpacity(0.5),
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