import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  static const _tag = 'AuthService';

  // =========================================================================================
  // REGISTER NEW USER
  // =========================================================================================

  // Future<void> registerUser({
  //   required BuildContext context,
  //   required String email,
  //   required String password,
  //   bool rememberMe = true,
  //   bool marketingConsent = false,
  // }) async {
  //   try {
  //     // Validate inputs
  //     if (!_isValidEmail(email)) {
  //       _showErrorAlert(context, 'Invalid email format');
  //       return;
  //     }

  //     if (!_isValidPassword(password)) {
  //       _showErrorAlert(context, 'Password must be at least 6 characters');
  //       return;
  //     }

  //     // Show loading overlay
  //     LoadingOverlay.show(context, message: "Creating account...");

  //     final now = DateTime.now().toIso8601String();

  //     // ✅ FIRST: Check if user already exists BEFORE trying to register
  //     try {
  //       await _supabase.auth.signInWithPassword(
  //         email: email.trim(),
  //         password: password.trim(),
  //       );

  //       // If sign in succeeds, user exists
  //       LoadingOverlay.hide();
  //       await _handleExistingUser(context, email);
  //       return;
  //     } on AuthException catch (e) {
  //       // Expected - user doesn't exist or wrong password
  //       // Continue with registration
  //       print('🔍 User check: ${e.message}');
  //     } catch (e) {
  //       // Other errors, continue with registration
  //       print('🔍 User check error: $e');
  //     }

  //     // Perform registration
  //     final response = await _supabase.auth.signUp(
  //       email: email.trim(),
  //       password: password.trim(),
  //       emailRedirectTo: _getRedirectUrl(),
  //       data: {
  //         'created_at': now,
  //         'email': email.trim(),
  //         'terms_accepted_at': now,
  //         'privacy_accepted_at': now,
  //         'data_consent_given': true,
  //         'marketing_consent': marketingConsent,
  //         'marketing_consent_at': marketingConsent ? now : null,
  //         'remember_me_enabled': rememberMe,
  //         'app_version': '1.0.0',
  //         'platform': 'mobile',
  //       },
  //     );

  //     final user = response.user;

  //     // ✅ BETTER check for existing user
  //     if (user?.identities?.isEmpty ?? true) {
  //       // User already exists in auth but might not have confirmed email
  //       LoadingOverlay.hide();
  //       await _handleExistingUser(context, email);
  //       return;
  //     }

  //     // Handle successful registration
  //     LoadingOverlay.hide();
  //     await _handleSuccessfulRegistration(
  //       context,
  //       user!,
  //       email,
  //       rememberMe,
  //       response.session?.refreshToken,
  //       marketingConsent,
  //     );
  //   } on AuthException catch (e) {
  //     LoadingOverlay.hide();
  //     await _handleAuthException(context, e, 'Registration');
  //   } catch (e, stackTrace) {
  //     LoadingOverlay.hide();
  //     await _handleGenericException(context, e, stackTrace, 'Registration');
  //   }
  // }

  Future<void> registerUser({
    required BuildContext context,
    required String email,
    required String password,
    bool rememberMe = true,
    bool marketingConsent = false,
  }) async {
    try {
      // Validate inputs
      if (!_isValidEmail(email)) {
        _showErrorAlert(context, 'Invalid email format');
        return;
      }

      if (!_isValidPassword(password)) {
        _showErrorAlert(context, 'Password must be at least 6 characters');
        return;
      }

      // Show loading overlay
      LoadingOverlay.show(context, message: "Creating account...");

      final now = DateTime.now().toIso8601String();

      // ✅ FIRST: Check if user already exists BEFORE trying to register
      try {
        await _supabase.auth.signInWithPassword(
          email: email.trim(),
          password: password.trim(),
        );

        // If sign in succeeds, user exists
        LoadingOverlay.hide();
        await _handleExistingUser(context, email);
        return;
      } on AuthException catch (e) {
        // Expected - user doesn't exist or wrong password
        print('🔍 User check: ${e.message}');
      } catch (e) {
        // Other errors, continue with registration
        print('🔍 User check error: $e');
      }

      // Perform registration
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password.trim(),
        emailRedirectTo: _getRedirectUrl(),
        data: {
          'created_at': now,
          'email': email.trim(),
          'terms_accepted_at': now,
          'privacy_accepted_at': now,
          'data_consent_given': true,
          'marketing_consent': marketingConsent,
          'marketing_consent_at': marketingConsent ? now : null,
          'remember_me_enabled': rememberMe,
          'app_version': '1.0.0',
          'platform': 'mobile',
          'registration_complete': false, // 👈 Track if profile created
          'role': null, // 👈 Will be set later
          'role_id': null, // 👈 Will be set later
        },
      );

      final user = response.user;

      // ✅ Check if user already exists (identities empty)
      if (user?.identities?.isEmpty ?? true) {
        LoadingOverlay.hide();
        await _handleExistingUser(context, email);
        return;
      }

      // ✅ If user is null, throw error
      if (user == null) {
        throw Exception('Failed to create user');
      }

      print('✅ User created: ${user.id}');
      print('📝 Initial metadata: ${user.userMetadata}');

      // ✅ IMPORTANT: Navigate to profile creation screen
      LoadingOverlay.hide();

      if (!context.mounted) return;

      await _handleSuccessfulRegistration(
        context,
        user,
        email,
        rememberMe,
        response.session?.refreshToken,
        marketingConsent,
      );
    } on AuthException catch (e) {
      LoadingOverlay.hide();
      await _handleAuthException(context, e, 'Registration');
    } catch (e, stackTrace) {
      LoadingOverlay.hide();
      await _handleGenericException(context, e, stackTrace, 'Registration');
    }
  }

  // ✅ Update registration handler
  Future<void> _handleSuccessfulRegistration(
    BuildContext context,
    User user,
    String email,
    bool rememberMe,
    String? refreshToken,
    bool marketingConsent,
  ) async {
    try {
      // ✅ Save user profile with all consent data
      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: email.split('@').first,
        rememberMe: rememberMe,
        refreshToken: refreshToken,
        termsAcceptedAt: DateTime.now(),
        privacyAcceptedAt: DateTime.now(),
        marketingConsent: marketingConsent,
        marketingConsentAt: marketingConsent ? DateTime.now() : null,
      );

      developer.log(
        '✅ User registered: $email '
        '(Remember Me: $rememberMe, '
        'Marketing: $marketingConsent)',
        name: _tag,
      );

      // ✅ Log consent for compliance
      developer.log(
        '✅ User consent recorded: '
        'Terms: ${DateTime.now()}, '
        'Privacy: ${DateTime.now()}, '
        'Marketing: ${marketingConsent ? DateTime.now() : "Not given"}',
        name: _tag,
      );

      // ✅ Refresh app state
      appState.refreshState();

      // ✅ Navigate to verify email
      if (context.mounted) {
        context.go('/verify-email');

        // ✅ Show success message
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     SnackBar(
        //       content: Text(
        //         rememberMe
        //             ? 'Account created! Check your email for verification.'
        //             : 'Account created! Please verify your email.',
        //       ),
        //       duration: const Duration(seconds: 4),
        //       backgroundColor: Colors.green,
        //       action: SnackBarAction(
        //         label: 'OK',
        //         textColor: Colors.white,
        //         onPressed: () {
        //           ScaffoldMessenger.of(context).hideCurrentSnackBar();
        //         },
        //       ),
        //     ),
        //   );
        // });
      }
    } catch (e) {
      developer.log('❌ Error in registration handler: $e', name: _tag);
      if (context.mounted) {
        await showCustomAlert(
          context: context,
          title: "Registration Error",
          message: "Unable to save profile. Please try again.",
          isError: true,
        );
      }
    }
  }

  // =========================================================================================
  // LOGIN USER
  // =========================================================================================

  Future<void> loginUser({
    required BuildContext context, // Fixed: Added required context parameter
    required String email,
    required String password,
  }) async {
    final Completer<void> completer = Completer<void>();

    try {
      // Validate inputs
      if (!_isValidEmail(email)) {
        _showErrorAlert(context, 'Invalid email format');
        return;
      }

      // Show loading overlay
      LoadingOverlay.show(context, message: "Signing in...");

      // Perform login
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final user = response.user;

      if (user != null) {
        if (context.mounted) {
          await _handleSuccessfulLogin(context, user, email);
        }
      } else {
        throw Exception('Login failed - no user returned');
      }

      completer.complete();
    } on AuthException catch (e) {
      if (context.mounted) {
        await _handleAuthException(context, e, 'Login');
      }
    } on TimeoutException catch (e) {
      if (context.mounted) {
        await _handleTimeoutException(context, e, 'Login');
      }
    } catch (e, stackTrace) {
      if (context.mounted) {
        await _handleGenericException(context, e, stackTrace, 'Login');
      }
    } finally {
      // Always ensure overlay is hidden
      if (context.mounted) {
        _safeHideOverlay(context);
      }
    }

    return completer.future;
  }

  // =========================================================================================
  // HELPER METHODS
  // =========================================================================================

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return emailRegex.hasMatch(email.trim());
  }

  bool _isValidPassword(String password) {
    return password.trim().length >= 6;
  }

  // bool _isExistingUser(User? user) {
  //   return user != null && user.identities != null && user.identities!.isEmpty;
  // }

  String _getRedirectUrl() {
    // if (kIsWeb) {
    //   return '${Uri.base.origin}/verify-email';
    // } else {
    //   return 'myapp://verify-email';
    // }
    if (kIsWeb) {
      final currentOrigin = Uri.base.origin;
      if (currentOrigin.contains('localhost')) {
        return '${Uri.base.origin}/auth/callback';
      } else {
        return 'https://yourdomain.com/auth/callback';
      }
    } else {
      // For Flutter apps | com.example.flutter_application_1
      // redirectUrl = 'com.example.flutter_application_1://auth/callback';
      return 'myapp://auth/callback';
      // redirectUrl = 'io.supabase.flutterquickstart://login-callback';
    }
  }

  // auth_service.dart - _handleExistingUser method
  // auth_service.dart - _handleExistingUser method
  Future<void> _handleExistingUser(BuildContext context, String email) async {
    developer.log('🎯 User already exists: $email', name: _tag);

    try {
      // Small delay for smooth transition
      await Future.delayed(const Duration(milliseconds: 200));

      if (context.mounted) {
        // ✅ Go directly to login with a clear message
        context.go(
          '/login',
          extra: {
            'prefilledEmail': email,
            'showMessage': true,
            'message':
                'An account with this email already exists. Please sign in.',
          },
        );
      }
    } catch (e) {
      developer.log('❌ Error in _handleExistingUser: $e', name: _tag);

      // Fallback
      if (context.mounted) {
        context.go('/login', extra: {'prefilledEmail': email});
      }
    }
  }

  Future<void> _handleSuccessfulLogin(
    BuildContext context,
    User user,
    String email,
  ) async {
    // Save user profile - REMOVE lastLoginAt parameter if not supported
    await SessionManager.saveUserProfile(
      email: email,
      userId: user.id,
      name: user.userMetadata?['full_name'] ?? email.split('@').first,
      // lastLoginAt: DateTime.now(), // Remove this line if SessionManager doesn't have this parameter
    );

    developer.log('User logged in successfully: $email', name: _tag);

    // Check if email needs verification
    if (user.emailConfirmedAt == null) {
      developer.log(
        'Email not verified, redirecting to verify page',
        name: _tag,
      );
      if (context.mounted) context.go('/verify-email');
      return;
    }

    // Refresh app state
    appState.refreshState();

    // Navigate based on user role/state
    if (context.mounted) {
      developer.log('Login successful, navigating to home', name: _tag);
      context.go('/home');

      // Show welcome message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Welcome back!'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      });
    }
  }

  Future<void> _handleAuthException(
    BuildContext context,
    AuthException e,
    String operation,
  ) async {
    developer.log(
      '$operation AuthException: ${e.message}',
      name: _tag,
      error: e,
    );

    final errorMessage = _getUserFriendlyErrorMessage(e);

    if (context.mounted) {
      await showCustomAlert(
        context: context, // Fixed: Added required context parameter
        title: "$operation Failed",
        message: errorMessage,
        isError: true,
      );
    }
  }

  Future<void> _handleTimeoutException(
    BuildContext context,
    TimeoutException e,
    String operation,
  ) async {
    developer.log('$operation timeout: ${e.message}', name: _tag, error: e);

    if (context.mounted) {
      await showCustomAlert(
        context: context, // Fixed: Added required context parameter
        title: "Connection Timeout",
        message:
            "The request took too long. Please check your internet connection and try again.",
        isError: true,
      );
    }
  }

  Future<void> _handleGenericException(
    BuildContext context,
    dynamic e,
    StackTrace stackTrace,
    String operation,
  ) async {
    developer.log(
      '$operation error: $e',
      name: _tag,
      error: e,
      stackTrace: stackTrace,
    );

    // Don't expose internal errors to users
    const userMessage = "An unexpected error occurred. Please try again.";

    if (context.mounted) {
      await showCustomAlert(
        context: context, // Fixed: Added required context parameter
        title: "$operation Failed",
        message: userMessage,
        isError: true,
      );
    }
  }

  void _safeHideOverlay(BuildContext context) {
    try {
      LoadingOverlay.hide();
    } catch (e) {
      developer.log('Error hiding overlay: $e', name: _tag);
    }
  }

  void _showErrorAlert(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showCustomAlert(
          context: context, // Fixed: Added required context parameter
          title: "Invalid Input",
          message: message,
          isError: true,
        );
      }
    });
  }

  String _getUserFriendlyErrorMessage(AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('user already exists')) {
      return 'An account with this email already exists. Please sign in instead.';
    } else if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      return 'Invalid email or password. Please check your credentials and try again.';
    } else if (message.contains('email not confirmed')) {
      return 'Please verify your email address before signing in. Check your inbox for the verification email.';
    } else if (message.contains('too many requests')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    } else if (message.contains('network') || message.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else if (message.contains('weak password')) {
      return 'Password is too weak. Please use a stronger password.';
    } else {
      return 'Unable to complete the request. Please try again.';
    }
  }

  // =========================================================================================
  // ADDITIONAL AUTH METHODS
  // =========================================================================================

  Future<void> logout(BuildContext context) async {
    try {
      LoadingOverlay.show(context, message: "Signing out...");

      await _supabase.auth.signOut();
      // await SessionManager.clearUserProfile();

      appState.refreshState();

      if (context.mounted) {
        context.go('/login');
      }

      developer.log('User logged out successfully', name: _tag);
    } catch (e, stackTrace) {
      developer.log(
        'Logout error: $e',
        name: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      if (context.mounted) {
        _safeHideOverlay(context);
      }
    }
  }

  Future<void> sendPasswordResetEmail({
    required BuildContext context,
    required String email,
  }) async {
    try {
      LoadingOverlay.show(context, message: "Sending reset email...");

      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: _getRedirectUrl().replaceFirst(
          'verify-email',
          'reset-password',
        ),
      );

      developer.log('Password reset email sent to: $email', name: _tag);

      if (context.mounted) {
        await showCustomAlert(
          context: context, // Fixed: Added required context parameter
          title: "Email Sent",
          message:
              "If an account exists with this email, you will receive a password reset link shortly.",
          isError: false,
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        'Password reset error: $e',
        name: _tag,
        error: e,
        stackTrace: stackTrace,
      );

      if (context.mounted) {
        await showCustomAlert(
          context: context, // Fixed: Added required context parameter
          title: "Error",
          message: "Failed to send reset email. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (context.mounted) {
        _safeHideOverlay(context);
      }
    }
  }
}
