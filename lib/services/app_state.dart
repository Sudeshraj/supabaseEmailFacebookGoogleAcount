import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_manager.dart';
import '../router/auth_gate.dart';

/// 🚀 Production-ready App State Management
class AppState extends ChangeNotifier {
  // ====================
  // PRIVATE PROPERTIES
  // ====================
  bool _loading = true;
  bool _loggedIn = false;
  bool _emailVerified = false;
  bool _profileCompleted = false;
  bool _hasLocalProfile = false;
  bool _continueSc = false;
  String? _role;
  String? _errorMessage;
  DateTime? _lastUpdateTime;
  bool _rememberMeEnabled = false;

  // ====================
  // PUBLIC GETTERS
  // ====================
  bool get loading => _loading;
  bool get loggedIn => _loggedIn;
  bool get emailVerified => _emailVerified;
  bool get profileCompleted => _profileCompleted;
  bool get hasLocalProfile => _hasLocalProfile;
  bool get continueSc => _continueSc;
  String? get role => _role;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  bool get rememberMeEnabled => _rememberMeEnabled;

  // ====================
  // PRIVATE SETTERS
  // ====================
  void _setLoading(bool value) {
    if (_loading != value) {
      _loading = value;
      notifyListeners();
    }
  }

  void _setLoggedIn(bool value) {
    if (_loggedIn != value) {
      _loggedIn = value;
      notifyListeners();
    }
  }

  void _setEmailVerified(bool value) {
    if (_emailVerified != value) {
      _emailVerified = value;
      notifyListeners();
    }
  }

  void _setProfileCompleted(bool value) {
    if (_profileCompleted != value) {
      _profileCompleted = value;
      notifyListeners();
    }
  }

  void _setHasLocalProfile(bool value) {
    if (_hasLocalProfile != value) {
      _hasLocalProfile = value;
      notifyListeners();
    }
  }

  void _setRole(String? value) {
    if (_role != value) {
      _role = value;
      notifyListeners();
    }
  }

  void _setErrorMessage(String? value) {
    if (_errorMessage != value) {
      _errorMessage = value;
      notifyListeners();
    }
  }

  void _setContinueScreen(bool value) {
    if (_continueSc != value) {
      _continueSc = value;
      notifyListeners();
    }
  }

  void _setRememberMeEnabled(bool value) {
    if (_rememberMeEnabled != value) {
      _rememberMeEnabled = value;
      notifyListeners();
    }
  }

  // ====================
  // PUBLIC METHODS
  // ====================

  /// 🚀 Initialize app state (call from main.dart)
  Future<void> initializeApp() async {
    _setLoading(true);
    _setErrorMessage(null);

    developer.log('🔄 AppState: Initializing...', name: 'AppState');

    try {
      // 1. Check local profiles and remember me settings
      final hasProfiles = await SessionManager.hasProfile();
      final csc = await SessionManager.shouldShowContinueScreen();
      final rememberMe = await SessionManager.isRememberMeEnabled();

      _setHasLocalProfile(hasProfiles);
      _setContinueScreen(csc);
      _setRememberMeEnabled(rememberMe);

      // 2. Check authentication state
      await _checkAuthenticationState();

      // 3. Update user profile data
      await _updateUserProfile();

      _lastUpdateTime = DateTime.now();

      developer.log('✅ AppState: Initialization successful', name: 'AppState');
    } catch (e, stackTrace) {
      _setErrorMessage('Initialization failed');
      developer.log(
        '❌ AppState Error: $e',
        name: 'AppState',
        error: e,
        stackTrace: stackTrace,
      );

      // Fallback to safe state
      _resetToSafeState();
    } finally {
      _setLoading(false);
    }
  }

  /// 🔄 Refresh app state (call after login/logout)
  Future<void> refreshState({bool silent = false}) async {
    if (!silent) {
      _setLoading(true);
    }

    try {
      await _checkAuthenticationState();
      await _updateUserProfile();

      final hasProfiles = await SessionManager.hasProfile();
      final rememberMe = await SessionManager.isRememberMeEnabled();
      
      _setHasLocalProfile(hasProfiles);
      _setRememberMeEnabled(rememberMe);

      _lastUpdateTime = DateTime.now();
      _setErrorMessage(null);

      developer.log('🔄 AppState: Refreshed', name: 'AppState');
    } catch (e, stackTrace) {
      developer.log(
        '❌ State refresh error: $e',
        name: 'AppState',
        error: e,
        stackTrace: stackTrace,
      );

      if (!silent) {
        _setErrorMessage('Failed to refresh state');
      }
    } finally {
      if (!silent) {
        _setLoading(false);
      }
    }
  }

/// 🚪 Logout user (full logout) - PRESERVE AUTO-LOGIN CAPABILITY
Future<void> logout() async {
  _setLoading(true);

  try {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    final email = user?.email;

    if (user != null && email != null) {
      // Get current session before logout
      final currentSession = supabase.auth.currentSession;
      final refreshToken = currentSession?.refreshToken;
      
      // Check if remember me is enabled
      final rememberMe = await SessionManager.isRememberMeEnabled();
      
      if (rememberMe && refreshToken != null) {
        // Save refresh token BEFORE logout for future auto-login
        await SessionManager.saveUserProfile(
          email: email,
          userId: user.id,
          name: user.userMetadata?['full_name'] ?? email.split('@').first,
          rememberMe: rememberMe,
          refreshToken: refreshToken, // Save token before logout
        );
        print('✅ Refresh token saved before logout for auto-login');
      }
    }

    // Sign out from Supabase (this clears the session)
    await supabase.auth.signOut();
    print('✅ User signed out from Supabase');

    // Update app state
    _setLoggedIn(false);
    _setEmailVerified(false);
    _setProfileCompleted(false);
    _setRole(null);

    developer.log('✅ User logged out (auto-login capability preserved)', name: 'AppState');
    
  } catch (e, stackTrace) {
    developer.log(
      '❌ Logout error: $e',
      name: 'AppState',
      error: e,
      stackTrace: stackTrace,
    );

    _setErrorMessage('Logout failed');
    rethrow;
  } finally {
    _setLoading(false);
  }
}

  /// 🔄 Logout for continue screen (keep profile)
  Future<void> logoutForContinue() async {
    _setLoading(true);

    try {
      // Use SessionManager's logoutForContinue method
      await SessionManager.logoutForContinue();
      
      // Update app state
      _setLoggedIn(false);
      _setEmailVerified(false);
      _setProfileCompleted(false);
      _setRole(null);

      developer.log('✅ User logged out for continue screen', name: 'AppState');
    } catch (e, stackTrace) {
      developer.log(
        '❌ Logout for continue error: $e',
        name: 'AppState',
        error: e,
        stackTrace: stackTrace,
      );

      _setErrorMessage('Logout failed');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// 🔍 Check if user can access a route
  bool canAccessRoute(String route) {
    if (_loading) return false;

    switch (route) {
      case '/owner':
        return _loggedIn &&
            _emailVerified &&
            _profileCompleted &&
            _role == 'business';
      case '/employee':
        return _loggedIn &&
            _emailVerified &&
            _profileCompleted &&
            _role == 'employee';
      case '/customer':
        return _loggedIn && _emailVerified && _profileCompleted;
      case '/reg':
        return _loggedIn && _emailVerified && !_profileCompleted;
      case '/verify-email':
        return _loggedIn && !_emailVerified;
      case '/login':
      case '/signup':
      case '/continue':
      case '/clear-data':
        return !_loggedIn;
      default:
        return true;
    }
  }

  /// 📊 Get user info
  Map<String, dynamic>? getCurrentUserInfo() {
    if (!_loggedIn) return null;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    return {
      'email': user?.email,
      'id': user?.id,
      'name': user?.userMetadata?['full_name'],
      'role': _role,
      'emailVerified': _emailVerified,
      'profileCompleted': _profileCompleted,
      'rememberMeEnabled': _rememberMeEnabled,
      'lastUpdate': _lastUpdateTime?.toIso8601String(),
    };
  }

  /// 🎯 Clear error message
  void clearError() {
    _setErrorMessage(null);
  }

  /// 💾 Enable/Disable Remember Me
  Future<void> setRememberMe(bool enabled) async {
    await SessionManager.setRememberMe(enabled);
    _setRememberMeEnabled(enabled);
  }

  // app_state.dart තුළ
Future<void> attemptAutoLogin() async {
  try {
    print('🔄 AppState: Attempting auto-login...');
    
    // Check if auto-login is enabled globally
    final rememberMeEnabled = await SessionManager.isRememberMeEnabled();
    if (!rememberMeEnabled) {
      print('⚠️ AppState: Auto-login disabled globally');
      return;
    }
    
    // Get most recent user
    final recentProfile = await SessionManager.getMostRecentProfile();
    if (recentProfile == null || recentProfile.isEmpty) {
      print('⚠️ AppState: No recent profile found');
      return;
    }
    
    final email = recentProfile['email'] as String?;
    if (email == null || email.isEmpty) {
      print('⚠️ AppState: No email in recent profile');
      return;
    }
    
    // Check consent (App Store requirement)
    final termsAccepted = recentProfile['termsAcceptedAt'] != null;
    final privacyAccepted = recentProfile['privacyAcceptedAt'] != null;
    
    if (!termsAccepted || !privacyAccepted) {
      print('⚠️ AppState: User consent not recorded - requiring re-login');
      return;
    }
    
    print('🔍 AppState: Attempting auto-login for $email');
    
    // Attempt auto-login with retry logic
    bool success = false;
    
    for (int attempt = 1; attempt <= 3; attempt++) {
      print('   - Attempt $attempt of 3');
      success = await SessionManager.tryAutoLogin(email);
      
      if (success) {
        print('✅ AppState: Auto-login successful for $email');
        refreshState();
        return;
      }
      
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    print('❌ AppState: Auto-login failed after 3 attempts');
    
  } catch (e) {
    print('❌ AppState: Error during auto-login: $e');
  }
}

  // ====================
  // PRIVATE METHODS
  // ====================

  Future<void> _checkAuthenticationState() async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    _setLoggedIn(session != null);
    _setEmailVerified(user?.emailConfirmedAt != null);
  }

  Future<void> _updateUserProfile() async {
    if (!_loggedIn) {
      _setProfileCompleted(false);
      _setRole(null);
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;
      
      // Save user profile only if remember me is enabled
      final rememberMe = await SessionManager.isRememberMeEnabled();
      if (user.email != null && rememberMe) {
        await SessionManager.saveUserProfile(
          email: user.email!,
          userId: user.id,
          name: user.email!.split('@').first,
          rememberMe: rememberMe,
        );
      }

      if (_loggedIn) {
        final profile = await supabase
            .from('profiles')
            .select('id, is_blocked, is_active')
            .eq('id', user.id)
            .maybeSingle();

        _setProfileCompleted(profile != null);

        if (_profileCompleted) {
          String? userRole = await SessionManager.getUserRole();
          _setRole(userRole);

          if (userRole == null) {
            // Fetch from database
            await initializeUserRole(user.id);
            return;
          }         
        } else {
          _setRole(null);
          _setProfileCompleted(false);
        }

        developer.log(
          '✅ Profile updated: role=$_role, profileCompleted=$_profileCompleted',
          name: 'AppState',
        );
      }
    } catch (e) {
      developer.log('❌ Profile update error: $e', name: 'AppState');
      _setProfileCompleted(false);
      _setRole(null);
    }
  }

  Future<void> initializeUserRole(String userId) async {
    const defaultRole = 'customer';
    String? userRole = await SessionManager.getUserRole();

    try {
      // 1. Database අයන්න
      final supabase = Supabase.instance.client;
      final result = await supabase
          .from('profiles')
          .select('roles(name)')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 5));

      // 2. Role එක ගන්න
      final roleName =
          (result['roles'] as List)
                  .cast<Map<String, dynamic>>()
                  .firstOrNull?['name']
              as String?;

      // 3. AuthGate එකට දෙන්න
      userRole = AuthGate.pickRole(roleName ?? defaultRole);

      // 4. Save කරන්න
      await SessionManager.saveUserRole(userRole);

      print('User role initialized: $userRole');
      _setRole(userRole);
    } on TimeoutException {
      print('Database timeout, using default role');
      userRole = defaultRole;
      await SessionManager.saveUserRole(userRole);
      _setRole(userRole);
    } catch (e) {
      print('Failed to get user role: $e');
      userRole = defaultRole;
      await SessionManager.saveUserRole(userRole);
      _setRole(userRole);      
    }
  }

  void _resetToSafeState() {
    _setLoggedIn(false);
    _setEmailVerified(false);
    _setProfileCompleted(false);
    _setRole(null);
    _setHasLocalProfile(false);
    _setRememberMeEnabled(false);
  }

  Future<void> emailVerifyerError() async {   
    print('awa');
    _setEmailVerified(false);   
  }
}