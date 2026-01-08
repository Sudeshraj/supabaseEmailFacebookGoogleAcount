import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// login, verified email alert
Future<void> showCustomAlert(
  BuildContext context, {
  required String title,
  required String message,
  bool isError = false,
  String buttonText = "OK",
  VoidCallback? onOk,
  VoidCallback? onClose,

  // 🔥 REMOVED FEATURE: showEmailButton, userEmail
}) async {
  final screenWidth = MediaQuery.of(context).size.width;
  final isWeb = screenWidth > 600;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 420 : double.infinity),
          child: Dialog(
            backgroundColor: const Color(0xFF121A24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        isError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: isError
                            ? Colors.redAccent
                            : const Color(0xFF4CAF50),
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 🔥 ONLY ONE BUTTON NOW (OK)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isError
                                ? Colors.redAccent
                                : const Color(0xFF1877F3),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            if (onOk != null) onOk();
                          },
                          child: Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // CLOSE ICON (top corner)
                Positioned(
                  right: -6,
                  top: -6,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      if (onClose != null) onClose();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> openEmailApp(BuildContext context, String? userEmail) async {
  try {
    Uri? emailUri;

    if (kIsWeb) {
      final domain = userEmail?.split('@').last.toLowerCase() ?? '';
      if (domain.contains('gmail')) {
        emailUri = Uri.parse('https://mail.google.com/mail/u/0/#inbox');
      } else if (domain.contains('yahoo')) {
        emailUri = Uri.parse('https://mail.yahoo.com/');
      } else if (domain.contains('outlook') ||
          domain.contains('hotmail') ||
          domain.contains('live')) {
        emailUri = Uri.parse('https://outlook.live.com/mail/inbox');
      } else {
        emailUri = Uri.parse('https://mail.google.com/');
      }

      await launchUrl(emailUri, mode: LaunchMode.platformDefault);
    } else if (Platform.isAndroid || Platform.isIOS) {
      emailUri = Uri(scheme: 'mailto');

      if (!await canLaunchUrl(emailUri)) {
        emailUri = Uri.parse('https://mail.google.com/');
      }

      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    } else {
      emailUri = Uri(scheme: 'mailto');
      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open your email app. Please open manually."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }
}
