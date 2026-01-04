import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/functions/delete_user.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/authantication/command/registration_flow.dart';
import 'package:flutter_application_1/screens/authantication/command/not_you.dart';
import 'package:flutter_application_1/screens/authantication/command/splash.dart';
import 'package:flutter_application_1/screens/authantication/command/email_verify_checker.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/screens/commands/alertBox/reset_password_onfirm.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';
import 'session_manager.dart';

class SaveUser {
  final SupabaseClient supabase = Supabase.instance.client;

  // =========================================================================================
  // RLS-SAFE WRITE using SECURITY DEFINER FUNCTION (RPC)
  // =========================================================================================
  Future<void> safeWriteProfile({
    required String userId,
    required String roleName,
    required String displayName,
    Map<String, dynamic>? extraData,
  }) async {
    int retries = 0;
    while (retries < 3) {
      try {
        await supabase.rpc(
          'create_user_profile',
          params: {
            'p_user_id': userId,
            'p_role_name': roleName,
            'p_display_name': displayName,
            'p_extra': extraData ?? {},
          },
        );
        return;
      } catch (e) {
        // Handle duplicate profile
        if (e.toString().contains('PROFILE_EXISTS')) {
          debugPrint('⚠️ Profile already exists for user $userId');
          return;
        }
        retries++;
        if (retries == 3) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  // =========================================================================================
  // REGISTER ACCOUNT (Supabase Auth)
  // =========================================================================================
  Future<AuthResponse> registerAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'name': displayName},
       // emailRedirectTo: 'https://myapp.com/verify-email' // live
      emailRedirectTo: kIsWeb
          ? 'https://myapp.com/verify-email'
          : 'myapp://verify-email',
    );

    final user = res.user;
    if (user == null) {
      throw Exception("Registration failed.");
    }

    // 🔑 Existing user detection (Supabase official behavior)
    if (user.identities?.isEmpty ?? true) {
      throw const AuthException('ACCOUNT_EXISTS');
    }

    return res;
  }

  // =========================================================================================
  // CREATE PROFILE (call RPC safely)
  // =========================================================================================
  Future<void> createProfile({
    required String userId,
    required String roleName,
    required String displayName,
    Map<String, dynamic>? extraData,
  }) async {
    // final session = supabase.auth.currentSession;
    // if (session == null) {
    //   throw const AuthException('NO_SESSION');
    // }

    await safeWriteProfile(
      userId: userId,
      roleName: roleName,
      displayName: displayName,
      extraData: extraData,
    );
  }

  // =========================================================================================
  // REGISTER NEW USER WITH ROLE (FULL FLOW)
  // =========================================================================================
  Future<void> registerUserWithRole(
    BuildContext context, {
    required String role,
    required String email,
    required String password,
    required String displayName,
    Map<String, dynamic>? extraData,
  }) async {
    LoadingOverlay.show(context, message: "Creating your $role account...");

    try {
      // 1️⃣ Register auth user
      final res = await registerAccount(
        email: email,
        password: password,
        displayName: displayName,
      );

      final user = res.user!;

      // 2️⃣ Create profile ONLY for new users
      await createProfile(
        userId: user.id,
        roleName: role,
        displayName: displayName,
        extraData: extraData,
      );

      // 3️⃣ Save locally
      await SessionManager.saveProfile(
        email: email,
        name: displayName,
        password: password,
        roles: [role],
        photo: null,
      );

      LoadingOverlay.hide();

      if (!context.mounted) return;

      // 4️⃣ Navigate (GoRouter-safe)
      context.go('/verify-email');
    }
    // 🔁 Existing account → login flow
    on AuthException catch (e) {
      LoadingOverlay.hide();
      if (!context.mounted) return;

      if (e.message == 'ACCOUNT_EXISTS') {
        return handleEmailAlreadyInUse(context, email, password);
      }

      await showCustomAlert(
        context,
        title: "Registration Failed",
        message: e.message,
        isError: true,
      );
    }
    // ❌ Unexpected errors
    catch (e) {
      LoadingOverlay.hide();
      if (!context.mounted) return;

      await showCustomAlert(
        context,
        title: "Registration Failed",
        message: e.toString(),
        isError: true,
      );
    }
  }

  // =========================================================================================
  // ADD NEW PROFILE FOR EXISTING USER
  // =========================================================================================
  Future<void> addNewProfileForExistingUser(
    BuildContext context, {
    required String role,
    required String displayName,
    Map<String, dynamic>? extraData,
  }) async {
    LoadingOverlay.show(context, message: "Creating your $role profile...");

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception("No logged-in user found. Please sign in first.");
      }

      final email = currentUser.email ?? '';
      final profiles = await SessionManager.getProfiles();

      String existingPassword = '';
      if (profiles.isNotEmpty) {
        final firstProfile = profiles.firstWhere(
          (p) => p['email'] == email,
          orElse: () => {},
        );
        if (firstProfile.isNotEmpty) {
          final existingRole = firstProfile['role'];
          existingPassword =
              await SessionManager.getPassword(email, existingRole) ?? '';
        }
      }

      await safeWriteProfile(
        userId: currentUser.id,
        roleName: role,
        displayName: displayName,
        extraData: extraData,
      );

      await SessionManager.saveProfile(
        email: email,
        name: displayName,
        password: existingPassword,
        roles: [role],
        photo: null,
      );

      LoadingOverlay.hide();

      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EmailVerifyChecker()),
      );
    } catch (e) {
      LoadingOverlay.hide();
      await showCustomAlert(
        context,
        title: "Error",
        message: e.toString(),
        isError: true,
      );
    }
  }

  // =========================================================================================
  // HANDLE EMAIL ALREADY REGISTERED
  // =========================================================================================
  Future<void> handleEmailAlreadyInUse(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user!;
      final isVerified = user.emailConfirmedAt != null;

      final profiles = await supabase
          .from('profiles')
          .select('roles(name)')
          .eq('id', user.id);

      final roles = profiles
          .map<String>((e) => e['roles']['name'].toString())
          .toList();

      if (!context.mounted) return;

      if (isVerified) {
        await handleVerifiedFlow(context, user, email, roles);
      } else {
        await handleNotVerifiedFlow(context, user, email, roles);
      }
    } catch (_) {
      if (!context.mounted) return;
      await showCustomAlert(
        context,
        title: "Email Already Registered",
        message: "Wrong password. Use Forgot Password.",
        isError: true,
      );
    }
  }

  // =========================================================================================
  // VERIFIED FLOW
  // =========================================================================================
  Future<void> handleVerifiedFlow(
    BuildContext context,
    User existUser,
    String email,
    List<String> roles,
  ) async {
    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NotYouScreen(
          email: email,
          name: existUser.userMetadata?['name'] ?? "",
          photoUrl: "",
          roles: roles,
          buttonText: "Change Password",
          page: 'signup',
          onNotYou: () async {
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            await showResetPasswordConfirmDialog(
              nav.overlay!.context,
              email: email,
            );
          },
          onContinue: () async {
            await supabase.auth.signOut();
            navigatorKey.currentState?.pushReplacement(
              MaterialPageRoute(builder: (_) => SplashScreen()),
            );
          },
        ),
      ),
    );
  }

  // =========================================================================================
  // NOT VERIFIED FLOW
  // =========================================================================================
  Future<void> handleNotVerifiedFlow(
    BuildContext context,
    User existUser,
    String email,
    List<String> roles,
  ) async {
    if (!context.mounted) return;
    final uid = existUser.id;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NotYouScreen(
          email: email,
          name: existUser.userMetadata?['name'] ?? "",
          photoUrl: "",
          roles: roles,
          buttonText: "Not You?",
          page: 'signup',
          onNotYou: () async {
            final nav = navigatorKey.currentState;
            if (nav == null) return;

            final dialogCtx = nav.overlay!.context;

            await showCustomAlert(
              dialogCtx,
              title: "Delete Account?",
              message: "Are you sure you want to delete this profile?",
              isError: true,
              buttonText: "Delete",
              onOk: () async {
                final success = await AuthHelper.deleteUserUsingUid(uid);
                if (!success) {
                  messengerKey.currentState?.showSnackBar(
                    const SnackBar(content: Text("Delete failed. Try again.")),
                  );
                  return;
                }
                await Supabase.instance.client.auth.signOut();
                nav.pushReplacement(
                  MaterialPageRoute(builder: (_) => const RegistrationFlow()),
                );
              },
              onClose: () async {},
            );
          },
          onContinue: () async {
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            nav.pushReplacement(
              MaterialPageRoute(builder: (_) => EmailVerifyChecker()),
            );
          },
        ),
      ),
    );
  }
}
