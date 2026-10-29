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
import 'package:flutter_application_1/utils/app_version.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../alertBox/simple_toast.dart';

// IMPORT SERVICES
import 'package:flutter_application_1/services/google_sign_in_service.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

// ============================================================
// MOBILE APP DOWNLOAD LINKS  -> paste your real links here later
//   Android e.g. https://play.google.com/store/apps/details?id=your.app.id
//   iOS     e.g. https://apps.apple.com/app/id1234567890
// While a link is empty, the button shows a "coming soon" message.
// ============================================================
const String _kAndroidAppUrl = '';
const String _kIosAppUrl = '';

// ============================================================
// HELP & COMMUNITY LINKS  -> paste your real links here later
//   YouTube channel (watch videos) / Facebook page
// While a link is empty, the button shows a "coming soon" message.
// ============================================================
const String _kYoutubeUrl = '';
const String _kFacebookPageUrl = '';

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

  // Validation
  String? _emailError;
  String? _passwordError;
  bool _isValid = false;
  bool _isValidEmail = false;
  bool _hasSavedProfile = false;

  // Services
  final supabase = Supabase.instance.client;
  final EnvironmentManager _env = EnvironmentManager();
  DateTime? _termsAcceptedAt;
  DateTime? _privacyAcceptedAt;

  // SERVICES
  late final GoogleSignInService _googleSignInService;
  final FacebookAuth _facebookAuth = FacebookAuth.instance;

  StreamSubscription<AuthState>? _authSubscription;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();

    _googleSignInService = GoogleSignInService();
    _googleSignInService.initialize();
    debugPrint('✅ Google Sign-In SDK initialize() called from SignInScreen');

    _emailController = TextEditingController(text: widget.prefilledEmail ?? '');

    _loadConsentStatus();
    _checkSavedProfile();
    _loadRememberMeSetting();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();

    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.showMessage && widget.message != null) {
        _showCustomMessage(widget.message!);
      }
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
            existingRoles: existingRoles.isNotEmpty
                ? List<String>.from(existingRoles)
                : null,
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

        debugPrint(
          '📊 Using marketing consent from parameter: $finalMarketingConsent',
        );

        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'remember_me_enabled': rememberMe,
              'terms_accepted_at': now.toIso8601String(),
              'privacy_accepted_at': now.toIso8601String(),
              'marketing_consent': finalMarketingConsent,
              'marketing_consent_at': finalMarketingConsentAt
                  ?.toIso8601String(),
            },
          ),
        );
        debugPrint('✅ Updated auth metadata with marketing consent');
      } else {
        finalMarketingConsent =
            userMetadata['marketing_consent'] as bool? ?? false;

        if (userMetadata['marketing_consent_at'] != null) {
          try {
            finalMarketingConsentAt = DateTime.parse(
              userMetadata['marketing_consent_at'].toString(),
            );
          } catch (e) {
            finalMarketingConsentAt = null;
          }
        }

        debugPrint(
          '📊 Using marketing consent from metadata: $finalMarketingConsent',
        );
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
        ),
        status
      ''')
            .eq('user_id', user.id)
            .eq('status', 'active');

        for (var roleEntry in userRolesResponse) {
          final role = roleEntry['roles'] as Map?;
          if (role != null && role['name'] != null) {
            finalRoles.add(role['name'].toString());
          }
        }
      } catch (e) {
        debugPrint('📊 Error fetching user roles: $e');
      }

      if (finalRoles.isEmpty &&
          existingRoles != null &&
          existingRoles.isNotEmpty) {
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

  Future<Map<String, dynamic>?> _showCombinedOAuthDialog({
    required String provider,
    required List<String> scopes,
    bool defaultAutoLogin = true,
    List<String>? existingRoles,
  }) async {
    bool rememberMe = defaultAutoLogin;
    bool marketingConsent = false;
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final backgroundColor = context.backgroundColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

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
            backgroundColor: backgroundColor,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _getProviderIcon(provider, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    "Sign in with $provider",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existingRoles != null && existingRoles.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info, size: 16, color: primaryColor),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "You have existing profiles",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: primaryColor,
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
                                  color: _getRoleColor(
                                    role,
                                  ).withValues(alpha: 0.1),
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

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield,
                              size: 16,
                              color: secondaryTextColor,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "$provider will share:",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: textColor,
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green.shade600,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "• $scope",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondaryTextColor,
                                    ),
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

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.description,
                              size: 16,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Terms & Privacy",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: primaryColor,
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
                              icon: Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: primaryColor,
                              ),
                              label: Text(
                                "Terms of Service",
                                style: TextStyle(color: primaryColor),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                textStyle: const TextStyle(fontSize: 12),
                                minimumSize: const Size(0, 30),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                if (mounted) {
                                  context.push('/privacy');
                                }
                              },
                              icon: Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: primaryColor,
                              ),
                              label: Text(
                                "Privacy Policy",
                                style: TextStyle(color: primaryColor),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                textStyle: const TextStyle(fontSize: 12),
                                minimumSize: const Size(0, 30),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "By continuing, you agree to our Terms and Privacy Policy",
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: rememberMe
                          ? Colors.green.shade50
                          : (isDark ? Colors.grey[800] : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: rememberMe
                            ? Colors.green.shade200
                            : (isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.remember_me,
                              size: 16,
                              color: rememberMe
                                  ? Colors.green.shade700
                                  : secondaryTextColor,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Quick Sign-in",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: rememberMe
                                      ? Colors.green.shade700
                                      : secondaryTextColor,
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
                                  Text(
                                    "Stay signed in on this device",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: textColor,
                                    ),
                                  ),
                                  Text(
                                    "✓ Faster login next time\n✓ Disable anytime in Settings",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: secondaryTextColor,
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green.shade600,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
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

                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: marketingConsent,
                          onChanged: (value) =>
                              setState(() => marketingConsent = value ?? false),
                          activeColor: _getProviderColor(provider),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Send me occasional offers and updates (optional)",
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Text(
                      "App v${AppVersion.version}",
                      style: TextStyle(fontSize: 10, color: secondaryTextColor),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(
                  "Cancel",
                  style: TextStyle(color: secondaryTextColor),
                ),
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
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
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
        return SvgPicture.asset(
          'assets/icons/google.svg',
          width: size,
          height: size,
        );
      case 'facebook':
        return SvgPicture.asset(
          'assets/icons/facebook.svg',
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

      final result = await _showCombinedOAuthDialog(
        provider: 'Google',
        scopes: ['email', 'profile'],
        defaultAutoLogin: returningUserCheck.hasAutoLoginSetting,
        existingRoles: returningUserCheck.existingRoles,
      );

      if (result == null) {
        debugPrint('User cancelled dialog');
        setState(() => _loadingGoogle = false);
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
            }
          } catch (e) {
            debugPrint('Supabase sign-in failed: $e');
            if (mounted) {
              await showCustomAlert(
                context: context,
                title: "Sign In Failed",
                message:
                    "Google sign-in couldn't be completed. Please try again.",
                isError: true,
              );
            }
          }
          return;
        }

        debugPrint(
          'Google authentication cancelled or failed - stopping (no browser fallback)',
        );
        return;
      }

      debugPrint('Non-mobile/web platform - using Supabase OAuth');
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

    if (!mounted) return;
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
            }
            return;
          } else if (fbResult.status == LoginStatus.cancelled) {
            debugPrint('User cancelled Facebook native login');
            return;
          }

          debugPrint(
            'Native Facebook login failed (status: ${fbResult.status}), falling back to web',
          );
        } catch (e) {
          debugPrint('Native Facebook login threw exception: $e');
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

    if (!mounted) return;
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
              if (credential.authorizationCode.isNotEmpty) {
                try {
                  await supabase.functions.invoke(
                    'save-apple-auth-code',
                    body: {'authorizationCode': credential.authorizationCode},
                  );
                  debugPrint(
                    '✅ Apple authorization code saved for revocation later',
                  );
                } catch (e) {
                  debugPrint('⚠️ Failed to save Apple authorization code: $e');
                }
              }

              await _completeAppleSignIn(
                user: user,
                session: session,
                userWantsAutoLogin: userWantsAutoLogin,
                marketingConsent: marketingConsent,
                existingRoles: returningUserCheck.existingRoles,
              );
            }
          }
          return;
        } on SignInWithAppleAuthorizationException catch (e) {
          if (e.code == AuthorizationErrorCode.canceled) {
            debugPrint('User cancelled native Apple Sign-In');
            return;
          }
          debugPrint(
            'Native Apple Sign-In authorization error: ${e.code} - ${e.message}',
          );
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

    final redirectUrl = _env.getRedirectUrl();
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

    if (!mounted) return;
    await _handlePostLogin(user.id);
  }

  Future<void> _handlePostLogin(String userId) async {
    if (!mounted) return;

    try {
      await SessionManager.setPendingQuickLogout(false);
      await appState.refreshState();
    } catch (e) {
      debugPrint('❌ Error refreshing app state after login: $e');
    }

    if (!mounted) return;

    // Restore / reactivation pending නම් කෙලින්ම ඒ screen එකට
    if (appState.pendingDeletionRestore || appState.pendingReactivation) {
      context.go('/account-restore-pending');
      return;
    }

    context.go('/');
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
   ${_env.getRedirectUrl()}
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
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Divider(
                  color: isDark
                      ? primaryColor.withValues(alpha: 0.3)
                      : primaryColor.withValues(alpha: 0.2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or',
                  style: TextStyle(color: secondaryTextColor, fontSize: 12),
                ),
              ),
              Expanded(
                child: Divider(
                  color: isDark
                      ? primaryColor.withValues(alpha: 0.3)
                      : primaryColor.withValues(alpha: 0.2),
                ),
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

  // ============================================================
  // ✅ UI HELPERS (design only - no logic changes)
  // ============================================================

  /// Circular logo - image is clipped to a perfect circle and
  /// no background colour shows behind / around it.
  Widget _buildLogo({required double size}) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final ringColor = isDark
        ? Colors.white24
        : primaryColor.withValues(alpha: 0.25);

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: primaryColor,
              child: Center(
                child: Icon(
                  Icons.account_circle,
                  color: Colors.white,
                  size: size * 0.55,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Back arrow only (shown when a saved profile exists)
  Widget _buildSavedProfileHeader() {
    final textColor = context.textColor;

    return Align(
      alignment: Alignment.topLeft,
      child: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 24),
        onPressed: _handleBackButton,
      ),
    );
  }

  /// Email / password / remember me / login / forgot password / OAuth
  List<Widget> _buildFormChildren({required bool compact}) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final surfaceColor = context.surfaceColor;

    final hintColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final inputFillColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade50;
    final inputBorderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    // Mobile = slightly taller fields & buttons (easier to tap)
    final double fieldVPad = compact ? 12 : 12;
    final double fieldRadius = compact ? 12 : 8;

    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderSide: BorderSide(color: c, width: 1.0),
      borderRadius: BorderRadius.circular(fieldRadius),
    );

    return [
      // Email Field
      Container(
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
        child: TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Email address',
            hintStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: inputFillColor,
            contentPadding: EdgeInsets.symmetric(
              vertical: fieldVPad,
              horizontal: 16,
            ),
            enabledBorder: border(inputBorderColor),
            focusedBorder: border(primaryColor),
            errorBorder: border(Colors.redAccent),
            focusedErrorBorder: border(Colors.redAccent),
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
      ),
      const SizedBox(height: 16),

      // Password Field
      Container(
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
        child: TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: inputFillColor,
            contentPadding: EdgeInsets.symmetric(
              vertical: fieldVPad,
              horizontal: 16,
            ),
            enabledBorder: border(inputBorderColor),
            focusedBorder: border(primaryColor),
            errorBorder: border(Colors.redAccent),
            focusedErrorBorder: border(Colors.redAccent),
            suffixIcon: _passwordController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      size: 22,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    splashRadius: 20,
                  )
                : null,
            errorText: _passwordError,
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Remember Me Checkbox
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _rememberMe
              ? primaryColor.withValues(alpha: 0.1)
              : surfaceColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(fieldRadius),
          border: Border.all(
            color: _rememberMe
                ? primaryColor.withValues(alpha: 0.3)
                : inputBorderColor,
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
              activeColor: primaryColor,
              checkColor: Colors.white,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Remember Me',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_rememberMe &&
                          !_userChangedRememberMe &&
                          !_hasSavedProfile)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Recommended',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_rememberMe)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
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
        height: 42,
        child: ElevatedButton(
          onPressed: (_isValid && !_loading && !_coolDown) ? loginUser : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            disabledBackgroundColor: isDark
                ? Colors.white12
                : Colors.grey.shade300,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : _coolDown
              ? const Text(
                  'Please wait...',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                )
              : const Text(
                  'Log in',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
        ),
      ),
      const SizedBox(height: 12),

      // Forgot Password
      GestureDetector(
        onTap: () => context.push('/reset-password'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Text(
            'Forgot password?',
            style: TextStyle(
              color: hintColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),

      // OAuth Buttons
      _buildOAuthButtons(),
    ];
  }

  /// "By continuing, you agree to our Terms of Service and Privacy Policy"
  Widget _buildPrivacyLinks() {
    final primaryColor = context.primaryColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 4,
        children: [
          Text(
            'By continuing, you agree to our',
            style: TextStyle(color: secondaryTextColor, fontSize: 11),
          ),
          GestureDetector(
            onTap: () =>
                context.push('/terms?from=${Uri.encodeComponent('/login')}'),
            child: Text(
              'Terms of Service',
              style: TextStyle(
                color: primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            'and',
            style: TextStyle(color: secondaryTextColor, fontSize: 11),
          ),
          GestureDetector(
            onTap: () =>
                context.push('/privacy?from=${Uri.encodeComponent('/login')}'),
            child: Text(
              'Privacy Policy',
              style: TextStyle(
                color: primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📚 HELP & COMMUNITY (web only, bottom of the left panel): video guide,
  // YouTube channel (watch videos) and Facebook page
  // ============================================================

  Future<void> _openExternalLink(String url, String label) async {
    if (url.trim().isEmpty) {
      SimpleToast.info(context, '$label link will be added soon');
      return;
    }
    try {
      final ok = await launchUrl(
        Uri.parse(url.trim()),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        SimpleToast.info(context, 'Could not open the link');
      }
    } catch (e) {
      debugPrint('Error opening link: $e');
      if (mounted) {
        SimpleToast.info(context, 'Could not open the link');
      }
    }
  }

  /// Compact help / community links bar - sits at the bottom of the LEFT
  /// panel, next to the middle divider line (YouTube + Facebook icons).
  Widget _buildHelpLinksBar() {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        _PillLink(
          icon: Icons.smart_display_rounded,
          color: const Color(0xFFFF0000),
          label: 'Watch',
          tooltip: 'Watch videos on YouTube',
          onTap: () => _openExternalLink(_kYoutubeUrl, 'YouTube'),
        ),
        _PillLink(
          icon: Icons.facebook_rounded,
          color: const Color(0xFF1877F2),
          tooltip: 'Visit our Facebook page',
          onTap: () => _openExternalLink(_kFacebookPageUrl, 'Facebook page'),
        ),
      ],
    );
  }

  // ============================================================
  // 📲 APP DOWNLOAD (web only)
  // ============================================================

  Future<void> _openAppLink(String url, String storeName) async {
    if (url.trim().isEmpty) {
      SimpleToast.info(context, '$storeName app link is coming soon');
      return;
    }
    try {
      final ok = await launchUrl(
        Uri.parse(url.trim()),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        SimpleToast.info(context, 'Could not open the download link');
      }
    } catch (e) {
      debugPrint('Error opening app link: $e');
      if (mounted) {
        SimpleToast.info(context, 'Could not open the download link');
      }
    }
  }

  Widget _buildAppDownloadSection() {
    final secondaryTextColor = context.secondaryTextColor;
    final dividerColor = context.dividerColor;
    final textColor = context.textColor;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: [
          Divider(color: dividerColor, thickness: 1),
          const SizedBox(height: 12),
          Text(
            'Get the mobile app',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StoreButton(
                  icon: Icons.android,
                  iconColor: const Color(0xFF3DDC84),
                  caption: 'Download for',
                  title: 'Android',
                  onTap: () => _openAppLink(_kAndroidAppUrl, 'Android'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StoreButton(
                  icon: Icons.apple,
                  iconColor: textColor,
                  caption: 'Download for',
                  title: 'iOS',
                  onTap: () => _openAppLink(_kIosAppUrl, 'iOS'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 💻 WEB LAYOUT - full screen split (left hero / right form)
  //    + footer: Privacy Policy · Terms of Service · Help
  // ============================================================

  Widget _buildWebLayout(Size size) {
    final backgroundColor = context.backgroundColor;
    final dividerColor = context.dividerColor;
    final textColor = context.textColor;
    final isDark = context.isDarkMode;

    // Hide the left hero panel on medium widths so the form never gets cramped
    final bool showHero = size.width >= 1000;

    // Login panel is narrow (about 1/3), the left side takes the rest
    final double rightW = (size.width * 0.32).clamp(400.0, 480.0).toDouble();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // ---------------- MAIN AREA (fills the screen) ----------------
              Expanded(
                child: Row(
                  children: [
                    // ===== LEFT: logo + illustration + headline =====
                    if (showHero) Expanded(child: _buildWebHero()),

                    // ===== vertical divider =====
                    if (showHero)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: dividerColor,
                      ),

                    // ===== RIGHT: login form =====
                    _rightSlot(
                      showHero,
                      rightW,
                      Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Back button when a saved profile exists
                                if (_hasSavedProfile)
                                  _buildSavedProfileHeader(),

                                // Logo shown here only when hero panel is hidden
                                if (!showHero)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 20,
                                      ),
                                      child: _buildLogo(size: 72),
                                    ),
                                  ),

                                // Title + who can log in
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Log in to your account',
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Customers, barbers and salon owners all sign in here.',
                                        style: TextStyle(
                                          color: context.secondaryTextColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (!showHero) ...[
                                        const SizedBox(height: 12),
                                        _buildRoleChips(),
                                      ],
                                    ],
                                  ),
                                ),

                                // Email / password / remember me / login /
                                // forgot password / OAuth buttons
                                ..._buildFormChildren(compact: false),

                                // Download the mobile app (Android / iOS)
                                _buildAppDownloadSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ---------------- FOOTER ----------------
              Divider(
                height: 1,
                thickness: 1,
                color: isDark ? Colors.white12 : dividerColor,
              ),
              _buildWebFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// Right slot: fixed (narrow) width next to the hero, or full width when
  /// the hero panel is hidden.
  Widget _rightSlot(bool showHero, double width, Widget child) {
    return showHero
        ? SizedBox(width: width, child: child)
        : Expanded(child: child);
  }

  /// Left panel: logo (top-left) + animated role showcase
  /// (image cards in the centre, headline at the bottom-left)
  Widget _buildWebHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
      child: _RoleShowcase(
        logo: _buildLogo(size: 60),
        footer: _buildHelpLinksBar(),
      ),
    );
  }

  /// Small role chips - shown above the form when the hero panel is hidden
  Widget _buildRoleChips() {
    final secondaryTextColor = context.secondaryTextColor;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kRoles.map((r) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: r.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(r.icon, size: 14, color: r.color),
              const SizedBox(width: 6),
              Text(
                r.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Footer: Privacy Policy · Terms of Service · Help (+ app version)
  Widget _buildWebFooter() {
    final secondaryTextColor = context.secondaryTextColor;
    final primaryColor = context.primaryColor;

    Widget link(String label, String route) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () =>
            context.push('$route?from=${Uri.encodeComponent('/login')}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          link('Privacy Policy', '/privacy'),
          link('Terms of Service', '/terms'),
          link('Help', '/help'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'v${AppVersion.version}',
              style: TextStyle(
                color: primaryColor.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD METHOD
  //   • Web / wide screen  -> full-screen split layout + footer
  //   • Mobile             -> frame removed, full screen layout (unchanged)
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.backgroundColor;
    final dividerColor = context.dividerColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;

    // ------------------------------------------------------------
    // 📱 MOBILE - full screen, no frame / card / border (UNCHANGED)
    // ------------------------------------------------------------
    if (!isWeb) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ---------- TOP: header + logo + form ----------
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Back button (only when saved profile exists)
                            if (_hasSavedProfile)
                              _buildSavedProfileHeader()
                            else
                              const SizedBox(height: 16),

                            // Logo (circle)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 0,
                                bottom: 20,
                              ),
                              child: _buildLogo(size: 80),
                            ),

                            // Form
                            ..._buildFormChildren(compact: true),
                          ],
                        ),

                        // ---------- BOTTOM: divider + privacy ----------
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 16),
                            Divider(color: dividerColor, thickness: 1),
                            const SizedBox(height: 16),
                            _buildPrivacyLinks(),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    // ------------------------------------------------------------
    // 💻 WEB - full screen split layout
    // ------------------------------------------------------------
    return _buildWebLayout(size);
  }
}

// ============================================================
// ✅ SOCIAL LOGIN BUTTON - Using AppTheme
// ============================================================

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
        return SvgPicture.asset(
          'assets/icons/google.svg',
          width: 18,
          height: 18,
        );
      case 'facebook':
        return SvgPicture.asset(
          'assets/icons/facebook.svg',
          width: 18,
          height: 18,
        );
      case 'apple':
        return SvgPicture.asset(
          'assets/icons/apple.svg',
          width: 20,
          height: 20,
        );
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
    // Same provider colours in light AND dark mode
    final buttonColor = _getButtonColor();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: buttonColor.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          minimumSize: const Size(0, 48),
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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _getIcon(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _getButtonText(),
                      style: TextStyle(
                        color: buttonColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}


// ============================================================
// ROLE DATA
//  Put your photos in  assets/images/roles/  (and list that folder in
//  pubspec.yaml under flutter -> assets). If a photo is missing, the
//  card automatically shows a coloured background with a big icon,
//  so nothing ever breaks.
// ============================================================

class _RoleCardInfo {
  final String label;
  final IconData icon;
  final String image;

  const _RoleCardInfo(this.label, this.icon, this.image);
}

class _RoleInfo {
  final String title;
  final IconData icon;
  final Color color;
  final String headlineTop;
  final String headlineAccent;
  final List<String> texts; // the text list shown on the right side
  final List<_RoleCardInfo> cards;
  final IconData badgeIcon;
  final Color badgeColor;
  final String? badgeText;

  const _RoleInfo({
    required this.title,
    required this.icon,
    required this.color,
    required this.headlineTop,
    required this.headlineAccent,
    required this.texts,
    required this.cards,
    required this.badgeIcon,
    required this.badgeColor,
    this.badgeText,
  });
}

const List<_RoleInfo> _kRoles = [
  _RoleInfo(
    title: 'Customer',
    icon: Icons.person_rounded,
    color: Colors.green,
    headlineTop: 'Find the\nstyle\n',
    headlineAccent: 'you love.',
    texts: [
      'Find salons & barbers',
      'Book appointments fast',
      'Track your bookings',
    ],
    cards: [
      _RoleCardInfo(
        'Top salons',
        Icons.storefront_rounded,
        'assets/images/roles/customer_1.webp',
      ),
      _RoleCardInfo(
        'Book in seconds',
        Icons.calendar_month_rounded,
        'assets/images/roles/customer_2.webp',
      ),
      _RoleCardInfo(
        'Your barber',
        Icons.content_cut_rounded,
        'assets/images/roles/customer_3.webp',
      ),
    ],
    badgeIcon: Icons.favorite_rounded,
    badgeColor: Color(0xFFE53958),
  ),
  _RoleInfo(
    title: 'Barber',
    icon: Icons.content_cut_rounded,
    color: Colors.orange,
    headlineTop: 'Manage\nyour day\n',
    headlineAccent: 'your way.',
    texts: [
      'Manage your appointments',
      'See your daily schedule',
      'Serve customers at your salon',
    ],
    cards: [
      _RoleCardInfo(
        'Appointments',
        Icons.event_available_rounded,
        'assets/images/roles/barber_1.webp',
      ),
      _RoleCardInfo(
        'Daily schedule',
        Icons.schedule_rounded,
        'assets/images/roles/barber_2.webp',
      ),
      _RoleCardInfo(
        'Happy clients',
        Icons.sentiment_very_satisfied_rounded,
        'assets/images/roles/barber_3.webp',
      ),
    ],
    badgeIcon: Icons.schedule_rounded,
    badgeColor: Color(0xFF5B5BD6),
    badgeText: '10:30',
  ),
  _RoleInfo(
    title: 'Salon Owner',
    icon: Icons.storefront_rounded,
    color: Colors.blueAccent,
    headlineTop: 'Build the\nsalon\n',
    headlineAccent: 'you dream of.',
    texts: [
      'Create & manage your salon',
      'Add & manage your barbers',
      'All appointments in one place',
    ],
    cards: [
      _RoleCardInfo(
        'Your salon',
        Icons.storefront_rounded,
        'assets/images/roles/owner_1.webp',
      ),
      _RoleCardInfo(
        'Your barbers',
        Icons.groups_rounded,
        'assets/images/roles/owner_2.webp',
      ),
      _RoleCardInfo(
        'All bookings',
        Icons.event_note_rounded,
        'assets/images/roles/owner_3.webp',
      ),
    ],
    badgeIcon: Icons.trending_up_rounded,
    badgeColor: Color(0xFF1E9E5A),
  ),
];

// ============================================================
// ANIMATION SPEED  (change these numbers to make it faster / slower)
// ============================================================
const Duration _kRoleHold = Duration(seconds: 6); // time each role stays
const Duration _kSceneAnim = Duration(milliseconds: 1600); // cards in
const Duration _kTextAnim = Duration(milliseconds: 1500); // text list in
const Duration _kHeadlineAnim = Duration(milliseconds: 600); // headline in
const Duration _kFadeOut = Duration(milliseconds: 300); // old content out

Widget _topLeftLayout(Widget? current, List<Widget> previous) {
  return Stack(
    alignment: Alignment.topLeft,
    clipBehavior: Clip.none,
    children: [...previous, ?current],
  );
}

// ============================================================
// ANIMATED ROLE SHOWCASE
//  - Own StatefulWidget + own Timer: only THIS widget rebuilds, the
//    login form (text fields) is never rebuilt by the animation.
//  - Implicit animations only (no per-frame controllers),
//    RepaintBoundary around the scene.
//  - Keeps changing no matter where the user clicks. It only stops when
//    a role chip is tapped (tap the same chip again to resume).
//    Respects the "reduce motion" accessibility setting.
// ============================================================

class _RoleShowcase extends StatefulWidget {
  final Widget logo;
  final Widget? footer; // e.g. help links, bottom-right (next to the divider)

  const _RoleShowcase({required this.logo, this.footer});

  @override
  State<_RoleShowcase> createState() => _RoleShowcaseState();
}

class _RoleShowcaseState extends State<_RoleShowcase> {
  Timer? _timer;
  int _active = 0;
  bool _pinned = false; // true after the user taps a role chip

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_kRoleHold, (_) {
      if (!mounted || _pinned) return;
      setState(() => _active = (_active + 1) % _kRoles.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final fadeIn = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 350);
    final fadeOut = reduceMotion ? Duration.zero : _kFadeOut;
    final headlineIn = reduceMotion ? Duration.zero : _kHeadlineAnim;
    final chipAnim = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 300);

    final role = _kRoles[_active];
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final isDark = context.isDarkMode;

    final headline = SizedBox(
      height: 150,
      child: AnimatedSwitcher(
        duration: headlineIn,
        reverseDuration: fadeOut,
        layoutBuilder: _topLeftLayout,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text.rich(
          key: ValueKey(_active),
          TextSpan(
            style: TextStyle(
              color: textColor,
              fontSize: 44,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
            children: [
              TextSpan(text: role.headlineTop),
              TextSpan(
                text: role.headlineAccent,
                style: TextStyle(color: role.color),
              ),
            ],
          ),
        ),
      ),
    );

    final textList = SizedBox(
      height: 100,
      child: AnimatedSwitcher(
        duration: fadeIn,
        reverseDuration: fadeOut,
        layoutBuilder: _topLeftLayout,
        child: _RoleTextList(
          key: ValueKey(_active),
          info: role,
          instant: reduceMotion,
        ),
      ),
    );

    final roleChips = Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _kRoles.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (_pinned && _active == i) {
                      // tapping the pinned role again -> auto change resumes
                      setState(() => _pinned = false);
                      _startTimer();
                    } else {
                      // user picked a role -> auto change stops
                      _timer?.cancel();
                      setState(() {
                        _active = i;
                        _pinned = true;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: chipAnim,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: i == _active
                          ? _kRoles[i].color.withValues(alpha: 0.15)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: i == _active
                            ? _kRoles[i].color.withValues(alpha: 0.6)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _kRoles[i].icon,
                          size: 16,
                          color: i == _active
                              ? _kRoles[i].color
                              : secondaryTextColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _kRoles[i].title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: i == _active ? textColor : secondaryTextColor,
                          ),
                        ),
                        if (_pinned && i == _active) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: _kRoles[i].color,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- top row: logo (left) + role chips (right) ----------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.logo,
              const SizedBox(width: 24),
              Expanded(child: roleChips),
            ],
          ),

          // ---------- image cards (centre) ----------
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                // Scale the scene to the free space (up to 1.4x bigger)
                final sx = c.maxWidth / 400;
                final sy = c.maxHeight / 440;
                final scale = (sx < sy ? sx : sy).clamp(0.3, 1.4).toDouble();

                return Center(
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: 400 * scale,
                      height: 440 * scale,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 400,
                          height: 440,
                          child: AnimatedSwitcher(
                            duration: fadeIn,
                            reverseDuration: fadeOut,
                            child: _RoleScene(
                              key: ValueKey(_active),
                              info: role,
                              instant: reduceMotion,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ---------- headline (left) + text list (right) ----------
          // Wide panel  -> side by side
          // Narrow panel -> text list under the headline
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 600) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    headline,
                    const SizedBox(width: 32),
                    Expanded(child: textList),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [headline, const SizedBox(height: 4), textList],
              );
            },
          ),


          if (widget.footer != null) ...[
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerRight, child: widget.footer!),
          ],
        ],
      ),
    );
  }
}

/// The text list for ONE role. Each line slides in from the RIGHT
/// towards the left, one after another.
class _RoleTextList extends StatelessWidget {
  final _RoleInfo info;
  final bool instant;

  const _RoleTextList({super.key, required this.info, this.instant = false});

  @override
  Widget build(BuildContext context) {
    final textColor = context.textColor;
    final total = instant ? Duration.zero : _kTextAnim;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < info.texts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StaggerIn(
              duration: total,
              start: 0.15 + i * 0.2,
              end: (0.15 + i * 0.2 + 0.4).clamp(0.0, 1.0),
              offset: const Offset(56, 0), // starts on the right
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: info.color),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      info.texts[i],
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The 3 image cards + floating badge for ONE role.
/// Each card slides/fades in one after another (staggered, slow).
class _RoleScene extends StatelessWidget {
  final _RoleInfo info;
  final bool instant;

  const _RoleScene({super.key, required this.info, this.instant = false});

  @override
  Widget build(BuildContext context) {
    final cards = info.cards;
    final hasText = info.badgeText != null;
    final total = instant ? Duration.zero : _kSceneAnim;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // back-left card
        Positioned(
          left: 0,
          top: 60,
          child: _StaggerIn(
            duration: total,
            start: 0.0,
            end: 0.4,
            child: _ImageCard(
              info: cards[0],
              color: info.color,
              shade: 0.0,
              width: 190,
              height: 240,
            ),
          ),
        ),

        // main tall card (right)
        Positioned(
          left: 150,
          top: 0,
          child: _StaggerIn(
            duration: total,
            start: 0.15,
            end: 0.55,
            child: _ImageCard(
              info: cards[1],
              color: info.color,
              shade: 0.22,
              width: 240,
              height: 340,
            ),
          ),
        ),

        // bottom card (overlaps the other two)
        Positioned(
          left: 70,
          top: 270,
          child: _StaggerIn(
            duration: total,
            start: 0.3,
            end: 0.7,
            child: _ImageCard(
              info: cards[2],
              color: info.color,
              shade: 0.42,
              width: 230,
              height: 170,
            ),
          ),
        ),

        // floating badge (heart / time / trend)
        Positioned(
          right: 0,
          bottom: 90,
          child: _PopIn(
            duration: total,
            start: 0.6,
            end: 1.0,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: hasText ? 14 : 16,
                vertical: hasText ? 10 : 16,
              ),
              decoration: BoxDecoration(
                color: info.badgeColor,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    info.badgeIcon,
                    color: Colors.white,
                    size: hasText ? 18 : 26,
                  ),
                  if (hasText) ...[
                    const SizedBox(width: 6),
                    Text(
                      info.badgeText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One image card: photo (or coloured fallback with a big icon),
/// small icon badge on the top-left, label at the bottom.
class _ImageCard extends StatelessWidget {
  final _RoleCardInfo info;
  final Color color;
  final double shade;
  final double width;
  final double height;

  const _ImageCard({
    required this.info,
    required this.color,
    required this.shade,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final base = Color.lerp(color, Colors.black, shade) ?? color;

    // Shown when the photo is not available -> big icon instead
    Widget fallback() {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base.withValues(alpha: 0.95), base.withValues(alpha: 0.55)],
          ),
        ),
        child: Center(
          child: Icon(
            info.icon,
            size: (width < height ? width : height) * 0.38,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              info.image,
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (context, error, stackTrace) => fallback(),
            ),

            // soft dark gradient so the label is always readable
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),

            // small icon badge (top-left)
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(info.icon, size: 18, color: base),
              ),
            ),

            // label (bottom-left)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text(
                info.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + slide in. It plays only between [start] and [end] (0..1) of the
/// total [duration], so several of these can be staggered one after another.
/// [offset] is where it starts from (default: 24px below its final place).
class _StaggerIn extends StatelessWidget {
  final Duration duration;
  final double start;
  final double end;
  final Offset offset;
  final Widget child;

  const _StaggerIn({
    required this.duration,
    required this.child,
    this.start = 0.0,
    this.end = 1.0,
    this.offset = const Offset(0, 24),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(offset.dx * (1 - v), offset.dy * (1 - v)),
          child: child,
        ),
      ),
    );
  }
}

/// Pop (scale) in with a little bounce, between [start] and [end].
class _PopIn extends StatelessWidget {
  final Duration duration;
  final double start;
  final double end;
  final Widget child;

  const _PopIn({
    required this.duration,
    required this.child,
    this.start = 0.0,
    this.end = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Interval(start, end, curve: Curves.easeOutBack),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: v, child: child),
      ),
    );
  }
}


// ============================================================
// STORE BUTTON (Android / iOS download)
// ============================================================

class _StoreButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String caption;
  final String title;
  final VoidCallback onTap;

  const _StoreButton({
    required this.icon,
    required this.iconColor,
    required this.caption,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondaryTextColor, fontSize: 10),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ============================================================
// PILL LINK (YouTube / Facebook icon buttons)
//   label given   -> pill with icon + text
//   label == null -> round icon-only button (with tooltip)
// ============================================================

class _PillLink extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  const _PillLink({
    required this.icon,
    required this.color,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final hasLabel = label != null;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: hasLabel ? 14 : 10,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              if (hasLabel) ...[
                const SizedBox(width: 8),
                Text(
                  label!,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}