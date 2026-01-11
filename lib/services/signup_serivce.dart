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

  Future<void> registerUser({
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

      if (!_isValidPassword(password)) {
        _showErrorAlert(context, 'Password must be at least 6 characters');
        return;
      }

      // Show loading overlay
      LoadingOverlay.show(
        context, 
        message: "Creating account...",
      );

      // Perform registration
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password.trim(),
        emailRedirectTo: _getRedirectUrl(),
        data: {
          'created_at': DateTime.now().toIso8601String(),
          'email': email.trim(),
        },
      );

      final user = response.user;
      
      // Handle existing user
      if (_isExistingUser(user)) {
        await _handleExistingUser(context, email);
        return;
      }

      // Handle successful registration
      await _handleSuccessfulRegistration(context, user, email);
      
      completer.complete();
      
    } on AuthException catch (e) {
      await _handleAuthException(context, e, 'Registration');
    } on TimeoutException catch (e) {
      await _handleTimeoutException(context, e, 'Registration');
    } catch (e, stackTrace) {
      await _handleGenericException(context, e, stackTrace, 'Registration');
    } finally {
      // Always ensure overlay is hidden
      _safeHideOverlay(context);
    }

    return completer.future;
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
      LoadingOverlay.show(
        context, 
        message: "Signing in...",
      );

      // Perform login
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final user = response.user;
      
      if (user != null) {
        await _handleSuccessfulLogin(context, user, email);
      } else {
        throw Exception('Login failed - no user returned');
      }
      
      completer.complete();
      
    } on AuthException catch (e) {
      await _handleAuthException(context, e, 'Login');
    } on TimeoutException catch (e) {
      await _handleTimeoutException(context, e, 'Login');
    } catch (e, stackTrace) {
      await _handleGenericException(context, e, stackTrace, 'Login');
    } finally {
      // Always ensure overlay is hidden
      _safeHideOverlay(context);
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

  bool _isExistingUser(User? user) {
    return user != null && 
           user.identities != null && 
           user.identities!.isEmpty;
  }

  String _getRedirectUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}/verify-email';
    } else {
      return 'myapp://verify-email';
    }
  }

  Future<void> _handleExistingUser(
    BuildContext context, 
    String email,
  ) async {
    developer.log('User already exists: $email', name: _tag);
    
    // Save email for login screen
    // await SessionManager.saveLastEmail(email);
    
    if (context.mounted) {
      // Navigate to login with pre-filled email
      context.go('/login', extra: {'email': email});
      
      // Show info message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account already exists. Please sign in.'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.blue,
          ),
        );
      });
    }
  }

  Future<void> _handleSuccessfulRegistration(
    BuildContext context,
    User? user,
    String email,
  ) async {
    if (user == null) {
      developer.log('Registration succeeded but user is null', name: _tag);
      throw Exception('Registration failed - no user created');
    }

    // Save user profile - REMOVE createdAt parameter if SessionManager doesn't support it
    await SessionManager.saveUserProfile(
      email: email,
      userId: user.id,
      name: email.split('@').first,
      // createdAt: DateTime.now(), // Remove this line if SessionManager doesn't have this parameter
    );

    developer.log('User registered successfully: $email', name: _tag);
    
    // Refresh app state
    appState.refreshState();

    // Navigate to verify email
    if (context.mounted) {
      context.go('/verify-email');
      
      // Show success message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account created! Please verify your email.'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green,
          ),
        );
      });
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
      developer.log('Email not verified, redirecting to verify page', name: _tag);
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
    developer.log('$operation AuthException: ${e.message}', 
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
    developer.log('$operation timeout: ${e.message}', 
      name: _tag, 
      error: e,
    );

    if (context.mounted) {
      await showCustomAlert(
        context: context, // Fixed: Added required context parameter
        title: "Connection Timeout",
        message: "The request took too long. Please check your internet connection and try again.",
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
    developer.log('$operation error: $e', 
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
    } else if (message.contains('network') || 
               message.contains('connection')) {
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
      developer.log('Logout error: $e', 
        name: _tag, 
        error: e, 
        stackTrace: stackTrace,
      );
    } finally {
      _safeHideOverlay(context);
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
        redirectTo: _getRedirectUrl().replaceFirst('verify-email', 'reset-password'),
      );
      
      developer.log('Password reset email sent to: $email', name: _tag);
      
      if (context.mounted) {
        await showCustomAlert(
          context: context, // Fixed: Added required context parameter
          title: "Email Sent",
          message: "If an account exists with this email, you will receive a password reset link shortly.",
          isError: false,
        );
      }
    } catch (e, stackTrace) {
      developer.log('Password reset error: $e', 
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
      _safeHideOverlay(context);
    }
  }
}