import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/email_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/finish_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/password_screen.dart';
import 'package:flutter_application_1/services/signup_serivce.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';

class SignupFlow extends StatefulWidget {
  const SignupFlow({super.key});

  @override
  State<SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<SignupFlow> {
  final PageController _controller = PageController();

  String? email;
  String? password;

  final SaveUser _saveUserService = SaveUser();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: [
        
          EmailScreen(
            onNext: (e) {
              setState(() => email = e);
              _nextPage();
            },
            controller: _controller,
          ),

          // STEP 3: PASSWORD
          PasswordScreen(
            onNext: (p) {
              setState(() => password = p);
              _nextPage();
            },
            controller: _controller,
          ),

          // STEP 4: FINISH
          FinishScreen(
            controller: _controller,
            onSignUp: _handleRegistration,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // REGISTRATION HANDLER (SINGLE USER)
  // -----------------------------------------------------------------------
  Future<void> _handleRegistration() async {

    try {
      LoadingOverlay.show(context, message: "Creating your account...");
      await _saveUserService.registerUser(
        context,       
        email: email!,
        password: password!       
      );      
    } catch (e) {
      if (!context.mounted) return;
      await showCustomAlert(
        context,
        title: "Registration Failed",
        message: e.toString(),
        isError: true,
      );
    } finally {
      LoadingOverlay.hide();
    }
  }

  // -----------------------------------------------------------------------
  void _nextPage() => _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
}
