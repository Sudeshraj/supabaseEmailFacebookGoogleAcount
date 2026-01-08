import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart'; // ✅ Import SessionManager

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
        
        // ✅ SAVE USER PROFILE TO SESSION MANAGER
        if (user != null) {
          await SessionManager.saveUserProfile(
            email: email,
            userId: user.id,
            name: email.split('@').first, // Default name
          );
          
          print('✅ Profile saved for new user: $email');
        }
        
        // 3️⃣ Save locally (Optional - if you still need this)
        // await SessionManagerto.saveEmailAndPassword(
        //   email: email,
        //   password: password,
        // );

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
  
  // ✅ OPTIONAL: Add this method for login flow too
  Future<void> loginUser(
    BuildContext context, {
    required String email,
    required String password,
  }) async {
    LoadingOverlay.show(context, message: "Logging in...");
    
    try {
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      final user = res.user;
      if (user != null) {
        // ✅ SAVE USER PROFILE TO SESSION MANAGER
        await SessionManager.saveUserProfile(
          email: email,
          userId: user.id,
          name: user.userMetadata?['full_name'] ?? email.split('@').first,
        );
        
        print('✅ Profile saved for logged in user: $email');
        
        LoadingOverlay.hide();
        
        if (!context.mounted) return;
        
        // Navigate to verify email or home based on state
        if (user.emailConfirmedAt == null) {
          context.go('/verify-email');
        } else {
          // AppState will handle redirection based on role
          context.go('/customer'); // Temporary, router will redirect
        }
      }
    } on AuthException catch (e) {
      LoadingOverlay.hide();
      if (!context.mounted) return;
      
      await showCustomAlert(
        context,
        title: "Login Failed",
        message: e.message,
        isError: true,
      );
    } catch (e) {
      LoadingOverlay.hide();
      if (!context.mounted) return;
      
      await showCustomAlert(
        context,
        title: "Login Failed",
        message: e.toString(),
        isError: true,
      );
    }
  }
}