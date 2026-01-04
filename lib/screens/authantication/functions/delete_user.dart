import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';




class AuthHelper {
  /// Delete User + Firestore Data + Local Prefs
  /// Returns TRUE if success, FALSE if failed
// static Future<bool> deleteUser(String email) async {
//   final auth = FirebaseAuth.instance;
//   final user = auth.currentUser;

//   if (user != null) {
//     try {
//       // ---------------------------
//       // DELETE FIRESTORE USER DOC
//       // ---------------------------
//       await FirebaseFirestore.instance
//           .collection("users")
//           .doc(user.uid)
//           .delete()
//           .catchError((_) {});

//       // ---------------------------
//       // DELETE AUTH USER
//       // ---------------------------
//       await user.delete();
//     } catch (e) {
//       debugPrint("Delete error: $e");
//       return false;
//     }
//   }

//   // ---------------------------
//   // CLEAR LOCAL PROFILE
//   // ---------------------------
//   try {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.clear();
//   } catch (e) {
//     debugPrint("Local clear error: $e");
//   }

//   return true;
// }

//............................................................................................................

 /// Deletes AUTH + FIRESTORE using Cloud Function
  /// Also clears local SharedPreferences
  /// Returns TRUE if success, FALSE otherwise
static Future<bool> deleteUserUsingUid(String uid) async {
  try {
    // ------------------------------------
    // CALL CLOUD FUNCTION TO DELETE USER
    // ------------------------------------
    final callable =
        FirebaseFunctions.instance.httpsCallable("deleteUserByUid");

    final response = await callable.call({"uid": uid});

    final data = response.data;

    // Safely check backend response
    if (data == null || data["success"] != true) {
      debugPrint("❌ Cloud Function returned failure: $data");
      return false;
    }
  } catch (e) {
    debugPrint("❌ Cloud Function error: $e");
    return false;
  }

  // ------------------------------------
  // CLEAR LOCAL STORED PROFILE DATA
  // ------------------------------------
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  } catch (e) {
    debugPrint("❌ Local prefs clear error: $e");
  }

  return true; // 🎉 Successfully deleted
}



}
