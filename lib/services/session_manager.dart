import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionManager {
  static const String _keyProfiles = 'saved_profiles';
  static const String _currentUserKey = 'current_user';
  static const String _showContinueKey = 'show_continue_screen';
  static const String _supabaseRefreshKey = 'supabase_refresh';
  
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    print('✅ SessionManager initialized');
  }

  // ✅ Save user profile WITHOUT password
  static Future<void> saveUserProfile({
    required String email,
    required String userId,
    String? name,
    String? photo,
    List<String>? roles,
  }) async {
    try {
      final profiles = await getProfiles();

      // Check if email already exists
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index == -1) {
        // New profile
        profiles.add({
          'email': email,
          'userId': userId,
          'name': name ?? email.split('@').first,
          'photo': photo ?? '',
          'roles': roles ?? <String>[],
          'lastLogin': DateTime.now().toIso8601String(),
          'createdAt': DateTime.now().toIso8601String(),
        });
        print('✅ New profile created for: $email');
      } else {
        // Update existing profile
        profiles[index] = {
          ...profiles[index],
          'userId': userId,
          'name': name ?? profiles[index]['name'],
          'photo': photo ?? profiles[index]['photo'],
          'roles': roles ?? profiles[index]['roles'],
          'lastLogin': DateTime.now().toIso8601String(),
        };
        print('✅ Profile updated for: $email');
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      
      // Set as current user
      await setCurrentUser(email);
      
      // Enable continue screen
      await _prefs.setBool(_showContinueKey, true);
      
      // Save Supabase session tokens
      await saveSupabaseSession();
      
    } catch (e) {
      print('❌ Error saving profile: $e');
    }
  }

  // ✅ Save Supabase session tokens securely
  static Future<void> saveSupabaseSession() async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      
      if (session != null && session.refreshToken != null) {
        // Save refresh token for session recovery
        await _prefs.setString(_supabaseRefreshKey, session.refreshToken!);
        print('✅ Supabase refresh token saved');
      }
    } catch (e) {
      print('❌ Error saving Supabase session: $e');
    }
  }

  // ✅ Try auto login using stored tokens
  static Future<bool> tryAutoLogin(String email) async {
    try {
      print('🔄 Attempting auto login for: $email');
      
      // 1. Get user profile
      final profile = await getProfileByEmail(email);
      if (profile == null || profile.isEmpty) {
        print('❌ No profile found for: $email');
        return false;
      }
      
      // 2. Check Supabase session
      final supabase = Supabase.instance.client;
      
      // Check current session first
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;
      
      if (currentSession != null && currentUser?.email == email) {
        print('✅ Already logged in via Supabase');
        await updateLastLogin(email); // ✅ Changed to public method
        return true;
      }
      
      // 3. Try to recover session using refresh token
      final refreshToken = _prefs.getString(_supabaseRefreshKey);
      if (refreshToken != null) {
        print('🔄 Attempting session recovery...');
        
        try {
          // Try to set session manually
          await supabase.auth.setSession(refreshToken);
          
          // Check if session was restored
          await Future.delayed(const Duration(milliseconds: 500));
          
          final restoredUser = supabase.auth.currentUser;
          final restoredSession = supabase.auth.currentSession;
          
          if (restoredSession != null && restoredUser?.email == email) {
            print('✅ Session restored successfully');
            await updateLastLogin(email); // ✅ Changed to public method
            return true;
          }
        } catch (e) {
          print('❌ Session recovery failed: $e');
          // Clear invalid token
          await _prefs.remove(_supabaseRefreshKey);
        }
      }
      
      print('❌ No valid session available');
      return false;
      
    } catch (e) {
      print('❌ Auto login error: $e');
      return false;
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
        final List<String> roles = List<String>.from(profiles[index]['roles'] ?? []);
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
        
        // If removing current user, clear current user
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

  // ✅ LOGOUT WITH CONTINUE SCREEN - Keep profile
  static Future<void> logoutForContinue() async {
    try {
      // Save current user email before logout
      final email = await getCurrentUserEmail();
      
      // Enable continue screen
      await _prefs.setBool(_showContinueKey, true);
      
      // Clear Supabase tokens
      await _prefs.remove(_supabaseRefreshKey);
      
      // Clear current user
      await _prefs.remove(_currentUserKey);
      
      // Sign out from Supabase
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();
      
      print('✅ Logged out (profile saved for continue screen)');
    } catch (e) {
      print('❌ Error during logout: $e');
    }
  }

  // Check if should show continue screen
  static Future<bool> shouldShowContinueScreen() async {
    final show = _prefs.getBool(_showContinueKey) ?? false;
    final hasProfiles = await hasProfile();
    return show && hasProfiles;
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
      await _prefs.remove(_supabaseRefreshKey);
      print('✅ All session data cleared');
    } catch (e) {
      print('❌ Error clearing all data: $e');
    }
  }
  
  // Check if user has valid Supabase session
  static Future<bool> hasValidSupabaseSession(String email) async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;
      
      if (session != null && user != null && user.email == email) {
        // Check if session is still valid
        if (session.expiresAt != null) {
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(session.expiresAt!);
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

  // ✅ Get most recent user based on lastLogin time
static Future<Map<String, dynamic>?> getMostRecentUser() async {
  try {
    final profiles = await getProfiles();
    if (profiles.isEmpty) return null;
    
    // Sort by lastLogin time (most recent first)
    profiles.sort((a, b) {
      final aTime = DateTime.tryParse(a['lastLogin'] ?? '') ?? DateTime(1970);
      final bTime = DateTime.tryParse(b['lastLogin'] ?? '') ?? DateTime(1970);
      return bTime.compareTo(aTime); // Descending order
    });
    
    return profiles.first;
  } catch (e) {
    print('❌ Error getting most recent user: $e');
    return null;
  }
}

  /// -------------------------------------------------------
  /// 🔹 SharedPreferences helper (for custom use)
  /// -------------------------------------------------------
  static Future<SharedPreferences> getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  // ✅ Get last added user (original functionality)
static Future<Map<String, dynamic>?> getLastUser() async {
  try {
    final profiles = await getProfiles();
    if (profiles.isEmpty) return null;
    return profiles.last; // Last in the list
  } catch (e) {
    print('❌ Error getting last user: $e');
    return null;
  }
}

}

