import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_manager.dart';

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

  // FIXED: Multiple roles support
  List<String> _roles = []; // All user roles
  String? _currentRole; // Currently selected role

  String? _errorMessage;
  DateTime? _lastUpdateTime;
  bool _rememberMeEnabled = false;
  String? _loginProvider;
  String? _currentEmail;
  User? _currentUser;

  // ✅ NEW: Pending deletion-restore state.
  // When a user logs back in and their profile is
  // scheduled_for_deletion, we no longer silently restore it.
  // Instead we surface this state so the UI can show an
  // explicit confirmation dialog ("Restore your account?").
  bool _pendingDeletionRestore = false;
  DateTime? _deletionRestoreDueDate;
  int? _deletionRestoreDaysRemaining;

  // ✅ NEW: Pending reactivation state - same idea, but for the
  // "Deactivate All" (self-deactivated, status = 'inactive')
  // case, which previously forced an immediate silent logout
  // with no way to reactivate inline. Now it's symmetric with
  // the deletion-restore flow: surface state, let the UI ask.
  bool _pendingReactivation = false;

  // ====================
  // PUBLIC GETTERS
  // ====================
  bool get loading => _loading;
  bool get loggedIn => _loggedIn;
  bool get emailVerified => _emailVerified;
  bool get profileCompleted => _profileCompleted;
  bool get hasLocalProfile => _hasLocalProfile;
  bool get continueSc => _continueSc;

  // FIXED: Role getters
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

  // ✅ NEW: Pending deletion-restore getters
  bool get pendingDeletionRestore => _pendingDeletionRestore;
  DateTime? get deletionRestoreDueDate => _deletionRestoreDueDate;
  int? get deletionRestoreDaysRemaining => _deletionRestoreDaysRemaining;

  // ✅ NEW: Pending reactivation getter
  bool get pendingReactivation => _pendingReactivation;

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

  // FIXED: Set all roles
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

  // ✅ NEW: Set pending deletion-restore state (does not touch DB)
  void _setPendingDeletionRestore({
    required bool pending,
    DateTime? dueDate,
    int? daysRemaining,
  }) {
    if (_pendingDeletionRestore != pending ||
        _deletionRestoreDueDate != dueDate ||
        _deletionRestoreDaysRemaining != daysRemaining) {
      _pendingDeletionRestore = pending;
      _deletionRestoreDueDate = dueDate;
      _deletionRestoreDaysRemaining = daysRemaining;
      notifyListeners();
    }
  }

  // ✅ NEW: Set pending reactivation state (does not touch DB)
  void _setPendingReactivation(bool value) {
    if (_pendingReactivation != value) {
      _pendingReactivation = value;
      notifyListeners();
    }
  }

  // ====================
  // PUBLIC METHODS
  // ====================

  // Initialize app state
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

  // Refresh app state
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

  // Logout user
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

      // 🔥 CRITICAL: Clear all roles and current role
      _setLoggedIn(false);
      _setEmailVerified(false);
      _setProfileCompleted(false);
      _setRoles([]); // Clear all roles
      _setCurrentRole(null); // Clear current role
      _setCurrentEmail(null);
      _setLoginProvider(null);
      _setPendingDeletionRestore(pending: false); // ✅ clear any pending state
      _setPendingReactivation(false); // ✅ clear any pending state

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
      _setPendingDeletionRestore(pending: false); // ✅ clear any pending state
      _setPendingReactivation(false); // ✅ clear any pending state

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

  /// FIXED: Set current role (call this after role selection)
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

  // ============================================================
  // ✅ NEW: EXPLICIT DELETION-RESTORE CONFIRMATION FLOW
  // ============================================================
  // These replace the old silent auto-restore behavior. The UI
  // (e.g. a dialog shown right after login) must call one of
  // these based on the user's explicit choice.

  /// User confirmed they want to restore their scheduled-for-deletion
  /// account. Call this only after explicit user confirmation
  /// (e.g. tapping "Restore my account" in a dialog).
  Future<void> confirmRestoreScheduledProfile() async {
    final email = _currentEmail ?? _currentUser?.email;
    if (email == null) {
      developer.log(
        'confirmRestoreScheduledProfile: no email available',
        name: 'AppState',
      );
      return;
    }

    _setLoading(true);
    try {
      debugPrint('🔄 User confirmed restore for scheduled profile: $email');
      await SessionManager.autoRestoreProfileLevelOnLogin(email: email);
      _setPendingDeletionRestore(pending: false);
      await refreshState();
    } catch (e) {
      debugPrint('❌ Error restoring profile: $e');
      _setErrorMessage('Failed to restore your account. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  /// User declined to restore their scheduled-for-deletion account
  /// (respecting their original deletion request). Signs them out
  /// rather than leaving them in a half-active state.
  Future<void> declineRestoreAndLogout() async {
    _setPendingDeletionRestore(pending: false);
    await logout();
  }

  /// User confirmed they want to reactivate their self-deactivated
  /// ("Deactivate All") account. Same underlying RPC as restore -
  /// updateProfileLevelStatus(status: 'active') - since deactivation
  /// and scheduled-deletion are both represented as inactive
  /// profile states that this one call clears.
  Future<void> confirmReactivateProfile() async {
    final email = _currentEmail ?? _currentUser?.email;
    if (email == null) {
      developer.log(
        'confirmReactivateProfile: no email available',
        name: 'AppState',
      );
      return;
    }

    _setLoading(true);
    try {
      debugPrint('🔄 User confirmed reactivation for: $email');
      await SessionManager.updateProfileLevelStatus(
        email: email,
        status: 'active',
      );
      _setPendingReactivation(false);
      await refreshState();
    } catch (e) {
      debugPrint('❌ Error reactivating profile: $e');
      _setErrorMessage('Failed to reactivate your account. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  /// User declined to reactivate their deactivated account. Signs
  /// them out rather than leaving them in a half-active state.
  Future<void> declineReactivationAndLogout() async {
    _setPendingReactivation(false);
    await logout();
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

  /// Attempt auto-login
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
          debugPrint('AppState: Auto-login successful for $email');
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

  /// Update user profile after login
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
    List<String>? roles, // NEW: Add roles parameter
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

  // 🔥 FIXED: Update user profile with multiple roles using user_roles table
  // ✅ SECURITY FIX: No longer silently auto-restores a
  // scheduled-for-deletion profile. Instead it surfaces
  // `pendingDeletionRestore` state so the UI can ask the user
  // to explicitly confirm restoration (see
  // confirmRestoreScheduledProfile() / declineRestoreAndLogout()
  // above). This respects the user's original deletion request
  // instead of silently overriding it on next login.
  Future<void> _updateUserProfile() async {
    if (!_loggedIn) {
      _setProfileCompleted(false);
      _setRoles([]);
      _setCurrentRole(null);
      _setLoginProvider(null);
      _setPendingDeletionRestore(pending: false);
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        _setProfileCompleted(false);
        return;
      }

      final email = user.email;
      if (email == null) {
        _setProfileCompleted(false);
        return;
      }

      final provider =
          user.userMetadata?['provider']?.toString().toLowerCase() ?? 'email';
      _setLoginProvider(provider);
      _setCurrentEmail(email);

      // ✅ UPDATED: Get ONLY active user roles
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

      // Extract role names from active roles only
      final List<String> roleNames = [];
      for (var roleEntry in userRolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }

      // Remove duplicates
      final uniqueRoles = roleNames.toSet().toList();

      // Check if user has any active roles
      _setProfileCompleted(uniqueRoles.isNotEmpty);
      _setRoles(uniqueRoles);

      // Get profile data for additional info
      if (uniqueRoles.isNotEmpty) {
        final profile = await supabase
            .from('profiles')
            .select('is_blocked, is_active, extra_data')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null) {
          if (profile['is_blocked'] == true) {
            _setErrorMessage('Account blocked');
            await logout();
            return;
          }

          if (profile['is_active'] == false) {
            // ✅ Check if scheduled for deletion
            final extraData =
                profile['extra_data'] as Map<String, dynamic>? ?? {};
            final profileStatus =
                extraData['profile_status'] as Map<String, dynamic>?;

            if (profileStatus != null &&
                profileStatus['status'] == 'scheduled_for_deletion') {
              // ✅ FIX: Do NOT auto-restore silently. Surface the
              // pending state instead so the UI can ask the user.
              debugPrint(
                '⏸️ Profile scheduled for deletion - awaiting user confirmation to restore',
              );

              DateTime? dueDate;
              int? daysRemaining;
              final dueDateStr =
                  profileStatus['deletion_due_date'] as String?;
              if (dueDateStr != null) {
                dueDate = DateTime.tryParse(dueDateStr);
                if (dueDate != null) {
                  daysRemaining = dueDate.difference(DateTime.now()).inDays;
                }
              }

              _setPendingDeletionRestore(
                pending: true,
                dueDate: dueDate,
                daysRemaining: daysRemaining,
              );

              // Keep profileCompleted false so routing sends the
              // user to a safe screen until they decide, but do
              // NOT log them out here - the confirmation dialog
              // needs an active session to call the restore RPC.
              _setProfileCompleted(false);
              return;
            } else if (profileStatus != null &&
                profileStatus['status'] == 'inactive') {
              // ✅ FIX: Self-deactivated via "Deactivate All" - this
              // is a reversible, user-initiated pause, not a
              // deletion. Symmetric with the restore flow above:
              // surface pending state instead of a silent forced
              // logout, so the UI can offer "Reactivate?".
              debugPrint(
                '⏸️ Profile deactivated - awaiting user confirmation to reactivate',
              );
              _setPendingReactivation(true);
              _setProfileCompleted(false);
              return;
            } else {
              // Unknown inactive state (e.g. set directly by an
              // admin outside the profile_status flow) - no
              // self-service option, force logout as before.
              _setErrorMessage('Account inactive');
              await logout();
              return;
            }
          } else {
            // Profile is active - make sure any stale pending flags are cleared
            _setPendingDeletionRestore(pending: false);
            _setPendingReactivation(false);
          }
        }
      }

      // Handle remember me
      final rememberMe = await SessionManager.isRememberMeEnabled();
      if (rememberMe && uniqueRoles.isNotEmpty) {
        final session = supabase.auth.currentSession;

        await SessionManager.saveUserProfile(
          email: email,
          userId: user.id,
          name: user.userMetadata?['full_name'] ?? email.split('@').first,
          photo:
              user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
          roles: uniqueRoles,
          rememberMe: rememberMe,
          provider: provider,
          accessToken: session?.accessToken,
          refreshToken: session?.refreshToken,
        );
      }

      // Get current role from SessionManager
      String? savedCurrentRole = await SessionManager.getCurrentRole();

      if (savedCurrentRole == null) {
        final pendingRole = await SessionManager.consumePendingRoleSelection(
          email,
        );
        if (pendingRole != null && uniqueRoles.contains(pendingRole)) {
          savedCurrentRole = pendingRole;
          await SessionManager.saveCurrentRole(pendingRole);
        }
      }

      // If saved role is valid, use it
      if (savedCurrentRole != null && uniqueRoles.contains(savedCurrentRole)) {
        _setCurrentRole(savedCurrentRole);
      }
      // If no saved role or saved role invalid, set first role in memory only
      else {
        final defaultRole = uniqueRoles.isNotEmpty ? uniqueRoles.first : null;
        _setCurrentRole(defaultRole);
      }

      developer.log(
        'Profile updated: activeRoles=$uniqueRoles, current=$_currentRole, provider=$provider',
        name: 'AppState',
      );
    } catch (e) {
      developer.log('Profile update error: $e', name: 'AppState');
      _setProfileCompleted(false);
      _setRoles([]);
      _setCurrentRole(null);
      _setLoginProvider(null);
    }
  }

  /// Initialize user roles from database
  Future<void> initializeUserRole(String userId) async {
    try {
      final supabase = Supabase.instance.client;

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('user_id', userId);

      final List<String> roleNames = [];
      for (var roleEntry in userRolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }

      final uniqueRoles = roleNames.toSet().toList();
      _setRoles(uniqueRoles);

      // Set current role (first role, but don't save)
      final currentRole = uniqueRoles.isNotEmpty ? uniqueRoles.first : null;
      _setCurrentRole(currentRole);

      debugPrint(
        'User roles initialized: $uniqueRoles, current: $currentRole (not saved)',
      );
    } catch (e) {
      debugPrint('Failed to get user roles: $e');
      _setRoles([]);
      _setCurrentRole(null);
    }
  }

  /// Try to auto-login using refresh token
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
    _setPendingDeletionRestore(pending: false);
    _setPendingReactivation(false);
  }

  /// Email verification error handler
  Future<void> emailVerifyerError() async {
    debugPrint('Email verification error handler called');
    _setEmailVerified(false);
    notifyListeners();
  }
}