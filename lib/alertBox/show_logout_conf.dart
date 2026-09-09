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

  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: isDark ? const Color(0xFF1E2A38) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          maxHeight: screenHeight * 0.8,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Logout',
                style: TextStyle(
                  color: textColor, // ✅ Used
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to logout?',
                style: TextStyle(
                  color: secondaryTextColor, // ✅ Used
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: secondaryTextColor, // ✅ Used
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
                        color: errorColor, // ✅ Used
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}