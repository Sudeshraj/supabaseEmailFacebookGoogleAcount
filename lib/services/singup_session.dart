import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 🧠 SessionManager (Supabase Edition)
/// Securely manages multiple role-based profiles and encrypted passwords.
class SessionManagerto {
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


static Future<void> saveEmailAndPassword({
  required String email,
  required String password,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final profiles = await getProfiles();

  // 🔐 Save password securely (email-based)
  await _secure.write(key: email, value: password);

  // Check email already exists
  final index = profiles.indexWhere((p) => p['email'] == email);

  if (index == -1) {
    profiles.add({
      'email': email,
      'name': '',
      'photo': '',
      'roles': <String>[],
    });
  }

  await prefs.setString(_keyProfiles, jsonEncode(profiles));
}


/// -------------------------------------------------------
static Future<void> updateProfile({
  required String email,
  String? name,
  String? photo,
  List<String>? roles,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final profiles = await getProfiles();

  final index = profiles.indexWhere((p) => p['email'] == email);

  if (index == -1) {
    throw Exception('Profile not found for $email');
  }

  final profile = profiles[index];

  profiles[index] = {
    'email': email,
    'name': name ?? profile['name'],
    'photo': photo ?? profile['photo'],
    'roles': roles ?? List<String>.from(profile['roles']),
  };

  await prefs.setString(_keyProfiles, jsonEncode(profiles));
}

static Future<String?> getPassword(String email) async {
  return await _secure.read(key: email);
}


}
