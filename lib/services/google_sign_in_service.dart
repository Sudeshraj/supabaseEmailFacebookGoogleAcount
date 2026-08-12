// lib/services/google_sign_in_service.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter_application_1/config/environment_manager.dart';

class GoogleSignInService {
  static final GoogleSignInService _instance = GoogleSignInService._internal();
  factory GoogleSignInService() => _instance;
  GoogleSignInService._internal();

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static bool _isInitialized = false;

  // ✅ FIX: in-flight initialize() call එක cache කරගන්නවා.
  // Second caller එකක් await කරන කොටම එනවා නම්, ආයෙත් JS
  // initialize() fire කරන්නේ නැතුව, දැනටමත් running Future එකම
  // await කරනවා. මේකෙන් "initialize() is called multiple times"
  // GIS console warning එක නවතිනවා.
  static Future<bool>? _initializingFuture;

  final EnvironmentManager _env = EnvironmentManager();

  static const List<String> _requiredScopes = ['email', 'profile', 'openid'];

  Future<bool> initialize() async {
    // දැනටමත් සම්පූර්ණයෙන් init වෙලා තියෙනවනම්, කෙලින්ම return
    if (_isInitialized) return true;

    // දැනටමත් initialize() call එකක් in-flight (running) නම්,
    // අලුත් JS call එකක් fire කරන්නේ නැතුව, ඒම Future එකම await කරනවා
    if (_initializingFuture != null) {
      debugPrint('ℹ️ GoogleSignIn initialize already in progress, awaiting it');
      return await _initializingFuture!;
    }

    // Actual init logic එක වෙනම function එකකට extract කරලා,
    // Future එක cache කරගන්නවා
    _initializingFuture = _doInitialize();

    try {
      final result = await _initializingFuture!;
      return result;
    } finally {
      // සම්පූර්ණ උනාට පස්සේ (success හෝ fail) clear කරන්න,
      // fail උනොත් ඊළඟ try එකකට ආයෙත් attempt කරන්න පුළුවන් වෙන්න
      _initializingFuture = null;
    }
  }

  Future<bool> _doInitialize() async {
    try {
      final String? clientId = _getPlatformClientId();
      final String webClientId = _env.googleWebClientId;

      if (!_env.enableGoogleOAuth) {
        return false;
      }

      if (webClientId.isEmpty) {
        debugPrint(
          '❌ GoogleSignIn initialize error: googleWebClientId is empty. '
          'serverClientId is required for idToken to work correctly.',
        );
        return false;
      }

      if (kIsWeb) {
        await _googleSignIn.initialize(clientId: webClientId);
        debugPrint('✅ GoogleSignIn initialized for Web (clientId only)');
      } else {
        await _googleSignIn.initialize(
          clientId: clientId,
          serverClientId: webClientId,
        );
        debugPrint(
          '✅ GoogleSignIn initialized for Mobile with serverClientId set',
        );
      }

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('❌ GoogleSignIn initialize error: $e');
      return false;
    }
  }

  // Get platform-specific client ID
  String? _getPlatformClientId() {
    if (!_env.enableGoogleOAuth) return null;

    if (kIsWeb) {
      // Web platform
      final webClientId = _env.googleWebClientId;
      if (webClientId.isEmpty) {
        return null;
      }
      return webClientId;
    } else {
      // Mobile platforms (Android/iOS)
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidClientId = _env.googleAndroidClientId;
        if (androidClientId.isNotEmpty) return androidClientId;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosClientId = _env.googleIosClientId;
        if (iosClientId.isNotEmpty) return iosClientId;
      }

      // Fallback to web client ID if platform-specific not found
      final fallbackClientId = _env.googleWebClientId;
      if (fallbackClientId.isNotEmpty) {
        return fallbackClientId;
      }
    }

    return null;
  }

  // Check if Google OAuth is properly configured
  bool isConfigured() {
    return _env.hasValidOAuthConfiguration('google') &&
        _getPlatformClientId() != null;
  }

  // Check if supports authenticate
  bool supportsAuthenticate() {
    return _googleSignIn.supportsAuthenticate();
  }

  // Authenticate (sign in) - Mobile only
  Future<GoogleSignInAccount?> authenticate() async {
    if (kIsWeb) {
      return null;
    }

    if (!_env.enableGoogleOAuth) {
      return null;
    }

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    try {
      return await _googleSignIn.authenticate();
    } catch (e) {
      debugPrint('authenticate error: $e');
      return null;
    }
  }

  // Get access token
  Future<String?> getAccessToken(GoogleSignInAccount account) async {
    try {
      var authorization = await account.authorizationClient
          .authorizationForScopes(_requiredScopes);

      if (authorization == null) {
        final result = await account.authorizationClient.authorizeScopes(
          _requiredScopes,
        );
        return result.accessToken.isEmpty ? null : result.accessToken;
      }

      return authorization.accessToken;
    } catch (e) {
      debugPrint('getAccessToken error: $e');
      return null;
    }
  }

  // Complete sign-in
  Future<Map<String, String?>?> authenticateAndGetDetails() async {
    if (kIsWeb) return null;

    if (!_env.enableGoogleOAuth) {
      return null;
    }

    try {
      final account = await authenticate();
      if (account == null) return null;

      final auth = account.authentication;

      // ✅ Extra diagnostic logging - helps confirm whether the fix
      // worked. If idToken is still null after adding serverClientId,
      // the issue is Android OAuth Client / SHA-1 registration, not
      // this file.
      if (auth.idToken == null) {
        debugPrint(
          '❌ authenticateAndGetDetails: idToken is null even after '
          'serverClientId fix. Check that the Android OAuth Client '
          '(matching this app\'s SHA-1 + package name) exists in '
          'Google Cloud Console, and that a fresh google-services.json '
          'has been pulled if using Firebase for anything else.',
        );
        return null;
      }

      final accessToken = await getAccessToken(account);

      debugPrint('✅ Got idToken successfully (native Google sign-in)');

      return {
        'idToken': auth.idToken,
        'accessToken': accessToken,
        'email': account.email,
        'displayName': account.displayName,
        'photoUrl': account.photoUrl,
      };
    } catch (e) {
      debugPrint('authenticateAndGetDetails error: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    if (!_isInitialized) return;

    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('signOut error: $e');
    }
  }
}
