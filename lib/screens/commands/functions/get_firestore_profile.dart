import 'package:cloud_firestore/cloud_firestore.dart';

Future<Map<String, dynamic>?> getFirestoreProfile(String email) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: email)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final data = snap.docs.first.data();

    String resolvedName = "";
    if (data.containsKey("firstName") && data["firstName"] != null) {
      resolvedName = data["firstName"];
    } else if (data.containsKey("companyName") && data["companyName"] != null) {
      resolvedName = data["companyName"];
    }

    return {
      "uid": snap.docs.first.id,
      "name": resolvedName,
      "email": data["email"] ?? "",
      "photo": data["photo"] ?? "",
      "roles": data["role"] ?? [], 
    };
  } catch (e) {
    // return error for UI layer to handle
    return {"error": e.toString()};
  }
}






// Future<String?> getUserRole(String email) async {
//   final snap = await FirebaseFirestore.instance
//       .collection("users")
//       .doc(email)
//       .get();

//   if (!snap.exists) return null;

//   return snap.data()?["role"]; // roles: "customer", "business", "employee"
// }

Future<String?> getUserRole(String email) async {
  final snap = await FirebaseFirestore.instance
      .collection("users")
      .doc(email)
      .get();

  if (!snap.exists) return null;

  final data = snap.data();

  // If single role exists
  if (data?["role"] != null && data?["role"] is String) {
    return data?["role"];
  }

  // If array exists → roles: ["business"]
  if (data?["roles"] != null && data?["roles"] is List) {
    final list = (data?["roles"] as List).cast<String>();
    if (list.isNotEmpty) return list.first;
  }

  return null;
}

Future<List<String>> fetchUserRoles(String uid) async {
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();

  if (!doc.exists) return [];

  final data = doc.data();
  if (data == null) return [];

  final roleField = data['role']; // <-- your field name

  if (roleField is List) {
    return roleField.map((e) => e.toString()).toList();
  }

  return [];
}

