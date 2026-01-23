import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthCallbackHandlerScreen extends StatefulWidget {
  const AuthCallbackHandlerScreen({super.key});

  @override
  State<AuthCallbackHandlerScreen> createState() => _AuthCallbackHandlerScreenState();
}

class _AuthCallbackHandlerScreenState extends State<AuthCallbackHandlerScreen> {
  final supabase = Supabase.instance.client;
  bool _processing = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _processAuthCallback();
  }

  Future<void> _processAuthCallback() async {
    try {
      final uri = Uri.base;
      
      if (kDebugMode) {
        print('🔄 Processing auth callback...');
        print('   URL: $uri');
        print('   Query: ${uri.queryParameters}');
        print('   Fragment: ${uri.fragment}');
      }

      setState(() => _status = 'Processing authentication...');

      // Wait for Supabase to process the callback
      await Future.delayed(const Duration(milliseconds: 500));

      // Get the current session after processing
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (kDebugMode) {
        print('   Session: ${session != null}');
        print('   User: ${user?.email}');
      }

      // Check callback type
      final type = uri.queryParameters['type'];
      final error = uri.queryParameters['error'];
      final errorCode = uri.queryParameters['error_code'];

      // Handle errors
      if (error != null || errorCode != null) {
        _handleAuthError(error, errorCode);
        return;
      }

      // Handle different callback types
      switch (type) {
        case 'recovery':
          await _handlePasswordRecovery();
          break;
        
        case 'signup':
        case 'invite':
          await _handleEmailVerification();
          break;
        
        case 'magiclink':
          await _handleMagicLink();
          break;
        
        default:
          // Generic OAuth or default callback
          await _handleDefaultCallback();
          break;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Callback error: $e');
      _handleAuthError(e.toString(), null);
    }
  }

  Future<void> _handlePasswordRecovery() async {
    setState(() => _status = 'Setting up password reset...');
    
    final session = supabase.auth.currentSession;
    
    if (session == null) {
      setState(() {
        _status = 'Invalid or expired reset link';
        _processing = false;
      });
      
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/reset-password');
      return;
    }
    
    // Success - go to password reset form
    if (mounted) {
      context.go('/reset-password-form');
    }
  }

  Future<void> _handleEmailVerification() async {
    setState(() => _status = 'Verifying email...');
    
    try {
      // Try to verify the email
      await supabase.auth.refreshSession();
      
      setState(() => _status = 'Email verified successfully!');
      
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      setState(() {
        _status = 'Email verification failed';
        _processing = false;
      });
    }
  }

  Future<void> _handleMagicLink() async {
    setState(() => _status = 'Completing login...');
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _handleDefaultCallback() async {
    setState(() => _status = 'Completing authentication...');
    
    // Refresh session to get latest state
    await supabase.auth.refreshSession();
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      context.go('/');
    }
  }

  void _handleAuthError(String? error, String? errorCode) {
    String message = 'Authentication failed';
    
    if (errorCode == 'otp_expired') {
      message = 'Verification link has expired';
    } else if (error == 'access_denied') {
      message = 'Access denied';
    } else if (error != null) {
      message = error;
    }
    
    setState(() {
      _status = message;
      _processing = false;
    });
    
    // Navigate to appropriate screen
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        if (errorCode == 'otp_expired' || error == 'access_denied') {
          context.go('/verify-invalid');
        } else {
          context.go('/login');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _processing 
                    ? const Color(0xFF1877F3).withOpacity(0.1)
                    : const Color(0xFF4CAF50).withOpacity(0.1),
                  border: Border.all(
                    color: _processing 
                      ? const Color(0xFF1877F3)
                      : const Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                child: _processing
                    ? const CircularProgressIndicator(
                        color: Color(0xFF1877F3),
                        strokeWidth: 3,
                      )
                    : const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF4CAF50),
                        size: 40,
                      ),
              ),
              
              const SizedBox(height: 24),
              
              // Status text
              Text(
                _status ?? 'Processing...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 8),
              
              if (_processing)
                Text(
                  'Please wait...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}