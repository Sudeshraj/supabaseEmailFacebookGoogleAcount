import 'package:flutter/material.dart';


void showLogoutConfirmation(
  BuildContext context, {
  required VoidCallback onLogoutConfirmed,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E2A38),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      // title: const Text(
      //   'Logout',
      //   style: TextStyle(
      //     color: Colors.white,
      //     fontWeight: FontWeight.w600,
      //   ),
      // ),
      content: const Text(
        'Are you sure you want to logout?',
        style: TextStyle(
          color: Colors.white70,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Colors.white54,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context); // Close confirmation dialog
            onLogoutConfirmed(); // Execute the logout callback
          },
          child: const Text(
            'Logout',
            style: TextStyle(
              color: Color(0xFFEF5350),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}