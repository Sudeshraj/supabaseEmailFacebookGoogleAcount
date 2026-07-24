import 'dart:convert';
import 'package:flutter_application_1/main.dart';
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
  static const String _locationcontinuesc = '_location_continue_sc';

  // Keys for profile switching
  static const String _keyUserRoles = '_all_roles';
  static const String _keyCurrentRole = 'current_selected_role';
  static const String _keyAvailableProfiles = 'available_profiles';

  // Secure storage
  static final FlutterSecureStorage _secureStorage =
      const FlutterSecureStorage();
  static late SharedPreferences _prefs;

  // Current consent version
  static const String _currentConsentVersion = '2.1';

  // Operation locks to prevent infinite loops
  static bool _isSavingProfile = false;
  static bool _isSavingRoles = false;
  static bool _isUpdatingAvailableProfiles = false;
  static Map<String, DateTime> lastOperationTimes = {};

  // Initialize
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('✅ SessionManager initialized with secure storage');
  }

  // Session validation
  static bool isSessionValid(Session? session) {
    if (session == null) return false;
    if (session.expiresAt == null) return true;

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(session.expiresAt!);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);
    return timeUntilExpiry.inMinutes > 2;
  }

  static const String _pendingRoleKey = 'pending_oauth_role';
  static const String _pendingEmailKey = 'pending_oauth_email';

  /// ✅ OAuth redirect එකට කලින් තෝරාගත්ත role එක save කරනවා
  static Future<void> setPendingRoleSelection({
    required String email,
    required String role,
  }) async {
    await _prefs.setString(_pendingRoleKey, role);
    await _prefs.setString(_pendingEmailKey, email);
    debugPrint('📌 Pending role saved before OAuth redirect: $email -> $role');
  }

  /// ✅ OAuth callback එකෙන් ආපහු ආවම, pending role එක ගන්නවා (once only)
  static Future<String?> consumePendingRoleSelection(String email) async {
    final pendingEmail = _prefs.getString(_pendingEmailKey);
    final pendingRole = _prefs.getString(_pendingRoleKey);

    if (pendingEmail == email && pendingRole != null) {
      await _prefs.remove(_pendingRoleKey);
      await _prefs.remove(_pendingEmailKey);
      debugPrint('✅ Consumed pending role: $email -> $pendingRole');
      return pendingRole;
    }
    return null;
  }

  // =====================================================
  // ✅ CONSENT MANAGEMENT FUNCTIONS
  // =====================================================

  static Future<void> updateMarketingConsent({
    required String email,
    required bool consent,
    required DateTime consentedAt,
  }) async {
    try {
      debugPrint('📝 Updating marketing consent for: $email');
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['marketingConsent'] = consent;
        profiles[index]['marketingConsentAt'] = consent
            ? consentedAt.toIso8601String()
            : '';

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('✅ Marketing consent updated for: $email');
      }
    } catch (e) {
      debugPrint('❌ Error updating marketing consent: $e');
      rethrow;
    }
  }

  static Future<void> updateConsentTimestamps({
    required String email,
    required DateTime termsAcceptedAt,
    required DateTime privacyAcceptedAt,
  }) async {
    try {
      debugPrint('📝 Updating consent timestamps for: $email');
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['termsAcceptedAt'] = termsAcceptedAt.toIso8601String();
        profiles[index]['privacyAcceptedAt'] = privacyAcceptedAt
            .toIso8601String();
        profiles[index]['consentVersion'] = _currentConsentVersion;

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('✅ Consent timestamps updated for: $email');
      }
    } catch (e) {
      debugPrint('❌ Error updating consent timestamps: $e');
      rethrow;
    }
  }

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
      debugPrint('❌ Error getting consent status: $e');
      rethrow;
    }
  }

  static Future<bool> needsReconsent(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      if (profile == null) return true;

      final consentVersion = profile['consentVersion'] as String?;
      return consentVersion != _currentConsentVersion;
    } catch (e) {
      debugPrint('❌ Error checking reconsent: $e');
      return true;
    }
  }

  static const String _keySalonId = 'salon_id';
  static const String _keySalonName = 'salon_name';

  // =====================================================
  // ✅ MAIN PROFILE FUNCTIONS
  // =====================================================

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
    if (_isSavingProfile) {
      debugPrint(
        '⏭️ Already saving profile for $email, skipping recursive call',
      );
      return;
    }

    final operationKey = 'profile_$email';
    final now = DateTime.now();
    final lastOp = lastOperationTimes[operationKey];
    if (lastOp != null &&
        now.difference(lastOp) < Duration(milliseconds: 500)) {
      debugPrint('⏭️ Too frequent save for $email, skipping');
      return;
    }

    _isSavingProfile = true;
    lastOperationTimes[operationKey] = now;

    debugPrint('📝 Saving profile for: $email');
    debugPrint('📸 Photo URL provided: ${photo ?? "NULL"}');
    debugPrint('🔑 Provider provided: $provider');
    debugPrint('👥 Roles provided: $roles');

    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      final existingProfile = index != -1
          ? profiles[index]
          : <String, dynamic>{};

      List<String> userRoles = [];

      if (roles != null && roles.isNotEmpty) {
        userRoles = roles;
      } else if (existingProfile.isNotEmpty &&
          existingProfile['roles'] != null) {
        userRoles = List<String>.from(existingProfile['roles'] as List);
      }

      if (index != -1 && roles != null && roles.isNotEmpty) {
        final existingRoles = List<String>.from(existingProfile['roles'] ?? []);
        userRoles = {...existingRoles.toSet(), ...roles.toSet()}.toList();
        debugPrint('📋 Merged new roles with existing: $userRoles');
      }

      debugPrint('📋 Final roles after merge: $userRoles');

      String? finalPhoto;
      if (photo != null && photo.isNotEmpty) {
        finalPhoto = photo;
      } else if (existingProfile['photo'] != null &&
          existingProfile['photo'].toString().isNotEmpty) {
        finalPhoto = existingProfile['photo'].toString();
      } else {
        finalPhoto = '';
      }

      String actualProvider;
      if (provider != null && provider.isNotEmpty && provider != 'email') {
        actualProvider = provider;
      } else if (finalPhoto.isNotEmpty) {
        if (finalPhoto.contains('googleusercontent.com')) {
          actualProvider = 'google';
        } else if (finalPhoto.contains('fbcdn.net') ||
            finalPhoto.contains('facebook.com') ||
            finalPhoto.contains('platform-lookaside.fbsbx.com')) {
          actualProvider = 'facebook';
        } else if (finalPhoto.contains('apple.com') ||
            finalPhoto.contains('appleid.apple.com')) {
          actualProvider = 'apple';
        } else {
          actualProvider = existingProfile['provider'] as String? ?? 'email';
        }
      } else {
        actualProvider = existingProfile['provider'] as String? ?? 'email';
      }

      String? lastLogin;

      if (existingProfile.containsKey('lastLogin') &&
          existingProfile['lastLogin'] != null) {
        lastLogin = now.toIso8601String();
        debugPrint(
          '⏰ Updating lastLogin for $email from ${existingProfile['lastLogin']} to $lastLogin',
        );
      } else {
        lastLogin = now.toIso8601String();
        debugPrint('⏰ Setting first lastLogin for $email: $lastLogin');
      }

      final profileData = <String, dynamic>{
        'email': email,
        'userId': userId,
        'name': name ?? existingProfile['name'] ?? email.split('@').first,
        'photo': finalPhoto,
        'roles': userRoles,
        'lastLogin': lastLogin,
        'createdAt': existingProfile['createdAt'] ?? now.toIso8601String(),
        'rememberMe': rememberMe,
        'provider': actualProvider,
        'termsAcceptedAt':
            termsAcceptedAt?.toIso8601String() ??
            existingProfile['termsAcceptedAt'] ??
            now.toIso8601String(),
        'privacyAcceptedAt':
            privacyAcceptedAt?.toIso8601String() ??
            existingProfile['privacyAcceptedAt'] ??
            now.toIso8601String(),
        'consentVersion': _currentConsentVersion,
        'dataConsentGiven': true,
        'dataDeletionRequested': false,
        'dataRetentionDate': now
            .add(const Duration(days: 730))
            .toIso8601String(),
        'marketingConsent': marketingConsent ?? false,
        'marketingConsentAt': marketingConsent == true
            ? (marketingConsentAt ?? now).toIso8601String()
            : '',
        'appVersion': appVersion ?? '1.0.0',
      };

      if (kDebugMode) {
        print('📊 PROFILE DATA SAVED:');
        print('   - Email: $email');
        print('   - Roles: $userRoles');
        print('   - Photo: ${profileData['photo']}');
        print('   - Provider: $actualProvider');
        print('   - LastLogin: $lastLogin');
      }

      if (index == -1) {
        if (rememberMe) {
          profiles.add(profileData);
          debugPrint('➕ New profile saved locally with roles: $userRoles');
        }
      } else {
        if (rememberMe) {
          profiles[index] = profileData;
          debugPrint(
            '🔄 Profile updated locally with merged roles: $userRoles',
          );
        } else {
          profiles.removeAt(index);
          debugPrint('🗑️ Profile removed');
        }
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));

      if (rememberMe && userRoles.isNotEmpty) {
        await _prefs.setStringList('$email$_keyUserRoles', userRoles);

        final currentUserId = await getCurrentUserId();
        if (currentUserId != null) {
          final existingProfiles = await getAvailableProfiles();
          final currentRole = await getCurrentRole();

          for (String role in userRoles) {
            final profileData = {
              'id': currentUserId,
              'email': email,
              'role': role,
              'role_id': _getRoleIdFromName(role),
              'is_active': true,
              'last_used': role == currentRole ? now.toIso8601String() : null,
            };

            final roleIndex = existingProfiles.indexWhere(
              (p) => p['role'] == role && p['email'] == email,
            );

            if (roleIndex == -1) {
              existingProfiles.add(profileData);
            } else {
              existingProfiles[roleIndex] = {
                ...existingProfiles[roleIndex],
                ...profileData,
              };
            }
          }

          await _prefs.setString(
            _keyAvailableProfiles,
            jsonEncode(existingProfiles),
          );
          debugPrint('✅ Updated available profiles directly');
        }
      }

      if (rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        debugPrint('👤 Continue screen enabled');

        if (userRoles.length == 1) {
          await saveCurrentRole(userRoles.first);
        }
      } else {
        final currentEmail = await getCurrentUserEmail();
        if (currentEmail == email) {
          await _prefs.remove(_currentUserKey);
          await _prefs.setBool(_showContinueKey, false);
        }
      }

      await setRememberMe(rememberMe);

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
      debugPrint('❌ Error saving profile: $e');
      debugPrint('📚 Stack trace: $stackTrace');
      rethrow;
    } finally {
      _isSavingProfile = false;
      debugPrint('🔓 Profile saving lock released for $email');
    }
  }

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
      debugPrint('❌ Error getting profiles: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getProfileByEmail(String email) async {
    try {
      final profiles = await getProfiles();
      return profiles.firstWhere(
        (p) => p['email'] == email,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      debugPrint('❌ Error getting profile: $e');
      return null;
    }
  }

  // =====================================================
  // ✅ ROLE MANAGEMENT FUNCTIONS
  // =====================================================

  static Future<void> saveUserRoles({
    required String email,
    required List<String> roles,
  }) async {
    if (_isSavingRoles) {
      debugPrint('⏭️ Already saving roles for $email, skipping recursive call');
      return;
    }

    final operationKey = 'roles_$email';
    final now = DateTime.now();
    final lastOp = lastOperationTimes[operationKey];
    if (lastOp != null &&
        now.difference(lastOp) < Duration(milliseconds: 500)) {
      debugPrint('⏭️ Too frequent roles save for $email, skipping');
      return;
    }

    _isSavingRoles = true;
    lastOperationTimes[operationKey] = now;

    try {
      debugPrint('📝 SessionManager.saveUserRoles START');
      debugPrint('   - Email: $email');
      debugPrint('   - Roles: $roles');

      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      List<String> mergedRoles;

      if (index != -1) {
        final existingRoles = List<String>.from(profiles[index]['roles'] ?? []);
        mergedRoles = {...existingRoles.toSet(), ...roles.toSet()}.toList();

        profiles[index]['roles'] = mergedRoles;
        profiles[index]['roles_updated_at'] = DateTime.now().toIso8601String();

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));

        debugPrint('📋 Merged roles: $mergedRoles');
      } else {
        mergedRoles = roles;
      }

      await _prefs.setStringList('$email$_keyUserRoles', mergedRoles);

      if (!_isUpdatingAvailableProfiles) {
        await _updateAvailableProfiles(email, mergedRoles);
      }

      debugPrint('✅ SessionManager: Saved all roles for $email: $mergedRoles');
    } catch (e) {
      debugPrint('❌ SessionManager: Error saving user roles: $e');
    } finally {
      _isSavingRoles = false;
    }
  }

  static Future<List<String>> getUserRoles(String email) async {
    try {
      final quickRoles = _prefs.getStringList('$email$_keyUserRoles');
      if (quickRoles != null) {
        return quickRoles;
      }

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

  static Future<void> saveCurrentRole(String? role) async {
    try {
      debugPrint('💾 ===== saveCurrentRole called =====');
      debugPrint('💾 Role to save: $role');

      final email = await getCurrentUserEmail();
      debugPrint('💾 Current user email: $email');

      if (role == null) {
        await _prefs.remove(_keyCurrentRole);
        debugPrint('✅ Cleared current role');
      } else {
        if (email != null) {
          final userRoles = await getUserRoles(email);
          debugPrint('💾 User roles from storage: $userRoles');

          if (!userRoles.contains(role)) {
            debugPrint('⚠️ Warning: User does not have role: $role');
            debugPrint('💾 Available roles: $userRoles');
          }
        }

        await _prefs.setString(_keyCurrentRole, role);
        debugPrint('✅ Saved current role to SharedPreferences: $role');

        final savedRole = _prefs.getString(_keyCurrentRole);
        debugPrint('✅ Verified saved role: $savedRole');

        if (email != null) {
          final profiles = await getAvailableProfiles();
          final updatedProfiles = profiles.map((p) {
            if (p['email'] == email && p['role'] == role) {
              return {...p, 'last_used': DateTime.now().toIso8601String()};
            }
            return p;
          }).toList();
          await saveAvailableProfiles(updatedProfiles);
          debugPrint('✅ Updated last_used for role: $role');
        }

        appState.refreshState(silent: true);
        debugPrint('✅ AppState refreshed');
      }

      debugPrint('💾 ===== saveCurrentRole completed =====');
    } catch (e) {
      debugPrint('❌ Error saving current role: $e');
    }
  }

  static Future<String?> getCurrentRole() async {
    try {
      final role = _prefs.getString(_keyCurrentRole);
      debugPrint('📖 Getting current role from SharedPreferences: $role');

      // ✅ FIX: SessionManager pref එකේ තියෙන stale email එකට වඩා
      // actual authenticated supabase user email එක use කරන්න
      final email =
          Supabase.instance.client.auth.currentUser?.email ??
          await getCurrentUserEmail();

      if (email != null && role != null) {
        final userRoles = await getUserRoles(email);
        if (!userRoles.contains(role)) {
          debugPrint(
            '⚠️ Stored role $role not in user roles $userRoles, clearing',
          );
          await _prefs.remove(_keyCurrentRole);
          return null;
        }
      }

      return role;
    } catch (e) {
      debugPrint('❌ Error getting current role: $e');
      return null;
    }
  }

  static Future<void> updateUserRole(String newRole) async {
    try {
      debugPrint('🔄 SessionManager.updateUserRole: $newRole');

      final email = await getCurrentUserEmail();
      if (email == null) {
        debugPrint('❌ No current user email found');
        return;
      }

      final roles = await getUserRoles(email);
      if (!roles.contains(newRole)) {
        debugPrint('❌ User does not have role: $newRole');
        return;
      }

      await saveCurrentRole(newRole);

      debugPrint('✅ Successfully updated user role to: $newRole');
    } catch (e) {
      debugPrint('❌ Error updating user role: $e');
    }
  }

  static Future<bool> hasMultipleRoles(String email) async {
    final roles = await getUserRoles(email);
    return roles.length > 1;
  }

  static Future<String?> getPrimaryRole(String email) async {
    try {
      final roles = await getUserRoles(email);
      if (roles.isEmpty) return null;

      final profiles = await getAvailableProfiles();
      final userProfiles = profiles.where((p) => p['email'] == email).toList();

      if (userProfiles.isNotEmpty) {
        userProfiles.sort((a, b) {
          final aTime = a['last_used'] as String?;
          final bTime = b['last_used'] as String?;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
        return userProfiles.first['role'] as String?;
      }

      return roles.first;
    } catch (e) {
      debugPrint('❌ Error getting primary role: $e');
      return null;
    }
  }

  static Future<void> clearUserRoles(String email) async {
    try {
      await _prefs.remove('$email$_keyUserRoles');

      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      if (index != -1) {
        profiles[index]['roles'] = [];
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      }

      final availableProfiles = await getAvailableProfiles();
      availableProfiles.removeWhere((p) => p['email'] == email);
      await saveAvailableProfiles(availableProfiles);

      if (email == await getCurrentUserEmail()) {
        await _prefs.remove(_keyCurrentRole);
      }

      debugPrint('✅ Cleared roles for $email');
    } catch (e) {
      debugPrint('❌ Error clearing user roles: $e');
    }
  }

  // =====================================================
  // ✅ AVAILABLE PROFILES FUNCTIONS
  // =====================================================

  static Future<void> saveAvailableProfiles(
    List<Map<String, dynamic>> profiles,
  ) async {
    try {
      await _prefs.setString(_keyAvailableProfiles, jsonEncode(profiles));
      debugPrint('✅ Saved ${profiles.length} available profiles');
    } catch (e) {
      debugPrint('❌ Error saving available profiles: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getAvailableProfiles() async {
    try {
      final jsonString = _prefs.getString(_keyAvailableProfiles);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint('❌ Error getting available profiles: $e');
      return [];
    }
  }

  static Future<void> _updateAvailableProfiles(
    String email,
    List<String> roles,
  ) async {
    if (_isUpdatingAvailableProfiles) {
      debugPrint('⏭️ Already updating available profiles, skipping');
      return;
    }

    _isUpdatingAvailableProfiles = true;

    try {
      final currentUserId = await getCurrentUserId();
      if (currentUserId == null) return;

      final existingProfiles = await getAvailableProfiles();
      final currentRole = await getCurrentRole();

      for (String role in roles) {
        final profileData = {
          'id': currentUserId,
          'email': email,
          'role': role,
          'role_id': _getRoleIdFromName(role),
          'is_active': true,
          'last_used': role == currentRole
              ? DateTime.now().toIso8601String()
              : null,
        };

        final index = existingProfiles.indexWhere(
          (p) => p['role'] == role && p['email'] == email,
        );

        if (index == -1) {
          existingProfiles.add(profileData);
        } else {
          existingProfiles[index] = {
            ...existingProfiles[index],
            ...profileData,
          };
        }
      }

      await saveAvailableProfiles(existingProfiles);
    } catch (e) {
      debugPrint('❌ Error updating available profiles: $e');
    } finally {
      _isUpdatingAvailableProfiles = false;
    }
  }

  static int _getRoleIdFromName(String role) {
    switch (role) {
      case 'owner':
        return 1;
      case 'barber':
        return 2;
      case 'customer':
        return 3;
      default:
        return 3;
    }
  }

  // =====================================================
  // ✅ SESSION MANAGEMENT FUNCTIONS
  // =====================================================

  static Future<void> setCurrentUser(String email) async {
    await _prefs.setString(_currentUserKey, email);
  }

  static Future<String?> getCurrentUserEmail() async {
    return _prefs.getString(_currentUserKey);
  }

  static Future<String?> getCurrentUserId() async {
    try {
      final email = await getCurrentUserEmail();
      if (email == null) return null;

      final profile = await getProfileByEmail(email);
      return profile?['userId'] as String?;
    } catch (e) {
      debugPrint('❌ Error getting current user ID: $e');
      return null;
    }
  }

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
          profiles[index]['roles'] = roles;
          await _prefs.setString(_keyProfiles, jsonEncode(profiles));
          await saveUserRoles(email: email, roles: roles);
          debugPrint('✅ Role saved: $role for $email');
        }
      }
    } catch (e) {
      debugPrint('❌ Error saving role: $e');
    }
  }

  static Future<String?> getUserRole() async {
    return getCurrentRole();
  }

  static Future<bool> hasProfile() async {
    final profiles = await getProfiles();
    debugPrint('📋 Checking profiles, count: ${profiles.length}');
    return profiles.isNotEmpty;
  }

  static Future<void> updateLastLogin(String email) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        final now = DateTime.now().toIso8601String();
        profiles[index]['lastLogin'] = now;
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('✅ Last login updated for: $email -> $now');
      } else {
        debugPrint('⚠️ Profile not found for lastLogin update: $email');
      }
    } catch (e) {
      debugPrint('❌ Error updating last login: $e');
    }
  }

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
          await _prefs.remove(_keyCurrentRole);
        }

        final profile = await getProfileByEmail(email);
        final userId = profile?['userId'] as String?;
        if (userId != null) {
          await _secureStorage.delete(key: '${userId}_refresh_token');
          await _secureStorage.delete(key: '${userId}_access_token');
        }

        await clearUserRoles(email);

        debugPrint('✅ Profile and secure data removed: $email');
      }
    } catch (e) {
      debugPrint('❌ Error removing profile: $e');
    }
  }

  // =====================================================
  // ✅ GET MOST RECENT PROFILE
  // =====================================================

  static Future<Map<String, dynamic>?> getMostRecentProfile() async {
    try {
      final profiles = await getProfiles();
      if (profiles.isEmpty) {
        debugPrint('📋 No profiles found for most recent');
        return null;
      }

      profiles.sort((a, b) {
        final aTime = DateTime.tryParse(a['lastLogin'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['lastLogin'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      final mostRecent = profiles.first;
      debugPrint(
        '✅ Most recent profile: ${mostRecent['email']} (${mostRecent['roles']})',
      );
      return mostRecent;
    } catch (e) {
      debugPrint('❌ Error getting most recent profile: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getMostRecentUser() async {
    return getMostRecentProfile();
  }

  static Future<Map<String, dynamic>?> getLastUser() async {
    try {
      final profiles = await getProfiles();
      if (profiles.isEmpty) return null;
      return profiles.last;
    } catch (e) {
      debugPrint('❌ Error getting last user: $e');
      return null;
    }
  }

  // =====================================================
  // ✅ REMEMBER ME & CONTINUE SCREEN
  // =====================================================

  static Future<void> setRememberMe(bool enabled) async {
    await _prefs.setBool(_rememberMeKey, enabled);
    debugPrint('✅ Remember Me set to: $enabled');
  }

  static Future<bool> isRememberMeEnabled() async {
    return _prefs.getBool(_rememberMeKey) ?? false;
  }

  static Future<void> setLocationContinuesc(bool enabled) async {
    await _prefs.setBool(_locationcontinuesc, enabled);
    debugPrint('✅ location continue sc set to: $enabled');
  }

  static Future<bool> isLocationContinuesc() async {
    return _prefs.getBool(_locationcontinuesc) ?? false;
  }

  static Future<bool> shouldShowContinueScreen() async {
    final show = _prefs.getBool(_showContinueKey) ?? false;
    final rememberMe = await isRememberMeEnabled();
    return show && rememberMe;
  }

  static Future<void> clearContinueScreen() async {
    await _prefs.setBool(_showContinueKey, false);
    debugPrint('✅ Continue screen flag cleared');
  }

  // =====================================================
  // ✅ AUTO-LOGIN & SESSION MANAGEMENT
  // =====================================================

  static Future<bool> tryAutoLogin(String email) async {
    try {
      debugPrint('===== ATTEMPTING AUTO-LOGIN =====');
      debugPrint('Target email: $email');

      final profile = await getProfileByEmail(email);
      if (profile == null || profile.isEmpty) {
        debugPrint('❌ Auto-login failed: No profile found');
        return false;
      }

      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;

      if (currentUser?.email == email && currentSession != null) {
        if (isSessionValid(currentSession)) {
          debugPrint('✅ AUTO-LOGIN SUCCESS: Already logged in');

          await updateLastLogin(email);

          final roles = await getUserRoles(email);
          if (roles.isNotEmpty && await getCurrentRole() == null) {
            final primaryRole = await getPrimaryRole(email);
            if (primaryRole != null) {
              await saveCurrentRole(primaryRole);
            }
          }

          return true;
        } else {
          debugPrint('⏰ Session expired, attempting refresh...');
        }
      }

      final userId = profile['userId'] as String?;
      if (userId == null) {
        debugPrint('❌ Auto-login failed: No user ID found');
        return false;
      }

      final refreshToken = await _secureStorage.read(
        key: '${userId}_refresh_token',
      );

      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('❌ Auto-login failed: No secure refresh token found');
        return false;
      }

      try {
        debugPrint('🔄 Attempting to restore session with secure token...');

        final response = await supabase.auth.refreshSession();

        if (response.session != null && response.user?.email == email) {
          debugPrint('✅ AUTO-LOGIN SUCCESS: Session refreshed');

          await updateLastLogin(email);
          await _updateSecureTokens(userId, response.session!);

          final roles = await getUserRoles(email);
          if (roles.isNotEmpty && await getCurrentRole() == null) {
            final primaryRole = await getPrimaryRole(email);
            if (primaryRole != null) {
              await saveCurrentRole(primaryRole);
            }
          }

          return true;
        }

        debugPrint('🔄 Refresh failed, attempting setSession...');
        await supabase.auth.setSession(refreshToken);
        await Future.delayed(const Duration(milliseconds: 500));

        final restoredUser = supabase.auth.currentUser;
        final restoredSession = supabase.auth.currentSession;

        if (restoredUser?.email == email && restoredSession != null) {
          debugPrint('✅ AUTO-LOGIN SUCCESS: Session restored securely');

          await updateLastLogin(email);
          await _updateSecureTokens(userId, restoredSession);

          final roles = await getUserRoles(email);
          if (roles.isNotEmpty && await getCurrentRole() == null) {
            final primaryRole = await getPrimaryRole(email);
            if (primaryRole != null) {
              await saveCurrentRole(primaryRole);
            }
          }

          return true;
        }
      } catch (e) {
        debugPrint('❌ Secure session restoration failed: $e');
        await _cleanupInvalidSession(userId, email);
      }

      debugPrint('❌ AUTO-LOGIN FAILED: Could not restore session');
      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ AUTO-LOGIN ERROR: $e');
      debugPrint('Stack: $stackTrace');
      return false;
    }
  }

  // =====================================================
  // ✅ NEW: SESSION + DB CHECK METHODS
  // =====================================================

  /// ✅ Check if user can login (Session + DB Combined)
  static Future<Map<String, dynamic>> checkLoginStatus(String email) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final session = supabase.auth.currentSession;

      // ✅ 1. Check local session
      bool hasValidSession = false;
      if (user != null && session != null && user.email == email) {
        if (session.expiresAt != null) {
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt!,
          );
          hasValidSession = DateTime.now().isBefore(expiryTime);
        } else {
          hasValidSession = true;
        }
      }

      debugPrint('📊 Session check: hasValidSession=$hasValidSession');

      // ✅ 2. Check database for user status
      bool isActive = false;
      bool isBlocked = false;
      bool isScheduledForDeletion = false;
      bool isInactive = false;
      bool profileExists = false;
      String statusMessage = '';
      String statusType = 'active';

      // Check profile
      if (user != null) {
        final profileCheck = await supabase
            .from('profiles')
            .select('is_blocked, is_active, extra_data')
            .eq('id', user.id)
            .maybeSingle();

        if (profileCheck != null) {
          profileExists = true;
          isActive = profileCheck['is_active'] ?? false;
          isBlocked = profileCheck['is_blocked'] ?? false;

          // Check extra_data for status
          final extraData =
              profileCheck['extra_data'] as Map<String, dynamic>? ?? {};

          // Check profile level status
          final profileStatus =
              extraData['profile_status'] as Map<String, dynamic>?;
          if (profileStatus != null) {
            final status = profileStatus['status'] as String?;
            if (status == 'scheduled_for_deletion') {
              isScheduledForDeletion = true;
            } else if (status == 'inactive') {
              isInactive = true;
            }
          }

          // If no profile level status, check role level
          if (!isScheduledForDeletion && !isInactive) {
            final rolesResponse = await supabase
                .from('user_roles')
                .select('status')
                .eq('user_id', user.id);

            for (var roleEntry in rolesResponse) {
              final status = roleEntry['status'] as String? ?? 'active';
              if (status == 'scheduled_for_deletion') {
                isScheduledForDeletion = true;
              }
              if (status == 'inactive') {
                isInactive = true;
              }
            }
          }
        }
      }

      // ✅ 3. Determine login status
      bool canLogin = false;

      // ❌ Blocked - Never allow login
      if (isBlocked) {
        canLogin = false;
        statusMessage =
            'Your account has been blocked. Please contact support.';
        statusType = 'blocked';
      }
      // ❌ Inactive (deactivated) - Not scheduled for deletion
      else if (isInactive && !isScheduledForDeletion) {
        canLogin = false;
        statusMessage = 'Your profile is deactivated. Please contact support.';
        statusType = 'inactive';
      }
      // ✅ Scheduled for deletion - Allow login with auto-restore
      else if (isScheduledForDeletion) {
        canLogin = true;
        statusMessage =
            'Your profile is scheduled for deletion. Login to restore it.';
        statusType = 'scheduled';
      }
      // ✅ Active - Allow login
      else if (isActive || !profileExists) {
        canLogin = true;
        statusMessage = profileExists
            ? 'Profile is active.'
            : 'No profile found. Please complete registration.';
        statusType = profileExists ? 'active' : 'no_profile';
      }

      // ✅ 4. Check if session exists but DB says inactive
      bool needsLogout = false;
      if (hasValidSession && !canLogin && !isScheduledForDeletion) {
        needsLogout = true;
        debugPrint('⚠️ Session exists but user is inactive - force logout');
      }

      return {
        'canLogin': canLogin,
        'hasValidSession': hasValidSession,
        'status': statusType,
        'message': statusMessage,
        'isActive': isActive,
        'isBlocked': isBlocked,
        'isInactive': isInactive,
        'isScheduledForDeletion': isScheduledForDeletion,
        'needsAutoRestore': isScheduledForDeletion,
        'needsLogout': needsLogout,
        'profileExists': profileExists,
      };
    } catch (e) {
      debugPrint('❌ Error checking login status: $e');
      return {
        'canLogin': false,
        'hasValidSession': false,
        'status': 'error',
        'message': 'Error checking login status: $e',
        'needsLogout': false,
        'needsAutoRestore': false,
      };
    }
  }

  /// ✅ Check if user has valid session (local only)
  static Future<bool> hasValidSession() async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (session == null || user == null) {
        debugPrint('❌ No active session found');
        return false;
      }

      if (session.expiresAt != null) {
        final expiryTime = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt!,
        );
        final now = DateTime.now();

        if (now.isAfter(expiryTime)) {
          debugPrint('❌ Session expired at: $expiryTime');
          return false;
        }
      }

      debugPrint('✅ Valid session found for user: ${user.email}');
      return true;
    } catch (e) {
      debugPrint('❌ Error checking session: $e');
      return false;
    }
  }

  /// ✅ Check if user is logged in (Session + DB)
  static Future<bool> isUserLoggedIn(String email) async {
    try {
      final status = await checkLoginStatus(email);
      return status['canLogin'] == true && status['hasValidSession'] == true;
    } catch (e) {
      debugPrint('❌ Error checking user login status: $e');
      return false;
    }
  }

  /// ✅ Check if user has been logged out
  static Future<bool> isUserLoggedOut(String email) async {
    try {
      final status = await checkLoginStatus(email);
      return status['hasValidSession'] == false ||
          status['needsLogout'] == true;
    } catch (e) {
      debugPrint('❌ Error checking logout status: $e');
      return true;
    }
  }

  /// ✅ Get session status with details
  static Future<Map<String, dynamic>> getSessionStatus(String email) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final session = supabase.auth.currentSession;

      final result = <String, dynamic>{
        'email': email,
        'has_user': user != null,
        'has_session': session != null,
        'is_logged_in': false,
        'session_expired': false,
        'user_matches': false,
        'db_status': {},
      };

      if (user != null) {
        result['user_matches'] = user.email == email;

        // Check DB
        try {
          final response = await supabase.rpc(
            'check_user_active_sessions',
            params: {'p_user_id': user.id},
          );
          if (response != null) {
            result['db_status'] = response;
          }
        } catch (e) {
          debugPrint('❌ DB session check failed: $e');
        }

        // Check session
        if (session != null) {
          result['is_logged_in'] = true;
          result['session_expires_at'] = session.expiresAt;

          if (session.expiresAt != null) {
            final expiryTime = DateTime.fromMillisecondsSinceEpoch(
              session.expiresAt!,
            );
            result['session_expired'] = DateTime.now().isAfter(expiryTime);
            result['seconds_until_expiry'] = expiryTime
                .difference(DateTime.now())
                .inSeconds;
          }
        }

        // Combine with DB status
        if (result['db_status']['is_logged_in'] == false &&
            result['is_logged_in'] == true) {
          result['is_logged_in'] = false;
          result['stale_session'] = true;
        }

        result['is_logged_in'] =
            result['is_logged_in'] &&
            result['user_matches'] &&
            !result['session_expired'];
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error getting session status: $e');
      return {'email': email, 'is_logged_in': false, 'error': e.toString()};
    }
  }

  // =====================================================
  // ✅ AUTO-RESTORE FUNCTIONS
  // =====================================================

  /// ✅ Auto-restore profile on login (Facebook style)
  static Future<void> autoRestoreProfileOnLogin({
    required String email,
    required String role,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return;
      }

      debugPrint('🔄 Auto-restoring role: $role for $email');

      // ✅ Try-catch for RPC call
      dynamic response;
      try {
        response = await supabase.rpc(
          'auto_restore_role_on_login',
          params: {'p_user_id': user.id, 'p_role': role},
        );
      } catch (rpcError) {
        debugPrint(
          '⚠️ RPC function "auto_restore_role_on_login" not found: $rpcError',
        );
        // RPC function not found - skip
        return;
      }

      if (response == null) {
        debugPrint('⚠️ No response from RPC');
        return;
      }

      final success = response['success'] as bool? ?? false;

      if (success) {
        debugPrint('✅ Role auto-restored: $role');

        // ✅ Update local available profiles
        try {
          final availableProfiles = await getAvailableProfiles();
          final exists = availableProfiles.any(
            (p) => p['email'] == email && p['role'] == role,
          );

          if (!exists) {
            availableProfiles.add({
              'id': user.id,
              'email': email,
              'role': role,
              'status': 'active',
              'is_active': true,
              'last_used': DateTime.now().toIso8601String(),
              'restored_at': DateTime.now().toIso8601String(),
            });
            await saveAvailableProfiles(availableProfiles);
          }
        } catch (e) {
          debugPrint('⚠️ Failed to update available profiles: $e');
        }

        // ✅ Remove schedule
        try {
          await _prefs.remove('del_${email}_$role');
        } catch (e) {
          debugPrint('⚠️ Failed to remove schedule: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error in autoRestoreProfileOnLogin: $e');
    }
  }

  /// ✅ Auto-restore entire profile on login
  static Future<void> autoRestoreProfileLevelOnLogin({
    required String email,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return;
      }

      debugPrint('🔄 Checking auto-restore for entire profile: $email');

      // ✅ Try-catch for RPC call
      dynamic response;
      try {
        response = await supabase.rpc(
          'auto_restore_profile_level_on_login',
          params: {'p_user_id': user.id},
        );
      } catch (rpcError) {
        debugPrint(
          '⚠️ RPC function "auto_restore_profile_level_on_login" not found: $rpcError',
        );
        // RPC function not found - skip
        return;
      }

      if (response == null) {
        debugPrint('⚠️ No response from RPC');
        return;
      }

      final success = response['success'] as bool? ?? false;

      if (success &&
          response['message']?.toString().contains('restored') == true) {
        debugPrint('✅ Entire profile auto-restored');

        // ✅ Update local status
        try {
          await _updateLocalProfileLevelStatus(email: email, status: 'active');
        } catch (e) {
          debugPrint('⚠️ _updateLocalProfileLevelStatus error: $e');
        }

        // ✅ Remove schedule
        try {
          await _prefs.remove('del_profile_$email');
        } catch (e) {
          debugPrint('⚠️ Failed to remove schedule: $e');
        }

        // ✅ Refresh app state
        appState.refreshState();
      }
    } catch (e) {
      debugPrint('❌ Error auto-restoring profile level: $e');
    }
  }

  /// ✅ Update local profile status
  static Future<void> _updateLocalProfileStatus({
    required String email,
    required String role,
    required String status,
  }) async {
    try {
      final availableProfiles = await getAvailableProfiles();
      final updatedProfiles = availableProfiles.map((p) {
        if (p['email'] == email && p['role'] == role) {
          return {
            ...p,
            'status': status,
            'is_active': status == 'active',
            'is_scheduled_for_deletion': status == 'scheduled_for_deletion',
            'status_updated_at': DateTime.now().toIso8601String(),
          };
        }
        return p;
      }).toList();

      final filteredProfiles = updatedProfiles.where((p) {
        final status = p['status'] as String? ?? 'active';
        return status == 'active';
      }).toList();

      await saveAvailableProfiles(filteredProfiles);
      debugPrint('✅ Local profile status updated: $role -> $status');

      if (status == 'deleted') {
        final rolesKey = '$email$_keyUserRoles';
        final cachedRoles = _prefs.getStringList(rolesKey) ?? [];
        final updatedRoles = cachedRoles.where((r) => r != role).toList();
        await _prefs.setStringList(rolesKey, updatedRoles);
      }
    } catch (e) {
      debugPrint('❌ Error updating local profile status: $e');
    }
  }

  /// ✅ Update local profile level status
  static Future<void> _updateLocalProfileLevelStatus({
    required String email,
    required String status,
  }) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        final profile = profiles[index];
        final extraData = profile['extra_data'] as Map<String, dynamic>? ?? {};

        if (!extraData.containsKey('profile_status')) {
          extraData['profile_status'] = {};
        }

        final profileStatus =
            extraData['profile_status'] as Map<String, dynamic>;
        profileStatus['status'] = status;
        profileStatus['updated_at'] = DateTime.now().toIso8601String();

        if (status == 'active') {
          profileStatus.remove('deletion_due_date');
          profileStatus.remove('deletion_scheduled_at');
          profileStatus.remove('grace_period_days');
          profileStatus['reactivated_at'] = DateTime.now().toIso8601String();
        }

        profile['extra_data'] = extraData;
        profiles[index] = profile;

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('✅ Local profile level status updated: $status');
      }
    } catch (e) {
      debugPrint('❌ Error updating local profile level status: $e');
    }
  }

  /// ✅ Schedule entire profile for deletion
  static Future<void> scheduleProfileLevelDeletion({
    required String email,
    int gracePeriodDays = 90,
  }) async {
    final deletionDate = DateTime.now().add(Duration(days: gracePeriodDays));
    await _prefs.setString(
      'del_profile_$email',
      deletionDate.toIso8601String(),
    );
    debugPrint(
      '🗑️ Entire profile scheduled for deletion: $email, due: $deletionDate',
    );
  }

  /// ✅ Cancel profile level deletion
  static Future<void> cancelProfileLevelDeletion({
    required String email,
  }) async {
    await _prefs.remove('del_profile_$email');
    debugPrint('✅ Profile deletion canceled: $email');
  }

  // =====================================================
  // ✅ LOGOUT FUNCTIONS
  // =====================================================

  static Future<void> logoutForContinue() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final email = await getCurrentUserEmail();
      final rememberMe = await isRememberMeEnabled();

      if (user != null && email != null && email == user.email) {
        final currentSession = supabase.auth.currentSession;
        final refreshToken = currentSession?.refreshToken;

        if (rememberMe && refreshToken != null) {
          await saveUserProfile(
            email: email,
            userId: user.id,
            name: user.userMetadata?['full_name'] ?? email.split('@').first,
            rememberMe: rememberMe,
            refreshToken: refreshToken,
            provider: await _getUserProvider(email),
          );
          debugPrint('✅ Refresh token saved before continue logout');
        }
      }

      await supabase.auth.signOut();

      await _prefs.remove(_keyCurrentRole);
      debugPrint('✅ Cleared current role on logout');

      if (email != null && rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        debugPrint(
          '✅ User prepared for continue screen (Remember Me: $rememberMe)',
        );
      } else {
        await _prefs.remove(_currentUserKey);
        await clearContinueScreen();
        debugPrint('✅ User cleared for continue screen');
      }
    } catch (e) {
      debugPrint('❌ Error during continue logout: $e');
    }
  }

  static Future<void> logoutUser() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        // Update last_logout in database
        await supabase
            .from('profiles')
            .update({
              'last_logout': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);

        debugPrint('✅ Updated last_logout for user: ${user.email}');
      }

      await supabase.auth.signOut();

      final email = await getCurrentUserEmail();
      if (email != null) {
        await _prefs.remove(_keyCurrentRole);
        await clearContinueScreen();
      }

      debugPrint('✅ User logged out successfully');
    } catch (e) {
      debugPrint('❌ Error during logout: $e');
      rethrow;
    }
  }

  // =====================================================
  // ✅ CLEAR ALL
  // =====================================================

  static Future<void> clearAll() async {
    try {
      debugPrint('🧹 SessionManager.clearAll() started');

      await _prefs.remove(_keyProfiles);
      await _prefs.remove(_currentUserKey);
      await _prefs.remove(_showContinueKey);
      await _prefs.remove(_rememberMeKey);
      await _prefs.remove(_keyAvailableProfiles);
      await _prefs.remove(_keyCurrentRole);

      final keys = _prefs.getKeys();
      for (var key in keys) {
        if (key.contains(_keyUserRoles) || key.contains(_keyCurrentRole)) {
          await _prefs.remove(key);
        }
      }

      await _secureStorage.deleteAll();

      debugPrint('✅ All session data cleared');
    } catch (e) {
      debugPrint('❌ Error clearing all data: $e');
    }
  }

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
          debugPrint('Session expiring soon, attempting refresh...');
          try {
            await supabase.auth.getUser();
            debugPrint('✅ Session refresh triggered');
          } catch (e) {
            debugPrint('❌ Session refresh failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error validating session: $e');
    }
  }

  // =====================================================
  // ✅ DEBUG FUNCTIONS
  // =====================================================

  static Future<void> debugPrintLocalProfiles() async {
    try {
      final profiles = await getProfiles();
      debugPrint('📋 ===== LOCAL PROFILES DEBUG =====');
      debugPrint('Total profiles: ${profiles.length}');

      for (var i = 0; i < profiles.length; i++) {
        final profile = profiles[i];
        debugPrint('Profile $i:');
        debugPrint('  - Email: ${profile['email']}');
        debugPrint('  - Roles: ${profile['roles']}');
        debugPrint('  - Name: ${profile['name']}');
        debugPrint('  - Provider: ${profile['provider']}');
        debugPrint('  - LastLogin: ${profile['lastLogin']}');
      }
      debugPrint('📋 ================================');
    } catch (e) {
      debugPrint('❌ Error debugging profiles: $e');
    }
  }

  // =====================================================
  // ✅ PRIVATE HELPER METHODS
  // =====================================================

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

      debugPrint('✅ Secure tokens updated');
    } catch (e) {
      debugPrint('❌ Error updating secure tokens: $e');
    }
  }

  static Future<void> _cleanupInvalidSession(
    String userId,
    String email,
  ) async {
    try {
      debugPrint('🧹 Cleaning up invalid session for: $email');

      await _secureStorage.delete(key: '${userId}_refresh_token');
      await _secureStorage.delete(key: '${userId}_access_token');

      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['tokenSavedAt'] = '';
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
      }

      debugPrint('✅ Invalid session cleaned up');
    } catch (e) {
      debugPrint('❌ Error cleaning up session: $e');
    }
  }

  static Future<String?> _getUserProvider(String email) async {
    final profile = await getProfileByEmail(email);
    return profile?['provider'] as String?;
  }

  static AndroidOptions _getAndroidOptions() => const AndroidOptions();

  static IOSOptions _getIOSOptions() => const IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    synchronizable: true,
  );

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
      debugPrint('❌ Error checking session validity: $e');
      return false;
    }
  }

  static Future<bool> restoreSessionFromStorage(String email) async {
    return tryAutoLogin(email);
  }

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

        final profiles = await getProfiles();
        final index = profiles.indexWhere((p) => p['email'] == email);

        if (index != -1) {
          profiles[index]['tokenSavedAt'] = DateTime.now().toIso8601String();
          await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        }

        debugPrint('✅ Refresh token saved securely for: $email');
      }
    } catch (e) {
      debugPrint('❌ Error saving refresh token: $e');
    }
  }

  static Future<String?> getRefreshToken(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      final userId = profile?['userId'] as String?;

      if (userId != null) {
        return await _secureStorage.read(key: '${userId}_refresh_token');
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting refresh token: $e');
      return null;
    }
  }

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
      debugPrint('❌ Error getting active session count: $e');
      return 0;
    }
  }

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
              debugPrint('✅ Cleaned up expired session for: $email');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error cleaning up expired sessions: $e');
    }
  }

  // =====================================================
  // ✅ GDPR FUNCTIONS
  // =====================================================

  static Future<Map<String, dynamic>> exportUserData(String email) async {
    try {
      final profile = await getProfileByEmail(email);
      if (profile == null) throw Exception('User not found');

      final exportData = Map<String, dynamic>.from(profile);
      exportData.remove('refreshToken');
      exportData.remove('tokenSavedAt');
      exportData['exportedAt'] = DateTime.now().toIso8601String();
      exportData['exportFormat'] = 'JSON';

      return exportData;
    } catch (e) {
      debugPrint('❌ Error exporting user data: $e');
      rethrow;
    }
  }

  /// ✅ FIXED: Now actually triggers the server-side deletion
  /// schedule (via updateProfileLevelStatus, same RPC path used
  /// by DeleteAccountScreen) instead of only flipping a local
  /// flag.
  ///
  /// Previously this function set 'dataDeletionRequested' = true
  /// locally but never told the database anything - the account
  /// stayed fully active on the server despite the app claiming
  /// deletion was "requested". That mismatch is a GDPR / App
  /// Store compliance gap; this fix closes it.
  static Future<bool> requestDataDeletion(String email) async {
    try {
      debugPrint('📝 Requesting data deletion for: $email');

      // ✅ Actually schedule deletion on the server (90-day grace
      // period, same as the in-app "Delete Account" flow).
      final success = await updateProfileLevelStatus(
        email: email,
        status: 'scheduled_for_deletion',
        gracePeriodDays: 90,
      );

      if (!success) {
        debugPrint('❌ Server-side deletion scheduling failed for: $email');
        return false;
      }

      // ✅ Also record the request locally for reference/audit
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['dataDeletionRequested'] = true;
        profiles[index]['deletionRequestedAt'] = DateTime.now()
            .toIso8601String();

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));

        final userId = profiles[index]['userId'] as String?;
        if (userId != null) {
          await _secureStorage.delete(key: '${userId}_refresh_token');
          await _secureStorage.delete(key: '${userId}_access_token');
        }
      }

      debugPrint('✅ Data deletion requested and scheduled for: $email');
      return true;
    } catch (e) {
      debugPrint('❌ Error requesting data deletion: $e');
      return false;
    }
  }

  static Future<bool> checkSecureStorageHealth() async {
    try {
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
      debugPrint('❌ Secure storage health check failed: $e');
      return false;
    }
  }

  // =====================================================
  // ✅ PROFILE STATUS SYNC METHODS - ADD TO SESSIONMANAGER
  // =====================================================

  /// ✅ Sync profile status with database
  static Future<void> syncProfileStatusWithDB({
    required String email,
    required String role,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in, cannot sync');
        return;
      }

      debugPrint('🔄 Syncing profile status with DB: $email - $role');

      // ✅ Get status from database using RPC function
      final response = await supabase.rpc(
        'get_role_status',
        params: {'p_user_id': user.id, 'p_role': role},
      );

      if (response != null) {
        final status = response['status'] as String? ?? 'active';
        final daysRemaining = response['days_remaining'] as int?;

        // ✅ Update local available profiles
        final availableProfiles = await getAvailableProfiles();
        final updatedProfiles = availableProfiles.map((p) {
          if (p['email'] == email && p['role'] == role) {
            return {
              ...p,
              'status': status,
              'is_active': status == 'active',
              'is_scheduled_for_deletion': status == 'scheduled_for_deletion',
              'days_remaining': daysRemaining,
              'db_synced_at': DateTime.now().toIso8601String(),
            };
          }
          return p;
        }).toList();

        await saveAvailableProfiles(updatedProfiles);
        debugPrint('✅ Profile status synced: $status');
      }
    } catch (e) {
      debugPrint('❌ Error syncing profile status: $e');
    }
  }

  /// ✅ Update profile status in database
  static Future<bool> updateProfileStatusInDB({
    required String email,
    required String role,
    required String
    status, // 'active', 'inactive', 'scheduled_for_deletion', 'deleted'
    int gracePeriodDays = 90,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return false;
      }

      debugPrint('📝 Updating profile status in DB: $role -> $status');

      // ✅ Call database function
      final response = await supabase.rpc(
        'update_role_status',
        params: {
          'p_user_id': user.id,
          'p_role': role,
          'p_status': status,
          'p_grace_period_days': gracePeriodDays,
        },
      );

      final success = response['success'] as bool? ?? false;

      if (success) {
        debugPrint('✅ Profile status updated in DB: $status');

        // ✅ Update local SessionManager
        await _updateLocalProfileStatus(
          email: email,
          role: role,
          status: status,
        );

        return true;
      } else {
        debugPrint('❌ Failed to update status: ${response['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error updating profile status in DB: $e');
      return false;
    }
  }

  /// ✅ Deactivate profile
  static Future<void> deactivateProfile({
    required String email,
    required String role,
  }) async {
    await updateProfileStatusInDB(email: email, role: role, status: 'inactive');
  }

  /// ✅ Reactivate profile
  static Future<void> reactivateProfile({
    required String email,
    required String role,
  }) async {
    await updateProfileStatusInDB(email: email, role: role, status: 'active');
  }

  /// ✅ Schedule profile deletion
  static Future<void> scheduleProfileDeletion({
    required String email,
    required String role,
    int gracePeriodDays = 90,
  }) async {
    final success = await updateProfileStatusInDB(
      email: email,
      role: role,
      status: 'scheduled_for_deletion',
      gracePeriodDays: gracePeriodDays,
    );

    if (success) {
      // Save schedule for background processing
      final deletionDate = DateTime.now().add(Duration(days: gracePeriodDays));
      await _prefs.setString(
        'del_${email}_$role',
        deletionDate.toIso8601String(),
      );
      debugPrint(
        '🗑️ Profile deletion scheduled: $email - $role, due: $deletionDate',
      );
    }
  }

  /// ✅ Cancel scheduled deletion
  static Future<void> cancelScheduledDeletion({
    required String email,
    required String role,
  }) async {
    final success = await updateProfileStatusInDB(
      email: email,
      role: role,
      status: 'active',
    );

    if (success) {
      await _prefs.remove('del_${email}_$role');
      debugPrint('✅ Deletion canceled, profile reactivated: $email - $role');
    }
  }

  // ============================================================
  // ✅ ADD THIS METHOD TO SESSIONMANAGER
  // ============================================================

  /// ✅ Update role status in database
  static Future<bool> updateRoleStatus({
    required String email,
    required String role,
    required String
    status, // 'active', 'inactive', 'scheduled_for_deletion', 'deleted'
    int gracePeriodDays = 90,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return false;
      }

      debugPrint('📝 Updating role status: $role -> $status');

      // ✅ Call database function
      final response = await supabase.rpc(
        'update_role_status',
        params: {
          'p_user_id': user.id,
          'p_role': role,
          'p_status': status,
          'p_grace_period_days': gracePeriodDays,
        },
      );

      final success = response['success'] as bool? ?? false;

      if (success) {
        debugPrint('✅ Role status updated: $status');

        // ✅ Update local SessionManager
        await _updateLocalProfileStatus(
          email: email,
          role: role,
          status: status,
        );

        return true;
      } else {
        debugPrint('❌ Failed to update status: ${response['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error updating role status: $e');
      return false;
    }
  }

  // =====================================================
  // ✅ PROFILE LEVEL STATUS METHODS - ADD TO SESSIONMANAGER
  // =====================================================

  /// ✅ Update profile level status (entire profile)
  static Future<bool> updateProfileLevelStatus({
    required String email,
    required String
    status, // 'active', 'inactive', 'scheduled_for_deletion', 'deleted'
    int gracePeriodDays = 90,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return false;
      }

      debugPrint('📝 Updating profile level status: $status');

      // ✅ Call database function
      final response = await supabase.rpc(
        'update_profile_level_status',
        params: {
          'p_user_id': user.id,
          'p_status': status,
          'p_grace_period_days': gracePeriodDays,
        },
      );

      final success = response['success'] as bool? ?? false;

      if (success) {
        debugPrint('✅ Profile level status updated: $status');

        // ✅ Update local SessionManager
        await _updateLocalProfileLevelStatus(email: email, status: status);

        return true;
      } else {
        debugPrint('❌ Failed to update profile status: ${response['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error updating profile level status: $e');
      return false;
    }
  }

  /// ✅ Delete complete profile (all roles + profile data)
  static Future<bool> deleteCompleteProfile({
    required String email,
    required String userId,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      debugPrint('🗑️ Deleting complete profile: $email (userId: $userId)');

      // ✅ 1. Call database function
      final response = await supabase.rpc(
        'delete_complete_profile',
        params: {'p_user_id': userId},
      );

      final success = response['success'] as bool? ?? false;

      if (!success) {
        debugPrint('❌ DB delete failed: ${response['message']}');
        return false;
      }

      debugPrint('✅ Database profile deleted successfully');

      // ✅ 2. Remove from SessionManager local storage
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      if (index != -1) {
        profiles.removeAt(index);
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        debugPrint('✅ Profile removed from local storage');
      }

      // ✅ 3. Remove from available profiles
      final availableProfiles = await getAvailableProfiles();
      final updatedAvailable = availableProfiles
          .where((p) => p['email'] != email)
          .toList();
      await saveAvailableProfiles(updatedAvailable);
      debugPrint('✅ Profile removed from available profiles');

      // ✅ 4. Clear user roles
      await _prefs.remove('$email$_keyUserRoles');

      // ✅ 5. Clear current role if this was the current user
      final currentEmail = await getCurrentUserEmail();
      if (currentEmail == email) {
        await _prefs.remove(_currentUserKey);
        await _prefs.remove(_keyCurrentRole);
        await _prefs.setBool(_showContinueKey, false);
        debugPrint('✅ Cleared current user data');
      }

      // ✅ 6. Delete secure tokens
      await _secureStorage.delete(key: '${userId}_refresh_token');
      await _secureStorage.delete(key: '${userId}_access_token');
      debugPrint('✅ Secure tokens deleted');

      // ✅ 7. Refresh app state
      appState.refreshState();

      debugPrint('✅ Complete profile deletion successful');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting complete profile: $e');
      return false;
    }
  }

  /// ✅ Get remaining profiles after deletion
  static Future<List<Map<String, dynamic>>> getRemainingProfiles(
    String email,
  ) async {
    try {
      final profiles = await getProfiles();
      return profiles.where((p) => p['email'] != email).toList();
    } catch (e) {
      debugPrint('❌ Error getting remaining profiles: $e');
      return [];
    }
  }

  // =====================================================
  // ✅ PROCESS EXPIRED DELETIONS - ADD TO SESSIONMANAGER
  // =====================================================

  /// 🔥 Process expired profile deletions (auto-delete after 90 days)
  static Future<void> processExpiredDeletions() async {
    try {
      final supabase = Supabase.instance.client;

      debugPrint('🧹 Processing expired deletions...');

      // ✅ Call database function for profile level deletions
      final profileResponse = await supabase.rpc(
        'process_expired_profile_deletions',
      );

      if (profileResponse != null && profileResponse is List) {
        for (var deleted in profileResponse) {
          final userId = deleted['user_id'] as String?;
          final email = deleted['email'] as String?;

          if (userId != null && email != null) {
            debugPrint('🗑️ Auto-deleted expired profile: $email');

            // ✅ Remove from local storage
            await removeProfile(email);
            await _prefs.remove('del_profile_$email');
          }
        }
        debugPrint(
          '✅ Expired profile deletions processed: ${profileResponse.length} profiles',
        );
      }

      // ✅ Call database function for role level deletions
      final roleResponse = await supabase.rpc('process_expired_role_deletions');

      if (roleResponse != null && roleResponse is List) {
        for (var deleted in roleResponse) {
          final userId = deleted['user_id'] as String?;
          final role = deleted['role'] as String?;

          if (userId != null && role != null) {
            debugPrint('🗑️ Auto-deleted expired role: $userId - $role');

            // ✅ Remove from local storage
            final profiles = await getProfiles();
            final index = profiles.indexWhere((p) => p['userId'] == userId);

            if (index != -1) {
              final email = profiles[index]['email'] as String?;
              if (email != null) {
                // Remove from available profiles
                final availableProfiles = await getAvailableProfiles();
                final updatedAvailable = availableProfiles
                    .where((p) => !(p['userId'] == userId && p['role'] == role))
                    .toList();
                await saveAvailableProfiles(updatedAvailable);

                // Remove schedule
                await _prefs.remove('del_${email}_$role');
              }
            }
          }
        }
        debugPrint(
          '✅ Expired role deletions processed: ${roleResponse.length} roles',
        );
      }
    } catch (e) {
      debugPrint('❌ Error processing expired deletions: $e');
    }
  }

  /// 🔥 Process expired profile deletions (Profile Level)
  static Future<void> processExpiredProfileDeletions() async {
    try {
      final supabase = Supabase.instance.client;

      debugPrint('🧹 Processing expired profile deletions...');

      final response = await supabase.rpc('process_expired_profile_deletions');

      if (response != null && response is List) {
        for (var deleted in response) {
          final userId = deleted['user_id'] as String?;
          final email = deleted['email'] as String?;

          if (userId != null && email != null) {
            debugPrint('🗑️ Auto-deleted expired profile: $email');

            // ✅ Remove from local storage
            await removeProfile(email);
            await _prefs.remove('del_profile_$email');
          }
        }
        debugPrint(
          '✅ Expired profile deletions processed: ${response.length} profiles',
        );
      }
    } catch (e) {
      debugPrint('❌ Error processing expired profile deletions: $e');
    }
  }

  /// 🔥 Process expired role deletions
  static Future<void> processExpiredRoleDeletions() async {
    try {
      final supabase = Supabase.instance.client;

      debugPrint('🧹 Processing expired role deletions...');

      final response = await supabase.rpc('process_expired_role_deletions');

      if (response != null && response is List) {
        for (var deleted in response) {
          final userId = deleted['user_id'] as String?;
          final role = deleted['role'] as String?;

          if (userId != null && role != null) {
            debugPrint('🗑️ Auto-deleted expired role: $userId - $role');

            // ✅ Remove from local storage
            final profiles = await getProfiles();
            final index = profiles.indexWhere((p) => p['userId'] == userId);

            if (index != -1) {
              final email = profiles[index]['email'] as String?;
              if (email != null) {
                // Remove from available profiles
                final availableProfiles = await getAvailableProfiles();
                final updatedAvailable = availableProfiles
                    .where((p) => !(p['userId'] == userId && p['role'] == role))
                    .toList();
                await saveAvailableProfiles(updatedAvailable);

                // Remove schedule
                await _prefs.remove('del_${email}_$role');
              }
            }
          }
        }
        debugPrint(
          '✅ Expired role deletions processed: ${response.length} roles',
        );
      }
    } catch (e) {
      debugPrint('❌ Error processing expired role deletions: $e');
    }
  }

  // =====================================================
  // ✅ AUTO-RESTORE FUNCTIONS - COMPLETE
  // =====================================================

  /// ✅ Auto-restore individual role on login (Facebook style)
  static Future<void> autoRestoreRoleOnLogin({
    required String email,
    required String role,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return;
      }

      debugPrint('🔄 Checking auto-restore for role: $role for $email');

      // ✅ Check if role is scheduled_for_deletion
      final roleCheck = await supabase
          .from('user_roles')
          .select('status, roles!inner (name)')
          .eq('user_id', user.id)
          .eq('roles.name', role)
          .maybeSingle();

      if (roleCheck == null) {
        debugPrint('⚠️ Role $role not found for user');
        return;
      }

      final status = roleCheck['status'] as String? ?? 'active';

      // ✅ Only restore if scheduled_for_deletion
      if (status != 'scheduled_for_deletion') {
        debugPrint(
          'ℹ️ Role $role is not scheduled for deletion (status: $status)',
        );
        return;
      }

      // ✅ Call database function to restore
      try {
        final response = await supabase.rpc(
          'auto_restore_role_on_login',
          params: {'p_user_id': user.id, 'p_role': role},
        );

        final success = response['success'] as bool? ?? false;

        if (success) {
          debugPrint('✅ Role auto-restored: $role');

          // ✅ Update local available profiles
          final availableProfiles = await getAvailableProfiles();
          final exists = availableProfiles.any(
            (p) => p['email'] == email && p['role'] == role,
          );

          if (!exists) {
            availableProfiles.add({
              'id': user.id,
              'email': email,
              'role': role,
              'role_id': _getRoleIdFromName(role),
              'status': 'active',
              'is_active': true,
              'last_used': DateTime.now().toIso8601String(),
              'restored_at': DateTime.now().toIso8601String(),
            });
            await saveAvailableProfiles(availableProfiles);
          }

          // ✅ Update user roles cache
          final rolesKey = '$email$_keyUserRoles';
          final cachedRoles = _prefs.getStringList(rolesKey) ?? [];
          if (!cachedRoles.contains(role)) {
            cachedRoles.add(role);
            await _prefs.setStringList(rolesKey, cachedRoles);
          }

          // ✅ Remove schedule
          await _prefs.remove('del_${email}_$role');

          // ✅ Refresh app state
          appState.refreshState();

          debugPrint('✅ Role $role restored and synced for: $email');
        } else {
          final message = response['message'] as String? ?? 'Unknown error';
          debugPrint('⚠️ Failed to restore role $role: $message');
        }
      } on PostgrestException catch (e) {
        debugPrint('⚠️ RPC error for auto_restore_role_on_login: $e');
        // RPC function not found - skip
      } catch (e) {
        debugPrint('⚠️ Error calling auto_restore_role_on_login: $e');
      }
    } catch (e) {
      debugPrint('❌ Error in autoRestoreRoleOnLogin: $e');
    }
  }

  // ============================================================
  // 🔥 SALON MANAGEMENT - ✅ FIXED
  // ============================================================

  static Future<void> saveSalonId(String salonId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySalonId, salonId);
      if (kDebugMode) debugPrint('✅ Salon ID saved: $salonId');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving salon ID: $e');
    }
  }

  // ✅ FIXED: Added async and await
  static Future<String?> getSalonId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keySalonId);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting salon ID: $e');
      return null;
    }
  }

  static Future<void> saveSalonName(String salonName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySalonName, salonName);
      if (kDebugMode) debugPrint('✅ Salon name saved: $salonName');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving salon name: $e');
    }
  }

  // ✅ FIXED: Added async and await
  static Future<String?> getSalonName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keySalonName);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting salon name: $e');
      return null;
    }
  }

  static Future<void> clearSalonData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySalonId);
      await prefs.remove(_keySalonName);
      if (kDebugMode) debugPrint('✅ Salon data cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error clearing salon data: $e');
    }
  }
}
