// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// // import 'package:flutter_application_1/screens/authantication/splash_screen.dart';
// import '../Models/user.dart';
// import '../services/session_manager.dart';
// import '../screens/alertBox/custom_alert.dart';

// class SaveUser {
//   final FirebaseAuth _auth = FirebaseAuth.instance;
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;

//   Future<void> saveUser(CustomerAuth user, BuildContext context) async {
//     try {
//       // Step 1: Create Firebase auth user
//       final credential = await _auth.createUserWithEmailAndPassword(
//         email: user.email,
//         password: user.password,
//       );

//       final firebaseUser = credential.user;
//       if (firebaseUser == null) {
//         throw Exception("Firebase user not created!");
//       }

//       // Step 2: Save Firestore data
//       await _firestore.collection('users').doc(firebaseUser.uid).set({
//         'uid': firebaseUser.uid,
//         'roles': user.roles,
//         'firstName': user.firstName,
//         'lastName': user.lastName,
//         'dob': user.dob.toIso8601String(),
//         'gender': user.gender,
//         'mobile': user.mobile,
//         'email': user.email,
//         'verified': false,
//         'createdAt': FieldValue.serverTimestamp(),
//       });

//       // Step 3: Send verification email
//       await firebaseUser.sendEmailVerification();

//       // ✅ Step 4: Only after all success → save local
//       // await SessionManager.saveProfile(
//       //   user.email,
//       //   '${user.firstName} ${user.lastName}',
//       //   user.password,
//       //   null,
//       // );

//       await SessionManager.saveProfile(
//         user.email,
//         user.firstName,
//         user.password,
//         user.roles, // convert List<String> → String
//         null,
//       );

//       // Step 5: Show success alert
//       await showCustomAlert(
//         context,
//         title: "Account Created 🎉",
//         message:
//             "Your account has been created successfully.\nPlease check your email for verification.",
//         isError: false,
//         onOk: () => Navigator.pushReplacementNamed(context, '/home'),
//       );
//     } on FirebaseAuthException catch (e) {
//       // ❌ Step 6: Firebase error → show alert + delete user if exists
//       String msg;
//       if (e.code == 'email-already-in-use') {
//         msg = 'This email is already registered. Please sign in instead.';
//       } else if (e.code == 'weak-password') {
//         msg = 'Your password is too weak. Try a stronger one.';
//       } else {
//         msg = e.message ?? 'Authentication failed.';
//       }

//       await showCustomAlert(
//         context,
//         title: "Error",
//         message: msg,
//         isError: true,
//       );

//       // 🔴 Delete auth user if created before saving local
//       if (_auth.currentUser != null) {
//         await _auth.currentUser!.delete();
//       }
//     } catch (e) {
//       // ❌ Step 7: Any other error
//       await showCustomAlert(
//         context,
//         title: "Error",
//         message: e.toString(),
//         isError: true,
//       );

//       // 🔴 Delete auth user if created before saving local
//       if (_auth.currentUser != null) {
//         await _auth.currentUser!.delete();
//       }
//     }
//   }

//   Future<void> saveCompany(CompanyAuth user, BuildContext context) async {
//     UserCredential? credential;
//     try {
//       // 🟩 Step 1: Create user in Firebase Auth
//       credential = await _auth.createUserWithEmailAndPassword(
//         email: user.email,
//         password: user.password,
//       );

//       final firebaseUser = credential.user;
//       if (firebaseUser == null) {
//         throw Exception("Firebase user not created!");
//       }

//       await firebaseUser.updateDisplayName(user.companyName);
//       // Must reload to refresh values
//       await firebaseUser.reload();

//       // 🟦 Step 2: Save business data in Firestore
//       await _firestore.collection('users').doc(firebaseUser.uid).set({
//         'uid': firebaseUser.uid,
//         'roles': user.roles,
//         'companyName': user.companyName,
//         'companyAddress': user.companyAddress,
//         'email': user.email,
//         'mobile': user.mobile,
//         'verified': false,
//         'createdAt': FieldValue.serverTimestamp(),
//       });

//       // 🟨 Step 3: Send verification email
//       await firebaseUser.sendEmailVerification();

//       // 🟩 Step 4: Only if all success → Save local session
//       await SessionManager.saveProfile(
//         user.email,
//         user.companyName,
//         user.password,
//         user.roles, // convert List<String> → String
//         null,
//       );

//       // 🟦 Step 5: Success alert
//       await showCustomAlert(
//         context,
//         title: "Business Registered ✅",
//         message:
//             "Your business account has been created.\nPlease verify your email before logging in.",
//         isError: false,
//         onOk: () => Navigator.pushReplacementNamed(context, '/home'),
//       );
//     } on FirebaseAuthException catch (e) {
//       // ❌ Step 6: Firebase authentication failed
//       String msg;
//       if (e.code == 'email-already-in-use') {
//         msg = 'This email is already registered. Please log in.';
//       } else if (e.code == 'weak-password') {
//         msg = 'Password is too weak. Try again with a stronger one.';
//       } else {
//         msg = e.message ?? 'Something went wrong.';
//       }

//       await showCustomAlert(
//         context,
//         title: "Error",
//         message: msg,
//         isError: true,
//       );

//       // 🔴 Delete Firebase user if created before saving local data
//       if (_auth.currentUser != null) {
//         // await _auth.currentUser!.delete();
//       }
//     } catch (e) {
//       // ❌ Step 7: Any other (Firestore / email / unexpected) error
//       await showCustomAlert(
//         context,
//         title: "Error",
//         message: e.toString(),
//         isError: true,
//       );

//       // 🔴 Delete Firebase user if created but failed before saving local session
//       if (_auth.currentUser != null) {
//         // await _auth.currentUser!.delete();
//       }
//     }
//   }
// }
