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
  // ✅ Save user profile WITH REMEMBER ME AND TOKENS
  static Future<void> saveUserProfile({
    required String email,
    required String userId,
    String? name,
    String? photo,
    List<String>? roles,
    bool rememberMe = false,
    String? refreshToken,
  }) async {
    try {
      if (!rememberMe) {
        print('⚠️ Remember Me not enabled, skipping profile save');
        return;
      }

      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index == -1) {
        profiles.add({
          'email': email,
          'userId': userId,
          'name': name ?? email.split('@').first,
          'photo': photo ?? '',
          'roles': roles ?? <String>[],
          'lastLogin': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
          'rememberMe': rememberMe,
          'refreshToken': refreshToken,
          'tokenSavedAt': DateTime.now().toIso8601String(),
        });
        print('✅ New profile created for: $email (Remember Me: $rememberMe)');
      } else {
        profiles[index] = {
          ...profiles[index],
          'userId': userId,
          'name': name ?? profiles[index]['name'],
          'photo': photo ?? profiles[index]['photo'],
          'roles': roles ?? profiles[index]['roles'],
          'lastLogin': DateTime.now().toIso8601String(),
          'rememberMe': rememberMe,
          'refreshToken': refreshToken ?? profiles[index]['refreshToken'],
          'tokenSavedAt': refreshToken != null
              ? DateTime.now().toIso8601String()
              : profiles[index]['tokenSavedAt'],
        };
        print('✅ Profile updated for: $email (Remember Me: $rememberMe)');
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      await setCurrentUser(email);
      await _prefs.setBool(_showContinueKey, true);
      await setRememberMe(rememberMe);
    } catch (e) {
      print('❌ Error saving profile: $e');
    }
  }

  // ✅ WORKING AUTO-LOGIN WITH PERSISTENCE CHECK
  static Future<bool> tryAutoLogin(String email) async {
    try {
      print('🚀 ===== ATTEMPTING AUTO-LOGIN =====');
      print('📧 Target email: $email');

      // 1. Check if remember me is enabled
      final rememberMeEnabled = await isRememberMeEnabled();
      if (!rememberMeEnabled) {
        print('⚠️ Auto-login failed: Remember Me not enabled');
        return false;
      }

      // 2. Check if profile exists
      final profile = await getProfileByEmail(email);
      if (profile == null || profile.isEmpty) {
        print('⚠️ Auto-login failed: No profile found');
        return false;
      }

      // 3. Check if profile has remember me enabled
      if (profile['rememberMe'] != true) {
        print('⚠️ Auto-login failed: Profile does not have Remember Me');
        return false;
      }

      // 4. DEBUG: Check session persistence
      await SupabasePersistenceHelper.debugSessionPersistence();

      // 5. Check current Supabase state
      final supabase = Supabase.instance.client;

      // Wait for Supabase to initialize
      await Future.delayed(const Duration(milliseconds: 300));

      // METHOD 1: Direct check
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;

      print('🔍 METHOD 1 - Direct check:');
      print('   - Current user: ${currentUser?.email}');
      print('   - Has session: ${currentSession != null}');

      if (currentSession != null && currentUser?.email == email) {
        print('✅ AUTO-LOGIN SUCCESS: User already authenticated!');
        await updateLastLogin(email);
        return true;
      }

      // METHOD 2: Check persisted session in storage
      print('🔄 METHOD 2 - Checking persisted storage...');

      final hasPersistedSession =
          await SupabasePersistenceHelper.hasPersistedSession();
      print('   - Has persisted session in storage: $hasPersistedSession');

      if (hasPersistedSession) {
        print('🔄 Persisted session found, waiting for Supabase to restore...');

        // Give Supabase more time to restore from storage
        for (int i = 0; i < 3; i++) {
          await Future.delayed(const Duration(milliseconds: 400));

          final userAfterWait = supabase.auth.currentUser;
          final sessionAfterWait = supabase.auth.currentSession;

          print(
            '   - Check ${i + 1}: User=${userAfterWait?.email}, Session=${sessionAfterWait != null}',
          );

          if (sessionAfterWait != null && userAfterWait?.email == email) {
            print('✅ AUTO-LOGIN SUCCESS: Session restored from persistence!');
            await updateLastLogin(email);
            return true;
          }
        }
      }

      // METHOD 3: Try to manually trigger session restoration
      print('🔄 METHOD 3 - Manual restoration attempt...');

      try {
        // Access auth properties to trigger any lazy loading
        final userId = currentUser?.id;
        final userRole = currentUser?.role;
        final appMetadata = currentUser?.appMetadata;

        print('   - User ID: $userId');
        print('   - User role: $userRole');
        print('   - App metadata: $appMetadata');

        // One more wait
        await Future.delayed(const Duration(milliseconds: 500));

        final finalUser = supabase.auth.currentUser;
        final finalSession = supabase.auth.currentSession;

        print('🔍 FINAL CHECK:');
        print('   - User: ${finalUser?.email}');
        print('   - Session: ${finalSession != null}');

        if (finalSession != null && finalUser?.email == email) {
          print('✅ AUTO-LOGIN SUCCESS: Manual restoration worked!');
          await updateLastLogin(email);
          return true;
        }
      } catch (e) {
        print('❌ Manual restoration error: $e');
      }

      // 6. Auto-login failed
      print('❌ AUTO-LOGIN FAILED: No active session could be restored');
      print('ℹ️ Possible reasons:');
      print('   1. User logged out manually');
      print('   2. Session expired (default: 1 hour)');
      print('   3. App data was cleared');
      print('   4. Supabase persistence not working');

      return false;
    } catch (e, stackTrace) {
      print('❌ AUTO-LOGIN ERROR: $e');
      print('Stack: $stackTrace');
      return false;
    }
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
}
