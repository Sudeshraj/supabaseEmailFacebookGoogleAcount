import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/signup_serivce.dart';
import 'package:flutter_application_1/screens/authantication/command/finish_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/email_password_screen.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupFlow extends StatefulWidget {
  const SignupFlow({super.key});

  @override
  State<SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<SignupFlow> {
  String? email;
  String? password;

  // Using the AuthService singleton
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: EmailPasswordScreen(
          initialEmail: email,
          initialPassword: password,
          onNext: (newEmail, newPassword) async {
            // print('Navigating to finish screen');
            // print('Email: $newEmail');
            // print('Password: $newPassword');

            // Direct navigation without using GoRouter extras
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FinishScreen(
                  onSignUp: _handleRegistration,
                  titleText: 'Ready to Sign Up',
                  privacyText:
                      'By signing up, you agree to our Terms and Privacy Policy',
                  btnText: 'Sign Up',
                  email: newEmail, // Pass email directly
                  password: newPassword, // Pass password directly
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // REGISTRATION HANDLER
  // -----------------------------------------------------------------------
  Future<void> _handleRegistration(String email, String password) async {
    try {
      // Show loading overlay
      LoadingOverlay.show(context, message: "Creating account...");

      // Call the updated AuthService registerUser method
      await _authService.registerUser(
        context: context,
        email: email,
        password: password,
      );

      // LoadingOverlay will be hidden by AuthService
    } catch (e) {
      // Hide loading overlay if not already hidden
      LoadingOverlay.hide();

      // Show appropriate error message
      if (context.mounted) {
        final errorMessage = e is AuthException
            ? _getUserFriendlyError(e.message)
            : "An unexpected error occurred. Please try again.";
        if (!mounted) return;
        await showCustomAlert(
          context: context,
          title: "Registration Failed",
          message: errorMessage,
          isError: true,
        );
      }
    }
  }

  String _getUserFriendlyError(String errorMessage) {
    final message = errorMessage.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('user already exists')) {
      return 'An account with this email already exists. Please log in instead.';
    } else if (message.contains('invalid email')) {
      return 'Please enter a valid email address.';
    } else if (message.contains('weak password')) {
      return 'Password is too weak. Please use a stronger password.';
    } else if (message.contains('network') || message.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else {
      return 'Unable to create account. Please try again.';
    }
  }
}
