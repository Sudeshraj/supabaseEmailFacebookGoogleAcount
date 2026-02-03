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
import '../../../utils/simple_toast.dart';

// ✅ NEW: Separate class for returning user check
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
  bool _showAdvancedOptions = false;
  bool _consentGiven = false;

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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
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

    if (widget.prefilledEmail != null) {
      _emailController = TextEditingController(text: widget.prefilledEmail);
      if (kDebugMode) {
        print('📧 Prefilled email: ${widget.prefilledEmail}');
      }
    } else {
      _emailController = TextEditingController();
    }

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForPrefilledEmail();

      if (widget.showMessage && widget.message != null) {
        _showCustomMessage(widget.message!);
      }
    });

    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
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
            _consentGiven =
                _termsAcceptedAt != null && _privacyAcceptedAt != null;
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

  void _validateForm() {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

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

      if (password.isEmpty) {
        _passwordError = 'Enter your password';
      } else {
        _passwordError = null;
      }

      _isValid = _emailError == null && _passwordError == null;
    });
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

  void _checkForPrefilledEmail() async {
    if (widget.prefilledEmail != null && widget.prefilledEmail!.isNotEmpty) {
      _emailController.text = widget.prefilledEmail!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _validateForm();
        setState(() {});
      }
    });
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

  AndroidOptions _getAndroidOptions() =>
      const AndroidOptions(encryptedSharedPreferences: true);

  IOSOptions _getIOSOptions() => const IOSOptions(
        accessibility: KeychainAccessibility.unlocked,
        synchronizable: true,
      );

  // ✅ COMPLIANT: Save OAuth profile with user choice
// SignInScreen.dart - FIXED _saveOAuthProfile method
Future<void> _saveOAuthProfile({
  required User user,
  required String provider,
  required bool rememberMe,
  String? accessToken,
  String? refreshToken,
}) async {
  try {
    final email = user.email!;
    final now = DateTime.now();

    if (kDebugMode) {
      print('💾 SAVING OAUTH PROFILE:');
      print('   - Email: $email');
      print('   - Provider: $provider');
      print('   - Remember Me: $rememberMe');
    }

    final userMetadata = user.userMetadata ?? {};
    final actualProvider = userMetadata['provider'] ?? provider;

    if (kDebugMode) {
      print('   - Actual provider from metadata: $actualProvider');
      print('   - Full metadata: $userMetadata');
    }

    // ✅ FIXED: Get photo URL properly
    String? photoUrl;

    // Try different possible keys for photo URL
    if (userMetadata['avatar_url'] != null && 
        userMetadata['avatar_url'].toString().isNotEmpty) {
      photoUrl = userMetadata['avatar_url'].toString();
      print('📸 Got avatar_url: $photoUrl');
    } else if (userMetadata['picture'] != null && 
        userMetadata['picture'].toString().isNotEmpty) {
      photoUrl = userMetadata['picture'].toString();
      print('📸 Got picture: $photoUrl');
    } else if (userMetadata['photo'] != null && 
        userMetadata['photo'].toString().isNotEmpty) {
      photoUrl = userMetadata['photo'].toString();
      print('📸 Got photo: $photoUrl');
    } else if (userMetadata['image'] != null && 
        userMetadata['image'].toString().isNotEmpty) {
      photoUrl = userMetadata['image'].toString();
      print('📸 Got image: $photoUrl');
    } else {
      photoUrl = '';
      print('📸 No photo URL found in metadata');
    }

    // ✅ FIXED: Get name properly
    String name = email.split('@').first; // Default

    if (userMetadata['full_name'] != null && 
        userMetadata['full_name'].toString().isNotEmpty) {
      name = userMetadata['full_name'].toString();
    } else if (userMetadata['name'] != null && 
        userMetadata['name'].toString().isNotEmpty) {
      name = userMetadata['name'].toString();
    } else if (userMetadata['given_name'] != null && 
        userMetadata['given_name'].toString().isNotEmpty) {
      name = userMetadata['given_name'].toString();
    }

    // ✅ FIXED: Save with proper photo URL
    await SessionManager.saveUserProfile(
      email: email,
      userId: user.id,
      name: name,
      photo: photoUrl, // ✅ Now properly passed
      rememberMe: rememberMe,
      refreshToken: refreshToken,
      accessToken: accessToken,
      provider: actualProvider,
      termsAcceptedAt: _termsAcceptedAt ?? now,
      privacyAcceptedAt: _privacyAcceptedAt ?? now,
      marketingConsent: false,
      marketingConsentAt: null,
    );

    await SessionManager.setCurrentUser(email);
    await SessionManager.setRememberMe(rememberMe);
    await appState.setRememberMe(rememberMe);

    if (rememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_continue_screen', true);
    }

    if (kDebugMode) {
      print('✅ OAuth Profile Saved Successfully');
      print('   - Provider: $actualProvider');
      print('   - Photo saved: ${photoUrl.isNotEmpty}');
      if (photoUrl.isNotEmpty) {
        print('   - Photo URL: $photoUrl');
      }
    }

    setState(() {
      _consentGiven = true;
      _termsAcceptedAt = _termsAcceptedAt ?? now;
      _privacyAcceptedAt = _privacyAcceptedAt ?? now;
    });
  } catch (e, stackTrace) {
    print('❌ Error saving OAuth profile: $e');
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

      // ✅ Check if consent needed (FIRST TIME ONLY)
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
        provider: 'email',
        rememberMe: _rememberMe,
        accessToken: session?.accessToken,
        refreshToken: session?.refreshToken,
      );

      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        appState.refreshState();
        if (!mounted) return;
        context.go('/');
        return;
      }

      if (profile['is_blocked'] == true) {
        await supabase.auth.signOut();
        await SessionManager.removeProfile(user.email!);
        await _secureStorage.delete(key: '${user.id}_access_token');
        await _secureStorage.delete(key: '${user.id}_refresh_token');

        if (!mounted) return;
        await showCustomAlert(
          context: context,
          title: "Account Blocked 🚫",
          message: "Your account has been blocked. Please contact support.",
          isError: true,
        );
        return;
      }

      if (profile['is_active'] == false) {
        await supabase.auth.signOut();
        await SessionManager.removeProfile(user.email!);
        await _secureStorage.delete(key: '${user.id}_access_token');
        await _secureStorage.delete(key: '${user.id}_refresh_token');

        if (!mounted) return;
        await showCustomAlert(
          context: context,
          title: "Account Inactive ⚠️",
          message: "Your account is deactivated.",
          isError: true,
        );
        return;
      }

      final String role = profile['role'] ?? 'customer';
      await SessionManager.saveUserRole(role);

      appState.refreshState();
      if (!mounted) return;
      context.go('/');
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
          provider: 'email',
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

      // ✅ 1. Check if this is a returning user
      final returningUser = await _checkIfReturningUser('google');
      bool needsConsent = true;

      if (returningUser.email != null) {
        needsConsent = await _shouldShowConsent(returningUser.email!);
        if (kDebugMode) {
          print('   - Returning user: ${returningUser.email}');
          print('   - Needs consent: $needsConsent');
        }
      }

      // ✅ 2. Show OAuth consent dialog (always required by platforms)
      final oauthConsent = await _showOAuthConsentDialog(
        provider: 'Google',
        scopes: ['email', 'profile'],
      );
      if (!oauthConsent) {
        setState(() => _loadingGoogle = false);
        return;
      }

      // ✅ 3. Show App Store compliant consent dialog (FIRST TIME ONLY)
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loadingGoogle = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent dialog (already given)');
      }

      // ✅ 4. Ask user about auto-login preference (first time or when changing)
      bool userWantsAutoLogin = _rememberMe;

      if (needsConsent || !returningUser.hasAutoLoginSetting) {
        userWantsAutoLogin = await _showAutoLoginConsentDialog(
          provider: 'Google',
        );
      }

      // ✅ 5. Set based on user's choice
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
            if (kDebugMode) {
              print('✅ Google OAuth User Signed In: ${user.email}');
              print('   - User wants auto-login: $userWantsAutoLogin');
            }

            await _saveOAuthProfile(
              user: user,
              provider: 'google',
              rememberMe: userWantsAutoLogin,
              accessToken: session?.accessToken,
              refreshToken: session?.refreshToken,
            );

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

      // ✅ 1. Check if returning user
      final returningUser = await _checkIfReturningUser('facebook');
      bool needsConsent = true;

      if (returningUser.email != null) {
        needsConsent = await _shouldShowConsent(returningUser.email!);
        if (kDebugMode) {
          print('   - Returning user: ${returningUser.email}');
          print('   - Needs consent: $needsConsent');
        }
      }

      // ✅ 2. OAuth consent
      final oauthConsent = await _showOAuthConsentDialog(
        provider: 'Facebook',
        scopes: ['email'],
      );
      if (!oauthConsent) {
        setState(() => _loadingFacebook = false);
        return;
      }

      // ✅ 3. App consent (FIRST TIME ONLY)
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loadingFacebook = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent (already given)');
      }

      // ✅ 4. Auto-login consent
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
            await _saveOAuthProfile(
              user: user,
              provider: 'facebook',
              rememberMe: userWantsAutoLogin,
              accessToken: session?.accessToken,
              refreshToken: session?.refreshToken,
            );

            await _handlePostLogin(user.id);
          }
        }
      });

      await supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: _getRedirectUrl(),
        scopes: 'email',
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

      // ✅ 1. Check if returning user
      final returningUser = await _checkIfReturningUser('apple');
      bool needsConsent = true;

      if (returningUser.email != null) {
        needsConsent = await _shouldShowConsent(returningUser.email!);
        if (kDebugMode) {
          print('   - Returning user: ${returningUser.email}');
          print('   - Needs consent: $needsConsent');
        }
      }

      // ✅ 2. Apple requires explicit OAuth consent
      final oauthConsent = await _showOAuthConsentDialog(
        provider: 'Apple',
        scopes: ['email', 'name'],
      );
      if (!oauthConsent) {
        setState(() => _loadingApple = false);
        return;
      }

      // ✅ 3. App consent (FIRST TIME ONLY)
      if (needsConsent) {
        final accepted = await _showConsentDialog(requireExplicit: true);
        if (!accepted) {
          setState(() => _loadingApple = false);
          return;
        }
      } else {
        if (kDebugMode) print('   - Skipping consent (already given)');
      }

      // ✅ 4. Apple is strict about auto-login
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
            await _saveOAuthProfile(
              user: user,
              provider: 'apple',
              rememberMe: userWantsAutoLogin,
              accessToken: session?.accessToken,
              refreshToken: session?.refreshToken,
            );

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

  // ✅ Handle post-login
  Future<void> _handlePostLogin(String userId) async {
    try {
      if (!mounted) return;

      await Future.delayed(const Duration(seconds: 3));

      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (profile != null) {
        if (profile['is_blocked'] == true) {
          await supabase.auth.signOut();
          await showCustomAlert(
            context: context,
            title: "Account Blocked 🚫",
            message: "Your account has been blocked. Please contact support.",
            isError: true,
          );
          return;
        }

        if (profile['is_active'] == false) {
          await supabase.auth.signOut();
          await showCustomAlert(
            context: context,
            title: "Account Inactive ⚠️",
            message: "Your account is deactivated.",
            isError: true,
          );
          return;
        }

        final String role = profile['role'] ?? 'customer';
        await SessionManager.saveUserRole(role);
      }

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
        return e.message ?? "Unable to sign in. Please try again.";
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

  // ✅ UPDATED: Consent dialog with FIRST-TIME ONLY logic
  Future<bool> _showConsentDialog({bool requireExplicit = false}) async {
    // Check if user has already given consent
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      final hasConsent = !(await _shouldShowConsent(email));
      if (hasConsent) {
        if (kDebugMode) print('   - User already gave consent, skipping dialog');
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
        _consentGiven = true;
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

  // ✅ OAuth buttons
  Widget _buildOAuthButtons() {
    final enabledProviders = _env.enabledOAuthProviders;

    if (enabledProviders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Divider(
                  color: Colors.white.withOpacity(0.2),
                  thickness: 0.5,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or continue with',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              Expanded(
                child: Divider(
                  color: Colors.white.withOpacity(0.2),
                  thickness: 0.5,
                ),
              ),
            ],
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (enabledProviders.contains('google'))
              _SocialLoginButton(
                isGoogle: true,
                color: const Color(0xFFDB4437),
                backgroundColor: const Color(0xFFDB4437).withOpacity(0.1),
                borderColor: const Color(0xFFDB4437),
                onPressed: _signInWithGoogle,
                isLoading: _loadingGoogle,
              ),

            if (enabledProviders.contains('google') &&
                enabledProviders.contains('facebook'))
              const SizedBox(width: 20),

            if (enabledProviders.contains('facebook'))
              _SocialLoginButton(
                isFacebook: true,
                color: const Color(0xFF1877F2),
                backgroundColor: const Color(0xFF1877F2).withOpacity(0.1),
                borderColor: const Color(0xFF1877F2),
                onPressed: _signInWithFacebook,
                isLoading: _loadingFacebook,
              ),

            if ((enabledProviders.contains('google') ||
                    enabledProviders.contains('facebook')) &&
                enabledProviders.contains('apple') &&
                defaultTargetPlatform == TargetPlatform.iOS)
              const SizedBox(width: 20),

            if (enabledProviders.contains('apple') &&
                defaultTargetPlatform == TargetPlatform.iOS)
              _SocialLoginButton(
                isApple: true,
                color: Colors.white,
                backgroundColor: Colors.black.withOpacity(0.1),
                borderColor: Colors.white,
                onPressed: _signInWithApple,
                isLoading: _loadingApple,
              ),
          ],
        ),
      ],
    );
  }

  // ✅ Debug options
  Widget _buildAdvancedOptions() {
    if (!kDebugMode) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
            TextButton(
              onPressed: () =>
                  setState(() => _showAdvancedOptions = !_showAdvancedOptions),
              child: Text(
                _showAdvancedOptions
                    ? 'Hide Debug Options'
                    : 'Show Debug Options',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
            Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
          ],
        ),
        if (_showAdvancedOptions) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Debug Info',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'App: ${_packageInfo.appName} ${_packageInfo.version}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Build: ${_packageInfo.buildNumber}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'Consent: ${_consentGiven ? "Given" : "Not Given"}',
                  style: TextStyle(
                    color: _consentGiven ? Colors.green : Colors.orange,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _clearSecureStorage(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.2),
                    foregroundColor: Colors.red,
                  ),
                  child: const Text(
                    'Clear Secure Storage',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _clearSecureStorage() async {
    try {
      await _secureStorage.deleteAll();
      SimpleToast.info(context, 'Secure storage cleared');
    } catch (e) {
      print('Error clearing storage: $e');
    }
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
                              const SizedBox(height: 10),
                              Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF1877F3),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Log in to MySalon',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 24),

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
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: _isValidEmail
                                          ? const Color(0xFF1877F3)
                                          : Colors.redAccent,
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
                                            )
                                          : const Icon(
                                              Icons.error_outline,
                                              color: Colors.redAccent,
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
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Color(0xFF1877F3),
                                    ),
                                  ),
                                  errorText: _passwordError,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white70,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),

                              // OAuth Buttons
                              _buildOAuthButtons(),

                              // Debug Options
                              _buildAdvancedOptions(),

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Section
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
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

                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            children: [
                              TextButton(
                                onPressed: () => context.go('/clear-data'),
                                child: Text(
                                  'Manage Account Data',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.go('/data-export'),
                                child: Text(
                                  'Export My Data',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Don\'t have an account?',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () => context.go('/signup'),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFF1877F3),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      backgroundColor: const Color(
                                        0xFF1877F3,
                                      ).withOpacity(0.1),
                                    ),
                                    child: Text(
                                      'Create Account',
                                      style: TextStyle(
                                        color: const Color(0xFF1877F3),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
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

// ✅ NEW: Separate file or top-level class for Social Login Button
class _SocialLoginButton extends StatelessWidget {
  final Color color;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isGoogle;
  final bool isFacebook;
  final bool isApple;

  const _SocialLoginButton({
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
    required this.onPressed,
    this.isLoading = false,
    this.isGoogle = false,
    this.isFacebook = false,
    this.isApple = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor.withOpacity(0.5), width: 1.5),
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              )
            : Center(
                child: isGoogle
                    ? _GoogleLetterIcon(color: color)
                    : isFacebook
                        ? _FacebookLetterIcon(color: color)
                        : isApple
                            ? _AppleIcon(color: color)
                            : const SizedBox(),
              ),
      ),
    );
  }
}

class _GoogleLetterIcon extends StatelessWidget {
  final Color color;
  const _GoogleLetterIcon({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        child: Text(
          'G',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            fontFamily: 'Roboto',
          ),
        ),
      );
}

class _FacebookLetterIcon extends StatelessWidget {
  final Color color;
  const _FacebookLetterIcon({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        child: Text(
          'f',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w500,
            fontFamily: 'Roboto',
          ),
        ),
      );
}

class _AppleIcon extends StatelessWidget {
  final Color color;
  const _AppleIcon({required this.color});
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.apple, color: color, size: 24);
}