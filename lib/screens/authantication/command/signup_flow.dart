// signup_flow.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/command/email_password_screen.dart';

class SignupFlow extends StatefulWidget {
  const SignupFlow({super.key});

  @override
  State<SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<SignupFlow> {
  String? email;
  String? password;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: EmailPasswordScreen(
          initialEmail: email,
          initialPassword: password,
          onNext: (newEmail, newPassword) async {
            setState(() {
              email = newEmail;
              password = newPassword;
            });
            
            // ✅ Navigate to Data Consent Screen
            context.push('/data-consent', extra: {
              'email': newEmail,
              'password': newPassword,
            });
          },
        ),
      ),
    );
  }
}