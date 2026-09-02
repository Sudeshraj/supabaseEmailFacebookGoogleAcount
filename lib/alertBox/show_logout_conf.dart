import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

void showLogoutConfirmation(
  BuildContext context, {
  required VoidCallback onLogoutConfirmed,
}) {
  final isDark = context.isDarkMode;
  final textColor = context.textColor;
  final secondaryTextColor = context.secondaryTextColor;
  final errorColor = context.errorColor;

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E2A38) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        'Logout',
        style: TextStyle(
          color: textColor,  // ✅ Used
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        'Are you sure you want to logout?',
        style: TextStyle(
          color: secondaryTextColor,  // ✅ Used
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: secondaryTextColor,  // ✅ Used
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onLogoutConfirmed();
          },
          child: Text(
            'Logout',
            style: TextStyle(
              color: errorColor,  // ✅ Used
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}