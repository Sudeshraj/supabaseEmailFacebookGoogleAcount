import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthCallbackHandlerScreen extends StatefulWidget {
  final String? code;
  final String? error;
  final String? errorCode;
  final String? errorDescription;

  const AuthCallbackHandlerScreen({
    super.key,
    this.code,
    this.error,
    this.errorCode,
    this.errorDescription,
  });

  @override
  State<AuthCallbackHandlerScreen> createState() => _AuthCallbackHandlerScreenState();
}

class _AuthCallbackHandlerScreenState extends State<AuthCallbackHandlerScreen> {
  final supabase = Supabase.instance.client;
  bool _processing = true;
  String? _status;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processAuthCallback();
    });
  }

  Future<void> _processAuthCallback() async {
    try {
      final uri = Uri.base;
      
      if (kDebugMode) {
        print('🔄 Processing auth callback...');
        print('   Full URL: ${uri.toString()}');
        print('   Query Parameters: ${uri.queryParameters}');
        print('   Fragment: ${uri.fragment}');
        print('   Path: ${uri.path}');
      }

      setState(() => _status = 'Processing authentication...');

      // 🔥 **MAJOR FIX**: Use try-catch for getSessionFromUrl with better error handling
      bool sessionProcessed = false;
      
      try {
        // Check if this looks like a Supabase auth URL
        final hasAuthParams = uri.queryParameters.containsKey('access_token') ||
                            uri.queryParameters.containsKey('refresh_token') ||
                            uri.queryParameters.containsKey('type') ||
                            uri.toString().contains('token=') ||
                            uri.fragment.contains('access_token');
        
        if (hasAuthParams) {
          if (kDebugMode) print('🎯 Supabase auth URL detected, calling getSessionFromUrl');
          
          // IMPORTANT: Parse fragment if it contains tokens
          String urlToProcess = uri.toString();
          
          // If tokens are in fragment (common with OAuth), move them to query params
          if (uri.fragment.isNotEmpty && uri.fragment.contains('access_token')) {
            if (kDebugMode) print('📦 Tokens found in fragment, converting...');
            final fragmentParams = Uri.parse('?${uri.fragment}').queryParameters;
            final newUri = uri.replace(
              queryParameters: {...uri.queryParameters, ...fragmentParams},
              fragment: ''
            );
            urlToProcess = newUri.toString();
          }
          
          await supabase.auth.getSessionFromUrl(Uri.parse(urlToProcess));
          sessionProcessed = true;
          
          if (kDebugMode) print('✅ Session processed from URL');
        } else {
          if (kDebugMode) print('⚠️ Not a Supabase auth URL, skipping getSessionFromUrl');
        }
      } catch (e, stack) {
        if (kDebugMode) {
          print('⚠️ getSessionFromUrl error: $e');
          print('Stack trace: $stack');
        }
        // Continue anyway - might be a different type of callback
      }

      // Get current session after processing
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (kDebugMode) {
        print('   Session exists: ${session != null}');
        print('   User: ${user?.email}');
        print('   User ID: ${user?.id}');
        print('   Session processed: $sessionProcessed');
      }

      // 🔥 **IMPORTANT**: Handle GoRouter query parameters from deep link
      // Get parameters from GoRouter state if available
      final state = GoRouterState.of(context);
      final goRouterParams = state.uri.queryParameters;
      
      if (goRouterParams.isNotEmpty && kDebugMode) {
        print('   GoRouter params: $goRouterParams');
      }

      // Combine both parameter sources
      final allParams = {...uri.queryParameters, ...goRouterParams};      
    

      // Handle errors FIRST (from any source)
      final error = allParams['error'] ?? 
                   uri.queryParameters['error'] ?? 
                   goRouterParams['error'];
      
      final errorCode = allParams['error_code'] ?? 
                       uri.queryParameters['error_code'] ?? 
                       goRouterParams['error_code'];
      
      final errorDescription = allParams['error_description'] ?? 
                              uri.queryParameters['error_description'] ?? 
                              goRouterParams['error_description'];

      if (error != null || errorCode != null) {
        _handleAuthError(error ?? errorDescription, errorCode);
        return;
      }

      // If session was processed successfully, handle success
      if (sessionProcessed && session != null && user != null) {
        await _handleSuccessfulAuth(user);
        return;
      }

      // Handle specific callback types
      final type = allParams['type'] ?? 
                  uri.queryParameters['type'] ?? 
                  goRouterParams['type'];

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
          // Default handler for OAuth or general auth
          await _handleDefaultCallback();
          break;
      }
    } catch (e, stack) {
      if (kDebugMode) {
        print('❌ Callback error: $e');
        print('Stack trace: $stack');
      }
      _handleAuthError(e.toString(), null);
    }
  }

  Future<void> _handleSuccessfulAuth(User? user) async {
    setState(() => _status = 'Authentication successful!');
    
    if (kDebugMode) {
      print('✅ Authentication successful');
      print('   User email: ${user?.email}');
      print('   Provider: ${user?.appMetadata['provider']}');
    }
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      // Check if user needs to complete profile
      final needsProfileSetup = await _checkIfNeedsProfileSetup(user);
      
      if (needsProfileSetup) {
        context.go('/reg');
      } else {
        context.go('/', extra: {
          'showMessage': true,
          'message': 'Welcome back!',
        });
      }
    }
  }

  Future<bool> _checkIfNeedsProfileSetup(User? user) async {
    // Add your logic here to check if user needs to complete profile
    // For example, check if they have a username, profile picture, etc.
    return false; // Default to false
  }

  Future<void> _handleDefaultCallback() async {
    setState(() => _status = 'Completing authentication...');
    
    try {
      // Try to refresh session
      await supabase.auth.refreshSession();
      
      final user = supabase.auth.currentUser;
      
      if (user != null) {
        await _handleSuccessfulAuth(user);
      } else {
        // No user found - might be an error
        setState(() {
          _status = 'Authentication failed - No user found';
          _processing = false;
          _hasError = true;
        });
        
        // await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          context.go('/login');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Default callback error: $e');
      // setState(() {
      //   _status = 'Authentication failed';
      //   _processing = false;
      //   _hasError = true;
      // });
      
      // await Future.delayed(const Duration(seconds: 2));
      
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
          context.go(
            '/reset-password',
            extra: {'email': user.email},
          );
        }
      } else {
        // No valid session - might need to extract email from URL
        final uri = Uri.base;
        final email = uri.queryParameters['email'];
        
        setState(() {
          _status = 'Please enter your new password';
          _processing = false;
        });
        
        await Future.delayed(const Duration(seconds: 1));
        
        if (mounted) {
          context.go(
            '/reset-password',
            extra: {'email': email},
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Password recovery error: $e');
      
      setState(() {
        _status = 'Error processing reset link';
        _processing = false;
        _hasError = true;
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
      // Refresh session to verify email
      await supabase.auth.refreshSession();
      
      final user = supabase.auth.currentUser;
      
      if (user != null && user.emailConfirmedAt != null) {
        setState(() => _status = 'Email verified successfully!');
        
        await Future.delayed(const Duration(seconds: 1));
        
        if (mounted) {
          context.go('/', extra: {
            'showMessage': true,
            'message': 'Email verified successfully!',
          });
        }
      } else {
        setState(() {
          _status = 'Email verification failed or pending';
          _processing = false;
          _hasError = true;
        });
        
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          context.go('/verify-email');
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Email verification failed';
        _processing = false;
        _hasError = true;
      });
      
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        context.go('/verify-email');
      }
    }
  }

  Future<void> _handleMagicLink() async {
    setState(() => _status = 'Completing magic link login...');
    
    try {
      // Magic link should have created a session via getSessionFromUrl
      final user = supabase.auth.currentUser;
      
      if (user != null) {
        await _handleSuccessfulAuth(user);
      } else {
        setState(() {
          _status = 'Magic link login failed';
          _processing = false;
          _hasError = true;
        });
        
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          context.go('/login');
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Error processing magic link';
        _processing = false;
        _hasError = true;
      });
      
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        context.go('/login');
      }
    }
  }

  void _handleAuthError(String? error, String? errorCode) {
    String message = 'Authentication failed';
    
    if (errorCode == 'otp_expired') {
      message = 'Verification link has expired. Please request a new one.';
    } else if (error == 'access_denied') {
      message = 'Access denied. Please try again.';
    } else if (error != null) {
      message = error.length > 100 ? '${error.substring(0, 100)}...' : error;
    }
    
    setState(() {
      _status = message;
      _processing = false;
      _hasError = true;
    });
    
    // Navigate to appropriate screen
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        if (errorCode == 'otp_expired' || error == 'access_denied') {
          // context.go('/verify-invalid');
        } else {
          context.go('/login', extra: {
            'error': message,
          });
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
                    : _hasError
                      ? const Color(0xFFF44336).withOpacity(0.1)
                      : const Color(0xFF4CAF50).withOpacity(0.1),
                  border: Border.all(
                    color: _processing 
                      ? const Color(0xFF1877F3)
                      : _hasError
                        ? const Color(0xFFF44336)
                        : const Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                child: _processing
                    ? const CircularProgressIndicator(
                        color: Color(0xFF1877F3),
                        strokeWidth: 3,
                      )
                    : _hasError
                      ? const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFF44336),
                          size: 40,
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
                style: TextStyle(
                  color: _hasError ? const Color(0xFFF44336) : Colors.white,
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
              
              if (_hasError && !_processing)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ElevatedButton(
                    onPressed: () {
                      context.go('/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1877F3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Go to Login',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}