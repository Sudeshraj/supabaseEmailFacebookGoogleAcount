import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
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
  State<AuthCallbackHandlerScreen> createState() =>
      _AuthCallbackHandlerScreenState();
}

class _AuthCallbackHandlerScreenState extends State<AuthCallbackHandlerScreen> {
  final supabase = Supabase.instance.client;
  bool _processing = true;
  String? _status;
  bool _hasError = false;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
      _processAuthCallback();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  Future<void> _processAuthCallback() async {
    try {
      final uri = Uri.base;

      if (kDebugMode) {
        print(' Processing auth callback...');
        print('   Full URL: ${uri.toString()}');
        print('   Query Parameters: ${uri.queryParameters}');
        print('   Fragment: ${uri.fragment}');
        print('   Path: ${uri.path}');
      }

      setState(() => _status = 'Processing authentication...');

      bool sessionProcessed = false;

      // ✅ Check widget parameters first
      if (widget.error != null || widget.errorCode != null) {
        _handleAuthError(widget.error ?? widget.errorDescription, widget.errorCode);
        return;
      }

      try {
        final hasAuthParams =
            uri.queryParameters.containsKey('access_token') ||
            uri.queryParameters.containsKey('refresh_token') ||
            uri.queryParameters.containsKey('type') ||
            uri.toString().contains('token=') ||
            uri.fragment.contains('access_token');

        if (hasAuthParams) {
          debugPrint('Supabase auth URL detected, calling getSessionFromUrl');

          String urlToProcess = uri.toString();

          if (uri.fragment.isNotEmpty &&
              uri.fragment.contains('access_token')) {
            if (kDebugMode) print('Tokens found in fragment, converting...');
            final fragmentParams = Uri.parse(
              '?${uri.fragment}',
            ).queryParameters;
            final newUri = uri.replace(
              queryParameters: {...uri.queryParameters, ...fragmentParams},
              fragment: '',
            );
            urlToProcess = newUri.toString();
          }

          await supabase.auth.getSessionFromUrl(Uri.parse(urlToProcess));
          sessionProcessed = true;

          debugPrint('Session processed from URL');
        } else {
          debugPrint('Not a Supabase auth URL, skipping getSessionFromUrl');
        }
      } catch (e, stack) {
        if (kDebugMode) {
          print('getSessionFromUrl error: $e');
          print('Stack trace: $stack');
        }
      }

      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (kDebugMode) {
        print('   Session exists: ${session != null}');
        print('   User: ${user?.email}');
        print('   User ID: ${user?.id}');
        print('   Session processed: $sessionProcessed');
      }

      if (!mounted) return;
      final state = GoRouterState.of(context);
      final goRouterParams = state.uri.queryParameters;

      if (goRouterParams.isNotEmpty && kDebugMode) {
        debugPrint('   GoRouter params: $goRouterParams');
      }

      final allParams = {...uri.queryParameters, ...goRouterParams};

      final error =
          allParams['error'] ??
          uri.queryParameters['error'] ??
          goRouterParams['error'];

      final errorCode =
          allParams['error_code'] ??
          uri.queryParameters['error_code'] ??
          goRouterParams['error_code'];

      final errorDescription =
          allParams['error_description'] ??
          uri.queryParameters['error_description'] ??
          goRouterParams['error_description'];

      if (error != null || errorCode != null) {
        _handleAuthError(error ?? errorDescription, errorCode);
        return;
      }

      if (sessionProcessed && session != null && user != null) {
        await _handleSuccessfulAuth(user);
        return;
      }

      final type =
          allParams['type'] ??
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
          await _handleDefaultCallback();
          break;
      }
    } catch (e, stack) {
      if (kDebugMode) {
        print('Callback error: $e');
        print('Stack trace: $stack');
      }
      _handleAuthError(e.toString(), null);
    }
  }

  Future<void> _handleSuccessfulAuth(User? user) async {
    setState(() => _status = 'Authentication successful!');

    if (kDebugMode) {
      print('Authentication successful');
      print('   User email: ${user?.email}');
      print('   Provider: ${user?.appMetadata['provider']}');
    }

    if (user != null && user.email != null) {
      await _saveProfileAfterOAuthCallback(user);
    }

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    context.go(
      '/',
      extra: {'showMessage': true, 'message': 'Welcome back!'},
    );
  }

  Future<void> _saveProfileAfterOAuthCallback(User user) async {
    try {
      final email = user.email!;
      final session = supabase.auth.currentSession;
      final userMetadata = user.userMetadata ?? {};
      final appMetadata = user.appMetadata;

      String provider = 'email';
      if (appMetadata['provider'] != null) {
        provider = appMetadata['provider'].toString();
      } else if (userMetadata['provider'] != null) {
        provider = userMetadata['provider'].toString();
      }

      String? photoUrl;
      if (userMetadata['avatar_url'] != null &&
          userMetadata['avatar_url'].toString().isNotEmpty) {
        photoUrl = userMetadata['avatar_url'].toString();
      } else if (userMetadata['picture'] != null &&
          userMetadata['picture'].toString().isNotEmpty) {
        photoUrl = userMetadata['picture'].toString();
      }

      String name = email.split('@').first;
      if (userMetadata['full_name'] != null &&
          userMetadata['full_name'].toString().isNotEmpty) {
        name = userMetadata['full_name'].toString();
      } else if (userMetadata['name'] != null &&
          userMetadata['name'].toString().isNotEmpty) {
        name = userMetadata['name'].toString();
      }

      List<String> roles = [];
      try {
        final userRolesResponse = await supabase
            .from('user_roles')
            .select('role_id, roles!inner (name), status')
            .eq('user_id', user.id)
            .eq('status', 'active');

        for (var roleEntry in userRolesResponse) {
          final role = roleEntry['roles'] as Map?;
          if (role != null && role['name'] != null) {
            roles.add(role['name'].toString());
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching roles in auth callback: $e');
      }

      bool rememberMe = true;
      try {
        final existingProfile = await SessionManager.getProfileByEmail(email);
        if (existingProfile != null && existingProfile.isNotEmpty) {
          rememberMe = existingProfile['rememberMe'] as bool? ?? true;
        }
      } catch (e) {
        debugPrint('⚠️ Error checking existing profile, defaulting rememberMe=true: $e');
      }

      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: name,
        photo: photoUrl ?? '',
        roles: roles,
        rememberMe: rememberMe,
        refreshToken: session?.refreshToken,
        accessToken: session?.accessToken,
        provider: provider,
        termsAcceptedAt: DateTime.now(),
        privacyAcceptedAt: DateTime.now(),
      );

      if (rememberMe) {
        await SessionManager.setRememberMe(true);
      }

      debugPrint(
        '✅ Profile saved from auth callback for: $email (rememberMe: $rememberMe, roles: $roles)',
      );
    } catch (e) {
      debugPrint('❌ Error saving profile in auth callback: $e');
    }
  }

  Future<void> _handleDefaultCallback() async {
    setState(() => _status = 'Completing authentication...');

    try {
      await supabase.auth.refreshSession();

      final user = supabase.auth.currentUser;

      if (user != null) {
        await _handleSuccessfulAuth(user);
      } else {
        setState(() {
          _status = 'Authentication failed - No user found';
          _processing = false;
          _hasError = true;
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          context.go('/login');
        }
      }
    } catch (e) {
      debugPrint('Default callback error: $e');

      setState(() {
        _status = 'Authentication failed';
        _processing = false;
        _hasError = true;
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
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (kDebugMode) {
        print('Password recovery flow:');
        print('   Session: ${session?.accessToken != null}');
        print('   User authenticated: ${user != null}');
      }

      if (session != null && user != null) {
        setState(() => _status = 'Please set your new password');

        if (kDebugMode) {
          print('Recovery successful, navigating to reset form');
        }

        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          context.go('/reset-password', extra: {'email': user.email});
        }
      } else {
        final uri = Uri.base;
        final email = uri.queryParameters['email'];

        setState(() {
          _status = 'Please enter your new password';
          _processing = false;
        });

        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          context.go('/reset-password', extra: {'email': email});
        }
      }
    } catch (e) {
      if (kDebugMode) print('Password recovery error: $e');

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
      await supabase.auth.refreshSession();

      final user = supabase.auth.currentUser;

      if (user != null && user.emailConfirmedAt != null) {
        setState(() => _status = 'Email verified successfully!');

        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          context.go(
            '/',
            extra: {
              'showMessage': true,
              'message': 'Email verified successfully!',
            },
          );
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

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        if (errorCode == 'otp_expired' || error == 'access_denied') {
          // context.go('/verify-invalid');
        } else {
          context.go('/login', extra: {'error': message});
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final errorColor = context.errorColor;
    final cardColor = context.cardColor;
    final successColor = context.successColor;

    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    final double maxWidth = isWeb ? 400 : 300;

    // Status color
    final statusColor = _processing
        ? primaryColor
        : _hasError
        ? errorColor
        : successColor;

    final statusBgColor = _processing
        ? primaryColor.withValues(alpha: 0.1)
        : _hasError
        ? errorColor.withValues(alpha: 0.1)
        : successColor.withValues(alpha: 0.1);

    final statusIcon = _processing
        ? null
        : _hasError
        ? Icons.error_outline_rounded
        : Icons.check_circle_rounded;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: Container(
            width: maxWidth,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusBgColor,
                    border: Border.all(
                      color: statusColor,
                      width: 2,
                    ),
                  ),
                  child: _processing
                      ? CircularProgressIndicator(
                          color: primaryColor,
                          strokeWidth: 3,
                        )
                      : Icon(
                          statusIcon!,
                          color: statusColor,
                          size: 40,
                        ),
                ),

                const SizedBox(height: 24),

                // Status Text
                Text(
                  _status ?? 'Processing...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _hasError ? errorColor : textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 8),

                if (_processing)
                  Text(
                    'Please wait...',
                    style: TextStyle(
                      color: secondaryTextColor,
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
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Go to Login'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}