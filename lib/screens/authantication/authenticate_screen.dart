import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/sign_in.dart';
// import 'package:flutter_application_1/screens/authantication/registration.dart';

class Authenticate extends StatefulWidget {
  const Authenticate({super.key});

  @override
  State<Authenticate> createState() => _AuthenticateState();
}

class _AuthenticateState extends State<Authenticate> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SignInScreen(),
    );
  }
}