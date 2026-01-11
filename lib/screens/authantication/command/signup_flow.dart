import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/email_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/finish_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/password_screen.dart';
import 'package:flutter_application_1/screens/authantication/services/auth_service.dart'; // Updated import
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/services/signup_serivce.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupFlow extends StatefulWidget {
  const SignupFlow({super.key});

  @override
  State<SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<SignupFlow> {
  final PageController _controller = PageController();

  String? email;
  String? password;

  // Using the AuthService singleton
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // STEP 2: EMAIL
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
              email: email,
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // REGISTRATION HANDLER
  // -----------------------------------------------------------------------
  Future<void> _handleRegistration() async {
    // Validate inputs
    if (email == null || email!.isEmpty) {
      await _showError("Please enter your email");
      return;
    }

    if (password == null || password!.isEmpty) {
      await _showError("Please enter your password");
      return;
    }

    if (password!.length < 6) {
      await _showError("Password must be at least 6 characters");
      return;
    }

    try {
      // Show loading overlay
      LoadingOverlay.show(
        context, 
        message: "Creating account...",
      );

      // Call the updated AuthService registerUser method
      await _authService.registerUser(
        context: context,
        email: email!,
        password: password!,
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
        
        await showCustomAlert(
          context: context,
          title: "Registration Failed",
          message: errorMessage,
          isError: true,
        );

        // If it's an existing user error, go back to login
        if (e is AuthException && 
            (e.message.contains('already registered') || 
             e.message.contains('user already exists'))) {
          // Optionally navigate to login page
          // GoRouter.of(context).go('/login');
        }
      }
    } 
  }

  // -----------------------------------------------------------------------
  // HELPER METHODS
  // -----------------------------------------------------------------------
  
  Future<void> _showError(String message) async {
    if (context.mounted) {
      await showCustomAlert(
        context: context,
        title: "Error",
        message: message,
        isError: true,
      );
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
    } else if (message.contains('network') || 
               message.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else {
      return 'Unable to create account. Please try again.';
    }
  }

  void _nextPage() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // Optional: Add back navigation
  void _previousPage() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}