import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_manager.dart';
import '../router/auth_gate.dart';

/// Production-ready App State Management with Multiple Role Support
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

  // ✅ FIXED: Multiple roles support
  List<String> _roles = []; // All user roles
  String? _currentRole; // Currently selected role

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

  // ✅ FIXED: Role getters
  List<String> get roles => List.unmodifiable(_roles);
  String? get role => _currentRole; // Keep for backward compatibility
  String? get currentRole => _currentRole;
  bool get hasMultipleRoles => _roles.length > 1;

  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  bool get rememberMeEnabled => _rememberMeEnabled;
  String? get loginProvider => _loginProvider;
  String? get currentEmail => _currentEmail;
  User? get currentUser => _currentUser;

  // ====================
  // PRIVATE SETTERS (UPDATED)
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

  // ✅ FIXED: Set all roles
  void _setRoles(List<String> roles) {
    if (!listEquals(_roles, roles)) {
      _roles = List.from(roles);
      notifyListeners();
    }
  }

  // ✅ FIXED: Set current role
  void _setCurrentRole(String? role) {
    if (_currentRole != role) {
      _currentRole = role;
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

    developer.log('AppState: Initializing...', name: 'AppState');

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

      developer.log(
        'AppState: Refreshed - Roles: $_roles, Current: $_currentRole',
        name: 'AppState',
      );
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
      _setRoles([]); // Clear all roles
      _setCurrentRole(null); // Clear current role
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
      _setRoles([]);
      _setCurrentRole(null);
      _setCurrentEmail(null);
      _setLoginProvider(null);

      developer.log('User logged out for continue screen', name: 'AppState');
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

  /// ✅ FIXED: Set current role (call this after role selection)
  Future<void> setCurrentRole(String role) async {
    if (_roles.contains(role)) {
      _setCurrentRole(role);
      await SessionManager.saveCurrentRole(role);
      developer.log('Current role set to: $role', name: 'AppState');
    } else {
      developer.log(
        'Cannot set role: $role not in user roles',
        name: 'AppState',
      );
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
            _currentRole == 'owner'; // FIXED: 'owner' not 'business'

      case '/employee':
        return _loggedIn &&
            _emailVerified &&
            _profileCompleted &&
            _currentRole == 'employee';

      case '/customer':
        return _loggedIn &&
            _emailVerified &&
            _profileCompleted &&
            (_currentRole == 'customer' || _currentRole == null);

      case '/reg':
        return _loggedIn && _emailVerified && !_profileCompleted;

      case '/verify-email':
        return _loggedIn && !_emailVerified;

      case '/role-selector':
        return _loggedIn &&
            _emailVerified &&
            _profileCompleted &&
            _roles.length > 1; // Only show if multiple roles

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
      'roles': _roles, // All roles
      'currentRole': _currentRole, // Current role
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
        'AppState: Attempting auto-login for $email (provider: $provider)',
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
    List<String>? roles, // ✅ NEW: Add roles parameter
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

      if (roles != null) {
        await SessionManager.saveUserRoles(email: email, roles: roles);
        _setRoles(roles);
      }

      _setCurrentEmail(email);
      _setLoginProvider(provider ?? 'email');

      debugPrint(
        'Profile updated for $email (provider: $provider, roles: $roles)',
      );
    } catch (e) {
      debugPrint('Error updating profile: $e');
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

  // ✅ FIXED: Update user profile with multiple roles
  Future<void> _updateUserProfile() async {
    if (!_loggedIn) {
      _setProfileCompleted(false);
      _setRoles([]);
      _setCurrentRole(null);
      _setLoginProvider(null);
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;
      final email = user.email!;

      final provider =
          user.userMetadata?['provider']?.toString().toLowerCase() ?? 'email';
      _setLoginProvider(provider);
      _setCurrentEmail(email);

      final rememberMe = await SessionManager.isRememberMeEnabled();
      if (rememberMe) {
        final session = supabase.auth.currentSession;

        await SessionManager.saveUserProfile(
          email: email,
          userId: user.id,
          name: user.userMetadata?['full_name'] ?? email.split('@').first,
          photo:
              user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
          rememberMe: rememberMe,
          provider: provider,
          accessToken: session?.accessToken,
          refreshToken: session?.refreshToken,
        );
      }

      // ✅ Get ALL profiles for this user (multiple roles)
      final profiles = await supabase
          .from('profiles')
          .select('''
            id, 
            is_blocked, 
            is_active, 
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('id', user.id);

      _setProfileCompleted(profiles.isNotEmpty);

      if (_profileCompleted) {
        // Check if any profile is blocked/inactive
        final hasBlocked = profiles.any((p) => p['is_blocked'] == true);
        final hasInactive = profiles.any((p) => p['is_active'] == false);

        if (hasBlocked) {
          _setErrorMessage('Account blocked');
          await logout();
          return;
        }

        if (hasInactive) {
          _setErrorMessage('Account inactive');
          await logout();
          return;
        }

        // ✅ Extract ALL role names
        final List<String> roleNames = [];
        for (var profile in profiles) {
          final role = profile['roles'] as Map?;
          if (role != null && role['name'] != null) {
            roleNames.add(role['name'].toString());
          }
        }

        // Remove duplicates (just in case)
        final uniqueRoles = roleNames.toSet().toList();
        _setRoles(uniqueRoles);

        // ✅ Get current role from SessionManager
        String? savedCurrentRole = await SessionManager.getCurrentRole();

        // If saved role is valid, use it
        if (savedCurrentRole != null &&
            uniqueRoles.contains(savedCurrentRole)) {
          _setCurrentRole(savedCurrentRole);
        }
        // Otherwise, use first role or default to 'customer'
        else {
          final defaultRole = uniqueRoles.isNotEmpty
              ? uniqueRoles.first
              : 'customer';
          _setCurrentRole(defaultRole);
          await SessionManager.saveCurrentRole(defaultRole);
        }

        developer.log(
          '✅ Profile updated: roles=$uniqueRoles, current=$_currentRole, provider=$provider',
          name: 'AppState',
        );
      } else {
        _setRoles([]);
        _setCurrentRole(null);
      }
    } catch (e) {
      developer.log('Profile update error: $e', name: 'AppState');
      _setProfileCompleted(false);
      _setRoles([]);
      _setCurrentRole(null);
      _setLoginProvider(null);
    }
  }

  Future<void> initializeUserRole(String userId) async {
    try {
      final supabase = Supabase.instance.client;

      final profiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('id', userId);

      final List<String> roleNames = [];
      for (var profile in profiles) {
        final role = profile['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }

      _setRoles(roleNames);

      final currentRole = roleNames.isNotEmpty ? roleNames.first : 'customer';
      _setCurrentRole(currentRole);

      await SessionManager.saveCurrentRole(currentRole);

      debugPrint('User roles initialized: $roleNames, current: $currentRole');
    } catch (e) {
      debugPrint('Failed to get user roles: $e');
      _setRoles([]);
      _setCurrentRole('customer');
    }
  }

  /// 🔐 Try to auto-login using refresh token
  Future<bool> _tryAutoLoginWithToken(String refreshToken) async {
    try {
      final supabase = Supabase.instance.client;

      // Check existing session
      final currentSession = supabase.auth.currentSession;
      if (currentSession != null) {
        debugPrint('Already has a valid session');
        return true;
      }

      // Try to refresh session
      try {
        final response = await supabase.auth.refreshSession();

        if (response.session != null && response.user != null) {
          debugPrint('Session refreshed successfully');
          return true;
        }
      } catch (e) {
        debugPrint('Failed to refresh session: $e');
      }

      return false;
    } catch (e) {
      debugPrint('Auto-login with token failed: $e');
      return false;
    }
  }

  void _resetToSafeState() {
    _setLoggedIn(false);
    _setEmailVerified(false);
    _setProfileCompleted(false);
    _setRoles([]);
    _setCurrentRole(null);
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
