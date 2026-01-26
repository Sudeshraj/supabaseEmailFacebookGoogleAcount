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
      print('   Full URL: ${uri.toString()}');
      print('   Query: ${uri.queryParameters}');
      print('   Fragment: ${uri.fragment}');
    }

    setState(() => _status = 'Processing authentication...');

    // 🔥 IMPORTANT CHANGE: ALWAYS try to get session from URL
    // OAuth, password reset, email verification සියල්ලම මේකෙන් වැඩ කරයි
    try {
      await supabase.auth.getSessionFromUrl(Uri.parse(uri.toString()));
      
      if (kDebugMode) {
        print('✅ Session processed from URL');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ getSessionFromUrl error: $e');
      // Continue anyway - might be a different type of callback
    }

    // Get current session after processing
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    if (kDebugMode) {
      print('   Session exists: ${session != null}');
      print('   User email: ${user?.email}');
      print('   User ID: ${user?.id}');
    }

    // 🔥 NEW: Check if this is an OAuth callback
    // OAuth URLs usually don't have 'type' parameter
    final hasNoTypeParameter = !uri.queryParameters.containsKey('type');
    final hasAccessToken = uri.toString().contains('access_token');
    
    if (hasNoTypeParameter && hasAccessToken && session != null) {
      if (kDebugMode) print('🔐 OAuth flow detected');
      await _handleOAuthCallback();
      return;
    }

    // Check for password recovery
    final isRecovery = uri.toString().contains('type=recovery') ||
                       uri.toString().contains('recovery') ||
                       (uri.queryParameters.containsKey('type') && 
                        uri.queryParameters['type'] == 'recovery');
    
    if (isRecovery) {
      if (kDebugMode) print('🔐 Password recovery flow detected');
      await _handlePasswordRecovery();
      return;
    }

    // Handle other callback types
    final type = uri.queryParameters['type'];
    final error = uri.queryParameters['error'];
    final errorCode = uri.queryParameters['error_code'];
    final errorDescription = uri.queryParameters['error_description'];

    // Handle errors
    if (error != null || errorCode != null) {
      _handleAuthError(error ?? errorDescription, errorCode);
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
        // If no type and no session, it might be an error
        if (session == null) {
          _handleAuthError('Authentication failed', null);
          return;
        }
        // Otherwise it's a successful authentication (OAuth or default)
        await _handleDefaultCallback();
        break;
    }
  } catch (e) {
    if (kDebugMode) print('❌ Callback error: $e');
    _handleAuthError(e.toString(), null);
  }
}

// 🔥 NEW: OAuth Handler
Future<void> _handleOAuthCallback() async {
  setState(() => _status = 'Completing OAuth login...');
  
  try {
    // Refresh session to ensure we have latest data
    await supabase.auth.refreshSession();
    
    final user = supabase.auth.currentUser;
    
    if (kDebugMode) {
      print('✅ OAuth login successful');
      print('   User: ${user?.email}');
      print('   Provider: ${user?.appMetadata?['provider']}');
    }
    
    setState(() => _status = 'Login successful!');
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      context.go('/', extra: {
        'showMessage': true,
        'message': 'Logged in successfully!',
      });
    }
  } catch (e) {
    if (kDebugMode) print('❌ OAuth error: $e');
    setState(() {
      _status = 'OAuth login failed';
      _processing = false;
    });
    
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      context.go('/login');
    }
  }
}

// Updated _handleDefaultCallback for OAuth
Future<void> _handleDefaultCallback() async {
  setState(() => _status = 'Completing authentication...');
  
  try {
    // Ensure session is fresh
    await supabase.auth.refreshSession();
    
    final user = supabase.auth.currentUser;
    
    if (kDebugMode) {
      print('✅ Default callback successful');
      print('   User authenticated: ${user != null}');
    }
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      // Check if user just signed up (no profile, etc.)
      final isNewUser = user?.createdAt != null && 
                       DateTime.now().difference(user!.createdAt as DateTime).inMinutes < 5;
      
      if (isNewUser) {
        // New user - go to profile setup
        context.go('/reg');
      } else {
        // Existing user - go to home
        context.go('/');
      }
    }
  } catch (e) {
    if (kDebugMode) print('❌ Default callback error: $e');
    setState(() {
      _status = 'Authentication failed';
      _processing = false;
    });
    
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      context.go('/login');
    }
  }
}

Future<void> _handlePasswordRecovery() async {
  setState(() => _status = 'Setting up password reset...');
  
  try {
    // Get current session
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;
    
    if (kDebugMode) {
      print('🔐 Password recovery flow:');
      print('   Session: ${session?.accessToken != null}');
      print('   User authenticated: ${user != null}');
      print('   User email: ${user?.email}');
    }
    
    // Check if user is authenticated (session exists)
    if (session != null && user != null) {
      // User is authenticated, navigate to password reset form
      setState(() => _status = 'Please set your new password');
      
      if (kDebugMode) {
        print('✅ Recovery successful, navigating to reset form');
      }
      
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        // Pass user email to reset form if needed
        context.go(
          '/reset-password-form',
          extra: {'email': user.email},
        );
      }
    } else {
      // No valid session
      setState(() {
        _status = 'Invalid or expired reset link';
        _processing = false;
      });
      
      if (kDebugMode) {
        print('❌ No valid session found for recovery');
      }
      
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        context.go('/reset-password');
      }
    }
  } catch (e) {
    if (kDebugMode) print('❌ Password recovery error: $e');
    
    setState(() {
      _status = 'Error processing reset link';
      _processing = false;
    });
    
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      context.go('/reset-password');
    }
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