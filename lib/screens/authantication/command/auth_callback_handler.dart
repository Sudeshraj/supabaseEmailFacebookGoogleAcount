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

  // ============================================================
  // ✅ NEW: pre-processed result from main.dart's
  // _establishSessionFromUri(), which already ran
  // getSessionFromUrl() against the FULL redirect URI (query AND
  // fragment) before this screen was ever built. This screen no
  // longer parses Uri.base or calls getSessionFromUrl() itself —
  // that logic was duplicated and, on mobile, Uri.base was
  // meaningless (it's a web-only concept), so session processing
  // silently no-op'd there every time.
  // ============================================================
  final String? preProcessedStatus; // 'success' | 'error' | 'none' | null
  final String? preProcessedType;   // 'signup' | 'recovery' | 'magiclink' | ...
  final String? preProcessedUserId;
  final String? preProcessedEmail;

  const AuthCallbackHandlerScreen({
    super.key,
    this.code,
    this.error,
    this.errorCode,
    this.errorDescription,
    this.preProcessedStatus,
    this.preProcessedType,
    this.preProcessedUserId,
    this.preProcessedEmail,
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

  // ============================================================
  // ✅ REWRITTEN: this used to manually parse Uri.base (web-only,
  // meaningless on mobile) and call getSessionFromUrl() itself,
  // duplicating and half-overlapping the logic that now lives
  // entirely in main.dart's _establishSessionFromUri(). This
  // screen's only job now is to read the already-classified
  // result (widget.preProcessedStatus/Type) and decide what to
  // show / where to go next — no URL parsing, no direct session
  // establishment calls.
  // ============================================================
  Future<void> _processAuthCallback() async {
    try {
      if (kDebugMode) {
        print('🔎 Processing auth callback...');
        print('   preProcessedStatus: ${widget.preProcessedStatus}');
        print('   preProcessedType: ${widget.preProcessedType}');
        print('   preProcessedUserId: ${widget.preProcessedUserId}');
        print('   preProcessedEmail: ${widget.preProcessedEmail}');
        print('   widget.error: ${widget.error}');
        print('   widget.errorCode: ${widget.errorCode}');
      }

      setState(() => _status = 'Processing authentication...');

      // ✅ An error (whether it came from the raw query string on a
      // direct link, or was classified upstream by
      // _establishSessionFromUri()) always takes priority — the
      // route builder in main.dart already merges both sources into
      // widget.error/errorCode/errorDescription, so checking these
      // here covers both cases.
      if (widget.error != null || widget.errorCode != null) {
        _handleAuthError(widget.error ?? widget.errorDescription, widget.errorCode);
        return;
      }

      final preStatus = widget.preProcessedStatus;

      if (preStatus == 'success') {
        // Session was already established upstream. Re-check locally
        // just to be safe (Supabase's client keeps this in sync
        // automatically after getSessionFromUrl(), but a defensive
        // refresh costs little and guards against edge-case timing
        // issues).
        var user = supabase.auth.currentUser;
        if (user == null) {
          try {
            final refreshed = await supabase.auth.refreshSession();
            user = refreshed.user;
          } catch (e) {
            debugPrint('⚠️ Could not refresh session after pre-processed success: $e');
          }
        }

        switch (widget.preProcessedType) {
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
            if (user != null) {
              await _handleSuccessfulAuth(user);
            } else {
              await _handleDefaultCallback();
            }
            break;
        }
        return;
      }

      // preStatus == 'none' (no token found upstream at all, e.g.
      // someone opened /auth/callback directly) or null (this screen
      // was reached some other way) — fall back to checking whatever
      // session already exists locally.
      await _handleDefaultCallback();
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
        // ✅ No session yet — fall back to the pre-processed email
        // (from main.dart's upstream processing) instead of Uri.base,
        // which is meaningless on mobile.
        final email = widget.preProcessedEmail;

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