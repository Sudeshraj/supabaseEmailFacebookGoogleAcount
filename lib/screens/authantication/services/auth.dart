// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter_application_1/Models/userModel.dart';

// class AuthServices {
//   //firebase instance
//   final FirebaseAuth _auth = FirebaseAuth.instance;

//   //create a user from firebase user with uid ----1
//   UserModel? _userWithFirebaseUserUid(User? user){
//     return user != null ? UserModel(uid: user.uid): null;
//   }

//   //create the stream for checking the auth changes in the user ----2
//   Stream<UserModel?> get user{
//     return _auth.authStateChanges()
//     .map(_userWithFirebaseUserUid);
//   }

//   //Sing in Anonymous - login as a gest
//   Future singInAnonymously() async {
//     try {
//       UserCredential result = await _auth.signInAnonymously();
//       User? user = result.user;
//       return _userWithFirebaseUserUid(user);
//     } catch (e) {
//       print(e.toString());
//       return null;
//     }
//   }


// //login with email and password
//   Future singInWithEmailAndPassword(String email, String password) async {
//     try {
//       UserCredential result = await _auth.signInWithEmailAndPassword(email: email, password: password);
//       User? user = result.user;
//       return _userWithFirebaseUserUid(user);
//     } catch (e) {
//       print(e.toString());
//       return null;
//     }
//   }
  

//   //sing out
//   Future singOut() async {
//     try {
//       return await _auth.signOut();
//     } catch (e) {
//       print(e.toString());
//       return null;
//     }
//   }
// }
