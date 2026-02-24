import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, kReleaseMode, defaultTargetPlatform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/simple_toast.dart';

// ✅ Class for returning user check
class _ReturningUserCheck {
  final String? email;
  final bool hasConsent;
  final bool hasAutoLoginSetting;

  _ReturningUserCheck({
    this.email,
    this.hasConsent = false,
    this.hasAutoLoginSetting = false,
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
  TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = false;
  bool _coolDown = false;
  bool _rememberMe = false;
  bool _loadingGoogle = false;
  bool _loadingFacebook = false;
  bool _loadingApple = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String? _emailError;
  String? _passwordError;
  bool _isValid = false;
  bool _isValidEmail = false;
  bool _hasSavedProfile = false;

  final supabase = Supabase.instance.client;
  final EnvironmentManager _env = EnvironmentManager();
  late PackageInfo _packageInfo;
  DateTime? _termsAcceptedAt;
  DateTime? _privacyAcceptedAt;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _loadConsentStatus();
    _checkSavedProfile();
    _loadRememberMeSetting();

    // Initialize controllers
    if (widget.prefilledEmail != null) {
      _emailController = TextEditingController(text: widget.prefilledEmail);
      if (kDebugMode) {
        print('📧 Prefilled email: ${widget.prefilledEmail}');
      }
    } else {
      _emailController = TextEditingController();
    }

    // ✅ FIX: Set initial state with NO ERRORS
    _emailError = null;
    _passwordError = null;
    _isValidEmail = true;
    _isValid = false; // Initially false because fields are empty

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

    // ✅ FIX: Don't validate immediately - wait for user interaction
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only set text, don't validate
      if (widget.prefilledEmail != null && widget.prefilledEmail!.isNotEmpty) {
        _emailController.text = widget.prefilledEmail!;
      }

      if (widget.showMessage && widget.message != null) {
        _showCustomMessage(widget.message!);
      }
    });

    // Add listeners but don't trigger validation immediately
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_onPasswordChanged);
  }

  // ✅ FIX: Separate validation from listeners
  void _onEmailChanged() {
    // Only validate if user has interacted or field is not empty
    if (_emailController.text.isNotEmpty) {
      _validateEmail();
    } else {
      // Clear errors when field becomes empty
      setState(() {
        _emailError = null;
        _isValidEmail = true;
      });
    }
    _updateFormValidity();
  }

  void _onPasswordChanged() {
    // Only validate if user has interacted or field is not empty
    if (_passwordController.text.isNotEmpty) {
      _validatePassword();
    } else {
      // Clear errors when field becomes empty
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

  // Keep this for backward compatibility
  void _validateForm() {
    _validateEmail();
    _validatePassword();
    _updateFormValidity();
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

  Future<void> _loadRememberMeSetting() async {
    try {
      final rememberMe = await SessionManager.isRememberMeEnabled();
      setState(() {
        _rememberMe = rememberMe;
      });
    } catch (e) {
      print('❌ Error loading remember me: $e');
      setState(() => _rememberMe = false);
    }
  }

  Future<void> _initPackageInfo() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      print('❌ Error getting package info: $e');
      _packageInfo = PackageInfo(
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
      if (kDebugMode) print('❌ Error loading consent: $e');
    }
  }

  // ✅ Check if consent is required for this user
  Future<bool> _shouldShowConsent(String email) async {
    try {
      final profiles = await SessionManager.getProfiles();
      final userProfile = profiles.firstWhere(
        (p) => p['email'] == email,
        orElse: () => {},
      );

      // Check if user has already given consent
      if (userProfile.isNotEmpty) {
        final termsAccepted = userProfile['termsAcceptedAt'] != null;
        final privacyAccepted = userProfile['privacyAcceptedAt'] != null;
        return !(termsAccepted && privacyAccepted);
      }

      // New user - requires consent
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking consent status: $e');
      return true; // Safe default - show consent
    }
  }

  // ✅ Check if user is returning
  Future<_ReturningUserCheck> _checkIfReturningUser(String provider) async {
    try {
      final profiles = await SessionManager.getProfiles();
      if (profiles.isEmpty) {
        return _ReturningUserCheck();
      }

      // Find profile with matching provider
      for (var profile in profiles) {
        final profileProvider = profile['provider']?.toString().toLowerCase();
        if (profileProvider == provider.toLowerCase()) {
          final email = profile['email']?.toString();
          final termsAccepted = profile['termsAcceptedAt'] != null;
          final privacyAccepted = profile['privacyAcceptedAt'] != null;
          final hasRememberMe = profile['rememberMe'] == true;

          return _ReturningUserCheck(
            email: email,
            hasConsent: termsAccepted && privacyAccepted,
            hasAutoLoginSetting: hasRememberMe,
          );
        }
      }

      return _ReturningUserCheck();
    } catch (e) {
      if (kDebugMode) print('❌ Error checking returning user: $e');
      return _ReturningUserCheck();
    }
  }

  bool _isValidEmailFormat(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value);
  }

  Future<void> _checkSavedProfile() async {
    try {
      final profiles = await SessionManager.getProfiles();
      setState(() {
        _hasSavedProfile = profiles.isNotEmpty;
      });
    } catch (e) {
      print('❌ Error checking saved profiles: $e');
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

  // ✅ Save OAuth profile with user choice
  Future<void> _saveOAuthProfile({
    required User user,
    required String providerToSave,
    required bool rememberMe,
    String? accessToken,
    String? refreshToken,
  }) async {
    try {
      final email = user.email!;
      final now = DateTime.now();

      print('=' * 60);
      print('🔍 DEBUG: _saveOAuthProfile');
      print('=' * 60);
      print('📧 User email: $email');
      print('🎯 Provider parameter: "$providerToSave"');
      print('🆔 User ID: ${user.id}');

      final userMetadata = user.userMetadata ?? {};
      final appMetadata = user.appMetadata;

      // Determine final provider
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

      // Get photo URL
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

      // Get name
      String name = email.split('@').first;
      if (userMetadata['full_name'] != null &&
          userMetadata['full_name'].toString().isNotEmpty) {
        name = userMetadata['full_name'].toString();
      } else if (userMetadata['name'] != null &&
          userMetadata['name'].toString().isNotEmpty) {
        name = userMetadata['name'].toString();
      }

      print('\n💾 SAVING PROFILE:');
      print('   - Email: $email');
      print('   - Provider: $finalProvider');
      print('   - Name: $name');
      print('   - Photo: ${photoUrl ?? "No photo"}');
      print('   - Remember Me: $rememberMe');

      // Save with CORRECT provider
      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: name,
        photo: photoUrl ?? '',
        rememberMe: rememberMe,
        refreshToken: refreshToken,
        accessToken: accessToken,
        provider: finalProvider,
        termsAcceptedAt: _termsAcceptedAt ?? now,
        privacyAcceptedAt: _privacyAcceptedAt ?? now,
        marketingConsent: false,
        marketingConsentAt: null,
      );

      print('✅ Profile saved with provider: $finalProvider');
    } catch (e, stackTrace) {
      print('❌ Error in _saveOAuthProfile: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // ✅ COMPLIANT: Login with user consent (FIRST TIME ONLY)
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

      // Check if consent needed (FIRST TIME ONLY)
      final needsConsent = await _shouldShowConsent(email);
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loading = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent (already given)');
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

      if (kDebugMode) {
        print('🎉 LOGIN SUCCESS: ${user.email}');
        print('   - Remember Me: $_rememberMe');
      }

      await _saveOAuthProfile(
        user: user,
        providerToSave: 'email',
        rememberMe: _rememberMe,
        accessToken: session?.accessToken,
        refreshToken: session?.refreshToken,
      );

      // ✅ Don't check profile directly - use _handlePostLogin
      appState.refreshState();
      if (!mounted) return;

      // ✅ Use _handlePostLogin for role-based redirect
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
        _emailController.text.trim();
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

  // ✅ COMPLIANT: Google OAuth with FIRST-TIME consent only
  Future<void> _signInWithGoogle() async {
    if (_loadingGoogle) return;

    try {
      setState(() => _loadingGoogle = true);

      if (kDebugMode) {
        print('🔵 Google OAuth starting...');
      }

      // 1. Check if this is a returning user
      final returningUser = await _checkIfReturningUser('google');
      bool needsConsent = true;

      if (returningUser.email != null) {
        needsConsent = await _shouldShowConsent(returningUser.email!);
        if (kDebugMode) {
          print('   - Returning user: ${returningUser.email}');
          print('   - Needs consent: $needsConsent');
        }
      }

      // 2. Show OAuth consent dialog
      final oauthConsent = await _showOAuthConsentDialog(
        provider: 'Google',
        scopes: ['email', 'profile'],
      );
      if (!oauthConsent) {
        setState(() => _loadingGoogle = false);
        return;
      }

      // 3. Show App Store compliant consent dialog (FIRST TIME ONLY)
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loadingGoogle = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent dialog (already given)');
      }

      // 4. Ask user about auto-login preference
      bool userWantsAutoLogin = _rememberMe;

      if (needsConsent || !returningUser.hasAutoLoginSetting) {
        userWantsAutoLogin = await _showAutoLoginConsentDialog(
          provider: 'Google',
        );
      }

      // 5. Set based on user's choice
      setState(() => _rememberMe = userWantsAutoLogin);
      await SessionManager.setRememberMe(userWantsAutoLogin);
      await appState.setRememberMe(userWantsAutoLogin);

      // Setup auth listener
      _authSubscription?.cancel();
      _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          await Future.delayed(const Duration(seconds: 2));
          final user = supabase.auth.currentUser;
          final session = supabase.auth.currentSession;

          if (user != null && user.email != null) {
            print('✅ Google OAuth User Signed In: ${user.email}');
            print('   - User wants auto-login: $userWantsAutoLogin');

            await _saveOAuthProfile(
              user: user,
              providerToSave: 'google',
              rememberMe: userWantsAutoLogin,
              accessToken: session?.accessToken,
              refreshToken: session?.refreshToken,
            );

            // ✅ Use _handlePostLogin for role-based redirect
            await _handlePostLogin(user.id);
          }
        }
      });

      // Sign in
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _getRedirectUrl(),
        scopes: 'email profile',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Google Sign In Failed",
        message: _getOAuthErrorMessage(e, 'Google'),
        isError: true,
      );
    } catch (e) {
      print('❌ Google OAuth error: $e');
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

  // ✅ COMPLIANT: Facebook OAuth with FIRST-TIME consent only
  Future<void> _signInWithFacebook() async {
    if (_loadingFacebook) return;

    try {
      setState(() => _loadingFacebook = true);

      if (!_env.enableFacebookOAuth) {
        SimpleToast.info(context, 'Facebook sign in is currently disabled');
        return;
      }

      if (kDebugMode) {
        print('🔵 Facebook OAuth starting...');
      }

      // 1. Check if returning user
      final returningUser = await _checkIfReturningUser('facebook');
      bool needsConsent = true;

      if (returningUser.email != null) {
        needsConsent = await _shouldShowConsent(returningUser.email!);
        if (kDebugMode) {
          print('   - Returning user: ${returningUser.email}');
          print('   - Needs consent: $needsConsent');
        }
      }

      // 2. OAuth consent
      final oauthConsent = await _showOAuthConsentDialog(
        provider: 'Facebook',
        scopes: ['email'],
      );
      if (!oauthConsent) {
        setState(() => _loadingFacebook = false);
        return;
      }

      // 3. App consent (FIRST TIME ONLY)
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loadingFacebook = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent (already given)');
      }

      // 4. Auto-login consent
      bool userWantsAutoLogin = _rememberMe;

      if (needsConsent || !returningUser.hasAutoLoginSetting) {
        userWantsAutoLogin = await _showAutoLoginConsentDialog(
          provider: 'Facebook',
        );
      }

      setState(() => _rememberMe = userWantsAutoLogin);
      await SessionManager.setRememberMe(userWantsAutoLogin);
      await appState.setRememberMe(userWantsAutoLogin);

      _authSubscription?.cancel();
      _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          await Future.delayed(const Duration(seconds: 2));
          final user = supabase.auth.currentUser;
          final session = supabase.auth.currentSession;

          if (user != null && user.email != null) {
            print('✅ Facebook OAuth User Signed In: ${user.email}');

            await _saveOAuthProfile(
              user: user,
              providerToSave: 'facebook',
              rememberMe: userWantsAutoLogin,
              accessToken: session?.accessToken,
              refreshToken: session?.refreshToken,
            );

            // ✅ Use _handlePostLogin for role-based redirect
            await _handlePostLogin(user.id);
          }
        }
      });

      await supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: _getRedirectUrl(),
        scopes: 'public_profile',
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
      print('❌ Facebook OAuth error: $e');
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

  // ✅ Apple Sign In with compliance
  Future<void> _signInWithApple() async {
    if (_loadingApple) return;

    try {
      setState(() => _loadingApple = true);

      if (kDebugMode) {
        print('🔵 Apple Sign In starting...');
      }

      // 1. Check if returning user
      final returningUser = await _checkIfReturningUser('apple');
      bool needsConsent = true;

      if (returningUser.email != null) {
        needsConsent = await _shouldShowConsent(returningUser.email!);
        if (kDebugMode) {
          print('   - Returning user: ${returningUser.email}');
          print('   - Needs consent: $needsConsent');
        }
      }

      // 2. Apple requires explicit OAuth consent
      final oauthConsent = await _showOAuthConsentDialog(
        provider: 'Apple',
        scopes: ['email', 'name'],
      );
      if (!oauthConsent) {
        setState(() => _loadingApple = false);
        return;
      }

      // 3. App consent (FIRST TIME ONLY)
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loadingApple = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent (already given)');
      }

      // 4. Apple is strict about auto-login
      bool userWantsAutoLogin = _rememberMe;

      if (needsConsent || !returningUser.hasAutoLoginSetting) {
        userWantsAutoLogin = await _showAutoLoginConsentDialog(
          provider: 'Apple',
          defaultToFalse: true,
        );
      }

      setState(() => _rememberMe = userWantsAutoLogin);
      await SessionManager.setRememberMe(userWantsAutoLogin);
      await appState.setRememberMe(userWantsAutoLogin);

      _authSubscription?.cancel();
      _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.signedIn) {
          await Future.delayed(const Duration(seconds: 2));
          final user = supabase.auth.currentUser;
          final session = supabase.auth.currentSession;

          if (user != null && user.email != null) {
            print('✅ Apple OAuth User Signed In: ${user.email}');

            await _saveOAuthProfile(
              user: user,
              providerToSave: 'apple',
              rememberMe: userWantsAutoLogin,
              accessToken: session?.accessToken,
              refreshToken: session?.refreshToken,
            );

            // ✅ Use _handlePostLogin for role-based redirect
            await _handlePostLogin(user.id);
          }
        }
      });

      await supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: _getRedirectUrl(),
        scopes: 'email name',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Apple Sign In Failed",
        message: _getOAuthErrorMessage(e, 'Apple'),
        isError: true,
      );
    } catch (e) {
      print('❌ Apple Sign In error: $e');
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

  // ✅ FIXED: Handle post-login with role-based redirect
  Future<void> _handlePostLogin(String userId) async {
    try {
      if (!mounted) return;

      await Future.delayed(const Duration(seconds: 1));

      // Get user email
      final user = supabase.auth.currentUser;
      if (user == null || user.email == null) {
        if (mounted) context.go('/');
        return;
      }

      final email = user.email!;

      // Check if profile exists and is active
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
            context.go('/login');
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
            context.go('/login');
          }
          return;
        }
      }

      // Get ALL profiles for this user (multiple roles)
      final profiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            is_active,
            is_blocked,
            roles!inner (
              name
            )
          ''')
          .eq('id', userId)
          .eq('is_active', true)
          .eq('is_blocked', false);

      print('📊 Found ${profiles.length} active profiles for user: $email');

      // Extract role names from profiles
      final List<String> roleNames = [];
      for (var profile in profiles) {
        final role = profile['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }

      print('📋 User roles: $roleNames');

      // ✅ SAVE ALL ROLES to SessionManager
      await SessionManager.saveUserRoles(email: email, roles: roleNames);

      if (roleNames.isEmpty) {
        // No roles - go to registration
        print('📍 No roles found - redirecting to /reg');
        if (mounted) context.go('/reg');
        return;
      }

      // If only ONE role, redirect directly
      if (roleNames.length == 1) {
        final singleRole = roleNames.first;
        print('🎯 Single role detected: $singleRole');

        // Save current role
        await SessionManager.saveCurrentRole(singleRole);

        // Update app state
        await appState.refreshState();

        if (!mounted) return;

        // Redirect based on role
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

      // If MULTIPLE roles, show role selector
      if (roleNames.length > 1) {
        print('🔄 Multiple roles detected - showing role selector');

        // Check for saved role preference
        final savedRole = await SessionManager.getCurrentRole();

        if (savedRole != null && roleNames.contains(savedRole)) {
          print('📌 Using saved role: $savedRole');
          await SessionManager.saveCurrentRole(savedRole);
          await appState.refreshState();

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

        // No saved role or saved role not valid - show selector
        if (mounted) {
          context.go(
            '/role-selector',
            extra: {'roles': roleNames, 'email': email, 'userId': userId},
          );
        }
        return;
      }

      // Fallback - go to home
      appState.refreshState();
      if (mounted) context.go('/');
    } catch (e) {
      print('❌ Post-login error: $e');
      appState.refreshState();
      if (mounted) context.go('/');
    }
  }

  // ✅ OAuth error messages
  String _getOAuthErrorMessage(AuthException e, String provider) {
    if (kReleaseMode) {
      return "Unable to sign in with $provider. Please try again.";
    }

    final code = e.code ?? '';
    switch (code) {
      case 'oauth_callback':
      case 'invalid_client':
        return '''
$provider OAuth Configuration Required:

1. Go to ${provider} Developers Console
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

  // ✅ OAuth consent dialog (App Store compliance)
  Future<bool> _showOAuthConsentDialog({
    required String provider,
    required List<String> scopes,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text("Sign in with $provider"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$provider will share:"),
                const SizedBox(height: 8),
                for (var scope in scopes)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 4),
                    child: Text("• $scope"),
                  ),
                const SizedBox(height: 12),
                const Text("This app will:"),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Text("• Create your account"),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Text("• Show your profile"),
                ),
                const SizedBox(height: 12),
                Text(
                  "You can manage permissions in your $provider account settings.",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Continue"),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ✅ Auto-login consent dialog (App Store compliance)
  Future<bool> _showAutoLoginConsentDialog({
    required String provider,
    bool defaultToFalse = false,
  }) async {
    bool rememberMe = defaultToFalse;

    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text("$provider Sign In"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Would you like to enable quick sign-in?"),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text("Remember me on this device"),
                      subtitle: const Text(
                        "You can change this later in settings",
                      ),
                      value: rememberMe,
                      onChanged: (value) =>
                          setState(() => rememberMe = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "If enabled, you can sign in quickly next time without entering credentials.",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "You can disable this anytime in app settings.",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Skip"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, rememberMe),
                    child: Text(rememberMe ? "Enable" : "Continue"),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;
  }

  // ✅ Consent dialog with FIRST-TIME ONLY logic
  Future<bool> _showConsentDialog({bool requireExplicit = false}) async {
    // Check if user has already given consent
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      final hasConsent = !(await _shouldShowConsent(email));
      if (hasConsent) {
        if (kDebugMode)
          print('   - User already gave consent, skipping dialog');
        return true;
      }
    }

    bool? marketingConsent = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !requireExplicit,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Terms & Privacy Policy"),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "By continuing, you agree to our:",
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),

                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text("Terms of Service"),
                    subtitle: Text(
                      "Last updated: ${DateTime.now().toString().split(' ')[0]}",
                    ),
                    onTap: () => _launchTerms(),
                  ),

                  ListTile(
                    leading: const Icon(Icons.privacy_tip),
                    title: const Text("Privacy Policy"),
                    subtitle: const Text("GDPR compliant"),
                    onTap: () => _launchPrivacy(),
                  ),

                  const SizedBox(height: 16),

                  if (!requireExplicit)
                    CheckboxListTile(
                      title: const Text(
                        "Send me promotional offers and updates",
                      ),
                      subtitle: const Text(
                        "You can change this later in settings",
                      ),
                      value: marketingConsent,
                      onChanged: (value) =>
                          setState(() => marketingConsent = value),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                  const SizedBox(height: 8),

                  Text(
                    "App Version: ${_packageInfo.version} (${_packageInfo.buildNumber})",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              if (!requireExplicit)
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F3),
                ),
                child: Text(requireExplicit ? "I Agree & Continue" : "I Agree"),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final now = DateTime.now();
      final email = _emailController.text.trim();

      if (email.isNotEmpty) {
        try {
          await SessionManager.updateConsentTimestamps(
            email: email,
            termsAcceptedAt: now,
            privacyAcceptedAt: now,
          );

          if (marketingConsent == true) {
            await SessionManager.updateMarketingConsent(
              email: email,
              consent: true,
              consentedAt: now,
            );
          }
        } catch (e) {
          print('❌ Error saving consent: $e');
        }
      }

      setState(() {
        _termsAcceptedAt = now;
        _privacyAcceptedAt = now;
      });
    }

    return result ?? false;
  }

  Future<void> _launchTerms() async {
    final url = Uri.parse('https://yourdomain.com/terms');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchPrivacy() async {
    final url = Uri.parse('https://yourdomain.com/privacy');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  // ✅ OAuth buttons with SVG icons
  // OAuth buttons with updated design
  Widget _buildOAuthButtons() {
    final enabledProviders = _env.enabledOAuthProviders;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
            ],
          ),
        ),

        // Privacy Policy Links (inside OAuth section)
        // Padding(
        //   padding: const EdgeInsets.only(bottom: 16),
        //   child: Wrap(
        //     alignment: WrapAlignment.center,
        //     spacing: 2,
        //     runSpacing: 4,
        //     children: [
        //       Text(
        //         'By continuing, you agree to our',
        //         style: TextStyle(color: Colors.white60, fontSize: 11),
        //       ),
        //       GestureDetector(
        //         onTap: () => context.push(
        //           '/terms?from=${Uri.encodeComponent('/login')}',
        //         ),
        //         child: Text(
        //           'Terms of Service',
        //           style: TextStyle(
        //             color: const Color(0xFF1877F3),
        //             fontSize: 11,
        //             fontWeight: FontWeight.w500,
        //           ),
        //         ),
        //       ),
        //       Text(
        //         'and',
        //         style: TextStyle(color: Colors.white60, fontSize: 11),
        //       ),
        //       GestureDetector(
        //         onTap: () => context.push(
        //           '/privacy?from=${Uri.encodeComponent('/login')}',
        //         ),
        //         child: Text(
        //           'Privacy Policy',
        //           style: TextStyle(
        //             color: const Color(0xFF1877F3),
        //             fontSize: 11,
        //             fontWeight: FontWeight.w500,
        //           ),
        //         ),
        //       ),
        //     ],
        //   ),
        // ),

        // Google button
        if (enabledProviders.contains('google'))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SocialLoginButton(
              provider: 'google',
              onPressed: _signInWithGoogle,
              isLoading: _loadingGoogle,
            ),
          ),

        // Facebook button
        if (enabledProviders.contains('facebook'))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SocialLoginButton(
              provider: 'facebook',
              onPressed: _signInWithFacebook,
              isLoading: _loadingFacebook,
            ),
          ),

        // Apple button (if enabled)
        if (enabledProviders.contains('apple') &&
            defaultTargetPlatform == TargetPlatform.iOS)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SocialLoginButton(
              provider: 'apple',
              onPressed: _signInWithApple,
              isLoading: _loadingApple,
            ),
          ),

        // Password button - using same design
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
                    color: Colors.white.withOpacity(0.03),
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
                              // const SizedBox(height: 10),
                              // Container(
                              //   width: 60,
                              //   height: 60,
                              //   decoration: const BoxDecoration(
                              //     shape: BoxShape.circle,
                              //     color: Color(0xFF1877F3),
                              //   ),
                              //   child: const Icon(
                              //     Icons.person,
                              //     color: Colors.white,
                              //     size: 32,
                              //   ),
                              // ),
                              // const SizedBox(height: 24),
                              // const Text(
                              //   'Log in to MySalon',
                              //   style: TextStyle(
                              //     color: Colors.white,
                              //     fontSize: 22,
                              //     fontWeight: FontWeight.bold,
                              //   ),
                              // ),
                              // const SizedBox(height: 24),
                              Stack(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(
                                      top: 5,
                                      bottom: 25,
                                    ),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Container(
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
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: Image.asset(
                                                'logo.png',
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
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
                                          // const SizedBox(height: 12),
                                          // const Text(
                                          //   'Log in to MySaloon',
                                          //   style: TextStyle(
                                          //     color: Colors.white,
                                          //     fontSize: 24,
                                          //     fontWeight: FontWeight.bold,
                                          //   ),
                                          // ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Email Field
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
                                  fillColor: Colors.white.withOpacity(0.05),

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

                                  // ✅ Email validation icon
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
                                  fillColor: Colors.white.withOpacity(0.05),

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

                                  // ✅ Password visibility icon - only shows when text exists
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
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                                    activeColor: const Color(0xFF1877F3),
                                    checkColor: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => setState(
                                      () => _rememberMe = !_rememberMe,
                                    ),
                                    child: const Text(
                                      'Remember Me',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

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
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),

                              // OAuth Buttons
                              _buildOAuthButtons(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),

                      // ✅ Updated Bottom Section with OAuth-like Create Account button
                      Column(
                        children: [
                          // Privacy Policy Links (inside OAuth section)
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
                          // const SizedBox(
                          //   height: 20,
                          // ), // Small space at the very bottom
                          // Data Management Links
                          // Wrap(
                          //   alignment: WrapAlignment.center,
                          //   spacing: 16,
                          //   children: [
                          //     TextButton(
                          //       onPressed: () => context.go('/clear-data'),
                          //       child: Text(
                          //         'Manage Account Data',
                          //         style: TextStyle(
                          //           color: Colors.white70,
                          //           fontSize: 11,
                          //         ),
                          //       ),
                          //     ),
                          //     TextButton(
                          //       onPressed: () => context.go('/data-export'),
                          //       child: Text(
                          //         'Export My Data',
                          //         style: TextStyle(
                          //           color: Colors.white70,
                          //           fontSize: 11,
                          //         ),
                          //       ),
                          //     ),
                          //   ],
                          // ),
                        ],
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

// ✅ Social Login Button with SVG Icons
class _SocialLoginButton extends StatelessWidget {
  final String provider; // 'google', 'facebook', 'password'
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
        return const Color(0xFFDB4437); // Google Red
      case 'facebook':
        return const Color(0xFF1877F2); // Facebook Blue
      case 'password':
        return const Color.fromARGB(255, 232, 236, 242); // Blue for password
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
      case 'password':
        return 'Continue with password';
      default:
        return 'Continue';
    }
  }

  Widget _getIcon() {
    switch (provider) {
      case 'google':
        // Google icon - keep original colors (NO colorFilter)
        return SvgPicture.asset(
          'icons/google.svg',
          width: 18,
          height: 18,
          // ❌ NO colorFilter - keeps original Google colors
        );

      case 'facebook':
        // Facebook icon - keep original blue (NO colorFilter)
        return SvgPicture.asset(
          'icons/facebook.svg',
          width: 18,
          height: 18,
          // ❌ NO colorFilter - keeps original Facebook blue
        );

      case 'password':
        // Password icon - blue key
        return Icon(
          Icons.key_rounded,
          size: 18,
          color: _getButtonColor(), // Blue color
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
          side: BorderSide(color: buttonColor),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: buttonColor.withOpacity(0.1),
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
