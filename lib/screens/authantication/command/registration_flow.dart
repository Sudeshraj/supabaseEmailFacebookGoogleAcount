import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/authantication/command/email_screen.dart';
import 'package:flutter_application_1/screens/authantication/business_reg/company_name_screen.dart';
import 'package:flutter_application_1/screens/authantication/customer_reg/name_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/finish_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/password_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/welcome.dart';
import 'package:flutter_application_1/screens/authantication/services/registration_service.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';

class RegistrationFlow extends StatefulWidget {
  const RegistrationFlow({super.key});

  @override
  State<RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends State<RegistrationFlow> {
  final PageController _controller = PageController();

  // ---- ROLE SYSTEM ----
  List<String> roles = [];

  // ---- COMMON FIELDS ----
  String? firstName;
  String? lastName;
  String? email;
  String? password;

  // ---- BUSINESS FIELD ----
  String? companyName;

  final SaveUser _saveUserService = SaveUser();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // ===============================================================
          // STEP 1: SELECT ROLE
          // ===============================================================
          WelcomeScreen(
            onNext: (selectedRole) {
              setState(() {
                roles = [selectedRole];
              });
              _nextPage();
            },
          ),

          // ===============================================================
          // CUSTOMER FLOW
          // ===============================================================
          if (roles.contains('customer')) ..._buildCustomerFlow(),

          // ===============================================================
          // BUSINESS FLOW
          // ===============================================================
          if (roles.contains('business')) ..._buildBusinessFlow(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // CUSTOMER FLOW
  // -----------------------------------------------------------------------
  List<Widget> _buildCustomerFlow() => [
    NameEntry(
      onNext: (f, l) {
        setState(() {
          firstName = f;
          lastName = l;
        });
        _nextPage();
      },
      controller: _controller,
    ),
    EmailScreen(
      onNext: (e) {
        setState(() => email = e);
        _nextPage();
      },
      controller: _controller,
    ),
    PasswordScreen(
      onNext: (p) {
        setState(() => password = p);
        _nextPage();
      },
      controller: _controller,
    ),
    FinishScreen(
      controller: _controller,
      onSignUp: () async => _handleRegistration(),
    ),
  ];

  // -----------------------------------------------------------------------
  // BUSINESS FLOW
  // -----------------------------------------------------------------------
  List<Widget> _buildBusinessFlow() => [
    CompanyNameScreen(
      onNext: (n) {
        setState(() => companyName = n);
        _nextPage();
      },
      controller: _controller,
    ),
    EmailScreen(
      onNext: (e) {
        setState(() => email = e);
        _nextPage();
      },
      controller: _controller,
    ),
    PasswordScreen(
      onNext: (p) {
        setState(() => password = p);
        _nextPage();
      },
      controller: _controller,
    ),
    FinishScreen(
      controller: _controller,
      onSignUp: () async => _handleRegistration(),
    ),
  ];

  // -----------------------------------------------------------------------
  // HANDLER — CALLED FOR BOTH ROLES
  // -----------------------------------------------------------------------
  Future<void> _handleRegistration() async {
    if (email == null || password == null || roles.isEmpty) {
      await showCustomAlert(
        context,
        title: "Incomplete Info",
        message: "Please complete all fields before signing up.",
        isError: true,
      );
      return;
    }

    try {
      LoadingOverlay.show(context, message: "Creating your account...");

      if (roles.contains('customer')) {
        // ✅ CUSTOMER REGISTRATION
        await _saveUserService.registerUserWithRole(
          context,
          role: 'customer',
          email: email!,
          password: password!,
          displayName: "${firstName ?? ''} ${lastName ?? ''}".trim(),
        );
      } else if (roles.contains('business')) {
        // ✅ BUSINESS REGISTRATION
        await _saveUserService.registerUserWithRole(
          context,
          role: 'business',
          email: email!,
          password: password!,
          displayName: companyName ?? "Business User",
        );
      }
      if (!context.mounted) return;
    } catch (e) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      final dialogCtx = nav.overlay!.context;
      await showCustomAlert(
        dialogCtx,
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
