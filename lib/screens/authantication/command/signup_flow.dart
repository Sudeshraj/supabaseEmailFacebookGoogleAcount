// signup_flow.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/command/email_password_screen.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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
    debugPrint('SignupFlow building, isLoading: $_isLoading');

    // ============================================================
    // ✅ FIX: the browser's native back button pops the pushed
    // '/data-consent' route through the browser history/URL, not
    // through GoRouter's normal pop() call. That means the Future
    // returned by `context.push()` in _navigateToDataConsent() never
    // completes in that case, so its `finally` block (which used to
    // be the ONLY place resetting `_isLoading`) never runs — the
    // button and spinner stay stuck forever.
    //
    // This screen's build() is called again whenever the route above
    // it is popped and it becomes the current/visible route, no
    // matter how that pop happened (in-app back OR browser back). So
    // we use that as a reliable safety net: if this route is current
    // again and we're still marked as loading, reset it right after
    // this frame.
    // ============================================================
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (isCurrentRoute && _isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isLoading) {
          debugPrint(
            'SignupFlow: route is current again but still loading — '
            'auto-resetting (likely a browser back-button pop)',
          );
          setState(() {
            _isLoading = false;
          });
        }
      });
    }

    // ✅ AppTheme colors from context extensions
    final backgroundColor = context.backgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: EmailPasswordScreen(
          initialEmail: _email,
          initialPassword: _password,
          onNext: _handleNextPressed,
          isLoading: _isLoading,
          onBack: () {
            debugPrint('EmailPasswordScreen wants to go back');

            if (_isLoading) {
              debugPrint('Cannot go back while loading');
              return;
            }

            try {
              if (Navigator.of(context).canPop()) {
                debugPrint('Using Navigator.pop()');
                Navigator.of(context).pop();
              } else if (GoRouter.of(context).canPop()) {
                debugPrint('Using GoRouter.pop()');
                GoRouter.of(context).pop();
              } else {
                debugPrint('Directly going to /login');
                GoRouter.of(context).go('/');
              }
            } catch (e) {
              debugPrint('Error in back navigation: $e');
              GoRouter.of(context).go('/login');
            }
          },
        ),
      ),
    );
  }

  Future<void> _handleNextPressed(String email, String password) async {
    if (_isLoading) {
      debugPrint('Already loading, ignoring request');
      return;
    }

    debugPrint('Next pressed with email: $email');

    setState(() {
      _isLoading = true;
      _email = email;
      _password = password;
    });

    try {
      await _navigateToDataConsent(email, password);
    } catch (e) {
      debugPrint('Error in _handleNextPressed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToDataConsent(String email, String password) async {
    debugPrint('Navigating to DataConsentScreen...');

    try {
      final result = await context.push<Map<String, dynamic>>(
        Uri(
          path: '/data-consent',
          queryParameters: {'email': email, 'password': password},
        ).toString(),
        extra: {'email': email, 'password': password},
      );

      debugPrint('Returned from DataConsentScreen: $result');

      if (result != null && result['action'] == 'user_exists') {
        debugPrint('User exists - showing message');
        _showUserExistsMessage();
      }
    } catch (e) {
      debugPrint('Navigation error: $e');
    } finally {
      // ✅ Still kept as the primary path — this fires correctly for
      // every normal pop (in-app back, successful registration, etc).
      // The build()-time check above is only a safety net for the
      // browser-back case where this finally block doesn't run.
      if (mounted) {
        setState(() {
          _isLoading = false;
          debugPrint('SignupFlow: Loading state reset');
        });
      }
    }
  }

  void _showUserExistsMessage() {
    // ✅ Use context for snackbar
    final isDark = context.isDarkMode;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'An account already exists with this email.',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: isDark ? Colors.orange.shade900 : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}