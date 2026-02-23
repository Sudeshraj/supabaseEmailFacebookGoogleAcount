import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class SessionManager {
  // Keys
  static const String _keyProfiles = 'saved_profiles';
  static const String _currentUserKey = 'current_user';
  static const String _showContinueKey = 'show_continue_screen';
  static const String _rememberMeKey = 'remember_me_enabled';

  // Secure storage
  static final FlutterSecureStorage _secureStorage =
      const FlutterSecureStorage();
  static late SharedPreferences _prefs;

  // Current consent version (update when TOS/Privacy changes)
  static const String _currentConsentVersion = '2.1';

  // Initialize
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('SessionManager initialized with secure storage');
  }

  //PUBLIC: Session validation method
  static bool isSessionValid(Session? session) {
    if (session == null) return false;
    if (session.expiresAt == null) return true;

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(session.expiresAt!);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);

    // Session is valid if it expires in more than 2 minutes
    return timeUntilExpiry.inMinutes > 2;
  }

  //SECURE: Save user profile with App Store compliance
  // SessionManager.dart - FIXED photo handling
  static Future<void> saveUserProfile({
    required String email,
    required String userId,
    String? name,
    String? photo,
    List<String>? roles,
    bool rememberMe = true,
    String? refreshToken,
    String? accessToken,
    String? provider,
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
    bool? marketingConsent,
    DateTime? marketingConsentAt,
    String? appVersion,
  }) async {
    debugPrint('Saving profile for: $email');
    debugPrint('Photo URL provided: ${photo ?? "NULL"}');   
      debugPrint('Provider provided: $provider');
  

    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      final existingProfile = index != -1
          ? profiles[index]
          : <String, dynamic>{};

      final now = DateTime.now();

      // FIXED: Better photo handling logic
      String? finalPhoto;

      if (photo != null && photo.isNotEmpty) {
        // 1. NEW photo always takes priority
        finalPhoto = photo;
        debugPrint('Using new photo URL: $finalPhoto');
      } else if (existingProfile['photo'] != null &&
          existingProfile['photo'].toString().isNotEmpty) {
        // 2. Keep existing photo if available
        finalPhoto = existingProfile['photo'].toString();
        debugPrint('Keeping existing photo: $finalPhoto');
      } else {
        // 3. No photo - set empty string (not null)
        finalPhoto = '';
        debugPrint('No photo available for $email');
      }

      // FIXED: Provider selection with better photo detection
      String actualProvider;

      if (provider != null && provider.isNotEmpty && provider != 'email') {
        actualProvider = provider;
        debugPrint('Using provided provider: $actualProvider');
      } else if (finalPhoto.isNotEmpty) {
        // Try to detect provider from photo URL
        if (finalPhoto.contains('googleusercontent.com')) {
          actualProvider = 'google';
          debugPrint('Detected Google from photo URL');
        } else if (finalPhoto.contains('fbcdn.net') ||
            finalPhoto.contains('facebook.com') || finalPhoto.contains('platform-lookaside.fbsbx.com')) {
          actualProvider = 'facebook';
          debugPrint('Detected Facebook from photo URL');
        } else if (finalPhoto.contains('apple.com') ||
            finalPhoto.contains('appleid.apple.com')) {
          actualProvider = 'apple';
          debugPrint('Detected Apple from photo URL');
        } else {
          actualProvider = existingProfile['provider'] as String? ?? 'email';
            debugPrint('Using existing provider or defaulting to email');
        }
      } else {
        actualProvider = existingProfile['provider'] as String? ?? 'email';
         debugPrint('Using existing provider or defaulting to email2');
      }

      final profileData = <String, dynamic>{
        'email': email,
        'userId': userId,
        'name': name ?? existingProfile['name'] ?? email.split('@').first,

        // CRITICAL FIX: Always set photo (even if empty)
        'photo': finalPhoto,

        'roles': roles ?? existingProfile['roles'] ?? <String>[],
        'lastLogin': now.toIso8601String(),
        'createdAt': existingProfile['createdAt'] ?? now.toIso8601String(),
        'rememberMe': rememberMe,
        'provider': actualProvider,

        // App Store compliance
        'termsAcceptedAt':
            termsAcceptedAt?.toIso8601String() ??
            existingProfile['termsAcceptedAt'] ??
            now.toIso8601String(),

        'privacyAcceptedAt':
            privacyAcceptedAt?.toIso8601String() ??
            existingProfile['privacyAcceptedAt'] ??
            now.toIso8601String(),

        'consentVersion': _currentConsentVersion,

        // GDPR compliance
        'dataConsentGiven': true,
        'dataDeletionRequested': false,
        'dataRetentionDate': now
            .add(const Duration(days: 730))
            .toIso8601String(),

        // Marketing consent
        'marketingConsent': marketingConsent ?? false,
        'marketingConsentAt': marketingConsent == true
            ? (marketingConsentAt ?? now).toIso8601String()
            : '',

        'appVersion': appVersion ?? '1.0.0',
      };

      // ✅ DEBUG: Log photo info
      if (kDebugMode) {
        print('PROFILE DATA SAVED:');
        print('   - Email: $email');
        print('   - Photo: ${profileData['photo']}');
        print('   - Photo type: ${profileData['photo'].runtimeType}');
        print('   - Photo empty: ${(profileData['photo'] as String).isEmpty}');
        print('   - Provider: $actualProvider');
      }

      // Save or update profile
      if (index == -1) {
        if (rememberMe) {
          profiles.add(profileData);
          debugPrint('New profile saved with photo');
        }
      } else {
        if (rememberMe) {
          profiles[index] = profileData;
          debugPrint('Profile updated with photo');
        } else {
          profiles.removeAt(index);
          debugPrint('Profile removed');
        }
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));

      // Set current user
      if (rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        debugPrint('Continue screen enabled');
      } else {
        final currentEmail = await getCurrentUserEmail();
        if (currentEmail == email) {
          await _prefs.remove(_currentUserKey);
          await _prefs.setBool(_showContinueKey, false);
          debugPrint('User removed from continue screen');
        }
      }

      await setRememberMe(rememberMe);

      // Save tokens if available
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _secureStorage.write(
          key: '${userId}_refresh_token',
          value: refreshToken,
          aOptions: _getAndroidOptions(),
          iOptions: _getIOSOptions(),
        );
      }

      if (accessToken != null && accessToken.isNotEmpty) {
        await _secureStorage.write(
          key: '${userId}_access_token',
          value: accessToken,
          aOptions: _getAndroidOptions(),
          iOptions: _getIOSOptions(),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(' Error saving profile: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // ✅ ENHANCED: AUTO-LOGIN with compliance checks
  static Future<bool> tryAutoLogin(String email) async {
    try {
      debugPrint('===== ATTEMPTING AUTO-LOGIN (COMPLIANT) =====');
      debugPrint('Target email: $email');

      // 1. Check if profile exists
      final profile = await getProfileByEmail(email);
      if (profile == null || profile.isEmpty) {
        debugPrint('Auto-login failed: No profile found');
        return false;
      }

      // 2. Check if user has valid session
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;

      // Check if already logged in
      if (currentUser?.email == email && currentSession != null) {
        if (isSessionValid(currentSession)) {
          debugPrint('AUTO-LOGIN SUCCESS: Already logged in');
          await updateLastLogin(email);
          return true;
        }
      }

      // 3. Get refresh token from secure storage
      final userId = profile['userId'] as String?;
      if (userId == null) {
        debugPrint('Auto-login failed: No user ID found');
        return false;
      }

      final refreshToken = await _secureStorage.read(
        key: '${userId}_refresh_token',
      );

      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('Auto-login failed: No secure refresh token found');
        return false;
      }

      // 4. Try to restore session with refresh token
      try {
        debugPrint('Attempting to restore session with secure token...');
        await supabase.auth.setSession(refreshToken);

        // Wait for session restoration
        await Future.delayed(const Duration(milliseconds: 500));

        final restoredUser = supabase.auth.currentUser;
        final restoredSession = supabase.auth.currentSession;

        if (restoredUser?.email == email && restoredSession != null) {
          debugPrint('AUTO-LOGIN SUCCESS: Session restored securely');
          await updateLastLogin(email);

          // Update tokens in secure storage
          await _updateSecureTokens(userId, restoredSession);

          return true;
        }
      } catch (e) {
        debugPrint(' Secure session restoration failed: $e');
        await _cleanupInvalidSession(userId, email);
      }

      debugPrint('AUTO-LOGIN FAILED: Could not restore session');
      return false;
    } catch (e, stackTrace) {
      debugPrint('AUTO-LOGIN ERROR: $e');
      debugPrint('Stack: $stackTrace');
      return false;
    }
  }

  // NEW: Update marketing consent (SignInScreen needs this)
  static Future<void> updateMarketingConsent({
    required String email,
    required bool consent,
    required DateTime consentedAt,
  }) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['marketingConsent'] = consent;
        profiles[index]['marketingConsentAt'] = consent
            ? consentedAt.toIso8601String()
            : '';

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('Marketing consent updated for: $email');
      }
    } catch (e) {
      debugPrint('Error updating marketing consent: $e');
      rethrow;
    }
  }

  // NEW: Update consent timestamps (SignInScreen needs this)
  static Future<void> updateConsentTimestamps({
    required String email,
    required DateTime termsAcceptedAt,
    required DateTime privacyAcceptedAt,
  }) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['termsAcceptedAt'] = termsAcceptedAt.toIso8601String();
        profiles[index]['privacyAcceptedAt'] = privacyAcceptedAt
            .toIso8601String();
        profiles[index]['consentVersion'] = _currentConsentVersion;

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint(' Consent timestamps updated for: $email');
      }
    } catch (e) {
      debugPrint('Error updating consent timestamps: $e');
      rethrow;
    }
  }

  // COMPLIANT LOGOUT FOR CONTINUE SCREEN
  static Future<void> logoutForContinue() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final email = await getCurrentUserEmail();
      final rememberMe = await isRememberMeEnabled();

      if (user != null && email != null && email == user.email) {
        final currentSession = supabase.auth.currentSession;

        if (rememberMe && currentSession != null) {
          // Save refresh token before logout
          await saveUserProfile(
            email: email,
            userId: user.id,
            name: user.userMetadata?['full_name'] ?? email.split('@').first,
            rememberMe: rememberMe,
            refreshToken: currentSession.refreshToken,
            accessToken: currentSession.accessToken,
            provider: await _getUserProvider(email),
          );
          debugPrint('Refresh token saved before continue logout');
        }
      }

      // Sign out from Supabase
      await supabase.auth.signOut();

      // Save current user for continue screen if remember me is enabled
      debugPrint('User prepared for continue screen (Remember Me: $rememberMe)');
      if (email != null && rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        debugPrint(' User prepared for continue screen (Remember Me: $rememberMe)');
      } else {
        await _prefs.remove(_currentUserKey);
        await clearContinueScreen();
        debugPrint(' User cleared for continue screen');
      }
    } catch (e) {
      debugPrint(' Error during continue logout: $e');
    }
  }

  // SECURE: Save refresh token
  static Future<void> saveRefreshToken(
    String email,
    String? refreshToken,
  ) async {
    try {
      final profile = await getProfileByEmail(email);
      final userId = profile?['userId'] as String?;

      if (userId != null && refreshToken != null && refreshToken.isNotEmpty) {
        await _secureStorage.write(
          key: '${userId}_refresh_token',
          value: refreshToken,
          aOptions: _getAndroidOptions(),
          iOptions: _getIOSOptions(),
        );

        // Update timestamp in profile
        final profiles = await getProfiles();
        final index = profiles.indexWhere((p) => p['email'] == email);

        if (index != -1) {
          profiles[index]['tokenSavedAt'] = DateTime.now().toIso8601String();
          await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        }

        debugPrint('Refresh token saved securely for: $email');
      }
    } catch (e) {
      debugPrint('Error saving refresh token: $e');
    }
  }

  // SECURE: Get refresh token
  static Future<String?> getRefreshToken(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      final userId = profile?['userId'] as String?;

      if (userId != null) {
        return await _secureStorage.read(key: '${userId}_refresh_token');
      }
      return null;
    } catch (e) {
      debugPrint('Error getting refresh token: $e');
      return null;
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
      debugPrint(' Error getting profiles: $e');
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
        debugPrint(' Role saved: $role for $email');
      }
    } catch (e) {
      debugPrint('Error saving role: $e');
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
    debugPrint('Checking profiles, count: ${profiles.length}');
    return profiles.isNotEmpty;
  }

  // Update last login time
  static Future<void> updateLastLogin(String email) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['lastLogin'] = DateTime.now().toIso8601String();
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('Last login updated for: $email');
      }
    } catch (e) {
      debugPrint('Error updating last login: $e');
    }
  }

  //  Remove a profile
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

        // Clean up secure storage
        final profile = await getProfileByEmail(email);
        final userId = profile?['userId'] as String?;
        if (userId != null) {
          await _secureStorage.delete(key: '${userId}_refresh_token');
          await _secureStorage.delete(key: '${userId}_access_token');
        }

        debugPrint(' Profile and secure data removed: $email');
      }
    } catch (e) {
      debugPrint('Error removing profile: $e');
    }
  }

  // Remember Me settings
  static Future<void> setRememberMe(bool enabled) async {
    await _prefs.setBool(_rememberMeKey, enabled);
    debugPrint('Remember Me set to: $enabled');
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
    debugPrint('Continue screen flag cleared');
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
      debugPrint('Error getting profile: $e');
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
      debugPrint('Error getting recent profile: $e');
      return null;
    }
  }

  // ✅ Clear all sessions and profiles
static Future<void> clearAll() async {
  try {
    print('🧹 SessionManager.clearAll() started');
    
    // 1. Clear all SharedPreferences data
    await _prefs.remove(_keyProfiles);
    await _prefs.remove(_currentUserKey);
    await _prefs.remove(_showContinueKey);
    await _prefs.remove(_rememberMeKey);
    
    // 2. Clear any role-related keys
    final keys = _prefs.getKeys();
    for (var key in keys) {
      if (key.contains('_all_roles') || key.contains('current_selected_role')) {
        await _prefs.remove(key);
        print('   - Removed: $key');
      }
    }
    
    // 3. Clear secure storage (tokens)
    await _secureStorage.deleteAll();
    print('   - Secure storage cleared');

    debugPrint('✅ All session data cleared (including secure storage)');
  } catch (e) {
    debugPrint('❌ Error clearing all data: $e');
  }
}

  // Get most recent user based on lastLogin time
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
      debugPrint('Error getting most recent user: $e');
      return null;
    }
  }

  // Get last added user
  static Future<Map<String, dynamic>?> getLastUser() async {
    try {
      final profiles = await getProfiles();
      if (profiles.isEmpty) return null;
      return profiles.last;
    } catch (e) {
      debugPrint('Error getting last user: $e');
      return null;
    }
  }

  // ✅ Check if user has valid Supabase session
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
      debugPrint('Error checking session validity: $e');
      return false;
    }
  }

  // Restore session from storage
  static Future<bool> restoreSessionFromStorage(String email) async {
    return tryAutoLogin(email);
  }

  // Validate and refresh session
  static Future<void> validateAndRefreshSession() async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session == null) {
        debugPrint('No active session to validate');
        return;
      }

      if (session.expiresAt != null) {
        final expiryTime = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt!,
        );
        final now = DateTime.now();
        final minutesUntilExpiry = expiryTime.difference(now).inMinutes;

        if (minutesUntilExpiry < 5) {
          debugPrint(
            'Session expiring soon ($minutesUntilExpiry minutes), attempting refresh...',
          );

          try {
            await supabase.auth.getUser();
            debugPrint('Session refresh triggered');
          } catch (e) {
            debugPrint(' Session refresh failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error validating session: $e');
    }
  }

  // PRIVATE HELPER METHODS

  static Future<void> _updateSecureTokens(
    String userId,
    Session session,
  ) async {
    try {
      await _secureStorage.write(
        key: '${userId}_refresh_token',
        value: session.refreshToken,
        aOptions: _getAndroidOptions(),
        iOptions: _getIOSOptions(),
      );

      await _secureStorage.write(
        key: '${userId}_access_token',
        value: session.accessToken,
        aOptions: _getAndroidOptions(),
        iOptions: _getIOSOptions(),
      );

      debugPrint('Secure tokens updated');
    } catch (e) {
      debugPrint('Error updating secure tokens: $e');
    }
  }

  static Future<void> _cleanupInvalidSession(
    String userId,
    String email,
  ) async {
    try {
      debugPrint('Cleaning up invalid session for: $email');

      await _secureStorage.delete(key: '${userId}_refresh_token');
      await _secureStorage.delete(key: '${userId}_access_token');

      // Update profile to remove token references
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['tokenSavedAt'] = '';
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      }

      debugPrint(' Invalid session cleaned up');
    } catch (e) {
      debugPrint(' Error cleaning up session: $e');
    }
  }

  static Future<String?> _getUserProvider(String email) async {
    final profile = await getProfileByEmail(email);
    return profile?['provider'] as String?;
  }


  static AndroidOptions _getAndroidOptions() =>
      const AndroidOptions(encryptedSharedPreferences: true);

  static IOSOptions _getIOSOptions() => const IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    synchronizable: true,
  );

  // NEW: GDPR Data Export
  static Future<Map<String, dynamic>> exportUserData(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      if (profile == null) throw Exception('User not found');

      // Remove sensitive information
      final exportData = Map<String, dynamic>.from(profile);

      // Exclude tokens and sensitive data
      exportData.remove('refreshToken');
      exportData.remove('tokenSavedAt');

      // Add export metadata
      exportData['exportedAt'] = DateTime.now().toIso8601String();
      exportData['exportFormat'] = 'JSON';
      exportData['dataTypesIncluded'] = [
        'profile',
        'preferences',
        'consent_history',
      ];

      return exportData;
    } catch (e) {
      debugPrint('Error exporting user data: $e');
      rethrow;
    }
  }

  // NEW: GDPR Data Deletion Request
  static Future<void> requestDataDeletion(String email) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        // Mark for deletion
        profiles[index]['dataDeletionRequested'] = true;
        profiles[index]['deletionRequestedAt'] = DateTime.now()
            .toIso8601String();

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));

        // Get user ID for secure storage cleanup
        final userId = profiles[index]['userId'] as String?;
        if (userId != null) {
          await _secureStorage.delete(key: '${userId}_refresh_token');
          await _secureStorage.delete(key: '${userId}_access_token');
        }

        debugPrint('Data deletion requested for: $email');
      }
    } catch (e) {
      debugPrint('Error requesting data deletion: $e');
    }
  }

  // NEW: Get user's consent status
  static Future<Map<String, dynamic>> getConsentStatus(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      if (profile == null) throw Exception('User not found');

      return {
        'termsAcceptedAt': profile['termsAcceptedAt'],
        'privacyAcceptedAt': profile['privacyAcceptedAt'],
        'consentVersion': profile['consentVersion'] ?? _currentConsentVersion,
        'marketingConsent': profile['marketingConsent'] ?? false,
        'marketingConsentAt': profile['marketingConsentAt'],
        'dataConsentGiven': profile['dataConsentGiven'] ?? false,
        'dataDeletionRequested': profile['dataDeletionRequested'] ?? false,
        'dataRetentionDate': profile['dataRetentionDate'],
      };
    } catch (e) {
      debugPrint('Error getting consent status: $e');
      rethrow;
    }
  }

  //  NEW: Check if user needs to re-consent
  static Future<bool> needsReconsent(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      if (profile == null) return true;

      final consentVersion = profile['consentVersion'] as String?;
      return consentVersion != _currentConsentVersion;
    } catch (e) {
      debugPrint(' Error checking reconsent: $e');
      return true;
    }
  }

  // NEW: Secure storage health check
  static Future<bool> checkSecureStorageHealth() async {
    try {
      // Try to write and read a test value
      const testKey = 'health_check_key';
      const testValue = 'health_check_value';

      await _secureStorage.write(
        key: testKey,
        value: testValue,
        aOptions: _getAndroidOptions(),
        iOptions: _getIOSOptions(),
      );

      final readValue = await _secureStorage.read(key: testKey);
      await _secureStorage.delete(key: testKey);

      return readValue == testValue;
    } catch (e) {
      debugPrint('Secure storage health check failed: $e');
      return false;
    }
  }

  // NEW: Get active session count
  static Future<int> getActiveSessionCount() async {
    try {
      final profiles = await getProfiles();
      int count = 0;

      for (var profile in profiles) {
        final email = profile['email'] as String?;
        if (email != null) {
          if (await hasValidSupabaseSession(email)) {
            count++;
          }
        }
      }

      return count;
    } catch (e) {
      debugPrint(' Error getting active session count: $e');
      return 0;
    }
  }

  // NEW: Clean up expired sessions
  static Future<void> cleanupExpiredSessions() async {
    try {
      final profiles = await getProfiles();
      final now = DateTime.now();

      for (var profile in profiles) {
        final retentionDate = profile['dataRetentionDate'] as String?;
        if (retentionDate != null) {
          final retention = DateTime.parse(retentionDate);
          if (retention.isBefore(now)) {
            final email = profile['email'] as String?;
            if (email != null) {
              await removeProfile(email);
              debugPrint('Cleaned up expired session for: $email');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up expired sessions: $e');
    }
  }


  // SessionManager.dart එකට මේ functions add කරන්න

// =====================================================
// ✅ SAVE ALL USER ROLES (from database)
// =====================================================
static Future<void> saveUserRoles({
  required String email,
  required List<String> roles,
}) async {
  try {
    print('📝 SessionManager.saveUserRoles START');
    print('   - Email: $email');
    print('   - Roles: $roles');
    
    final profiles = await getProfiles();
    print('   - Current profiles count: ${profiles.length}');
    
    final index = profiles.indexWhere((p) => p['email'] == email);
    print('   - Profile index: $index');

    if (index != -1) {
      // Update existing profile
      profiles[index]['roles'] = roles;
      profiles[index]['roles_updated_at'] = DateTime.now().toIso8601String();
      print('   ✅ Updated existing profile');
    } else {
      // Create new profile entry
      profiles.add({
        'email': email,
        'roles': roles,
        'created_at': DateTime.now().toIso8601String(),
      });
      print('   ✅ Created new profile');
    }
    
    // Save to SharedPreferences
    final jsonString = jsonEncode(profiles);
    await _prefs.setString(_keyProfiles, jsonString);
    print('   ✅ Saved to SharedPreferences (_keyProfiles)');
    
    // Save as separate key for quick access
    await _prefs.setStringList('${email}_all_roles', roles);
    print('   ✅ Saved quick access: ${email}_all_roles');
    
    // Verify quick access save
    final savedQuick = _prefs.getStringList('${email}_all_roles');
    print('   🔍 Quick access verification: $savedQuick');
    
    debugPrint('✅ SessionManager: Saved all roles for $email: $roles');
    print('📝 SessionManager.saveUserRoles END');
  } catch (e, stackTrace) {
    debugPrint('❌ SessionManager: Error saving user roles: $e');
    print('   ❌ Stack trace: $stackTrace');
  }
}

// =====================================================
// ✅ GET ALL USER ROLES
// =====================================================
static Future<List<String>> getUserRoles(String email) async {
  try {
    // Try quick access first
    final quickRoles = _prefs.getStringList('${email}_all_roles');
    if (quickRoles != null) {
      return quickRoles;
    }
    
    // Fallback to profiles
    final profile = await getProfileByEmail(email);
    if (profile != null && profile['roles'] != null) {
      final roles = List<String>.from(profile['roles'] as List);
      return roles;
    }
    
    return [];
  } catch (e) {
    debugPrint('❌ Error getting user roles: $e');
    return [];
  }
}

// =====================================================
// ✅ SAVE CURRENT SELECTED ROLE
// =====================================================
static Future<void> saveCurrentRole(String role) async {
  try {
    await _prefs.setString('current_selected_role', role);
    debugPrint('✅ Saved current role: $role');
  } catch (e) {
    debugPrint('❌ Error saving current role: $e');
  }
}

// =====================================================
// ✅ GET CURRENT SELECTED ROLE
// =====================================================
static Future<String?> getCurrentRole() async {
  try {
    return _prefs.getString('current_selected_role');
  } catch (e) {
    debugPrint('❌ Error getting current role: $e');
    return null;
  }
}

// =====================================================
// ✅ CLEAR USER ROLES (on logout)
// =====================================================
static Future<void> clearUserRoles(String email) async {
  try {
    await _prefs.remove('${email}_all_roles');
    await _prefs.remove('current_selected_role');
    
    // Also update profiles
    final profiles = await getProfiles();
    final index = profiles.indexWhere((p) => p['email'] == email);
    if (index != -1) {
      profiles[index]['roles'] = [];
      await _prefs.setString(_keyProfiles, jsonEncode(profiles));
    }
    
    debugPrint('✅ Cleared roles for $email');
  } catch (e) {
    debugPrint('❌ Error clearing user roles: $e');
  }
}
}
