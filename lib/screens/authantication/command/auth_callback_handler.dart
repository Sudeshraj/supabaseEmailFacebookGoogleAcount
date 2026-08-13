import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/session_manager.dart';
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
        print(' Processing auth callback...');
        print('   Full URL: ${uri.toString()}');
        print('   Query Parameters: ${uri.queryParameters}');
        print('   Fragment: ${uri.fragment}');
        print('   Path: ${uri.path}');
      }

      setState(() => _status = 'Processing authentication...');

      // **MAJOR FIX**: Use try-catch for getSessionFromUrl with better error handling
      bool sessionProcessed = false;

      try {
        // Check if this looks like a Supabase auth URL
        final hasAuthParams =
            uri.queryParameters.containsKey('access_token') ||
            uri.queryParameters.containsKey('refresh_token') ||
            uri.queryParameters.containsKey('type') ||
            uri.toString().contains('token=') ||
            uri.fragment.contains('access_token');

        if (hasAuthParams) {
          debugPrint('Supabase auth URL detected, calling getSessionFromUrl');

          // IMPORTANT: Parse fragment if it contains tokens
          String urlToProcess = uri.toString();

          // If tokens are in fragment (common with OAuth), move them to query params
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

      // **IMPORTANT**: Handle GoRouter query parameters from deep link
      // Get parameters from GoRouter state if available
      if (!mounted) return;
      final state = GoRouterState.of(context);
      final goRouterParams = state.uri.queryParameters;

      if (goRouterParams.isNotEmpty && kDebugMode) {
        debugPrint('   GoRouter params: $goRouterParams');
      }

      // Combine both parameter sources
      final allParams = {...uri.queryParameters, ...goRouterParams};

      // Handle errors FIRST (from any source)
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

      // If session was processed successfully, handle success
      if (sessionProcessed && session != null && user != null) {
        await _handleSuccessfulAuth(user);
        return;
      }

      // Handle specific callback types
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
          // Default handler for OAuth or general auth
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

    // ✅ FIX: Web OAuth (සහ mobile browser-fallback OAuth) callback
    // එකෙන් ආපු users ලාට profile එක local SessionManager storage
    // එකට save කරනවා - SignInScreen එකේ _saveOAuthProfile() එකේ
    // කරන දේම. මේක නැතුව Continue screen, Remember Me, සහ
    // auto-login කිසිවක් web OAuth users ලාට වැඩ කරන්නේ නෑ.
    if (user != null && user.email != null) {
      await _saveProfileAfterOAuthCallback(user);
    }

    await Future.delayed(const Duration(seconds: 1));

    // ✅ CLEANUP: '_checkIfNeedsProfileSetup()' කියන hardcoded-false
    // dead code එක අයින් කළා. Profile-completion check එක ONE
    // PLACE එකකින් විතරයි කරන්න ඕන - AppState._updateUserProfile()
    // + main.dart router redirect() (appState.profileCompleted).
    // ඒක duplicate කරන්න ගියොත්, දෙතැන කවදාහරි sync නොවී conflicting
    // redirect logic එකක් හැදෙන්න පුළුවන් (කලින් auto-restore bug
    // එක හැදුනේත් මේ විදිහටමයි). Router එකම හරි තැනට
    // (dashboard/reg/role-selector/recoverable-roles) route කරයි.
    if (!mounted) return;
    context.go(
      '/',
      extra: {'showMessage': true, 'message': 'Welcome back!'},
    );
  }

  /// ✅ Web OAuth (සහ mobile browser-fallback OAuth) callback එකෙන්
  /// ආපු users ලාට profile එක local SessionManager storage එකට
  /// save කරනවා - SignInScreen එකේ _saveOAuthProfile() එකේ කරන
  /// දේම. මේක නැතුව Continue screen, Remember Me, සහ auto-login
  /// කිසිවක් web OAuth users ලාට වැඩ කරන්නේ නෑ.
  Future<void> _saveProfileAfterOAuthCallback(User user) async {
    try {
      final email = user.email!;
      final session = supabase.auth.currentSession;
      final userMetadata = user.userMetadata ?? {};
      final appMetadata = user.appMetadata;

      // Provider එක ගන්නවා
      String provider = 'email';
      if (appMetadata['provider'] != null) {
        provider = appMetadata['provider'].toString();
      } else if (userMetadata['provider'] != null) {
        provider = userMetadata['provider'].toString();
      }

      // Photo url
      String? photoUrl;
      if (userMetadata['avatar_url'] != null &&
          userMetadata['avatar_url'].toString().isNotEmpty) {
        photoUrl = userMetadata['avatar_url'].toString();
      } else if (userMetadata['picture'] != null &&
          userMetadata['picture'].toString().isNotEmpty) {
        photoUrl = userMetadata['picture'].toString();
      }

      // Display name
      String name = email.split('@').first;
      if (userMetadata['full_name'] != null &&
          userMetadata['full_name'].toString().isNotEmpty) {
        name = userMetadata['full_name'].toString();
      } else if (userMetadata['name'] != null &&
          userMetadata['name'].toString().isNotEmpty) {
        name = userMetadata['name'].toString();
      }

      // ✅ Active roles fetch කරනවා (_saveOAuthProfile එකේ කරන විදිහටම)
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

      // ═══════════════════════════════════════════════════════════
      // 🔥 FIX: rememberMe default handling.
      //
      // Web OAuth callback එකේදී SignInScreen එකේ dialog එක
      // (Remember Me checkbox) bypass වෙනවා - browser redirect
      // එකකින් page reload එකක් වෙන නිසා, ඒ dialog එකේ user
      // ගත්ත තීරණය මේ callback screen එකට කවදාවත් pass වෙන්නේ
      // නෑ.
      //
      // කලින් තිබ්බ code එකේ:
      //   `SessionManager.isRememberMeEnabled()` කියලා GLOBAL
      //   setting එකක් කියෙව්වා. First-time user කෙනෙක්ට (කිසිම
      //   profile එකක් තාම save වෙලා නැති කෙනෙක්ට) මේ global
      //   setting එකේ default එක 'false'. rememberMe==false නම්
      //   SessionManager.saveUserProfile() එකේ:
      //       if (rememberMe) { profiles.add(profileData); }
      //   කියන check එකෙන් - profile එකම local storage එකට
      //   කිසිසේත් save වෙන්නේ නැහැ! ඒ කියන්නේ web OAuth එකෙන්
      //   පළමු වතාවට login කරන කෙනාගේ profile එකම හදිසියේම
      //   අතුරුදහන් වුනා (Continue screen, auto-login කිසිවක්
      //   ඒ user ට වැඩ කරන්නේ නෑ).
      //
      // FIX: existing profile එකක් තියෙනවා නම් ඒකේ saved
      // preference එකම respect කරනවා. නැත්නම් (පළමු වතාවේ user
      // කෙනෙක් නම්) default 'true' - මොකද 'Remember Me' කියන
      // core purpose එකම, පළමු වතාවේම profile එක save කරගැනීමයි.
      // ═══════════════════════════════════════════════════════════
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

      // ✅ rememberMe true නම් auto-login/continue-screen flow
      // එකට අවශ්‍ය current-user pointer එකත් මෙතනින්ම set කරනවා
      // (SessionManager.saveUserProfile() එක ඇතුළතින්ම මේක කරනවා
      // නම් duplicate වෙයි - නමුත් explicit කරන එක safe).
      if (rememberMe) {
        await SessionManager.setRememberMe(true);
      }

      debugPrint(
        '✅ Profile saved from auth callback for: $email (rememberMe: $rememberMe, roles: $roles)',
      );
    } catch (e) {
      debugPrint('❌ Error saving profile in auth callback: $e');
      // Non-fatal - user ට login කරන්න පුළුවන්, next login එකේදී
      // profile sync වෙයි (SessionManager rememberMe logic එකෙන්)
    }
  }

  Future<void> _handleDefaultCallback() async {
    setState(() => _status = 'Completing authentication...');

    try {
      // ═══════════════════════════════════════════════════════════
      // 🔥 NOTE: මේ path එක run වෙන්නේ 'sessionProcessed == false'
      // වුනු විට විතරයි (i.e. getSessionFromUrl() fail වුනා /
      // auth params නොතිබුනා). ඒ අවස්ථාවේ Supabase client එකේම
      // දැනටමත් session එකක් තියෙනවා නම් විතරයි මේ no-argument
      // refreshSession() එක success වෙන්නේ (refresh token එකක්
      // explicit විදිහට අපිට මෙතන නෑ - Uri.base එකෙන් session
      // සකසුනා නම් client එකේ already තියෙන session එකෙන්මයි
      // refresh වෙන්නේ). මේක web browser-redirect callback
      // path එකක් නිසා safe.
      // ═══════════════════════════════════════════════════════════
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
      debugPrint('Default callback error: $e');
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
        print('Password recovery flow:');
        print('   Session: ${session?.accessToken != null}');
        print('   User authenticated: ${user != null}');
      }

      // Check if user is authenticated (session exists)
      if (session != null && user != null) {
        // User is authenticated, navigate to password reset form
        setState(() => _status = 'Please set your new password');

        if (kDebugMode) {
          print('Recovery successful, navigating to reset form');
        }

        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          context.go('/reset-password', extra: {'email': user.email});
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
      // Refresh session to verify email
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
          context.go('/login', extra: {'error': message});
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
                      ? const Color(0xFF1877F3).withValues(alpha: 0.1)
                      : _hasError
                      ? const Color(0xFFF44336).withValues(alpha: 0.1)
                      : const Color(0xFF4CAF50).withValues(alpha: 0.1),
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
                    color: Colors.white.withValues(alpha: 0.6),
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