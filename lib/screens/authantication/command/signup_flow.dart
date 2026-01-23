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
  String? _email;
  String? _password;
  bool _isLoading = false;

  // signup_flow.dart
  @override
  Widget build(BuildContext context) {
    print('🏗️ SignupFlow building, isLoading: $_isLoading');

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: EmailPasswordScreen(
          initialEmail: _email,
          initialPassword: _password,
          onNext: _handleNextPressed,
          isLoading: _isLoading,
          // ✅ Add callback for when screen is popped
          // signup_flow.dart
          onBack: () {
            print('🔙 EmailPasswordScreen wants to go back');

            if (_isLoading) {
              print('⚠️ Cannot go back while loading');
              return;
            }

            // Try multiple approaches
            try {
              // Approach 1: Use Navigator instead of GoRouter
              if (Navigator.of(context).canPop()) {
                print('⬅️ Using Navigator.pop()');
                Navigator.of(context).pop();
              }
              // Approach 2: Use GoRouter
              else if (GoRouter.of(context).canPop()) {
                print('⬅️ Using GoRouter.pop()');
                GoRouter.of(context).pop();
              }
              // Approach 3: Direct navigation
              else {
                print('🔀 Directly going to /login');
                GoRouter.of(context).go('/login');
              }
            } catch (e) {
              print('❌ Error in back navigation: $e');
              GoRouter.of(context).go('/login');
            }
          },
        ),
      ),
    );
  }

  Future<void> _handleNextPressed(String email, String password) async {
    if (_isLoading) {
      print('⚠️ Already loading, ignoring request');
      return;
    }

    print('▶️ Next pressed with email: $email');

    setState(() {
      _isLoading = true;
      _email = email;
      _password = password;
    });

    try {
      // Navigate to Data Consent Screen
      await _navigateToDataConsent(email, password);
    } catch (e) {
      print('❌ Error in _handleNextPressed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // signup_flow.dart
  // signup_flow.dart
  Future<void> _navigateToDataConsent(String email, String password) async {
    print('📤 Navigating to DataConsentScreen...');

    try {
      // Use push (not pushNamed) to get better control
      final result = await context.push<Map<String, dynamic>>(
        Uri(
          path: '/data-consent',
          queryParameters: {'email': email, 'password': password},
        ).toString(),
        extra: {'email': email, 'password': password},
      );

      print('📥 Returned from DataConsentScreen: $result');

      // ✅ Check what happened
      if (result != null && result['action'] == 'user_exists') {
        print('⚠️ User exists - showing message');
        _showUserExistsMessage();
      }
    } catch (e) {
      print('❌ Navigation error: $e');
    } finally {
      // ✅ ALWAYS reset loading state
      if (mounted) {
        setState(() {
          _isLoading = false;
          print('✅ SignupFlow: Loading state reset');
        });
      }
    }
  }

  void _showUserExistsMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('An account already exists with this email.'),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
