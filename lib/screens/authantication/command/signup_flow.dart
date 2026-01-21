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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: EmailPasswordScreen(
          initialEmail: _email,
          initialPassword: _password,
          onNext: _handleNextPressed,
        ),
      ),
    );
  }

  Future<void> _handleNextPressed(String email, String password) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _email = email;
      _password = password;
    });

    try {
      // Brief delay to show loading state
      await Future.delayed(const Duration(milliseconds: 300));

      // Navigate to Data Consent Screen
      await _navigateToDataConsent(email, password);
      
    } catch (e) {
      print('❌ Navigation error: $e');
      // Handle error appropriately
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _navigateToDataConsent(String email, String password) async {
    // Use pushNamed with extra data
    await context.pushNamed(
      'data-consent',
      extra: {
        'email': email,
        'password': password,
        'source': 'signup-flow',
      },
    );

    // When returning from DataConsentScreen, check if we need to refresh
    _checkForNavigationResult();
  }

  void _checkForNavigationResult() {
    // This method can be used to handle any return data from DataConsentScreen
    // For example, if registration was successful, we might want to navigate away
    print('↩️ Returned to SignupFlow');
    print('📧 Current email: $_email');
  }

  @override
  void dispose() {
    // Clean up any resources if needed
    super.dispose();
  }
}