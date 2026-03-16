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

  // 🔥 FIX: Operation locks to prevent infinite loops
  static bool _isSavingProfile = false;
  static bool _isSavingRoles = false;
  static bool _isUpdatingAvailableProfiles = false;
  static Map<String, DateTime> _lastOperationTimes = {};

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
        profiles[index]['privacyAcceptedAt'] = privacyAcceptedAt.toIso8601String();
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

  // =====================================================
  // ✅ MAIN PROFILE FUNCTIONS - FIXED VERSION
  // =====================================================

  // 🔥 FIXED: Save COMPLETE user profile locally (with role array) - NO LOOP
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
    // 🔥 PREVENT RECURSIVE CALLS
    if (_isSavingProfile) {
      debugPrint('⏭️ Already saving profile for $email, skipping recursive call');
      return;
    }

    // 🔥 THROTTLE: Prevent too frequent saves
    final operationKey = 'profile_$email';
    final now = DateTime.now();
    final lastOp = _lastOperationTimes[operationKey];
    if (lastOp != null && now.difference(lastOp) < Duration(milliseconds: 500)) {
      debugPrint('⏭️ Too frequent save for $email, skipping');
      return;
    }

    // Set locks
    _isSavingProfile = true;
    _lastOperationTimes[operationKey] = now;
    
    debugPrint('📝 Saving profile for: $email');
    debugPrint('📸 Photo URL provided: ${photo ?? "NULL"}');   
    debugPrint('🔑 Provider provided: $provider');
    debugPrint('👥 Roles provided: $roles');

    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      final existingProfile = index != -1 ? profiles[index] : <String, dynamic>{};

      // MERGE roles properly - this is key for multiple roles
      List<String> userRoles = [];
      
      if (roles != null && roles.isNotEmpty) {
        userRoles = roles;
      } else if (existingProfile.isNotEmpty && existingProfile['roles'] != null) {
        userRoles = List<String>.from(existingProfile['roles'] as List);
      }

      // If we have existing profile and new roles, MERGE them (no duplicates)
      if (index != -1 && roles != null && roles.isNotEmpty) {
        final existingRoles = List<String>.from(existingProfile['roles'] ?? []);
        userRoles = {...existingRoles.toSet(), ...roles.toSet()}.toList();
        debugPrint('📋 Merged new roles with existing: $userRoles');
      }

      debugPrint('📋 Final roles after merge: $userRoles');

      // Photo handling
      String? finalPhoto;
      if (photo != null && photo.isNotEmpty) {
        finalPhoto = photo;
      } else if (existingProfile['photo'] != null &&
          existingProfile['photo'].toString().isNotEmpty) {
        finalPhoto = existingProfile['photo'].toString();
      } else {
        finalPhoto = '';
      }

      // Provider selection
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

      // 🔥 IMPORTANT: Get existing lastLogin or set new one
      String? lastLogin;
      
      if (existingProfile.containsKey('lastLogin') && existingProfile['lastLogin'] != null) {
        // Update existing lastLogin
        lastLogin = now.toIso8601String();
        debugPrint('⏰ Updating lastLogin for $email from ${existingProfile['lastLogin']} to $lastLogin');
      } else {
        // First time login
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
        'termsAcceptedAt': termsAcceptedAt?.toIso8601String() ??
            existingProfile['termsAcceptedAt'] ??
            now.toIso8601String(),
        'privacyAcceptedAt': privacyAcceptedAt?.toIso8601String() ??
            existingProfile['privacyAcceptedAt'] ??
            now.toIso8601String(),
        'consentVersion': _currentConsentVersion,
        'dataConsentGiven': true,
        'dataDeletionRequested': false,
        'dataRetentionDate': now.add(const Duration(days: 730)).toIso8601String(),
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

      // Save or update profile in local storage
      if (index == -1) {
        if (rememberMe) {
          profiles.add(profileData);
          debugPrint('➕ New profile saved locally with roles: $userRoles');
        }
      } else {
        if (rememberMe) {
          profiles[index] = profileData;
          debugPrint('🔄 Profile updated locally with merged roles: $userRoles');
        } else {
          profiles.removeAt(index);
          debugPrint('🗑️ Profile removed');
        }
      }

      await _prefs.setString(_keyProfiles, jsonEncode(profiles));

      // 🔥 FIX: Save roles WITHOUT triggering recursion
      if (rememberMe && userRoles.isNotEmpty) {
        // Directly save to prefs without calling saveUserRoles
        await _prefs.setStringList('$email$_keyUserRoles', userRoles);
        
        // Update available profiles WITHOUT recursion
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
            
            final roleIndex = existingProfiles.indexWhere((p) => 
              p['role'] == role && p['email'] == email
            );
            
            if (roleIndex == -1) {
              existingProfiles.add(profileData);
            } else {
              existingProfiles[roleIndex] = {...existingProfiles[roleIndex], ...profileData};
            }
          }
          
          await _prefs.setString(_keyAvailableProfiles, jsonEncode(existingProfiles));
          debugPrint('✅ Updated available profiles directly');
        }
      }

      // Set current user
      if (rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        debugPrint('👤 Continue screen enabled');
        
        // Don't auto-set current role if multiple roles
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

      // Save tokens
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
      // 🔥 IMPORTANT: Always release locks
      _isSavingProfile = false;
      debugPrint('🔓 Profile saving lock released for $email');
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
      debugPrint('❌ Error getting profiles: $e');
      return [];
    }
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
      debugPrint('❌ Error getting profile: $e');
      return null;
    }
  }

  // =====================================================
  // ✅ ROLE MANAGEMENT FUNCTIONS - FIXED
  // =====================================================

  // 🔥 FIXED: Save ALL user roles (with merge) - SAFE VERSION
  static Future<void> saveUserRoles({
    required String email,
    required List<String> roles,
  }) async {
    // 🔥 PREVENT RECURSIVE CALLS
    if (_isSavingRoles) {
      debugPrint('⏭️ Already saving roles for $email, skipping recursive call');
      return;
    }

    // 🔥 THROTTLE
    final operationKey = 'roles_$email';
    final now = DateTime.now();
    final lastOp = _lastOperationTimes[operationKey];
    if (lastOp != null && now.difference(lastOp) < Duration(milliseconds: 500)) {
      debugPrint('⏭️ Too frequent roles save for $email, skipping');
      return;
    }

    _isSavingRoles = true;
    _lastOperationTimes[operationKey] = now;

    try {
      debugPrint('📝 SessionManager.saveUserRoles START');  
      debugPrint('   - Email: $email');
      debugPrint('   - Roles: $roles');
      
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);
      
      // Get existing roles and MERGE (no duplicates)
      List<String> mergedRoles;
      
      if (index != -1) {
        final existingRoles = List<String>.from(profiles[index]['roles'] ?? []);
        mergedRoles = {...existingRoles.toSet(), ...roles.toSet()}.toList();
        
        // Update existing profile's roles
        profiles[index]['roles'] = mergedRoles;
        profiles[index]['roles_updated_at'] = DateTime.now().toIso8601String();
        
        // Save updated profiles
        await _prefs.setString(_keyProfiles, jsonEncode(profiles));
        
        debugPrint('📋 Merged roles: $mergedRoles');
      } else {
        mergedRoles = roles;
      }
      
      // Save as separate key for quick access
      await _prefs.setStringList('$email$_keyUserRoles', mergedRoles);
      
      // Update available profiles - SAFELY
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

  // Get all user roles
  static Future<List<String>> getUserRoles(String email) async {
    try {
      // Try quick access first
      final quickRoles = _prefs.getStringList('$email$_keyUserRoles');
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

  // 🔥 FIXED: Save current selected role - MOST IMPORTANT FUNCTION
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
        // Check if user has this role
        if (email != null) {
          final userRoles = await getUserRoles(email);
          debugPrint('💾 User roles from storage: $userRoles');
          
          if (!userRoles.contains(role)) {
            debugPrint('⚠️ Warning: User does not have role: $role');
            debugPrint('💾 Available roles: $userRoles');
          }
        }
        
        // Save to SharedPreferences
        await _prefs.setString(_keyCurrentRole, role);
        debugPrint('✅ Saved current role to SharedPreferences: $role');
        
        // Verify it was saved
        final savedRole = _prefs.getString(_keyCurrentRole);
        debugPrint('✅ Verified saved role: $savedRole');
        
        // Update available profiles with last_used
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
        
        // Refresh app state
        appState.refreshState(silent: true);
        debugPrint('✅ AppState refreshed');
      }
      
      debugPrint('💾 ===== saveCurrentRole completed =====');
    } catch (e) {
      debugPrint('❌ Error saving current role: $e');
    }
  }

  // 🔥 FIXED: Get current selected role
  static Future<String?> getCurrentRole() async {
    try {
      final role = _prefs.getString(_keyCurrentRole);
      debugPrint('📖 Getting current role from SharedPreferences: $role');
      
      // Verify with user roles
      final email = await getCurrentUserEmail();
      if (email != null && role != null) {
        final userRoles = await getUserRoles(email);
        if (!userRoles.contains(role)) {
          debugPrint('⚠️ Stored role $role not in user roles $userRoles, clearing');
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

  // Update user role (switch role)
  static Future<void> updateUserRole(String newRole) async {
    try {
      debugPrint('🔄 SessionManager.updateUserRole: $newRole');
      
      final email = await getCurrentUserEmail();
      if (email == null) {
        debugPrint('❌ No current user email found');
        return;
      }
      
      // Check if user has this role
      final roles = await getUserRoles(email);
      if (!roles.contains(newRole)) {
        debugPrint('❌ User does not have role: $newRole');
        return;
      }
      
      // Save as current role
      await saveCurrentRole(newRole);
      
      debugPrint('✅ Successfully updated user role to: $newRole');
    } catch (e) {
      debugPrint('❌ Error updating user role: $e');
    }
  }

  // Check if user has multiple roles
  static Future<bool> hasMultipleRoles(String email) async {
    final roles = await getUserRoles(email);
    return roles.length > 1;
  }

  // Get primary role (most used)
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

  // Clear user roles
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
  // ✅ AVAILABLE PROFILES FUNCTIONS - FIXED
  // =====================================================

  // Save all available profiles
  static Future<void> saveAvailableProfiles(List<Map<String, dynamic>> profiles) async {
    try {
      await _prefs.setString(_keyAvailableProfiles, jsonEncode(profiles));
      debugPrint('✅ Saved ${profiles.length} available profiles');
    } catch (e) {
      debugPrint('❌ Error saving available profiles: $e');
    }
  }

  // Get all available profiles
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

  // 🔥 FIXED: Update available profiles list - SAFE VERSION
  static Future<void> _updateAvailableProfiles(String email, List<String> roles) async {
    // 🔥 PREVENT RECURSIVE CALLS
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
      
      // Create profile entries for each role
      for (String role in roles) {
        final profileData = {
          'id': currentUserId,
          'email': email,
          'role': role,
          'role_id': _getRoleIdFromName(role),
          'is_active': true,
          'last_used': role == currentRole ? DateTime.now().toIso8601String() : null,
        };
        
        final index = existingProfiles.indexWhere((p) => 
          p['role'] == role && p['email'] == email
        );
        
        if (index == -1) {
          existingProfiles.add(profileData);
        } else {
          existingProfiles[index] = {...existingProfiles[index], ...profileData};
        }
      }
      
      await saveAvailableProfiles(existingProfiles);
    } catch (e) {
      debugPrint('❌ Error updating available profiles: $e');
    } finally {
      _isUpdatingAvailableProfiles = false;
    }
  }

  // Get role ID from role name
  static int _getRoleIdFromName(String role) {
    switch (role) {
      case 'owner': return 1;
      case 'barber': return 2;
      case 'customer': return 3;
      default: return 3;
    }
  }

  // =====================================================
  // ✅ SESSION MANAGEMENT FUNCTIONS
  // =====================================================

  // Set current user
  static Future<void> setCurrentUser(String email) async {
    await _prefs.setString(_currentUserKey, email);
  }

  // Get current user email
  static Future<String?> getCurrentUserEmail() async {
    return _prefs.getString(_currentUserKey);
  }

  // Get current user ID
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

  // Save user role (legacy - single role)
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

  // Get user role (legacy)
  static Future<String?> getUserRole() async {
    return getCurrentRole();
  }

  // Check if has any profiles
  static Future<bool> hasProfile() async {
    final profiles = await getProfiles();
    debugPrint('📋 Checking profiles, count: ${profiles.length}');
    return profiles.isNotEmpty;
  }

  // 🔥 UPDATE LAST LOGIN - IMPORTANT FIX
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

  // Remove profile
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
      debugPrint('✅ Most recent profile: ${mostRecent['email']} (${mostRecent['roles']})');
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
  
  // 🔥 UPDATED AUTO-LOGIN METHOD
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

      // 🔥 Check if already logged in with valid session
      if (currentUser?.email == email && currentSession != null) {
        if (isSessionValid(currentSession)) {
          debugPrint('✅ AUTO-LOGIN SUCCESS: Already logged in');
          
          // Update lastLogin time
          await updateLastLogin(email);
          
          // Update roles if needed
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

      // 🔥 Try to refresh session using refresh token
      final refreshToken = await _secureStorage.read(
        key: '${userId}_refresh_token',
      );

      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('❌ Auto-login failed: No secure refresh token found');
        return false;
      }

      try {
        debugPrint('🔄 Attempting to restore session with secure token...');
        
        // First try to refresh the session
        final response = await supabase.auth.refreshSession();
        
        if (response.session != null && response.user?.email == email) {
          debugPrint('✅ AUTO-LOGIN SUCCESS: Session refreshed');
          
          // Update lastLogin time
          await updateLastLogin(email);
          
          // Update secure tokens
          await _updateSecureTokens(userId, response.session!);
          
          // Update roles
          final roles = await getUserRoles(email);
          if (roles.isNotEmpty && await getCurrentRole() == null) {
            final primaryRole = await getPrimaryRole(email);
            if (primaryRole != null) {
              await saveCurrentRole(primaryRole);
            }
          }
          
          return true;
        }
        
        // If refresh fails, try setSession with refresh token
        debugPrint('🔄 Refresh failed, attempting setSession...');
        await supabase.auth.setSession(refreshToken);
        await Future.delayed(const Duration(milliseconds: 500));

        final restoredUser = supabase.auth.currentUser;
        final restoredSession = supabase.auth.currentSession;

        if (restoredUser?.email == email && restoredSession != null) {
          debugPrint('✅ AUTO-LOGIN SUCCESS: Session restored securely');
          
          // Update lastLogin time
          await updateLastLogin(email);
          
          // Update secure tokens
          await _updateSecureTokens(userId, restoredSession);
          
          // Update roles
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

  // 🔥 UPDATED LOGOUT FOR CONTINUE
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
            refreshToken: refreshToken,
            provider: await _getUserProvider(email),
          );
          debugPrint('✅ Refresh token saved before continue logout');
        }
      }

      // Sign out from Supabase
      await supabase.auth.signOut();

      // 🔥 CRITICAL: Clear current role on logout
      await _prefs.remove(_keyCurrentRole);
      debugPrint('✅ Cleared current role on logout');

      // Save current user for continue screen if remember me is enabled
      if (email != null && rememberMe) {
        await setCurrentUser(email);
        await _prefs.setBool(_showContinueKey, true);
        debugPrint('✅ User prepared for continue screen (Remember Me: $rememberMe)');
      } else {
        await _prefs.remove(_currentUserKey);
        await clearContinueScreen();
        debugPrint('✅ User cleared for continue screen');
      }
    } catch (e) {
      debugPrint('❌ Error during continue logout: $e');
    }
  }

  // Clear all
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

  static AndroidOptions _getAndroidOptions() =>
      const AndroidOptions(encryptedSharedPreferences: true);

  static IOSOptions _getIOSOptions() => const IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    synchronizable: true,
  );

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
      debugPrint('❌ Error checking session validity: $e');
      return false;
    }
  }

  // Restore session from storage
  static Future<bool> restoreSessionFromStorage(String email) async {
    return tryAutoLogin(email);
  }

  // Save refresh token
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

  // Get refresh token
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

  // Get active session count
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

  // Clean up expired sessions
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

  static Future<void> requestDataDeletion(String email) async {
    try {
      final profiles = await getProfiles();
      final index = profiles.indexWhere((p) => p['email'] == email);

      if (index != -1) {
        profiles[index]['dataDeletionRequested'] = true;
        profiles[index]['deletionRequestedAt'] = DateTime.now().toIso8601String();

        await _prefs.setString(_keyProfiles, jsonEncode(profiles));

        final userId = profiles[index]['userId'] as String?;
        if (userId != null) {
          await _secureStorage.delete(key: '${userId}_refresh_token');
          await _secureStorage.delete(key: '${userId}_access_token');
        }
        
        await clearUserRoles(email);
        debugPrint('✅ Data deletion requested for: $email');
      }
    } catch (e) {
      debugPrint('❌ Error requesting data deletion: $e');
    }
  }

  // Secure storage health check
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
}