import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show
        kIsWeb,
        kDebugMode,
        kReleaseMode,
        defaultTargetPlatform,
        TargetPlatform;
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/simple_toast.dart';

// IMPORT SERVICES
import 'package:flutter_application_1/services/google_sign_in_service.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// Global flag to prevent multiple Google SDK initializations
bool _googleSdkInitialized = false;

// Class for returning user check
class _ReturningUserCheck {
  final String? email;
  final bool hasConsent;
  final bool hasAutoLoginSetting;
  final List<String>? existingRoles;

  _ReturningUserCheck({
    this.email,
    this.hasConsent = false,
    this.hasAutoLoginSetting = true,
    this.existingRoles,
  });
}

class SignInScreen extends StatefulWidget {
  final String? prefilledEmail;
  final bool showMessage;
  final String? message;

  const SignInScreen({
    super.key,
    this.prefilledEmail,
    this.showMessage = false,
    this.message,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  late TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();

  // State variables
  bool _obscurePassword = true;
  bool _loading = false;
  bool _coolDown = false;
  bool _rememberMe = true;
  bool _loadingGoogle = false;
  bool _loadingFacebook = false;
  bool _loadingApple = false;
  bool _userChangedRememberMe = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Validation
  String? _emailError;
  String? _passwordError;
  bool _isValid = false;
  bool _isValidEmail = false;
  bool _hasSavedProfile = false;

  // Services
  final supabase = Supabase.instance.client;
  final EnvironmentManager _env = EnvironmentManager();
  late PackageInfo packageInfo;
  DateTime? _termsAcceptedAt;
  DateTime? _privacyAcceptedAt;

  // SERVICES
  late final GoogleSignInService _googleSignInService;
  final FacebookAuth _facebookAuth = FacebookAuth.instance;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize GoogleSignInService with check to prevent multiple initializations
    _googleSignInService = GoogleSignInService();
    
    // Only initialize if not already initialized globally
    if (!_googleSdkInitialized) {
      _googleSignInService.initialize();
      _googleSdkInitialized = true;
      if (kDebugMode) print('✅ Google Sign-In SDK initialized once');
    } else {
      if (kDebugMode) print('ℹ️ Google Sign-In SDK already initialized, skipping');
    }

    // Initialize controllers
    _emailController = TextEditingController(text: widget.prefilledEmail ?? '');

    // Load data
    _initPackageInfo();
    _loadConsentStatus();
    _checkSavedProfile();
    _loadRememberMeSetting();

    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();

    // Add listeners
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);

    // Post frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.showMessage && widget.message != null) {
        _showCustomMessage(widget.message!);
      }
    });
  }

  // Load remember me setting with smart default
  Future<void> _loadRememberMeSetting() async {
    try {
      final profiles = await SessionManager.getProfiles();
      final hasExistingProfile = profiles.isNotEmpty;
      final savedRememberMe = await SessionManager.isRememberMeEnabled();

      setState(() {
        if (hasExistingProfile) {
          _rememberMe = savedRememberMe;
        } else {
          _rememberMe = true;
        }
      });

      if (kDebugMode) {
        print(' Remember Me setting loaded: $_rememberMe');
        print(' Has saved profile: $_hasSavedProfile');
      }
    } catch (e) {
      debugPrint(' Error loading remember me: $e');
      setState(() => _rememberMe = true);
    }
  }

  void _onEmailChanged() {
    if (_emailController.text.isNotEmpty) {
      _validateEmail();
    } else {
      setState(() {
        _emailError = null;
        _isValidEmail = true;
      });
    }
    _updateFormValidity();
  }

  void _onPasswordChanged() {
    if (_passwordController.text.isNotEmpty) {
      _validatePassword();
    } else {
      setState(() {
        _passwordError = null;
      });
    }
    _updateFormValidity();
  }

  void _validateEmail() {
    String email = _emailController.text.trim();
    setState(() {
      if (email.isEmpty) {
        _emailError = 'Enter your email address';
        _isValidEmail = false;
      } else if (!_isValidEmailFormat(email)) {
        _emailError = 'Enter a valid email address';
        _isValidEmail = false;
      } else {
        _emailError = null;
        _isValidEmail = true;
      }
    });
  }

  void _validatePassword() {
    String password = _passwordController.text.trim();
    setState(() {
      if (password.isEmpty) {
        _passwordError = 'Enter your password';
      } else {
        _passwordError = null;
      }
    });
  }

  void _updateFormValidity() {
    setState(() {
      _isValid =
          _emailError == null &&
          _passwordError == null &&
          _emailController.text.isNotEmpty &&
          _passwordController.text.isNotEmpty;
    });
  }

  bool _isValidEmailFormat(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _showCustomMessage(String message) {
    SimpleToast.info(context, message);
  }

  Future<void> _initPackageInfo() async {
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint(' Error getting package info: $e');
      packageInfo = PackageInfo(
        appName: 'MySalon',
        packageName: 'com.example.mysalon',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    }
  }

  Future<void> _loadConsentStatus() async {
    try {
      final profiles = await SessionManager.getProfiles();
      final currentUser = await SessionManager.getCurrentUserEmail();

      if (currentUser != null) {
        final profile = profiles.firstWhere(
          (p) => p['email'] == currentUser,
          orElse: () => {},
        );

        if (profile.isNotEmpty) {
          setState(() {
            _termsAcceptedAt = profile['termsAcceptedAt'] != null
                ? DateTime.parse(profile['termsAcceptedAt'])
                : null;
            _privacyAcceptedAt = profile['privacyAcceptedAt'] != null
                ? DateTime.parse(profile['privacyAcceptedAt'])
                : null;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print(' Error loading consent: $e');
    }
  }

  Future<_ReturningUserCheck> _checkIfReturningUser(String provider) async {
    try {
      final profiles = await SessionManager.getProfiles();
      debugPrint('📊 Total profiles found: ${profiles.length}');

      if (profiles.isEmpty) {
        debugPrint('📊 No profiles found - new user');
        return _ReturningUserCheck(hasAutoLoginSetting: true);
      }

      for (var profile in profiles) {
        final profileProvider = profile['provider']?.toString().toLowerCase();
        debugPrint('📊 Checking profile - Provider: $profileProvider');

        if (profileProvider == provider.toLowerCase()) {
          final email = profile['email']?.toString();
          final termsAccepted = profile['termsAcceptedAt'] != null;
          final privacyAccepted = profile['privacyAcceptedAt'] != null;
          final hasRememberMe = profile['rememberMe'] == true;
          
          final existingRoles = profile['roles'] as List? ?? [];

          debugPrint('✅ Found returning user: $email for provider: $provider');
          debugPrint('📊 Has rememberMe: $hasRememberMe');
          debugPrint('📊 Existing roles: $existingRoles');

          return _ReturningUserCheck(
            email: email,
            hasConsent: termsAccepted && privacyAccepted,
            hasAutoLoginSetting: hasRememberMe,
            existingRoles: existingRoles.isNotEmpty ? List<String>.from(existingRoles) : null,
          );
        }
      }

      debugPrint('📊 No matching profile found for provider: $provider');
      return _ReturningUserCheck(hasAutoLoginSetting: true);
    } catch (e) {
      debugPrint('❌ Error checking returning user: $e');
      return _ReturningUserCheck(hasAutoLoginSetting: true);
    }
  }

  Future<void> _checkSavedProfile() async {
    try {
      final profiles = await SessionManager.getProfiles();
      setState(() {
        _hasSavedProfile = profiles.isNotEmpty;
      });
      debugPrint('📊 Has saved profile: ${profiles.isNotEmpty}');
    } catch (e) {
      debugPrint('❌ Error checking saved profiles: $e');
    }
  }

  String _getRedirectUrl() {
    if (kReleaseMode) {
      return 'com.yourcompany.mysalon://auth-callback';
    } else if (kDebugMode) {
      return kIsWeb
          ? 'http://localhost:5000/auth/callback'
          : 'com.yourcompany.mysalon.dev://auth-callback';
    }
    return 'com.yourcompany.mysalon.staging://auth-callback';
  }

  Future<void> _saveOAuthProfile({
    required User user,
    required String providerToSave,
    required bool rememberMe,
    String? accessToken,
    String? refreshToken,
    bool? marketingConsent,
    List<String>? existingRoles,
  }) async {
    try {
      final email = user.email!;
      final now = DateTime.now();

      final userMetadata = user.userMetadata ?? {};
      final appMetadata = user.appMetadata;

      bool finalMarketingConsent;
      DateTime? finalMarketingConsentAt;

      if (marketingConsent != null) {
        finalMarketingConsent = marketingConsent;
        finalMarketingConsentAt = marketingConsent ? now : null;

        debugPrint('📊 Using marketing consent from parameter: $finalMarketingConsent');

        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'remember_me_enabled': rememberMe,
              'terms_accepted_at': now.toIso8601String(),
              'privacy_accepted_at': now.toIso8601String(),
              'marketing_consent': finalMarketingConsent,
              'marketing_consent_at': finalMarketingConsentAt?.toIso8601String(),
            },
          ),
        );
        debugPrint('✅ Updated auth metadata with marketing consent');
      } else {
        finalMarketingConsent = userMetadata['marketing_consent'] as bool? ?? false;

        if (userMetadata['marketing_consent_at'] != null) {
          try {
            finalMarketingConsentAt = DateTime.parse(
              userMetadata['marketing_consent_at'].toString(),
            );
          } catch (e) {
            finalMarketingConsentAt = null;
          }
        }

        debugPrint('📊 Using marketing consent from metadata: $finalMarketingConsent');
      }

      String finalProvider = providerToSave;

      if (providerToSave == 'facebook') {
        finalProvider = 'facebook';
      } else if (providerToSave == 'google') {
        finalProvider = 'google';
      } else if (providerToSave == 'apple') {
        finalProvider = 'apple';
      } else if (providerToSave == 'email') {
        finalProvider = 'email';
      } else {
        if (appMetadata['provider'] != null) {
          finalProvider = appMetadata['provider'].toString();
        } else if (userMetadata['provider'] != null) {
          finalProvider = userMetadata['provider'].toString();
        }
      }

      String? photoUrl;
      if (userMetadata['avatar_url'] != null &&
          userMetadata['avatar_url'].toString().isNotEmpty) {
        photoUrl = userMetadata['avatar_url'].toString();
      } else if (userMetadata['picture'] != null &&
          userMetadata['picture'].toString().isNotEmpty) {
        photoUrl = userMetadata['picture'].toString();
      } else if (userMetadata['photo'] != null &&
          userMetadata['photo'].toString().isNotEmpty) {
        photoUrl = userMetadata['photo'].toString();
      }

      String name = email.split('@').first;
      if (userMetadata['full_name'] != null &&
          userMetadata['full_name'].toString().isNotEmpty) {
        name = userMetadata['full_name'].toString();
      } else if (userMetadata['name'] != null &&
          userMetadata['name'].toString().isNotEmpty) {
        name = userMetadata['name'].toString();
      } else if (userMetadata['display_name'] != null &&
          userMetadata['display_name'].toString().isNotEmpty) {
        name = userMetadata['display_name'].toString();
      }

      List<String> finalRoles = [];
      
      try {
        final userRolesResponse = await supabase
            .from('user_roles')
            .select('''
              role_id,
              roles!inner (
                name
              )
            ''')
            .eq('user_id', user.id);

        for (var roleEntry in userRolesResponse) {
          final role = roleEntry['roles'] as Map?;
          if (role != null && role['name'] != null) {
            finalRoles.add(role['name'].toString());
          }
        }
      } catch (e) {
        debugPrint('📊 Error fetching user roles: $e');
      }

      if (finalRoles.isEmpty && existingRoles != null && existingRoles.isNotEmpty) {
        finalRoles = existingRoles;
      }

      debugPrint('📊 Final roles for profile: $finalRoles');

      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: name,
        photo: photoUrl ?? '',
        roles: finalRoles,
        rememberMe: rememberMe,
        refreshToken: refreshToken,
        accessToken: accessToken,
        provider: finalProvider,
        termsAcceptedAt: _termsAcceptedAt ?? now,
        privacyAcceptedAt: _privacyAcceptedAt ?? now,
        marketingConsent: finalMarketingConsent,
        marketingConsentAt: finalMarketingConsentAt,
      );

      debugPrint('✅ Saved profile for $email with rememberMe: $rememberMe');
    } catch (e) {
      debugPrint('❌ Error in _saveOAuthProfile: $e');
    }
  }

  Future<void> loginUser() async {
    if (_loading) return;

    try {
      setState(() => _loading = true);

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (!_isValid) {
        _validateForm();
        if (!_isValid) {
          setState(() => _loading = false);
          return;
        }
      }

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      final session = response.session;

      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      await SessionManager.setRememberMe(_rememberMe);
      await appState.setRememberMe(_rememberMe);

      await _saveOAuthProfile(
        user: user,
        providerToSave: 'email',
        rememberMe: _rememberMe,
        accessToken: session?.accessToken,
        refreshToken: session?.refreshToken,
      );

      appState.refreshState();
      if (!mounted) return;

      await _handlePostLogin(user.id);
    } on AuthException catch (e) {
      if (!mounted) return;

      final errorMessage = _getUserFriendlyErrorMessage(e);
      await showCustomAlert(
        context: context,
        title: "Login Failed",
        message: errorMessage,
        isError: true,
      );

      if (e.code == 'email_not_confirmed') {
        final session = supabase.auth.currentSession;

        await _saveOAuthProfile(
          user: User(
            id: '',
            appMetadata: {},
            userMetadata: {},
            aud: '',
            createdAt: DateTime.now().toIso8601String(),
          ),
          providerToSave: 'email',
          rememberMe: _rememberMe,
          refreshToken: session?.refreshToken,
        );

        appState.emailVerifyerError();
        appState.refreshState();
        if (!mounted) return;
        context.go('/verify-email');
      } else if (e.code == 'too_many_requests') {
        setState(() => _coolDown = true);
        Future.delayed(const Duration(seconds: 60), () {
          if (mounted) setState(() => _coolDown = false);
        });
      }
    } catch (e) {
      if (!mounted) return;
      final errorMessage = _getUserFriendlyErrorMessage(e);
      await showCustomAlert(
        context: context,
        title: "Unexpected Error",
        message: errorMessage,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    if (error is AuthException) {
      final code = error.code ?? '';

      if (code.contains('network') || code.contains('connection')) {
        return "Please check your internet connection and try again.";
      } else if (code.contains('timeout')) {
        return "The request timed out. Please try again.";
      } else if (code.contains('invalid') || code.contains('credentials')) {
        return "Invalid email or password. Please try again.";
      } else if (code.contains('too_many_requests')) {
        return "Too many attempts. Please try again later.";
      } else if (code.contains('email_not_confirmed')) {
        return "Please verify your email address before logging in.";
      }
    }

    return kReleaseMode
        ? "An error occurred. Please try again."
        : error.toString();
  }

  // FIXED: COMBINED OAuth DIALOG with proper overflow handling
  Future<Map<String, dynamic>?> _showCombinedOAuthDialog({
    required String provider,
    required List<String> scopes,
    bool defaultAutoLogin = true,
    List<String>? existingRoles,
  }) async {
    bool rememberMe = defaultAutoLogin;
    bool marketingConsent = false;

    if (_hasSavedProfile) {
      final savedRememberMe = await SessionManager.isRememberMeEnabled();
      rememberMe = savedRememberMe;
      debugPrint('📊 Loaded saved remember me: $rememberMe');
    } else {
      debugPrint('📊 New user - default remember me: $rememberMe');
    }

    if (!mounted) return null;

    final dialogResult = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                _getProviderIcon(provider, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Sign in with $provider",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing roles info (if any)
                  if (existingRoles != null && existingRoles.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "You have existing profiles",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: existingRoles.map((role) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRoleColor(role).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _getRoleDisplayName(role),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getRoleColor(role),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                  // OAuth Permissions Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield,
                              size: 16,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "$provider will share:",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (var scope in scopes)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green.shade600,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "• $scope",
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Terms & Privacy Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.description,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Terms & Privacy",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                if (mounted) {
                                  context.push('/terms');
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text("Terms of Service"),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue.shade700,
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                if (mounted) {
                                  context.push('/privacy');
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text("Privacy Policy"),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue.shade700,
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "By continuing, you agree to our Terms and Privacy Policy",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Auto-login Section with Remember Me
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: rememberMe
                          ? Colors.green.shade50
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: rememberMe
                            ? Colors.green.shade200
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.remember_me,
                              size: 16,
                              color: rememberMe
                                  ? Colors.green.shade700
                                  : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Quick Sign-in",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: rememberMe
                                      ? Colors.green.shade700
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: rememberMe,
                              onChanged: (value) =>
                                  setState(() => rememberMe = value ?? false),
                              activeColor: _getProviderColor(provider),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Stay signed in on this device",
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    "✓ Faster login next time\n✓ Disable anytime in Settings",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_hasSavedProfile && rememberMe)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green.shade600,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "Saved preference applied",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Marketing Consent (Optional)
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: marketingConsent,
                          onChanged: (value) =>
                              setState(() => marketingConsent = value ?? false),
                          activeColor: _getProviderColor(provider),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            "Send me occasional offers and updates (optional)",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // App version
                  Center(
                    child: Text(
                      "App v${packageInfo.version} (${packageInfo.buildNumber})",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'accepted': true,
                    'rememberMe': rememberMe,
                    'marketingConsent': marketingConsent,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getProviderColor(provider),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Continue"),
              ),
            ],
          );
        },
      ),
    );

    return dialogResult;
  }

  Widget _getProviderIcon(String provider, {double size = 18}) {
    switch (provider.toLowerCase()) {
      case 'google':
        return SvgPicture.asset('icons/google.svg', width: size, height: size);
      case 'facebook':
        return SvgPicture.asset(
          'icons/facebook.svg',
          width: size,
          height: size,
        );
      case 'apple':
        return Icon(Icons.apple, size: size, color: Colors.black);
      default:
        return Icon(Icons.lock, size: size);
    }
  }

  Color _getProviderColor(String provider) {
    switch (provider.toLowerCase()) {
      case 'google':
        return const Color(0xFFDB4437);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'apple':
        return Colors.black;
      default:
        return const Color(0xFF1877F3);
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return Colors.blueAccent;
      case 'barber':
        return Colors.orangeAccent;
      case 'customer':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'barber':
        return 'Barber';
      case 'customer':
        return 'Customer';
      default:
        return role;
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_loadingGoogle) return;

    try {
      setState(() => _loadingGoogle = true);

      debugPrint('Starting Google Sign-In process...');

      final returningUserCheck = await _checkIfReturningUser('google');

      debugPrint('Returning User Check - Google:');
      debugPrint('   Email: ${returningUserCheck.email}');
      debugPrint('   Has Consent: ${returningUserCheck.hasConsent}');
      debugPrint('   Auto Login Setting: ${returningUserCheck.hasAutoLoginSetting}');
      debugPrint('   Existing Roles: ${returningUserCheck.existingRoles}');

      final result = await _showCombinedOAuthDialog(
        provider: 'Google',
        scopes: ['email', 'profile'],
        defaultAutoLogin: returningUserCheck.hasAutoLoginSetting,
        existingRoles: returningUserCheck.existingRoles,
      );

      debugPrint('Dialog result: $result');

      if (result == null) {
        debugPrint('User cancelled dialog');
        setState(() => _loadingGoogle = false);
        return;
      }

      final bool userWantsAutoLogin = result['rememberMe'] ?? true;
      final bool marketingConsent = result['marketingConsent'] ?? false;

      debugPrint('User wants auto login: $userWantsAutoLogin');
      debugPrint('Marketing consent: $marketingConsent');

      setState(() => _rememberMe = userWantsAutoLogin);
      await SessionManager.setRememberMe(userWantsAutoLogin);
      await appState.setRememberMe(userWantsAutoLogin);

      final now = DateTime.now();
      final email = _emailController.text.trim();

      if (email.isNotEmpty) {
        await SessionManager.updateConsentTimestamps(
          email: email,
          termsAcceptedAt: now,
          privacyAcceptedAt: now,
        );

        if (marketingConsent) {
          await SessionManager.updateMarketingConsent(
            email: email,
            consent: true,
            consentedAt: now,
          );
        }
      }

      if (kIsWeb) {
        debugPrint('Web platform - starting Supabase OAuth');
        _authSubscription?.cancel();

        _authSubscription = supabase.auth.onAuthStateChange.listen((
          data,
        ) async {
          debugPrint('Auth event: ${data.event}');
          if (data.event == AuthChangeEvent.signedIn && mounted) {
            final user = supabase.auth.currentUser;
            final session = supabase.auth.currentSession;
            if (user != null && user.email != null) {
              await _completeGoogleSignIn(
                user: user,
                session: session,
                userWantsAutoLogin: userWantsAutoLogin,
                marketingConsent: marketingConsent,
                existingRoles: returningUserCheck.existingRoles,
              );
            }
          }
        });

        await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: _env.getRedirectUrl(),
          scopes: 'email profile',
          queryParams: {'prompt': 'select_account'},
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        debugPrint('Mobile platform - using native Google Sign-In');

        final authData = await _googleSignInService.authenticateAndGetDetails();

        if (authData != null && authData['idToken'] != null) {
          debugPrint('Got auth data from Google');

          try {
            final response = await supabase.auth.signInWithIdToken(
              provider: OAuthProvider.google,
              idToken: authData['idToken']!,
              accessToken: authData['accessToken'],
            );

            final user = response.user;
            final session = response.session;

            if (user != null && mounted) {
              await _completeGoogleSignIn(
                user: user,
                session: session,
                userWantsAutoLogin: userWantsAutoLogin,
                marketingConsent: marketingConsent,
                existingRoles: returningUserCheck.existingRoles,
              );
              return;
            }
          } catch (e) {
            debugPrint('Supabase sign-in failed: $e');
          }
        } else {
          debugPrint('Google authentication failed');
        }
      }

      debugPrint('Falling back to Supabase OAuth');
      _authSubscription?.cancel();

      _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn && mounted) {
          final user = supabase.auth.currentUser;
          final session = supabase.auth.currentSession;
          if (user != null && user.email != null) {
            await _completeGoogleSignIn(
              user: user,
              session: session,
              userWantsAutoLogin: userWantsAutoLogin,
              marketingConsent: marketingConsent,
              existingRoles: returningUserCheck.existingRoles,
            );
          }
        }
      });

      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _env.getRedirectUrl(),
        scopes: 'email profile',
        queryParams: {'prompt': 'select_account'},
      );
    } on AuthException catch (e) {
      debugPrint('AuthException: ${e.message}');
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Google Sign In Failed",
        message: _getOAuthErrorMessage(e, 'Google'),
        isError: true,
      );
    } catch (e) {
      debugPrint('Error: $e');
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Google Sign In Error",
        message: _getUserFriendlyErrorMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  Future<void> _completeGoogleSignIn({
    required User user,
    required Session? session,
    required bool userWantsAutoLogin,
    required bool marketingConsent,
    List<String>? existingRoles,
  }) async {
    if (!mounted) return;
    
    await _saveOAuthProfile(
      user: user,
      providerToSave: 'google',
      rememberMe: userWantsAutoLogin,
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
      marketingConsent: marketingConsent,
      existingRoles: existingRoles,
    );

    if (marketingConsent) {
      await SessionManager.updateMarketingConsent(
        email: user.email!,
        consent: true,
        consentedAt: DateTime.now(),
      );
    }

    final userRolesResponse = await supabase
        .from('user_roles')
        .select('role_id')
        .eq('user_id', user.id);

    if (userRolesResponse.isEmpty) {
      if (mounted) {
        context.go('/reg');
        return;
      }
    }

    await _handlePostLogin(user.id);
  }

  Future<void> _signInWithFacebook() async {
    if (_loadingFacebook) return;

    try {
      setState(() => _loadingFacebook = true);

      if (!_env.enableFacebookOAuth) {
        SimpleToast.info(context, 'Facebook sign in is currently disabled');
        setState(() => _loadingFacebook = false);
        return;
      }

      final returningUserCheck = await _checkIfReturningUser('facebook');

      final result = await _showCombinedOAuthDialog(
        provider: 'Facebook',
        scopes: ['email', 'public_profile'],
        defaultAutoLogin: returningUserCheck.hasAutoLoginSetting,
        existingRoles: returningUserCheck.existingRoles,
      );

      if (result == null) {
        setState(() => _loadingFacebook = false);
        return;
      }

      final bool userWantsAutoLogin = result['rememberMe'] ?? true;
      final bool marketingConsent = result['marketingConsent'] ?? false;

      setState(() => _rememberMe = userWantsAutoLogin);
      await SessionManager.setRememberMe(userWantsAutoLogin);
      await appState.setRememberMe(userWantsAutoLogin);

      final now = DateTime.now();
      final email = _emailController.text.trim();

      if (email.isNotEmpty) {
        await SessionManager.updateConsentTimestamps(
          email: email,
          termsAcceptedAt: now,
          privacyAcceptedAt: now,
        );
      }

      if (kIsWeb) {
        await _signInWithFacebookWeb(
          userWantsAutoLogin,
          marketingConsent,
          returningUserCheck,
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final LoginResult fbResult = await _facebookAuth.login(
            permissions: ['email', 'public_profile'],
          );

          if (fbResult.status == LoginStatus.success) {
            final AccessToken accessToken = fbResult.accessToken!;
            final response = await supabase.auth.signInWithIdToken(
              provider: OAuthProvider.facebook,
              idToken: accessToken.tokenString,
            );

            final user = response.user;
            final session = response.session;

            if (user != null && mounted) {
              await _completeFacebookSignIn(
                user: user,
                session: session,
                userWantsAutoLogin: userWantsAutoLogin,
                marketingConsent: marketingConsent,
                existingRoles: returningUserCheck.existingRoles,
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('Native Facebook login failed: $e');
        }
      }

      await _signInWithFacebookWeb(
        userWantsAutoLogin,
        marketingConsent,
        returningUserCheck,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Facebook Sign In Failed",
        message: _getOAuthErrorMessage(e, 'Facebook'),
        isError: true,
      );
    } catch (e) {
      debugPrint('Facebook OAuth error: $e');
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Facebook Sign In Error",
        message: _getUserFriendlyErrorMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loadingFacebook = false);
    }
  }

  Future<void> _signInWithFacebookWeb(
    bool userWantsAutoLogin,
    bool marketingConsent,
    _ReturningUserCheck returningUserCheck,
  ) async {
    _authSubscription?.cancel();
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        final user = supabase.auth.currentUser;
        final session = supabase.auth.currentSession;
        if (user != null && user.email != null) {
          await _completeFacebookSignIn(
            user: user,
            session: session,
            userWantsAutoLogin: userWantsAutoLogin,
            marketingConsent: marketingConsent,
            existingRoles: returningUserCheck.existingRoles,
          );
        }
      }
    });

    await supabase.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: _env.getRedirectUrl(),
      scopes: 'public_profile',
    );
  }

  Future<void> _completeFacebookSignIn({
    required User user,
    required Session? session,
    required bool userWantsAutoLogin,
    required bool marketingConsent,
    List<String>? existingRoles,
  }) async {
    if (!mounted) return;
    
    await _saveOAuthProfile(
      user: user,
      providerToSave: 'facebook',
      rememberMe: userWantsAutoLogin,
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
      marketingConsent: marketingConsent,
      existingRoles: existingRoles,
    );

    if (marketingConsent) {
      await SessionManager.updateMarketingConsent(
        email: user.email!,
        consent: true,
        consentedAt: DateTime.now(),
      );
    }

    final userRolesResponse = await supabase
        .from('user_roles')
        .select('role_id')
        .eq('user_id', user.id);

    if (userRolesResponse.isEmpty) {
      if (mounted) {
        context.go('/reg');
        return;
      }
    }

    await _handlePostLogin(user.id);
  }

  Future<void> _signInWithApple() async {
    if (_loadingApple) return;

    try {
      setState(() => _loadingApple = true);

      final returningUserCheck = await _checkIfReturningUser('apple');

      final result = await _showCombinedOAuthDialog(
        provider: 'Apple',
        scopes: ['email', 'name'],
        defaultAutoLogin: returningUserCheck.hasAutoLoginSetting,
        existingRoles: returningUserCheck.existingRoles,
      );

      if (result == null) {
        setState(() => _loadingApple = false);
        return;
      }

      final bool userWantsAutoLogin = result['rememberMe'] ?? true;
      final bool marketingConsent = result['marketingConsent'] ?? false;

      setState(() => _rememberMe = userWantsAutoLogin);
      await SessionManager.setRememberMe(userWantsAutoLogin);
      await appState.setRememberMe(userWantsAutoLogin);

      final now = DateTime.now();
      final email = _emailController.text.trim();

      if (email.isNotEmpty) {
        await SessionManager.updateConsentTimestamps(
          email: email,
          termsAcceptedAt: now,
          privacyAcceptedAt: now,
        );
      }

      if (kIsWeb) {
        debugPrint('Web platform - starting Apple OAuth');
        await _signInWithAppleWeb(
          userWantsAutoLogin,
          marketingConsent,
          returningUserCheck,
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        debugPrint('Android platform - starting Apple OAuth');
        await _signInWithAppleWeb(
          userWantsAutoLogin,
          marketingConsent,
          returningUserCheck,
        );
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        debugPrint('iOS platform - trying native Apple Sign-In');
        try {
          final credential = await SignInWithApple.getAppleIDCredential(
            scopes: [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
          );

          if (credential.identityToken != null) {
            debugPrint('Got native Apple credential');

            final response = await supabase.auth.signInWithIdToken(
              provider: OAuthProvider.apple,
              idToken: credential.identityToken!,
            );

            final user = response.user;
            final session = response.session;

            if (user != null && mounted) {
              await _completeAppleSignIn(
                user: user,
                session: session,
                userWantsAutoLogin: userWantsAutoLogin,
                marketingConsent: marketingConsent,
                existingRoles: returningUserCheck.existingRoles,
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('Native Apple Sign-In failed: $e');
        }
      }

      debugPrint('Falling back to Supabase OAuth for Apple');
      await _signInWithAppleWeb(
        userWantsAutoLogin,
        marketingConsent,
        returningUserCheck,
      );
    } on AuthException catch (e) {
      debugPrint('Apple AuthException: ${e.message}');
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Apple Sign In Failed",
        message: _getOAuthErrorMessage(e, 'Apple'),
        isError: true,
      );
    } catch (e) {
      debugPrint('Apple Sign In error: $e');
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Apple Sign In Error",
        message: _getUserFriendlyErrorMessage(e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loadingApple = false);
    }
  }

  Future<void> _signInWithAppleWeb(
    bool userWantsAutoLogin,
    bool marketingConsent,
    _ReturningUserCheck returningUserCheck,
  ) async {
    _authSubscription?.cancel();

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
      debugPrint('Apple Auth event: ${data.event}');
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        final user = supabase.auth.currentUser;
        final session = supabase.auth.currentSession;
        if (user != null && user.email != null) {
          await _completeAppleSignIn(
            user: user,
            session: session,
            userWantsAutoLogin: userWantsAutoLogin,
            marketingConsent: marketingConsent,
            existingRoles: returningUserCheck.existingRoles,
          );
        }
      }
    });

    final redirectUrl = _getRedirectUrl();
    debugPrint('Starting Apple OAuth with redirect: $redirectUrl');

    await supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _env.getRedirectUrl(),
      scopes: 'email name',
    );
  }

  Future<void> _completeAppleSignIn({
    required User user,
    required Session? session,
    required bool userWantsAutoLogin,
    required bool marketingConsent,
    List<String>? existingRoles,
  }) async {
    if (!mounted) return;
    debugPrint('Completing Apple Sign-In for: ${user.email}');

    await _saveOAuthProfile(
      user: user,
      providerToSave: 'apple',
      rememberMe: userWantsAutoLogin,
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
      marketingConsent: marketingConsent,
      existingRoles: existingRoles,
    );

    if (marketingConsent) {
      await SessionManager.updateMarketingConsent(
        email: user.email!,
        consent: true,
        consentedAt: DateTime.now(),
      );
    }

    final userRolesResponse = await supabase
        .from('user_roles')
        .select('role_id')
        .eq('user_id', user.id);

    if (userRolesResponse.isEmpty) {
      if (mounted) {
        context.go('/reg');
        return;
      }
    }

    await _handlePostLogin(user.id);
  }

  Future<void> _handlePostLogin(String userId) async {
    try {
      if (!mounted) return;

      await Future.delayed(const Duration(seconds: 1));

      final user = supabase.auth.currentUser;
      if (user == null || user.email == null) {
        if (mounted) context.go('/');
        return;
      }

      final email = user.email!;

      final profileCheck = await supabase
          .from('profiles')
          .select('is_blocked, is_active')
          .eq('id', userId)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          await supabase.auth.signOut();
          await SessionManager.removeProfile(email);
          if (mounted) {
            await showCustomAlert(
              context: context,
              title: "Account Blocked 🚫",
              message: "Your account has been blocked. Please contact support.",
              isError: true,
            );
            if (mounted) context.go('/login');
          }
          return;
        }

        if (profileCheck['is_active'] == false) {
          await supabase.auth.signOut();
          await SessionManager.removeProfile(email);
          if (mounted) {
            await showCustomAlert(
              context: context,
              title: "Account Inactive ⚠️",
              message: "Your account is deactivated.",
              isError: true,
            );
            if (mounted) context.go('/login');
          }
          return;
        }
      }

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('user_id', userId);

      debugPrint('📋 userRolesResponse: $userRolesResponse');

      final List<String> roleNames = [];
      for (var roleEntry in userRolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }

      debugPrint('📋 Extracted role names: $roleNames');

      await SessionManager.saveUserRoles(email: email, roles: roleNames);

      if (roleNames.isEmpty) {
        debugPrint('⚠️ No roles found, redirecting to /reg');
        if (mounted) context.go('/reg');
        return;
      }

      if (roleNames.length == 1) {
        final singleRole = roleNames.first;
        debugPrint('✅ Single role: $singleRole, saving and redirecting');

        await SessionManager.saveCurrentRole(singleRole);
        await appState.refreshState();

        if (!mounted) return;

        switch (singleRole) {
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
        return;
      }

      if (roleNames.length > 1) {
        debugPrint('🔄 Multiple roles: $roleNames');

        final savedRole = await SessionManager.getCurrentRole();
        debugPrint('📋 Saved role from SessionManager: $savedRole');

        if (savedRole != null && roleNames.contains(savedRole)) {
          debugPrint('✅ Using saved role: $savedRole');
          await SessionManager.saveCurrentRole(savedRole);
          await appState.refreshState();

          if (!mounted) return;

          switch (savedRole) {
            case 'owner':
              context.go('/owner');
              break;
            case 'barber':
              context.go('/barber');
              break;
            default:
              context.go('/customer');
              break;
          }
          return;
        }

        debugPrint('🔄 No saved role, going to role selector');
        if (mounted) {
          context.go(
            '/role-selector',
            extra: {'roles': roleNames, 'email': email, 'userId': userId},
          );
        }
        return;
      }

      debugPrint('⚠️ Fallback - refreshing app state');
      appState.refreshState();
      if (mounted) context.go('/');

    } catch (e) {
      debugPrint('❌ Post-login error: $e');
      appState.refreshState();
      if (mounted) context.go('/');
    }
  }

  String _getOAuthErrorMessage(AuthException e, String provider) {
    if (kReleaseMode) {
      return "Unable to sign in with $provider. Please try again.";
    }

    final code = e.code ?? '';
    final message = e.message.toLowerCase();

    if (message.contains('network') || message.contains('connection')) {
      return "Please check your internet connection and try again.";
    }

    if (message.contains('cancelled') || message.contains('canceled')) {
      return "Sign in was cancelled.";
    }

    switch (code) {
      case 'oauth_callback':
      case 'invalid_client':
        return '''
$provider OAuth Configuration Required:

1. Go to $provider Developers Console
2. Add this redirect URL:
   ${_getRedirectUrl()}
3. Save changes and wait a few minutes
''';
      case 'user_cancelled':
        return "Sign in was cancelled";
      case 'network_error':
        return "Please check your internet connection";
      default:
        return e.message;
    }
  }

  Widget _buildOAuthButtons() {
    final enabledProviders = _env.enabledOAuthProviders;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ],
          ),
        ),

        if (enabledProviders.contains('google'))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SocialLoginButton(
              provider: 'google',
              onPressed: _signInWithGoogle,
              isLoading: _loadingGoogle,
            ),
          ),

        if (enabledProviders.contains('facebook'))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SocialLoginButton(
              provider: 'facebook',
              onPressed: _signInWithFacebook,
              isLoading: _loadingFacebook,
            ),
          ),

        if (enabledProviders.contains('apple') &&
            (defaultTargetPlatform == TargetPlatform.iOS || kIsWeb))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SocialLoginButton(
              provider: 'apple',
              onPressed: _signInWithApple,
              isLoading: _loadingApple,
            ),
          ),

        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SocialLoginButton(
            provider: 'password',
            onPressed: () => context.go('/signup'),
            isLoading: false,
          ),
        ),
      ],
    );
  }

  void _handleBackButton() {
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
    } else {
      GoRouter.of(context).go('/');
    }
  }

  void _validateForm() {
    _validateEmail();
    _validatePassword();
    _updateFormValidity();
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF0F1820);
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: bg,
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
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_hasSavedProfile)
                        Align(
                          alignment: Alignment.topLeft,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: _handleBackButton,
                              ),
                              if (_hasSavedProfile)
                                GestureDetector(
                                  onTap: () => context.push('/continue'),
                                  child: const Text(
                                    'Use another account',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Logo
                              Container(
                                margin: const EdgeInsets.only(
                                  top: 5,
                                  bottom: 25,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 70,
                                    height: 70,
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
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.asset(
                                        'logo.png',
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
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
                                ),
                              ),

                              // Email Field
                              TextField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Email address',
                                  hintStyle: const TextStyle(
                                    color: Colors.white54,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1877F3),
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.redAccent,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.redAccent,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.email_outlined,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  suffixIcon: _emailController.text.isEmpty
                                      ? null
                                      : _isValidEmail
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF4CAF50),
                                          size: 22,
                                        )
                                      : const Icon(
                                          Icons.error_outline,
                                          color: Colors.redAccent,
                                          size: 22,
                                        ),
                                  errorText: _emailError,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Password Field
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  hintStyle: const TextStyle(
                                    color: Colors.white54,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1877F3),
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.redAccent,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.redAccent,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  suffixIcon:
                                      _passwordController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                            color: Colors.white70,
                                            size: 22,
                                          ),
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                          splashRadius: 20,
                                        )
                                      : null,
                                  errorText: _passwordError,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Remember Me Checkbox
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _rememberMe
                                      ? const Color(
                                          0xFF1877F3,
                                        ).withValues(alpha: 0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _rememberMe
                                        ? const Color(
                                            0xFF1877F3,
                                          ).withValues(alpha: 0.3)
                                        : Colors.white12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _rememberMe,
                                      onChanged: (value) {
                                        setState(() {
                                          _rememberMe = value ?? false;
                                          _userChangedRememberMe = true;
                                        });
                                      },
                                      activeColor: const Color(0xFF1877F3),
                                      checkColor: Colors.white,
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'Remember Me',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (_rememberMe &&
                                                  !_userChangedRememberMe &&
                                                  !_hasSavedProfile)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'Recommended',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (_rememberMe)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                '✓ Quick sign-in enabled • Disable anytime in Settings',
                                                style: TextStyle(
                                                  color: Colors.green.shade300,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Login Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      (_isValid && !_loading && !_coolDown)
                                      ? loginUser
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1877F3),
                                    disabledBackgroundColor: Colors.white12,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: _loading
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : _coolDown
                                      ? const Text(
                                          'Please wait...',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      : const Text(
                                          'Log in',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Forgot Password
                              GestureDetector(
                                onTap: () => context.push('/reset-password'),
                                child: const Text(
                                  'Forgotten password?',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),

                              // OAuth Buttons
                              _buildOAuthButtons(),
                              const SizedBox(height: 24),

                              // Privacy Links
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 2,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'By continuing, you agree to our',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => context.push(
                                        '/terms?from=${Uri.encodeComponent('/login')}',
                                      ),
                                      child: Text(
                                        'Terms of Service',
                                        style: TextStyle(
                                          color: const Color(0xFF1877F3),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'and',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => context.push(
                                        '/privacy?from=${Uri.encodeComponent('/login')}',
                                      ),
                                      child: Text(
                                        'Privacy Policy',
                                        style: TextStyle(
                                          color: const Color(0xFF1877F3),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
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
}

// Social Login Button
class _SocialLoginButton extends StatelessWidget {
  final String provider;
  final VoidCallback onPressed;
  final bool isLoading;

  const _SocialLoginButton({
    required this.provider,
    required this.onPressed,
    this.isLoading = false,
  });

  Color _getButtonColor() {
    switch (provider) {
      case 'google':
        return const Color(0xFFDB4437);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'apple':
        return const Color.fromARGB(255, 227, 227, 227);
      case 'password':
        return const Color.fromARGB(255, 192, 8, 243);
      default:
        return const Color(0xFF1877F3);
    }
  }

  String _getButtonText() {
    switch (provider) {
      case 'google':
        return 'Continue with Google';
      case 'facebook':
        return 'Continue with Facebook';
      case 'apple':
        return 'Continue with Apple';
      case 'password':
        return 'Create new account with password';
      default:
        return 'Continue';
    }
  }

  Widget _getIcon() {
    switch (provider) {
      case 'google':
        return SvgPicture.asset('icons/google.svg', width: 18, height: 18);
      case 'facebook':
        return SvgPicture.asset('icons/facebook.svg', width: 18, height: 18);
      case 'apple':
        return SvgPicture.asset('icons/apple.svg', width: 20, height: 20);
      case 'password':
        return Icon(
          Icons.person_add_alt_1_rounded,
          size: 18,
          color: _getButtonColor(),
        );
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = _getButtonColor();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: buttonColor.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: buttonColor.withValues(alpha: 0.1),
        ),
        child: isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(buttonColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _getIcon(),
                  const SizedBox(width: 8),
                  Text(
                    _getButtonText(),
                    style: TextStyle(
                      color: buttonColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}