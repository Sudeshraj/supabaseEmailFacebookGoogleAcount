// import 'dart:convert';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class AuthService {
//   final FirebaseAuth _auth = FirebaseAuth.instance;

//   Future<List<Map<String, dynamic>>> getSavedProfiles() async {
//     final prefs = await SharedPreferences.getInstance();
//     final data = prefs.getString('profiles');
//     if (data == null) return [];
//     return List<Map<String, dynamic>>.from(jsonDecode(data));
//   }

//   Future<void> saveProfile(String email, String name, [String? photo]) async {
//     final prefs = await SharedPreferences.getInstance();
//     final profiles = await getSavedProfiles();

//     // Avoid duplicates
//     if (!profiles.any((p) => p['email'] == email)) {
//       profiles.add({
//         'email': email,
//         'name': name,
//         'photo': photo ?? '',
//       });
//       await prefs.setString('profiles', jsonEncode(profiles));
//     }
//   }

//   Future<void> removeProfile(String email) async {
//     final prefs = await SharedPreferences.getInstance();
//     final profiles = await getSavedProfiles();
//     profiles.removeWhere((p) => p['email'] == email);
//     await prefs.setString('profiles', jsonEncode(profiles));
//   }

//   Future<void> clearAllProfiles() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove('profiles');
//   }

//   Future<void> signOut() async {
//     await _auth.signOut();
//   }
// }
