import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_manager.dart';
import '../router/auth_gate.dart';

///  Production-ready App State Management
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
  String? _loginProvider;
  String? _currentEmail;
  User? _currentUser;

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
  String? get loginProvider => _loginProvider;
  String? get currentEmail => _currentEmail;
  User? get currentUser => _currentUser;

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

  void _setLoginProvider(String? value) {
    if (_loginProvider != value) {
      _loginProvider = value;
      notifyListeners();
    }
  }

  void _setCurrentEmail(String? value) {
    if (_currentEmail != value) {
      _currentEmail = value;
      notifyListeners();
    }
  }

  void _setCurrentUser(User? value) {
    if (_currentUser != value) {
      _currentUser = value;
      notifyListeners();
    }
  }

  // ====================
  // PUBLIC METHODS
  // ====================

  /// 🚀 Initialize app state
  Future<void> initializeApp() async {
    _setLoading(true);
    _setErrorMessage(null);

    developer.log(' AppState: Initializing...', name: 'AppState');

    try {
      final hasProfiles = await SessionManager.hasProfile();
      final csc = await SessionManager.shouldShowContinueScreen();
      final rememberMe = await SessionManager.isRememberMeEnabled();

      _setHasLocalProfile(hasProfiles);
      _setContinueScreen(csc);
      _setRememberMeEnabled(rememberMe);
      _setCurrentUser(Supabase.instance.client.auth.currentUser);

      await _checkAuthenticationState();
      await _updateUserProfile();

      _lastUpdateTime = DateTime.now();

      developer.log('AppState: Initialization successful', name: 'AppState');

      if (!_loggedIn && hasProfiles && rememberMe) {
        await attemptAutoLogin();
      }
    } catch (e, stackTrace) {
      _setErrorMessage('Initialization failed');
      developer.log(
        'AppState Error: $e',
        name: 'AppState',
        error: e,
        stackTrace: stackTrace,
      );
      _resetToSafeState();
    } finally {
      _setLoading(false);
    }
  }

  /// Refresh app state
  Future<void> refreshState({bool silent = false}) async {
    if (!silent) _setLoading(true);

    try {
      _setCurrentUser(Supabase.instance.client.auth.currentUser);
      await _checkAuthenticationState();
      await _updateUserProfile();

      final hasProfiles = await SessionManager.hasProfile();
      final rememberMe = await SessionManager.isRememberMeEnabled();

      _setHasLocalProfile(hasProfiles);
      _setRememberMeEnabled(rememberMe);

      _lastUpdateTime = DateTime.now();
      _setErrorMessage(null);

      developer.log('AppState: Refreshed', name: 'AppState');
    } catch (e, stackTrace) {
      developer.log(
        'State refresh error: $e',
        name: 'AppState',
        error: e,
        stackTrace: stackTrace,
      );

      if (!silent) _setErrorMessage('Failed to refresh state');
    } finally {
      if (!silent) _setLoading(false);
    }
  }

  /// 🚪 Logout user
  Future<void> logout() async {
    _setLoading(true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final email = user?.email;

      if (user != null && email != null) {
        final currentSession = supabase.auth.currentSession;
        final refreshToken = currentSession?.refreshToken;
        final rememberMe = await SessionManager.isRememberMeEnabled();

        if (rememberMe && refreshToken != null) {
          final provider =
              _loginProvider ??
              user.userMetadata?['provider']?.toString().toLowerCase() ??
              'email';

          await SessionManager.saveUserProfile(
            email: email,
            userId: user.id,
            name: user.userMetadata?['full_name'] ?? email.split('@').first,
            rememberMe: rememberMe,
            refreshToken: refreshToken,
            provider: provider,
          );
        }
      }

      await supabase.auth.signOut();

      _setLoggedIn(false);
      _setEmailVerified(false);
      _setProfileCompleted(false);
      _setRole(null);
      _setCurrentEmail(null);
      _setLoginProvider(null);

      developer.log('User logged out', name: 'AppState');
    } catch (e, stackTrace) {
      developer.log(
        'Logout error: $e',
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

  /// Logout for continue screen
  Future<void> logoutForContinue() async {
    _setLoading(true);

    try {
      await SessionManager.logoutForContinue();

      _setLoggedIn(false);
      _setEmailVerified(false);
      _setProfileCompleted(false);
      _setRole(null);
      _setCurrentEmail(null);
      _setLoginProvider(null);

      developer.log(' User logged out for continue screen', name: 'AppState');
    } catch (e, stackTrace) {
      developer.log(
        'Logout for continue error: $e',
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

  /// Get user info
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
      'loginProvider': _loginProvider,
      'lastUpdate': _lastUpdateTime?.toIso8601String(),
    };
  }

  /// Clear error message
  void clearError() {
    _setErrorMessage(null);
  }

  /// Enable/Disable Remember Me
  Future<void> setRememberMe(bool enabled) async {
    await SessionManager.setRememberMe(enabled);
    _setRememberMeEnabled(enabled);
  }

  /// 🔐 Attempt auto-login
  Future<void> attemptAutoLogin() async {
    try {
      debugPrint('AppState: Attempting auto-login...');

      final rememberMeEnabled = await SessionManager.isRememberMeEnabled();
      if (!rememberMeEnabled) {
        debugPrint('AppState: Auto-login disabled globally');
        return;
      }

      final recentProfile = await SessionManager.getMostRecentProfile();
      if (recentProfile == null || recentProfile.isEmpty) {
        debugPrint('AppState: No recent profile found');
        return;
      }

      final email = recentProfile['email'] as String?;
      final provider = recentProfile['provider'] as String?;

      if (email == null || email.isEmpty) {
        debugPrint('AppState: No email in recent profile');
        return;
      }

      final termsAccepted = recentProfile['termsAcceptedAt'] != null;
      final privacyAccepted = recentProfile['privacyAcceptedAt'] != null;

      if (!termsAccepted || !privacyAccepted) {
        debugPrint('AppState: User consent not recorded - requiring re-login');
        return;
      }

      debugPrint(
        '🔍 AppState: Attempting auto-login for $email (provider: $provider)',
      );

      if (provider != null &&
          provider != 'email' &&
          provider != 'email_password') {
        debugPrint(
          'AppState: OAuth provider ($provider) requires manual login',
        );
        _setContinueScreen(true);
        return;
      }

      final refreshToken = recentProfile['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('AppState: No refresh token available');
        return;
      }

      bool success = false;

      for (int attempt = 1; attempt <= 3; attempt++) {
        debugPrint('   - Attempt $attempt of 3');
        success = await _tryAutoLoginWithToken(refreshToken);

        if (success) {
          debugPrint('✅ AppState: Auto-login successful for $email');
          await refreshState();
          return;
        }

        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      debugPrint('AppState: Auto-login failed after 3 attempts');
    } catch (e) {
      debugPrint('AppState: Error during auto-login: $e');
    }
  }

  /// 📝 Update user profile after login
  Future<void> updateUserProfileAfterLogin({
    required String email,
    required String userId,
    String? name,
    String? photo,
    bool rememberMe = false,
    String? provider,
    String? accessToken,
    String? refreshToken,
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
  }) async {
    try {
      await SessionManager.saveUserProfile(
        email: email,
        userId: userId,
        name: name ?? email.split('@').first,
        photo: photo,
        rememberMe: rememberMe,
        provider: provider ?? 'email',
        accessToken: accessToken,
        refreshToken: refreshToken,
        termsAcceptedAt: termsAcceptedAt,
        privacyAcceptedAt: privacyAcceptedAt,
      );

      _setCurrentEmail(email);
      _setLoginProvider(provider ?? 'email');

      debugPrint('Profile updated for $email (provider: $provider)');
    } catch (e) {
      debugPrint(' Error updating profile: $e');
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

    if (user?.email != null) {
      _setCurrentEmail(user!.email);
    }
  }

  Future<void> _updateUserProfile() async {
    if (!_loggedIn) {
      _setProfileCompleted(false);
      _setRole(null);
      _setLoginProvider(null);
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;

      final provider =
          user.userMetadata?['provider']?.toString().toLowerCase() ?? 'email';
      _setLoginProvider(provider);
      _setCurrentEmail(user.email);

      final rememberMe = await SessionManager.isRememberMeEnabled();
      if (user.email != null && rememberMe) {
        final session = supabase.auth.currentSession;

        await SessionManager.saveUserProfile(
          email: user.email!,
          userId: user.id,
          name: user.userMetadata?['full_name'] ?? user.email!.split('@').first,
          photo:
              user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
          rememberMe: rememberMe,
          provider: provider,
          accessToken: session?.accessToken,
          refreshToken: session?.refreshToken,
        );
      }

      // Get profile with role_id and join with roles table to get role name
      final profile = await supabase
          .from('profiles')
          .select('''
          id, 
          is_blocked, 
          is_active, 
          role_id,
          role:role_id (
            name
          )
        ''')
          .eq('id', user.id)
          .maybeSingle();

      _setProfileCompleted(profile != null);

      if (_profileCompleted) {
        if (profile?['is_blocked'] == true) {
          _setErrorMessage('Account blocked');
          await logout();
          return;
        }

        if (profile?['is_active'] == false) {
          _setErrorMessage('Account inactive');
          await logout();
          return;
        }

        String? userRole = await SessionManager.getUserRole();

        // If no role in session, get it from profile
        if (userRole == null) {
          // Try to get role name from joined data first
          if (profile != null &&
              profile['role'] != null &&
              profile['role'] is Map) {
            userRole = profile['role']['name']?.toString().toLowerCase();
          }

          // If still no role, use initializeUserRole which will fetch using role_id
          if (userRole == null) {
            await initializeUserRole(user.id);
            userRole = await SessionManager.getUserRole();
          } else {
            // Save the role we got from joined data
            await SessionManager.saveUserRole(userRole!);
          }
        }

        _setRole(userRole);

        developer.log(
          '✅ Profile updated: role=$userRole, provider=$provider, profileCompleted=$_profileCompleted',
          name: 'AppState',
        );
      } else {
        _setRole(null);
      }
    } catch (e) {
      developer.log('Profile update error: $e', name: 'AppState');
      _setProfileCompleted(false);
      _setRole(null);
      _setLoginProvider(null);
    }
  }

  Future<void> initializeUserRole(String userId) async {
    const defaultRole = 'customer';
    String? userRole = await SessionManager.getUserRole();

    try {
      final supabase = Supabase.instance.client;

      // Get the profile with role_id
      final profile = await supabase
          .from('profiles')
          .select('role_id')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 5));

      // Use the updated pickRole function (which handles UUID)
      final role = await AuthGate.pickRole(profile['role_id']);

      userRole = role;
      await SessionManager.saveUserRole(userRole);

      debugPrint('User role initialized: $userRole');
      _setRole(userRole);
    } on TimeoutException {
      debugPrint('Database timeout, using default role');
      userRole = defaultRole;
      await SessionManager.saveUserRole(userRole);
      _setRole(userRole);
    } catch (e) {
      debugPrint('Failed to get user role: $e');
      userRole = defaultRole;
      await SessionManager.saveUserRole(userRole);
      _setRole(userRole);
    }
  }

  /// 🔐 Try to auto-login using refresh token
  Future<bool> _tryAutoLoginWithToken(String refreshToken) async {
    try {
      final supabase = Supabase.instance.client;

      // METHOD 1: Try to restore session
      try {
        // First, try to see if we already have a valid session
        final currentSession = supabase.auth.currentSession;
        if (currentSession != null) {
          debugPrint('Already has a valid session');
          return true;
        }
      } catch (e) {
        debugPrint('No existing session: $e');
      }

      // METHOD 2: Try to refresh the session
      // Note: This might require the user to be recently logged in
      // Refresh tokens have limited lifespan
      try {
        // You might need to store and use the entire session JSON
        // This is a simplified approach
        final response = await supabase.auth.refreshSession();

        if (response.session != null && response.user != null) {
          debugPrint('Session refreshed successfully');
          return true;
        }
      } catch (e) {
        debugPrint('Failed to refresh session: $e');
      }

      // METHOD 3: Manual token refresh (advanced)
      // This requires making direct API calls
      try {
        // This is complex and depends on your Supabase setup
        debugPrint('Manual token refresh would be complex to implement');
      } catch (e) {
        debugPrint('Manual refresh failed: $e');
      }

      return false;
    } catch (e) {
      debugPrint(' Auto-login with token failed: $e');
      return false;
    }
  }

  void _resetToSafeState() {
    _setLoggedIn(false);
    _setEmailVerified(false);
    _setProfileCompleted(false);
    _setRole(null);
    _setHasLocalProfile(false);
    _setRememberMeEnabled(false);
    _setLoginProvider(null);
    _setCurrentEmail(null);
  }

  /// 📧 Email verification error handler
  Future<void> emailVerifyerError() async {
    debugPrint('Email verification error handler called');
    _setEmailVerified(false);
    notifyListeners();
  }
}
