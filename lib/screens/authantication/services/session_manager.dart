import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 🧠 SessionManager (Supabase Edition)
/// Securely manages multiple role-based profiles and encrypted passwords.
class SessionManager {
  static const _keyProfiles = 'profiles';
  static const _secure = FlutterSecureStorage(); // Encrypted OS-level storage

  /// -------------------------------------------------------
  /// 🔹 Get all locally saved profiles (without password)
  /// -------------------------------------------------------
  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProfiles);

    if (raw == null || raw.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map<Map<String, dynamic>>((item) {
        return {
          'email': item['email'] ?? '',
          'name': item['name'] ?? '',
          'photo': item['photo'] ?? '',
          'role': item['role'] ?? '',
        };
      }).toList();
    } catch (e) {
      ("❌ Failed to decode profiles: $e");
      return [];
    }
  }

  /// -------------------------------------------------------
  /// 🔹 Save a new or updated role profile
  /// Passwords are stored securely in FlutterSecureStorage.
  /// -------------------------------------------------------
  static Future<void> saveProfile({
    required String email,
    required String name,
    required String password,
    required List<String> roles,
    String? photo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();

    // 🔐 Save password securely (per role)
    for (String role in roles) {
      await _secure.write(key: '${email}_$role', value: password);

      // Replace or add profile
      final index = profiles.indexWhere(
        (p) => p['email'] == email && p['role'] == role,
      );

      final profileData = {
        'email': email,
        'name': name,
        'photo': photo ?? '',
        'role': role,
      };

      if (index != -1) {
        profiles[index] = profileData;
      } else {
        profiles.add(profileData);
      }
    }

    await prefs.setString(_keyProfiles, jsonEncode(profiles));
  }

  /// -------------------------------------------------------
  /// 🔹 Retrieve stored password for a specific email + role
  /// -------------------------------------------------------
  static Future<String?> getPassword(String email, String role) async {
    return await _secure.read(key: '${email}_$role');
  }

  /// -------------------------------------------------------
  /// 🔹 Delete a single role-profile (and password)
  /// -------------------------------------------------------
  static Future<void> deleteRoleProfile(String email, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();

    profiles.removeWhere((p) => p['email'] == email && p['role'] == role);
    await _secure.delete(key: '${email}_$role');

    if (profiles.isEmpty) {
      await prefs.remove(_keyProfiles);
    } else {
      await prefs.setString(_keyProfiles, jsonEncode(profiles));
    }
  }

  /// -------------------------------------------------------
  /// 🔹 Delete all roles associated with an email
  /// -------------------------------------------------------
  static Future<void> deleteAllProfilesByEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();

    // Delete related secure passwords
    for (final p in profiles.where((p) => p['email'] == email)) {
      await _secure.delete(key: '${p['email']}_${p['role']}');
    }

    profiles.removeWhere((p) => p['email'] == email);
    await prefs.setString(_keyProfiles, jsonEncode(profiles));
  }

  /// -------------------------------------------------------
  /// 🔹 Completely clear all saved data
  /// -------------------------------------------------------
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProfiles);
    await _secure.deleteAll();
  }

  /// -------------------------------------------------------
  /// 🔹 Get last logged user (for quick resume)
  /// -------------------------------------------------------
  static Future<Map<String, dynamic>?> getLastUser() async {
    final profiles = await getProfiles();
    if (profiles.isEmpty) return null;
    return profiles.last;
  }

  /// -------------------------------------------------------
  /// 🔹 Save or get current role in use (runtime session)
  /// -------------------------------------------------------
  static Future<void> saveUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("userRole", role);
  }

  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("userRole");
  }

  /// -------------------------------------------------------
  /// 🔹 Check if any profile exists (used for ContinueScreen)
  /// -------------------------------------------------------
  static Future<bool> hasProfile() async {
    final profiles = await getProfiles();
    return profiles.isNotEmpty;
  }

  /// -------------------------------------------------------
  /// 🔹 SharedPreferences helper (for custom use)
  /// -------------------------------------------------------
  static Future<SharedPreferences> getPrefs() async {
    return await SharedPreferences.getInstance();
  }

   // ------------------------------------------------------------
  // 🕒 Wait for deep-link session restore (EDGE CASE HANDLER)
  // ------------------------------------------------------------
  static Future<void> waitForSession({
    int retries = 10,
    Duration delay = const Duration(milliseconds: 300),
  }) async {
    final supabase = Supabase.instance.client;

    for (int i = 0; i < retries; i++) {
      final session = supabase.auth.currentSession;
      if (session != null) return;
      await Future.delayed(delay);
    }
  }


}
