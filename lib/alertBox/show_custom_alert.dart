import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

// ========================================================================
// CUSTOM ALERT DIALOG (Production Ready)
// ========================================================================

/// Shows a custom alert dialog with optional actions
Future<void> showCustomAlert({
  required BuildContext context,
  required String title,
  required String message,
  bool isError = false,
  String buttonText = "OK",
  VoidCallback? onOk,
  VoidCallback? onClose,
  List<Widget>? customActions,
}) async {
  // Prevent multiple dialogs
  if (ModalRoute.of(context)?.isCurrent != true) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (context) {
      return _CustomAlertDialog(
        title: title,
        message: message,
        isError: isError,
        buttonText: buttonText,
        onOk: onOk,
        onClose: onClose,
        customActions: customActions,
      );
    },
  );
}

// ========================================================================
// CUSTOM ALERT DIALOG WIDGET
// ========================================================================

class _CustomAlertDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool isError;
  final String buttonText;
  final VoidCallback? onOk;
  final VoidCallback? onClose;
  final List<Widget>? customActions;

  const _CustomAlertDialog({
    required this.title,
    required this.message,
    required this.isError,
    required this.buttonText,
    this.onOk,
    this.onClose,
    this.customActions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;

    // Colors based on theme and error state
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final messageColor = isDark ? Colors.white70 : Colors.black54;
    final primaryColor = isError 
        ? theme.colorScheme.error 
        : theme.primaryColor;
    final iconColor = isError 
        ? theme.colorScheme.error 
        : theme.colorScheme.primary;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isLargeScreen ? 420 : screenWidth * 0.9,
        ),
        child: Material(
          color: Colors.transparent,
          child: IntrinsicWidth(
            child: IntrinsicHeight(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Main content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Icon
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isError 
                                  ? Icons.error_outline 
                                  : Icons.check_circle_outline,
                              color: iconColor,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Title
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Message
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: messageColor,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Actions
                          if (customActions != null) ...[
                            ...customActions!,
                          ] else ...[
                            // Default OK button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 32,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  onOk?.call();
                                },
                                child: Text(
                                  buttonText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Close button (only for dialogs without custom actions)
                    if (customActions == null)
                      Positioned(
                        right: 12,
                        top: 12,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            onClose?.call();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: titleColor.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

