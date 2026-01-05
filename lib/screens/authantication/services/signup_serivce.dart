import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/services/singup_session.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';

class SaveUser {
  final SupabaseClient supabase = Supabase.instance.client;
  // =========================================================================================
  // REGISTER NEW USER WITH ROLE (FULL FLOW)

  Future<void> registerUser(
    BuildContext context, {
    required String email,
    required String password,
  }) async {
    LoadingOverlay.show(context, message: "Creating your account...");

    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        // emailRedirectTo: 'https://myapp.com/verify-email' // live
        emailRedirectTo: kIsWeb
            ? '${Uri.base.origin}/verify-email'
            : 'myapp://verify-email',
      );

      final user = res.user;
      if (user != null && user.identities != null && user.identities!.isEmpty) {
        // 🔴 Already existing user

        if (!context.mounted) return;

        await showCustomAlert(
          context,
          title: "Account already exists",
          message: 'Account already exists. Please log in.',
          isError: true,
        );
      } else {
        // 🟢 New user
        // 3️⃣ Save locally
        await SessionManagerto.saveEmailAndPassword(
          email: email,
          password: password,
        );

        LoadingOverlay.hide();

        if (!context.mounted) return;

        // 4️⃣ Navigate (GoRouter-safe)
        context.go('/verify-email');
      }
    }
    // 🔁 Existing account → login flow
    on AuthException catch (e) {
      LoadingOverlay.hide();
      if (!context.mounted) return;

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
}
