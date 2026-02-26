// lib/services/google_sign_in_service.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_application_1/config/environment_manager.dart';

class GoogleSignInService {
  static final GoogleSignInService _instance = GoogleSignInService._internal();
  factory GoogleSignInService() => _instance;
  GoogleSignInService._internal();

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static bool _isInitialized = false;
  
  // EnvironmentManager instance
  final EnvironmentManager _env = EnvironmentManager();

  // Required scopes
  static const List<String> _requiredScopes = [
    'email',
    'profile',
    'openid',
  ];

  // 🔥 Initialize with clientId from EnvironmentManager
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      // Get platform-specific client ID from EnvironmentManager
      final String? clientId = _getPlatformClientId();
      
      print('Initializing GoogleSignIn with clientId: $clientId');
      print('Platform: ${kIsWeb ? "Web" : "Mobile"}');
      print('Environment: ${_env.environment}');
      
      // Validate if Google OAuth is enabled
      if (!_env.enableGoogleOAuth) {
        print('⚠️ Google OAuth is disabled in environment');
        return false;
      }
      
      await _googleSignIn.initialize(
        clientId: clientId,
      );
      
      _isInitialized = true;
      print('✅ GoogleSignIn initialized successfully');
      return true;
    } catch (e) {
      print('❌ GoogleSignIn initialize error: $e');
      return false;
    }
  }

  // 🔥 Get platform-specific client ID
  String? _getPlatformClientId() {
    if (!_env.enableGoogleOAuth) return null;
    
    if (kIsWeb) {
      // Web platform
      final webClientId = _env.googleWebClientId;
      if (webClientId.isEmpty) {
        print('⚠️ Google Web Client ID is not configured');
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
        print('⚠️ Using Web Client ID as fallback for mobile');
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
      print('❌ authenticate() cannot be used on web - use Supabase OAuth');
      return null;
    }
    
    if (!_env.enableGoogleOAuth) {
      print('❌ Google OAuth is disabled');
      return null;
    }
    
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }
    
    try {
      return await _googleSignIn.authenticate();
    } catch (e) {
      print('authenticate error: $e');
      return null;
    }
  }

  // Get access token
  Future<String?> getAccessToken(GoogleSignInAccount account) async {
    try {
      var authorization = await account.authorizationClient
          .authorizationForScopes(_requiredScopes);
      
      if (authorization == null) {
        final result = await account.authorizationClient
            .authorizeScopes(_requiredScopes);
        return result.accessToken.isEmpty ? null : result.accessToken;
      }
      
      return authorization.accessToken;
    } catch (e) {
      print('getAccessToken error: $e');
      return null;
    }
  }

  // Complete sign-in
  Future<Map<String, String?>?> authenticateAndGetDetails() async {
    if (kIsWeb) return null;
    
    if (!_env.enableGoogleOAuth) {
      print('❌ Google OAuth is disabled');
      return null;
    }
    
    try {
      final account = await authenticate();
      if (account == null) return null;
      
      final auth = await account.authentication;
      if (auth.idToken == null) return null;
      
      final accessToken = await getAccessToken(account);
      
      return {
        'idToken': auth.idToken,
        'accessToken': accessToken,
        'email': account.email,
        'displayName': account.displayName,
        'photoUrl': account.photoUrl,
      };
    } catch (e) {
      print('authenticateAndGetDetails error: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    if (!_isInitialized) return;
    
    try {
      await _googleSignIn.signOut();
      print('✅ GoogleSignIn signed out');
    } catch (e) {
      print('signOut error: $e');
    }
  }
}