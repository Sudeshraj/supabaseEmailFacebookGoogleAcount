import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:io' show Platform;

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
    print('✅ SessionManager initialized with secure storage');
  }

  // ✅ PUBLIC: Session validation method
  static bool isSessionValid(Session? session) {
    if (session == null) return false;
    if (session.expiresAt == null) return true;

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(session.expiresAt!);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);

    // Session is valid if it expires in more than 2 minutes
    return timeUntilExpiry.inMinutes > 2;
  }

  // ✅ SECURE: Save user profile with App Store compliance
  // SessionManager.dart - FIXED saveUserProfile method
  static Future<void> saveUserProfile({
    required String email,
    required String userId,
    String? name,
    String? photo,
    List<String>? roles,
    bool rememberMe = true,
    String? refreshToken,
    String? accessToken,
    String? provider, // ✅ OAuth provider (google, facebook, apple)
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
    bool? marketingConsent,
    DateTime? marketingConsentAt,
    String? appVersion,
  }) async {
    print('💾 Saving profile for: $email');
    print('💾 Saving profile for..............: $provider');

    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      final existingProfile = index != -1
          ? profiles[index]
          : <String, dynamic>{};

      final now = DateTime.now();

      // ✅ FIXED: Priority for provider selection
      String actualProvider;

      if (provider != null && provider.isNotEmpty && provider != 'email') {
        // 1. New OAuth provider takes priority
        actualProvider = provider;
        print('✅ Using new OAuth provider: $actualProvider');
      } else if (existingProfile['provider'] != null &&
          existingProfile['provider'] != 'email') {
        // 2. Keep existing OAuth provider
        actualProvider = existingProfile['provider'] as String;
        print('✅ Keeping existing OAuth provider: $actualProvider');
      } else {
        // 3. Default to 'email' only if truly email/password
        actualProvider = 'email';
        print('✅ Defaulting to email provider');
      }

      // ✅ Additional check: If this looks like OAuth but provider is 'email', fix it
      if (actualProvider == 'email') {
        // Check OAuth indicators
        final hasOAuthToken =
            (refreshToken != null && refreshToken.isNotEmpty) ||
            (accessToken != null && accessToken.isNotEmpty);
        final hasOAuthPhoto = photo != null && photo.isNotEmpty;
        final hasOAuthMetadata = name != null && name.contains(' ');

        if (hasOAuthToken && (hasOAuthPhoto || hasOAuthMetadata)) {
          // Try to detect provider from photo URL
          if (photo?.contains('googleusercontent.com') ?? false) {
            actualProvider = 'google';
            print('🔄 Detected Google from photo URL');
          } else if (photo?.contains('fbcdn.net') ?? false) {
            actualProvider = 'facebook';
            print('🔄 Detected Facebook from photo URL');
          } else if (provider != null && provider != 'email') {
            // Use the passed provider if available
            actualProvider = provider!;
            print('🔄 Using passed provider: $actualProvider');
          }
        }
      }

      final profileData = <String, dynamic>{
        'email': email,
        'userId': userId,
        'name': name ?? existingProfile['name'] ?? email.split('@').first,
        'photo': photo ?? existingProfile['photo'] ?? '',
        'roles': roles ?? existingProfile['roles'] ?? <String>[],
        'lastLogin': now.toIso8601String(),
        'createdAt': existingProfile['createdAt'] ?? now.toIso8601String(),
        'rememberMe': rememberMe,

        // ✅ FIXED: Always use determined provider
        'provider': actualProvider,

        // App Store compliance data
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

        // App info
        'appVersion': appVersion ?? '1.0.0',
      };

      if (kDebugMode) {
        print('📊 Profile Data:');
        print('   - Email: $email');
        print('   - Provider: $actualProvider');
        print('   - Remember Me: $rememberMe');
        print(
          '   - Has refresh token: ${refreshToken != null && refreshToken.isNotEmpty}',
        );
        print(
          '   - Has access token: ${accessToken != null && accessToken.isNotEmpty}',
        );
      }

      // Save logic...
      if (index == -1) {
        if (rememberMe) {
          profiles.add(profileData);
          print('✅ New profile saved: $email (Provider: $actualProvider)');
        }
      } else {
        if (rememberMe) {
          profiles[index] = profileData;
          print('✅ Profile updated: $email (Provider: $actualProvider)');
        } else {
          profiles.removeAt(index);
          print('✅ Profile removed: $email');
        }
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));

      // Set current user
      // if (rememberMe) {
      //   await setCurrentUser(email);
      //   await _prefs.setBool(_showContinueKey, true);
      // }

      if (rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        print('✅ Continue screen enabled for: $email');
      } else {
        // If rememberMe is false, remove from current user
        final currentEmail = await getCurrentUserEmail();
        if (currentEmail == email) {
          await _prefs.remove(_currentUserKey);
          await _prefs.setBool(_showContinueKey, false);
          print('✅ User removed from continue screen (rememberMe: false)');
        }
      }

      await setRememberMe(rememberMe);
    } catch (e) {
      print('❌ Error saving profile: $e');
      rethrow;
    }
  }

  // ✅ ENHANCED: AUTO-LOGIN with compliance checks
  static Future<bool> tryAutoLogin(String email) async {
    try {
      print('🚀 ===== ATTEMPTING AUTO-LOGIN (COMPLIANT) =====');
      print('📧 Target email: $email');

      // 1. Check if profile exists
      final profile = await getProfileByEmail(email);
      if (profile == null || profile.isEmpty) {
        print('⚠️ Auto-login failed: No profile found');
        return false;
      }

      // 2. Check if user has valid session
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;

      // Check if already logged in
      if (currentUser?.email == email && currentSession != null) {
        if (isSessionValid(currentSession)) {
          print('✅ AUTO-LOGIN SUCCESS: Already logged in');
          await updateLastLogin(email);
          return true;
        }
      }

      // 3. Get refresh token from secure storage
      final userId = profile['userId'] as String?;
      if (userId == null) {
        print('⚠️ Auto-login failed: No user ID found');
        return false;
      }

      final refreshToken = await _secureStorage.read(
        key: '${userId}_refresh_token',
      );

      if (refreshToken == null || refreshToken.isEmpty) {
        print('⚠️ Auto-login failed: No secure refresh token found');
        return false;
      }

      // 4. Try to restore session with refresh token
      try {
        print('🔄 Attempting to restore session with secure token...');
        await supabase.auth.setSession(refreshToken);

        // Wait for session restoration
        await Future.delayed(const Duration(milliseconds: 500));

        final restoredUser = supabase.auth.currentUser;
        final restoredSession = supabase.auth.currentSession;

        if (restoredUser?.email == email && restoredSession != null) {
          print('✅ AUTO-LOGIN SUCCESS: Session restored securely');
          await updateLastLogin(email);

          // Update tokens in secure storage
          await _updateSecureTokens(userId, restoredSession);

          return true;
        }
      } catch (e) {
        print('❌ Secure session restoration failed: $e');
        await _cleanupInvalidSession(userId, email);
      }

      print('❌ AUTO-LOGIN FAILED: Could not restore session');
      return false;
    } catch (e, stackTrace) {
      print('❌ AUTO-LOGIN ERROR: $e');
      print('Stack: $stackTrace');
      return false;
    }
  }

  // ✅ NEW: Update marketing consent (SignInScreen needs this)
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
        print('✅ Marketing consent updated for: $email');
      }
    } catch (e) {
      print('❌ Error updating marketing consent: $e');
      rethrow;
    }
  }

  // ✅ NEW: Update consent timestamps (SignInScreen needs this)
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
        print('✅ Consent timestamps updated for: $email');
      }
    } catch (e) {
      print('❌ Error updating consent timestamps: $e');
      rethrow;
    }
  }

  // ✅ COMPLIANT LOGOUT FOR CONTINUE SCREEN
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
          print('✅ Refresh token saved before continue logout');
        }
      }

      // Sign out from Supabase
      await supabase.auth.signOut();

      // Save current user for continue screen if remember me is enabled
      print('✅ User prepared for continue screen (Remember Me: $rememberMe)');
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

  // ✅ SECURE: Save refresh token
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

        print('✅ Refresh token saved securely for: $email');
      }
    } catch (e) {
      print('❌ Error saving refresh token: $e');
    }
  }

  // ✅ SECURE: Get refresh token
  static Future<String?> getRefreshToken(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      final userId = profile?['userId'] as String?;

      if (userId != null) {
        return await _secureStorage.read(key: '${userId}_refresh_token');
      }
      return null;
    } catch (e) {
      print('❌ Error getting refresh token: $e');
      return null;
    }
  }

  // ✅ Get all saved profiles
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

  // ✅ Set current user
  static Future<void> setCurrentUser(String email) async {
    await _prefs.setString(_currentUserKey, email);
  }

  // ✅ Get current user email
  static Future<String?> getCurrentUserEmail() async {
    return _prefs.getString(_currentUserKey);
  }

  // ✅ Save user role
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

  // ✅ Get user role
  static Future<String?> getUserRole() async {
    final email = await getCurrentUserEmail();
    if (email == null) return null;

    final profile = await getProfileByEmail(email);
    if (profile == null || profile.isEmpty) return null;

    final roles = List<String>.from(profile['roles'] ?? []);
    return roles.isNotEmpty ? roles.first : null;
  }

  // ✅ Check if has any profiles
  static Future<bool> hasProfile() async {
    final profiles = await getProfiles();
    print('🔍 Checking profiles, count: ${profiles.length}');
    return profiles.isNotEmpty;
  }

  // ✅ Update last login time
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

  // ✅ Remove a profile
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

        print('✅ Profile and secure data removed: $email');
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

  // ✅ Check if should show continue screen
  static Future<bool> shouldShowContinueScreen() async {
    final show = _prefs.getBool(_showContinueKey) ?? false;
    final rememberMe = await isRememberMeEnabled();
    return show && rememberMe;
  }

  // ✅ Clear continue screen flag
  static Future<void> clearContinueScreen() async {
    await _prefs.setBool(_showContinueKey, false);
    print('✅ Continue screen flag cleared');
  }

  // ✅ Get profile by email
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

  // ✅ Get most recent profile
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

  // ✅ Clear all sessions and profiles
  static Future<void> clearAll() async {
    try {
      await _prefs.remove(_keyProfiles);
      await _prefs.remove(_currentUserKey);
      await _prefs.remove(_showContinueKey);
      await _prefs.remove(_rememberMeKey);

      // Clear secure storage
      await _secureStorage.deleteAll();

      print('✅ All session data cleared (including secure storage)');
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

  // ✅ Get last added user
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
      print('❌ Error checking session validity: $e');
      return false;
    }
  }

  // ✅ Restore session from storage
  static Future<bool> restoreSessionFromStorage(String email) async {
    return tryAutoLogin(email);
  }

  // ✅ Validate and refresh session
  static Future<void> validateAndRefreshSession() async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session == null) {
        print('⚠️ No active session to validate');
        return;
      }

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

  // ✅ PRIVATE HELPER METHODS

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

      print('✅ Secure tokens updated');
    } catch (e) {
      print('❌ Error updating secure tokens: $e');
    }
  }

  static Future<void> _cleanupInvalidSession(
    String userId,
    String email,
  ) async {
    try {
      print('🧹 Cleaning up invalid session for: $email');

      await _secureStorage.delete(key: '${userId}_refresh_token');
      await _secureStorage.delete(key: '${userId}_access_token');

      // Update profile to remove token references
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['tokenSavedAt'] = '';
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      }

      print('✅ Invalid session cleaned up');
    } catch (e) {
      print('❌ Error cleaning up session: $e');
    }
  }

  static Future<String?> _getUserProvider(String email) async {
    final profile = await getProfileByEmail(email);
    return profile?['provider'] as String?;
  }

  static String _getPlatformInfo() {
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
      return 'Unknown';
    } catch (e) {
      return 'Flutter';
    }
  }

  static AndroidOptions _getAndroidOptions() =>
      const AndroidOptions(encryptedSharedPreferences: true);

  static IOSOptions _getIOSOptions() => const IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    synchronizable: true,
  );

  // ✅ NEW: GDPR Data Export
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
      print('❌ Error exporting user data: $e');
      rethrow;
    }
  }

  // ✅ NEW: GDPR Data Deletion Request
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

        print('✅ Data deletion requested for: $email');
      }
    } catch (e) {
      print('❌ Error requesting data deletion: $e');
    }
  }

  // ✅ NEW: Get user's consent status
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
      print('❌ Error getting consent status: $e');
      rethrow;
    }
  }

  // ✅ NEW: Check if user needs to re-consent
  static Future<bool> needsReconsent(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      if (profile == null) return true;

      final consentVersion = profile['consentVersion'] as String?;
      return consentVersion != _currentConsentVersion;
    } catch (e) {
      print('❌ Error checking reconsent: $e');
      return true;
    }
  }

  // ✅ NEW: Secure storage health check
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
      print('❌ Secure storage health check failed: $e');
      return false;
    }
  }

  // ✅ NEW: Get active session count
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
      print('❌ Error getting active session count: $e');
      return 0;
    }
  }

  // ✅ NEW: Clean up expired sessions
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
              print('✅ Cleaned up expired session for: $email');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error cleaning up expired sessions: $e');
    }
  }
}
