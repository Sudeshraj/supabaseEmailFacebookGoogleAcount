import 'dart:convert';
import 'package:flutter_application_1/services/supabase_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionManager {
  static const String _keyProfiles = 'saved_profiles';
  static const String _currentUserKey = 'current_user';
  static const String _showContinueKey = 'show_continue_screen';
  static const String _rememberMeKey = 'remember_me_enabled';

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    print('✅ SessionManager initialized');
  }

  // ✅ Save user profile WITH REMEMBER ME OPTION
  // SessionManager.dart - Best solution
  // SessionManager.dart - saveUserProfile method
  static Future<void> saveUserProfile({
    required String email,
    required String userId,
    String? name,
    String? photo,
    List<String>? roles,
    bool rememberMe = true,
    String? refreshToken,
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
    bool? marketingConsent,
    DateTime? marketingConsentAt,
  }) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      final existingProfile = index != -1
          ? profiles[index]
          : <String, dynamic>{};

      final profileData = <String, dynamic>{
        'email': email,
        'userId': userId,
        'name': name ?? existingProfile['name'] ?? email.split('@').first,
        'photo': photo ?? existingProfile['photo'] ?? '',
        'roles': roles ?? existingProfile['roles'] ?? <String>[],
        'lastLogin': DateTime.now().toIso8601String(),
        'createdAt':
            existingProfile['createdAt'] ?? DateTime.now().toIso8601String(),
        'rememberMe': rememberMe,

        // Session tokens
        'refreshToken': refreshToken ?? existingProfile['refreshToken'] ?? '',
        'tokenSavedAt': refreshToken != null
            ? DateTime.now().toIso8601String()
            : existingProfile['tokenSavedAt'] ?? '',

        // Required consents (App Store compliance)
        'termsAcceptedAt':
            termsAcceptedAt?.toIso8601String() ??
            existingProfile['termsAcceptedAt'] ??
            DateTime.now().toIso8601String(),

        'privacyAcceptedAt':
            privacyAcceptedAt?.toIso8601String() ??
            existingProfile['privacyAcceptedAt'] ??
            DateTime.now().toIso8601String(),

        'dataConsentGiven': true,

        // Optional marketing consent
        'marketingConsent':
            marketingConsent ?? existingProfile['marketingConsent'] ?? false,
        'marketingConsentAt':
            marketingConsentAt?.toIso8601String() ??
            existingProfile['marketingConsentAt'] ??
            (marketingConsent == true ? DateTime.now().toIso8601String() : ''),

        // App version info for debugging
        'appVersion': '1.0.0',
        'consentVersion': '2.0',
      };

      if (index == -1) {
        if (rememberMe) {
          profiles.add(profileData);
        }
        print('✅ New profile saved: $email');
      } else {
        print('✅ Profile updated: $email');
        if (rememberMe) {
          profiles[index] = profileData;
        } else {
          profiles.removeAt(index);
        }
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      await setCurrentUser(email);

      if (rememberMe) {
        await _prefs.setBool(_showContinueKey, true);
        print('✅ Continue screen enabled for: $email');
      }

      await setRememberMe(rememberMe);

      // ✅ Log consent for App Store compliance
      print('📊 Consent Data Saved:');
      print('   - Terms accepted: ${profileData['termsAcceptedAt']}');
      print('   - Privacy accepted: ${profileData['privacyAcceptedAt']}');
      print('   - Marketing consent: ${profileData['marketingConsent']}');
      print('   - Marketing consent at: ${profileData['marketingConsentAt']}');
    } catch (e) {
      print('❌ Error saving profile: $e');
      rethrow;
    }
  }

  // ✅ WORKING AUTO-LOGIN WITH PERSISTENCE CHECK
  // SessionManager.dart - tryAutoLogin method
  static Future<bool> tryAutoLogin(String email) async {
    try {
      print('🚀 ===== ATTEMPTING AUTO-LOGIN =====');
      print('📧 Target email: $email');

      // 1. Check if profile exists
      final profile = await getProfileByEmail(email);
      if (profile == null || profile.isEmpty) {
        print('⚠️ Auto-login failed: No profile found');
        return false;
      }

      // 2. Check if profile has remember me enabled
      final profileRememberMe = profile['rememberMe'] ?? true;

      if (!profileRememberMe) {
        print('⚠️ Auto-login failed: User opted out of auto-login');
        return false;
      }

      // 3. Check if user has given consent (App Store/Play Store requirement)
      final termsAccepted = profile['termsAcceptedAt'] != null;
      final privacyAccepted = profile['privacyAcceptedAt'] != null;
      final dataConsentGiven = profile['dataConsentGiven'] == true;

      if (!termsAccepted || !privacyAccepted || !dataConsentGiven) {
        print('⚠️ Auto-login failed: User consent not recorded');
        return false;
      }

      // 4. DEBUG: Check session persistence
      await SupabasePersistenceHelper.debugSessionPersistence();

      // 5. Get Supabase instance
      final supabase = Supabase.instance.client;

      // Wait for Supabase to initialize
      await Future.delayed(const Duration(milliseconds: 500));

      // METHOD 1: Check current session
      final currentSession = supabase.auth.currentSession;
      final currentUser = supabase.auth.currentUser;

      print('🔍 Current session check:');
      print('   - Current user: ${currentUser?.email}');
      print('   - Has session: ${currentSession != null}');

      if (currentSession != null && currentUser?.email == email) {
        // ✅ Check if session is valid
        if (_isSessionValid(currentSession)) {
          print('✅ AUTO-LOGIN SUCCESS: Valid session found!');
          await updateLastLogin(email);
          return true;
        } else {
          print('⚠️ Session expired, trying to refresh...');
        }
      }

      // METHOD 2: Try using refresh token
      final refreshToken = profile['refreshToken'] as String?;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        print('🔄 Found refresh token, attempting to restore session...');

        try {
          // ✅ CORRECT METHOD: Use setSession with refresh token
          await supabase.auth.setSession(refreshToken);

          // Wait for session to be set
          await Future.delayed(const Duration(milliseconds: 300));

          final newSession = supabase.auth.currentSession;
          final newUser = supabase.auth.currentUser;

          if (newSession != null && newUser?.email == email) {
            print('✅ Session restored using refresh token!');
            await updateLastLogin(email);
            return true;
          } else {
            print('❌ Refresh token did not restore session');
          }
        } catch (e) {
          print('❌ Refresh token error: $e');
        }
      }

      // METHOD 3: Try to get current user directly
      print('🔄 Attempting to get current user...');

      try {
        // ✅ Get current user directly
        final user = supabase.auth.currentUser;

        if (user != null && user.email == email) {
          print('✅ Found authenticated user!');
          await updateLastLogin(email);
          return true;
        }

        // Try one more time after delay
        await Future.delayed(const Duration(milliseconds: 800));

        final userAfterDelay = supabase.auth.currentUser;
        if (userAfterDelay != null && userAfterDelay.email == email) {
          print('✅ User found after delay!');
          await updateLastLogin(email);
          return true;
        }
      } catch (e) {
        print('❌ Error getting current user: $e');
      }

      // METHOD 4: Check session storage directly
      print('🔄 Checking persisted storage...');

      final hasPersistedSession =
          await SupabasePersistenceHelper.hasPersistedSession();
      if (hasPersistedSession) {
        print('📊 Persisted session found in storage');

        // Try multiple checks with delays
        for (int i = 0; i < 3; i++) {
          await Future.delayed(const Duration(milliseconds: 500));

          final user = supabase.auth.currentUser;
          final session = supabase.auth.currentSession;

          print(
            '   - Check ${i + 1}: User=${user?.email}, Session=${session != null}',
          );

          if (session != null && user?.email == email) {
            print('✅ Session restored from persistence!');
            await updateLastLogin(email);
            return true;
          }
        }
      }

      // 6. Auto-login failed
      print('❌ AUTO-LOGIN FAILED: Could not restore session');

      // Log debug info
      print('📊 Debug Information:');
      print('   - Profile exists: Yes');
      print('   - Remember Me enabled: $profileRememberMe');
      print('   - Terms accepted: $termsAccepted');
      print('   - Privacy accepted: $privacyAccepted');
      print(
        '   - Refresh token available: ${refreshToken != null && refreshToken.isNotEmpty}',
      );

      return false;
    } catch (e, stackTrace) {
      print('❌ AUTO-LOGIN ERROR: $e');
      print('Stack: $stackTrace');
      return false;
    }
  }

  // ✅ Helper method to check session validity
  static bool _isSessionValid(Session? session) {
    if (session == null) return false;
    if (session.expiresAt == null) return true; // Assume valid if no expiry

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(session.expiresAt!);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);

    // Session is valid if it expires in more than 2 minutes
    return timeUntilExpiry.inMinutes > 2;
  }

  // ✅ Check if we have valid stored token
  static Future<bool> hasValidStoredToken(String email) async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session != null) {
        // Check if session is still valid
        if (session.expiresAt != null) {
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt!,
          );
          final now = DateTime.now();
          final timeUntilExpiry = expiryTime.difference(now);

          // Session is valid if it expires in more than 5 minutes
          if (timeUntilExpiry.inMinutes > 5) {
            print(
              '✅ Valid session found (expires in ${timeUntilExpiry.inMinutes} minutes)',
            );
            return true;
          } else {
            print(
              '⚠️ Session expires soon (in ${timeUntilExpiry.inMinutes} minutes)',
            );
          }
        }
      }

      // Check if we have any stored profiles for this email
      final profile = await getProfileByEmail(email);
      return profile != null && profile.isNotEmpty;
    } catch (e) {
      print('❌ Error checking token validity: $e');
      return false;
    }
  }

  // ✅ Save refresh token for auto-login
  static Future<void> saveRefreshToken(
    String email,
    String? refreshToken,
  ) async {
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final profiles = await getProfiles();
        final index = profiles.indexWhere((p) => p['email'] == email);

        if (index != -1) {
          profiles[index]['refreshToken'] = refreshToken;
          profiles[index]['tokenSavedAt'] = DateTime.now().toIso8601String();
          await _prefs.setString(_keyProfiles, jsonEncode(profiles));
          print('✅ Refresh token saved for: $email');
        }
      }
    } catch (e) {
      print('❌ Error saving refresh token: $e');
    }
  }

  // ✅ Get stored refresh token
  static Future<String?> getRefreshToken(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      return profile?['refreshToken'] as String?;
    } catch (e) {
      print('❌ Error getting refresh token: $e');
      return null;
    }
  }

  // ✅ LOGOUT FOR CONTINUE SCREEN (Compliant version)
  // ✅ ENHANCED LOGOUT FOR CONTINUE SCREEN - PRESERVE AUTO-LOGIN
  static Future<void> logoutForContinue() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final email = await getCurrentUserEmail();
      final rememberMe = await isRememberMeEnabled();

      if (user != null && email != null && email == user.email) {
        // Get current session before logout
        final currentSession = supabase.auth.currentSession;
        final refreshToken = currentSession?.refreshToken;

        if (rememberMe && refreshToken != null) {
          // Save refresh token BEFORE logout
          await saveUserProfile(
            email: email,
            userId: user.id,
            name: user.userMetadata?['full_name'] ?? email.split('@').first,
            rememberMe: rememberMe,
            refreshToken: refreshToken, // Save token for future auto-login
          );
          print('✅ Refresh token saved before continue logout');
        }
      }

      // Sign out from Supabase
      await supabase.auth.signOut();

      // Save current user for continue screen if remember me is enabled
      if (email != null && rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        print('✅ User prepared for continue screen (Remember Me: $rememberMe)');
      } else {
        await _prefs.remove(_currentUserKey);
        await clearContinueScreen();
        print('✅ User cleared for continue screen');
      }
    } catch (e) {
      print('❌ Error during continue logout: $e');
    }
  }

  // Get all saved profiles
  static Future<List<Map<String, dynamic>>> getProfiles() async {
    try {
      final jsonString = _prefs.getString(_keyProfiles) ?? '[]';
      final List<dynamic> jsonList = jsonDecode(jsonString);

      return jsonList.map((item) {
        final map = Map<String, dynamic>.from(item);
        if (map['roles'] is! List<String>) {
          map['roles'] = List<String>.from(map['roles'] ?? []);
        }
        return map;
      }).toList();
    } catch (e) {
      print('❌ Error getting profiles: $e');
      return [];
    }
  }

  // Set current user
  static Future<void> setCurrentUser(String email) async {
    await _prefs.setString(_currentUserKey, email);
  }

  // Get current user email
  static Future<String?> getCurrentUserEmail() async {
    return _prefs.getString(_currentUserKey);
  }

  // Save user role
  static Future<void> saveUserRole(String role) async {
    try {
      final email = await getCurrentUserEmail();
      if (email == null) return;

      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        final List<String> roles = List<String>.from(
          profiles[index]['roles'] ?? [],
        );
        if (!roles.contains(role)) {
          roles.add(role);
        }
        profiles[index]['roles'] = roles;
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        print('✅ Role saved: $role for $email');
      }
    } catch (e) {
      print('❌ Error saving role: $e');
    }
  }

  // Get user role
  static Future<String?> getUserRole() async {
    final email = await getCurrentUserEmail();
    if (email == null) return null;

    final profile = await getProfileByEmail(email);
    if (profile == null || profile.isEmpty) return null;

    final roles = List<String>.from(profile['roles'] ?? []);
    return roles.isNotEmpty ? roles.first : null;
  }

  // Check if has any profiles
  static Future<bool> hasProfile() async {
    final profiles = await getProfiles();
    print('🔍 Checking profiles, count: ${profiles.length}');
    return profiles.isNotEmpty;
  }

  // ✅ PUBLIC METHOD: Update last login time
  static Future<void> updateLastLogin(String email) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['lastLogin'] = DateTime.now().toIso8601String();
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        print('✅ Last login updated for: $email');
      }
    } catch (e) {
      print('❌ Error updating last login: $e');
    }
  }

  // Remove a profile
  static Future<void> removeProfile(String email) async {
    try {
      final profiles = await getProfiles();
      final initialCount = profiles.length;

      profiles.removeWhere((p) => p['email'] == email);

      if (profiles.length < initialCount) {
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));

        final currentEmail = await getCurrentUserEmail();
        if (currentEmail == email) {
          await _prefs.remove(_currentUserKey);
        }

        print('✅ Profile removed: $email');
      }
    } catch (e) {
      print('❌ Error removing profile: $e');
    }
  }

  // ✅ Remember Me settings
  static Future<void> setRememberMe(bool enabled) async {
    await _prefs.setBool(_rememberMeKey, enabled);
    print('✅ Remember Me set to: $enabled');
  }

  static Future<bool> isRememberMeEnabled() async {
    return _prefs.getBool(_rememberMeKey) ?? false;
  }

  // Check if should show continue screen
  static Future<bool> shouldShowContinueScreen() async {
    final show = _prefs.getBool(_showContinueKey) ?? false;
    final rememberMe = await isRememberMeEnabled();
    return show && rememberMe;
  }

  // Clear continue screen flag
  static Future<void> clearContinueScreen() async {
    await _prefs.setBool(_showContinueKey, false);
    print('✅ Continue screen flag cleared');
  }

  // Get profile by email
  static Future<Map<String, dynamic>?> getProfileByEmail(String email) async {
    try {
      final profiles = await getProfiles();
      return profiles.firstWhere(
        (p) => p['email'] == email,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      print('❌ Error getting profile: $e');
      return null;
    }
  }

  // Get most recent profile
  static Future<Map<String, dynamic>?> getMostRecentProfile() async {
    try {
      final profiles = await getProfiles();
      if (profiles.isEmpty) return null;

      profiles.sort((a, b) {
        final aTime = DateTime.tryParse(a['lastLogin'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['lastLogin'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      return profiles.first;
    } catch (e) {
      print('❌ Error getting recent profile: $e');
      return null;
    }
  }

  // Clear all sessions and profiles
  static Future<void> clearAll() async {
    try {
      await _prefs.remove(_keyProfiles);
      await _prefs.remove(_currentUserKey);
      await _prefs.remove(_showContinueKey);
      await _prefs.remove(_rememberMeKey);
      print('✅ All session data cleared');
    } catch (e) {
      print('❌ Error clearing all data: $e');
    }
  }

  // ✅ Get most recent user based on lastLogin time
  static Future<Map<String, dynamic>?> getMostRecentUser() async {
    try {
      final profiles = await getProfiles();
      if (profiles.isEmpty) return null;

      profiles.sort((a, b) {
        final aTime = DateTime.tryParse(a['lastLogin'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['lastLogin'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      return profiles.first;
    } catch (e) {
      print('❌ Error getting most recent user: $e');
      return null;
    }
  }

  // ✅ Get last added user (original functionality)
  static Future<Map<String, dynamic>?> getLastUser() async {
    try {
      final profiles = await getProfiles();
      if (profiles.isEmpty) return null;
      return profiles.last;
    } catch (e) {
      print('❌ Error getting last user: $e');
      return null;
    }
  }

  // Check if user has valid Supabase session
  static Future<bool> hasValidSupabaseSession(String email) async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (session != null && user != null && user.email == email) {
        if (session.expiresAt != null) {
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt!,
          );
          final now = DateTime.now();
          return now.isBefore(expiryTime);
        }
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error checking session validity: $e');
      return false;
    }
  }

  // SessionManager.dart - Add these helper methods
  static Future<bool> restoreSessionFromStorage(String email) async {
    try {
      final supabase = Supabase.instance.client;

      // Try to get the current session
      final currentSession = supabase.auth.currentSession;
      final currentUser = supabase.auth.currentUser;

      // If already logged in with correct user, return success
      if (currentSession != null && currentUser?.email == email) {
        return true;
      }

      // Try to get profile and refresh token
      final profile = await getProfileByEmail(email);
      if (profile == null) return false;

      final refreshToken = profile['refreshToken'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      // Try to set session with refresh token
      await supabase.auth.setSession(refreshToken);

      // Wait and check
      await Future.delayed(const Duration(milliseconds: 800));

      final newSession = supabase.auth.currentSession;
      final newUser = supabase.auth.currentUser;

      return newSession != null && newUser?.email == email;
    } catch (e) {
      print('❌ Error restoring session: $e');
      return false;
    }
  }

  static Future<void> validateAndRefreshSession() async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session == null) {
        print('⚠️ No active session to validate');
        return;
      }

      // Check if session is about to expire (less than 5 minutes)
      if (session.expiresAt != null) {
        final expiryTime = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt!,
        );
        final now = DateTime.now();
        final minutesUntilExpiry = expiryTime.difference(now).inMinutes;

        if (minutesUntilExpiry < 5) {
          print(
            '🔄 Session expiring soon ($minutesUntilExpiry minutes), attempting refresh...',
          );

          try {
            // Supabase automatically refreshes tokens when needed
            // We just need to trigger a check
            await supabase.auth.getUser();
            print('✅ Session refresh triggered');
          } catch (e) {
            print('❌ Session refresh failed: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error validating session: $e');
    }
  }
}
