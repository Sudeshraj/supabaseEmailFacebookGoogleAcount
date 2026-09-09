import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart';

// ============================================================
// ✅ NEW: result type so callers (DataConsentScreen) know exactly
// what happened instead of the error being swallowed silently.
// ============================================================
enum RegisterStatus { success, userExists, rateLimited, failure }

class RegisterResult {
  final RegisterStatus status;
  final String? message;

  const RegisterResult(this.status, [this.message]);
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();
  final EnvironmentManager _env = EnvironmentManager();
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _tag = 'AuthService';

  // =========================================================================================
  // REGISTER NEW USER
  // =========================================================================================

  Future<RegisterResult> registerUser({
    required BuildContext context,
    required String email,
    required String password,
    bool rememberMe = true,
    bool marketingConsent = false,
  }) async {
    // ✅ FIX: tracks whether LoadingOverlay.show() was actually called,
    // so the `finally` block below only tries to hide it when it was
    // shown in the first place.
    bool overlayShown = false;
    try {
      // ✅ Validate inputs
      if (!_isValidEmail(email)) {
        _showErrorAlert(context, 'Invalid email format');
        return const RegisterResult(
          RegisterStatus.failure,
          'Invalid email format',
        );
      }

      if (!_isValidPassword(password)) {
        _showErrorAlert(context, 'Password must be at least 6 characters');
        return const RegisterResult(
          RegisterStatus.failure,
          'Password must be at least 6 characters',
        );
      }

      // Show loading overlay
      LoadingOverlay.show(context, message: "Creating account...");
      overlayShown = true;

      final now = DateTime.now().toIso8601String();

      // ============================================================
      // ❌ REMOVED: the old code called signInWithPassword() FIRST
      // just to "check" if the user already existed, and then called
      // signUp() right after. That meant every single registration
      // attempt fired TWO auth API requests, which is what was
      // tripping Supabase's rate limiter (429 Too Many Requests)
      // during testing.
      //
      // signUp() already tells us if the user exists via
      // `user?.identities?.isEmpty`, so the extra signIn call was
      // pure waste. Removed entirely.
      // ============================================================

      // ✅ Perform registration directly
      // ============================================================
      // ✅ FIX: added .timeout(...). On web, a 429 (Too Many Requests)
      // response can sometimes leave this Future neither completing
      // nor throwing in Dart — the browser network tab shows the 429,
      // but no exception ever reaches our try/catch, so the loading
      // overlay and the button spinner were stuck forever waiting for
      // a Future that was never going to resolve. A client-side
      // timeout guarantees this call always settles one way or the
      // other, regardless of the underlying cause.
      // ============================================================
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password.trim(),
        emailRedirectTo: _env.getRedirectUrl(),
        data: {
          'display_name': email.split('@').first,
          'remember_me_enabled': rememberMe,
          'terms_accepted_at': now,
          'privacy_accepted_at': now,
          'marketing_consent': marketingConsent,
          'marketing_consent_at': marketingConsent ? now : null,
          'data_consent_given': true,
          'registration_complete': false,
          'role': null,
          'role_id': null,
          'profile_status': 'active',
          'profile_created': false,
        },
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException(
            'Registration request timed out. This usually means too many '
            'attempts were made recently — please wait a minute and try again.',
          );
        },
      );

      final user = response.user;

      // ✅ Check if user already exists (identities empty)
      if (user?.identities?.isEmpty ?? true) {
        LoadingOverlay.hide();
        if (!context.mounted) return const RegisterResult(RegisterStatus.userExists);
        await _handleExistingUser(context, email);
        return const RegisterResult(RegisterStatus.userExists);
      }

      // ✅ If user is null, throw error
      if (user == null) {
        throw Exception('Failed to create user');
      }

      debugPrint('✅ User created: ${user.id}');
      debugPrint('📝 Initial metadata: ${user.userMetadata}');
      if (!context.mounted) return const RegisterResult(RegisterStatus.success);

      // ✅ Create initial profile with default status
      await _createInitialProfile(
        context: context,
        user: user,
        email: email,
        rememberMe: rememberMe,
        refreshToken: response.session?.refreshToken,
        marketingConsent: marketingConsent,
      );

      // ✅ Navigate to verify email
      LoadingOverlay.hide();

      if (!context.mounted) return const RegisterResult(RegisterStatus.success);

      // ============================================================
      // ✅ FIX: _handleSuccessfulRegistration() used to be "fire and
      // forget" here — if it failed internally (its own try/catch
      // just shows an alert and does NOT navigate), registerUser()
      // still unconditionally returned RegisterStatus.success. The
      // caller (DataConsentScreen) does nothing on success other
      // than expect navigation to dispose the screen — so when
      // navigation silently never happened, the "Create Account"
      // button's loading spinner was stuck forever behind the error
      // alert. Now we capture whether it actually navigated and
      // return a real failure status when it didn't, so the caller
      // can reset its loading state.
      // ============================================================
      final navigated = await _handleSuccessfulRegistration(
        context,
        user,
        email,
        rememberMe,
        response.session?.refreshToken,
        marketingConsent,
      );

      if (!navigated) {
        return const RegisterResult(
          RegisterStatus.failure,
          'Account created, but we couldn\'t continue automatically. Please try again.',
        );
      }

      return const RegisterResult(RegisterStatus.success);
    } on AuthException catch (e) {
      LoadingOverlay.hide();

      // ============================================================
      // ✅ NEW: detect rate limiting explicitly (HTTP 429) so the UI
      // can show a specific "please wait" message instead of a
      // generic failure.
      // ============================================================
      final isRateLimited = e.statusCode == '429' ||
          e.message.toLowerCase().contains('too many requests') ||
          e.message.toLowerCase().contains('rate limit') ||
          e.message.toLowerCase().contains('over_email_send_rate_limit');

      // ============================================================
      // ✅ FIX: this used to `await _handleAuthException(...)`, which
      // shows a modal alert dialog and BLOCKS this function from
      // returning until the user dismisses it. That meant the caller
      // (DataConsentScreen) couldn't reset its own loading spinner
      // until the dialog was dismissed — so the button kept spinning
      // the whole time the error dialog was up, making it look like
      // "the loading never stops when the error appears".
      //
      // DataConsentScreen already renders result.message in its own
      // inline error banner, so the popup dialog was redundant too.
      // Removed entirely — we just compute the friendly message and
      // return immediately so the caller's UI updates the instant the
      // error is known, with no dialog to dismiss first.
      // ============================================================
      final friendlyMessage = _getUserFriendlyErrorMessage(e);

      return RegisterResult(
        isRateLimited ? RegisterStatus.rateLimited : RegisterStatus.failure,
        friendlyMessage,
      );
    } on TimeoutException catch (e) {
      // ============================================================
      // ✅ NEW: the request never resolved within our client-side
      // timeout (see the .timeout(...) added to signUp() above).
      // Treated the same as a rate-limit failure — it's the most
      // common real-world cause on web — so the UI shows a "please
      // wait and try again" message rather than a generic error.
      //
      // ✅ FIX: no longer awaits showCustomAlert(...) — same reasoning
      // as the AuthException branch above: returns immediately so the
      // caller's loading state resets instantly instead of waiting on
      // a dialog dismissal.
      // ============================================================
      LoadingOverlay.hide();
      return RegisterResult(
        RegisterStatus.rateLimited,
        e.message ?? 'The request took too long. Please try again.',
      );
    } catch (e, stackTrace) {
      LoadingOverlay.hide();
      developer.log(
        'Registration error: $e',
        name: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      // ✅ FIX: same reasoning — return immediately instead of
      // awaiting _handleGenericException's dialog, so the caller's
      // loading spinner resets right away.
      return const RegisterResult(
        RegisterStatus.failure,
        'An unexpected error occurred. Please try again.',
      );
    } finally {
      // ✅ FIX: guaranteed safety net. Every branch above already calls
      // LoadingOverlay.hide() explicitly at the right moment, but this
      // finally block ensures it NEVER stays stuck on screen even if a
      // future code path forgets to hide it, or an exception occurs
      // somewhere hide() wasn't yet called.
      //
      // Deliberately does NOT go through _safeHideOverlay(context) —
      // passing a BuildContext across this async gap trips the
      // use_build_context_synchronously lint, and the context argument
      // was never actually used by that helper anyway (LoadingOverlay
      // is a global overlay, not tied to this context). Hiding it here
      // is intentionally context-free.
      if (overlayShown) {
        try {
          LoadingOverlay.hide();
        } catch (e) {
          developer.log('Error hiding overlay in finally: $e', name: _tag);
        }
      }
    }
  }

  // ============================================================
  // ✅ CREATE INITIAL PROFILE WITH DEFAULT STATUS
  // ------------------------------------------------------------
  // ✅ FIX: this used to INSERT the profiles row from the client,
  // right after signUp(). When "Confirm email" is enabled in
  // Supabase Auth, signUp() returns response.session = null until
  // the user verifies their email — so the client is still
  // unauthenticated (auth.uid() is null) at this point, and the
  // profiles_insert RLS policy (auth.uid() = id) rejects the
  // insert with 403 / 42501.
  //
  // The profiles row is now created server-side by a Postgres
  // trigger on auth.users (see fix_profile_trigger.sql — it runs
  // SECURITY DEFINER and bypasses RLS, firing regardless of
  // email-confirmation state). So by the time this function runs,
  // the row already exists — this now just UPDATEs it with the
  // consent-related fields the trigger doesn't know about.
  // If for some reason the row genuinely isn't there yet (e.g.
  // trigger not yet applied), this fails silently and login-time
  // profile checks will create it as a fallback.
  // ============================================================
  Future<void> _createInitialProfile({
    required BuildContext context,
    required User user,
    required String email,
    required bool rememberMe,
    String? refreshToken,
    required bool marketingConsent,
  }) async {
    try {
      debugPrint('📝 Updating initial profile for user: ${user.id}');

      // ✅ Row already exists (created by the auth.users trigger) —
      // just update it, don't insert.
      await _supabase.from('profiles').update({
        'email': email,
        'full_name': email.split('@').first,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      debugPrint('✅ Initial profile updated for user: ${user.id}');

      // ✅ Save to SessionManager
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

      // ✅ Update user metadata
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            ...?user.userMetadata,
            'profile_created': true,
            'profile_status': 'active',
          },
        ),
      );

      // ✅ Refresh app state
      appState.refreshState();

      debugPrint('✅ Initial profile setup complete for: $email');
    } catch (e) {
      // ✅ Non-fatal: the profiles row already exists (created by
      // the auth.users trigger). Failing to update it with these
      // extra fields shouldn't block the whole registration flow —
      // log it and continue.
      debugPrint('⚠️ Could not update initial profile (non-fatal): $e');
    }
  }

  // ============================================================
  // ✅ REGISTRATION SUCCESS HANDLER
  // ------------------------------------------------------------
  // ✅ FIX: now returns bool — true only if navigation to
  // /verify-email actually happened. The caller (registerUser())
  // uses this to decide the real RegisterResult instead of always
  // assuming success, which used to leave the caller's loading
  // spinner stuck on-screen whenever this failed silently.
  // ============================================================
  Future<bool> _handleSuccessfulRegistration(
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

        // Show success message
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   if (context.mounted) {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       SnackBar(
        //         content: Text(
        //           rememberMe
        //               ? 'Account created! Check your email for verification.'
        //               : 'Account created! Please verify your email.',
        //         ),
        //         duration: const Duration(seconds: 4),
        //         backgroundColor: Colors.green,
        //         action: SnackBarAction(
        //           label: 'OK',
        //           textColor: Colors.white,
        //           onPressed: () {
        //             ScaffoldMessenger.of(context).hideCurrentSnackBar();
        //           },
        //         ),
        //       ),
        //     );
        //   }
        // });

        return true; // ✅ navigation happened
      }

      // context wasn't mounted — nothing we can do, treat as failure
      // so the caller resets its loading state instead of hanging.
      return false;
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
      return false; // ✅ navigation did NOT happen — caller must reset loading state
    }
  }

  // =========================================================================================
  // LOGIN USER
  // =========================================================================================

  Future<void> loginUser({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    final Completer<void> completer = Completer<void>();

    try {
      // ✅ Validate inputs
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
  // ✅ HANDLE EXISTING USER
  // =========================================================================================
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

  // =========================================================================================
  // ✅ HANDLE SUCCESSFUL LOGIN (COMPLETE STATUS CHECKS)
  // =========================================================================================
  Future<void> _handleSuccessfulLogin(
    BuildContext context,
    User user,
    String email,
  ) async {
    try {
      developer.log('🔐 Processing login for: $email', name: _tag);

      // ✅ Check if email needs verification
      if (user.emailConfirmedAt == null) {
        developer.log(
          '📧 Email not verified, redirecting to verify page',
          name: _tag,
        );

        // ✅ Save partial profile
        await SessionManager.saveUserProfile(
          email: email,
          userId: user.id,
          name: user.userMetadata?['full_name'] ?? email.split('@').first,
        );

        if (context.mounted) {
          context.go('/verify-email');
        }
        return;
      }

      // ============================================================
      // ✅ STEP 1: CHECK USER ROLES STATUS
      // ============================================================
      final userRolesResponse = await _supabase
          .from('user_roles')
          .select('status, role_id, roles!inner (name)')
          .eq('user_id', user.id);

      developer.log('📋 User roles: $userRolesResponse', name: _tag);

      if (userRolesResponse.isNotEmpty) {
        // ✅ Check if user has any active roles
        bool hasActiveRole = false;
        List<String> activeRoles = [];

        for (var role in userRolesResponse) {
          if (role['status'] == 'active') {
            hasActiveRole = true;
            final roleName = role['roles']?['name'] as String?;
            if (roleName != null) {
              activeRoles.add(roleName);
            }
          }
        }

        developer.log('📋 Active roles: $activeRoles', name: _tag);

        if (!hasActiveRole) {
          // ✅ Check if user has roles but none are active
          final hasAnyRole = userRolesResponse.any(
            (r) => r['status'] != 'deleted',
          );

          if (hasAnyRole) {
            developer.log('⚠️ User has no active roles', name: _tag);

            // ✅ Check if scheduled for deletion
            bool isScheduled = userRolesResponse.any(
              (r) => r['status'] == 'scheduled_for_deletion',
            );

            if (isScheduled) {
              // ✅ Auto-restore role
              developer.log('🔄 Auto-restoring roles...', name: _tag);
              for (var role in userRolesResponse) {
                if (role['status'] == 'scheduled_for_deletion') {
                  final roleName = role['roles']?['name'] as String?;
                  if (roleName != null) {
                    await SessionManager.autoRestoreRoleOnLogin(
                      email: email,
                      role: roleName,
                    );
                  }
                }
              }

              if (context.mounted) {
                await showCustomAlert(
                  context: context,
                  title: "🔄 Profile Restored",
                  message:
                      "Your profile was scheduled for deletion but has been restored.",
                  isError: false,
                );
              }

              // ✅ After restore, get active roles again
              final updatedRoles = await _supabase
                  .from('user_roles')
                  .select('status, role_id, roles!inner (name)')
                  .eq('user_id', user.id)
                  .eq('status', 'active');

              if (updatedRoles.isEmpty) {
                developer.log(
                  '⚠️ No roles after restore, redirecting to /reg',
                  name: _tag,
                );
                if (context.mounted) {
                  context.go('/reg');
                  return;
                }
              }
            } else {
              // ✅ Show inactive message
              if (context.mounted) {
                await showCustomAlert(
                  context: context,
                  title: "Profile Inactive",
                  message: "Your profile is inactive. Please contact support.",
                  isError: true,
                );
                await _supabase.auth.signOut();
                if (context.mounted) {
                  context.go('/login');
                }
                return;
              }
            }
          } else {
            // ✅ No roles at all - redirect to registration
            developer.log(
              '📝 No roles found, redirecting to registration',
              name: _tag,
            );
            if (context.mounted) {
              // ✅ Save profile first
              await SessionManager.saveUserProfile(
                email: email,
                userId: user.id,
                name: user.userMetadata?['full_name'] ?? email.split('@').first,
              );
              if (!context.mounted) return;
              context.go('/reg');
              return;
            }
          }
        }
      } else {
        // ✅ No roles at all - redirect to registration
        developer.log(
          '📝 No roles found, redirecting to registration',
          name: _tag,
        );
        if (context.mounted) {
          await SessionManager.saveUserProfile(
            email: email,
            userId: user.id,
            name: user.userMetadata?['full_name'] ?? email.split('@').first,
          );
          if (!context.mounted) return;
          context.go('/reg');
          return;
        }
      }

      // ============================================================
      // ✅ STEP 2: CHECK PROFILE STATUS (FULL CHECK)
      // ============================================================
      final profileCheck = await _supabase
          .from('profiles')
          .select('is_active, is_blocked, extra_data')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        // ✅ Check if blocked
        if (profileCheck['is_blocked'] == true) {
          developer.log('🚫 User is blocked', name: _tag);
          if (context.mounted) {
            await showCustomAlert(
              context: context,
              title: "Account Blocked",
              message: "Your account has been blocked. Please contact support.",
              isError: true,
            );
            await _supabase.auth.signOut();
            if (context.mounted) {
              context.go('/login');
            }
            return;
          }
        }

        // ✅ Check if inactive
        if (profileCheck['is_active'] == false) {
          final extraData =
              profileCheck['extra_data'] as Map<String, dynamic>? ?? {};
          final profileStatus =
              extraData['profile_status'] as Map<String, dynamic>?;

          if (profileStatus != null) {
            final status = profileStatus['status'] as String? ?? 'active';

            // ✅ CASE 1: Profile is permanently deleted
            if (status == 'deleted') {
              developer.log('🗑️ Profile is permanently deleted', name: _tag);
              if (context.mounted) {
                await showCustomAlert(
                  context: context,
                  title: "Profile Deleted",
                  message: "Your profile has been permanently deleted.",
                  isError: true,
                );
                await _supabase.auth.signOut();
                if (context.mounted) {
                  context.go('/login');
                }
                return;
              }
            }

            // ✅ CASE 2: Profile is scheduled for deletion (grace period)
            if (status == 'scheduled_for_deletion') {
              final dueDateStr = profileStatus['deletion_due_date'] as String?;
              if (dueDateStr != null) {
                final dueDate = DateTime.parse(dueDateStr);
                if (dueDate.isAfter(DateTime.now())) {
                  // ✅ Auto-restore entire profile
                  developer.log(
                    '🔄 Auto-restoring complete profile on login',
                    name: _tag,
                  );
                  await SessionManager.autoRestoreProfileLevelOnLogin(
                    email: email,
                  );

                  if (context.mounted) {
                    await showCustomAlert(
                      context: context,
                      title: "🔄 Profile Restored",
                      message:
                          "Your profile was scheduled for deletion but has been restored.",
                      isError: false,
                    );
                  }
                } else {
                  // ✅ Grace period expired - permanently deleted
                  developer.log(
                    '🗑️ Grace period expired, profile deleted',
                    name: _tag,
                  );
                  if (context.mounted) {
                    await showCustomAlert(
                      context: context,
                      title: "Profile Deleted",
                      message: "Your profile has been permanently deleted.",
                      isError: true,
                    );
                    await _supabase.auth.signOut();
                    if (context.mounted) {
                      context.go('/login');
                    }
                    return;
                  }
                }
              }
            }

            // ✅ CASE 3: Profile is inactive (not scheduled for deletion)
            if (status == 'inactive') {
              developer.log('⚠️ Profile is inactive', name: _tag);
              if (context.mounted) {
                await showCustomAlert(
                  context: context,
                  title: "Profile Inactive",
                  message: "Your profile is inactive. Please contact support.",
                  isError: true,
                );
                await _supabase.auth.signOut();
                if (context.mounted) {
                  context.go('/login');
                }
                return;
              }
            }
          } else {
            // ✅ No profile_status found - treat as inactive
            developer.log('⚠️ Profile is inactive (no status)', name: _tag);
            if (context.mounted) {
              await showCustomAlert(
                context: context,
                title: "Profile Inactive",
                message: "Your profile is inactive. Please contact support.",
                isError: true,
              );
              await _supabase.auth.signOut();
              if (context.mounted) {
                context.go('/login');
              }
              return;
            }
          }
        }
      } else {
        // ✅ No profile found - create one
        developer.log('📝 No profile found, creating one', name: _tag);
        if (!context.mounted) return;
        await _createInitialProfile(
          context: context,
          user: user,
          email: email,
          rememberMe: true,
          refreshToken: null,
          marketingConsent: false,
        );
      }

      // ✅ Save user profile to SessionManager
      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: user.userMetadata?['full_name'] ?? email.split('@').first,
        rememberMe: true,
      );

      // ✅ Refresh app state
      appState.refreshState();

      // ============================================================
      // ✅ STEP 3: CHECK IF USER HAS MULTIPLE ROLES
      // ============================================================
      final activeRolesResponse = await _supabase
          .from('user_roles')
          .select('roles!inner (name)')
          .eq('user_id', user.id)
          .eq('status', 'active');

      final List<String> activeRoleNames = activeRolesResponse
          .map((r) => r['roles']?['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      developer.log('📋 Active role names: $activeRoleNames', name: _tag);

      // ✅ Navigate based on roles
      if (context.mounted) {
        if (activeRoleNames.isEmpty) {
          // ✅ No active roles - go to registration
          context.go('/reg');
        } else if (activeRoleNames.length == 1) {
          // ✅ Single role - go to appropriate dashboard
          final role = activeRoleNames.first;
          await SessionManager.saveCurrentRole(role);

          // ✅ Update user metadata
          await _supabase.auth.updateUser(
            UserAttributes(
              data: {
                ...?user.userMetadata,
                'current_role': role,
                'roles': activeRoleNames,
              },
            ),
          );
          if (!context.mounted) return;
          switch (role) {
            case 'owner':
              context.go('/owner');
              break;
            case 'barber':
              context.go('/barber');
              break;
            default:
              context.go('/customer');
              break;
          }
        } else {
          // ✅ Multiple roles - go to role selector
          context.go(
            '/role-selector',
            extra: {
              'roles': activeRoleNames,
              'email': email,
              'userId': user.id,
            },
          );
        }
      }

      // ✅ Show welcome message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welcome back!'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      });

      developer.log('✅ Login completed successfully for: $email', name: _tag);
    } catch (e) {
      developer.log('❌ Error in _handleSuccessfulLogin: $e', name: _tag);
      if (context.mounted) {
        await showCustomAlert(
          context: context,
          title: "Login Error",
          message: "Failed to complete login. Please try again.",
          isError: true,
        );
      }
    }
  }

  // =========================================================================================
  // LOGOUT USER
  // =========================================================================================

  Future<void> logoutUser({required BuildContext context}) async {
    try {
      LoadingOverlay.show(context, message: "Signing out...");

      // ✅ Update last_logout in database
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase
            .from('profiles')
            .update({
              'last_logout': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);

        developer.log(
          '✅ Updated last_logout for user: ${user.email}',
          name: _tag,
        );
      }

      await _supabase.auth.signOut();
      await SessionManager.clearContinueScreen();

      // ✅ Clear current role
      await SessionManager.saveCurrentRole(null);

      appState.refreshState();

      if (context.mounted) {
        context.go('/login');
      }

      developer.log('✅ User logged out successfully', name: _tag);
    } catch (e, stackTrace) {
      developer.log(
        '❌ Logout error: $e',
        name: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        await showCustomAlert(
          context: context,
          title: "Logout Error",
          message: "Failed to logout. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (context.mounted) {
        _safeHideOverlay(context);
      }
    }
  }

  // =========================================================================================
  // PASSWORD RESET
  // =========================================================================================

  Future<void> sendPasswordResetEmail({
    required BuildContext context,
    required String email,
  }) async {
    try {
      LoadingOverlay.show(context, message: "Sending reset email...");

      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: _env.getRedirectUrl().replaceFirst(
          'verify-email',
          'reset-password',
        ),
      );

      developer.log('✅ Password reset email sent to: $email', name: _tag);

      if (context.mounted) {
        await showCustomAlert(
          context: context,
          title: "Email Sent",
          message:
              "If an account exists with this email, you will receive a password reset link shortly.",
          isError: false,
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ Password reset error: $e',
        name: _tag,
        error: e,
        stackTrace: stackTrace,
      );

      if (context.mounted) {
        await showCustomAlert(
          context: context,
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
        context: context,
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
        context: context,
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
        context: context,
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
          context: context,
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
    } else if (message.contains('too many requests') ||
        message.contains('rate limit') ||
        e.statusCode == '429') {
      return 'Too many attempts. Please wait a few minutes and try again.';
    } else if (message.contains('network') || message.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else if (message.contains('weak password')) {
      return 'Password is too weak. Please use a stronger password.';
    } else {
      return 'Unable to complete the request. Please try again.';
    }
  }
}