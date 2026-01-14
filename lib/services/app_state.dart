import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:firebase_crashlytics/firebase_crashlytics.dart';

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
  bool _countinueSc = false;
  String? _role;
  String? _errorMessage;
  DateTime? _lastUpdateTime;

  // ====================
  // PUBLIC GETTERS
  // ====================
  bool get loading => _loading;
  bool get loggedIn => _loggedIn;
  bool get emailVerified => _emailVerified;
  bool get profileCompleted => _profileCompleted;
  bool get hasLocalProfile => _hasLocalProfile;
  bool get continueSc => _countinueSc;
  String? get role => _role;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;

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
  void _setCountinueScreen(bool value) {
    if (_countinueSc != value) {
      _countinueSc = value;
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
      // 1. Check local profiles
      final hasProfiles = await SessionManager.hasProfile();
      final csc = await SessionManager.shouldShowContinueScreen();
      print(hasProfiles);
     
    
      _setHasLocalProfile(hasProfiles);
      _setCountinueScreen(csc);

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

      // Report to Crashlytics in production
      if (!kDebugMode) {
        // FirebaseCrashlytics.instance.recordError(e, stackTrace);
      }

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
       _setHasLocalProfile(hasProfiles);

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

  /// 🚪 Logout user
  Future<void> logout() async {
    _setLoading(true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null && user.email != null) {
        // Save user data for continue screen
        await SessionManager.saveUserProfile(
          email: user.email!,
          userId: user.id,
          name: user.userMetadata?['full_name'],
        );
      }

      // Sign out
      await supabase.auth.signOut();

      // Clear role but keep profiles
      // await SessionManager.clearUserRole();

      // Update state
      _setLoggedIn(false);
      _setEmailVerified(false);
      _setProfileCompleted(false);
      _setRole(null);

      developer.log('✅ User logged out', name: 'AppState');
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
      'lastUpdate': _lastUpdateTime?.toIso8601String(),
    };
  }

  /// 🎯 Clear error message
  void clearError() {
    _setErrorMessage(null);
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
      // Save user profile
      if (user.email != null) {
        await SessionManager.saveUserProfile(
          email: user.email!,
          userId: user.id,
          name: user.email!.split('@').first,
        );
      }

      if (_loggedIn) {
        // final profile = await supabase
        //     .from('profiles')
        //     .select('role, roles')
        //     .eq('id', user.id)
        //     .maybeSingle();
        final profile = await supabase
            .from('profiles')
            .select('id, is_blocked, is_active')
            .eq('id', user.id)
            .maybeSingle();

        _setProfileCompleted(profile != null);

        if (profileCompleted) {
          String? userRole = await SessionManager.getUserRole();
           _setProfileCompleted(true);
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

  // Future<Map<String, dynamic>?> _fetchDatabaseProfile(String userId) async {
  //   try {
  //     final supabase = Supabase.instance.client;
  //     final response = await supabase
  //         .from('profiles')
  //         .select('roles!inner(name)')
  //         .eq('id', userId)
  //         .maybeSingle();

  //     return response;
  //   } catch (e) {
  //     developer.log('❌ Database profile fetch error: $e', name: 'AppState');
  //     return null;
  //   }
  // }

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
      var userRole = AuthGate.pickRole(roleName ?? defaultRole);

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
  }

  Future<void> emailVerifyerError() async {   
    _setEmailVerified(false);   
  }
}
