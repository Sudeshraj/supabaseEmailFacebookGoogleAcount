import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void showResetPasswordDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF0F1820),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.lock_reset_rounded,
              color: Color(0xFF1877F3),
            ),
            SizedBox(width: 12),
            Text(
              'Reset Password',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'You will be redirected to password reset page where you can enter your email address to receive a reset link.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to reset password screen
              context.push('/reset-password');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1877F3),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    },
  );
}