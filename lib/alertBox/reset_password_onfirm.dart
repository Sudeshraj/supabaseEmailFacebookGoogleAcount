import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> showResetPasswordConfirmDialog(
  BuildContext context, {
  required String email,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF121A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Reset Password?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Send a password reset link to:\n\n$email',
          style: const TextStyle(color: Colors.white70),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1877F3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: email);

                if (!ctx.mounted) return;

                Navigator.of(ctx, rootNavigator: true).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset link sent!'),
                    backgroundColor: Colors.green,
                  ),
                );

                await FirebaseAuth.instance.signOut();
              } catch (e) {
                if (!ctx.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text(
              'Send Link',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    },
  );
}
