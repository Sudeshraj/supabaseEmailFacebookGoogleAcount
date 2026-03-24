import 'package:flutter/material.dart';

/// Shows a custom alert dialog with optional actions
/// Returns:
/// - true if OK button is pressed
/// - false if Cancel button is pressed (when showCancelButton is true)
/// - null if dialog is dismissed (close button)
Future<bool?> showCustomAlert({
  required BuildContext context,
  required String title,
  required String message,
  bool isError = false,
  String buttonText = "OK",
  VoidCallback? onOk,
  VoidCallback? onClose,
  List<Widget>? customActions,
  IconData? buttonIcon,
  // NEW OPTIONAL PARAMETERS (won't affect old code)
  bool showCancelButton = false,
  String cancelButtonText = "Cancel",
  VoidCallback? onCancel,
}) async {
  // Prevent multiple dialogs
  if (ModalRoute.of(context)?.isCurrent != true) return null;

  final result = await showDialog<bool>(
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
        buttonIcon: buttonIcon,
        showCancelButton: showCancelButton,
        cancelButtonText: cancelButtonText,
        onCancel: onCancel,
      );
    },
  );
  
  return result;
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
  final IconData? buttonIcon;
  final bool showCancelButton;
  final String cancelButtonText;
  final VoidCallback? onCancel;

  const _CustomAlertDialog({
    required this.title,
    required this.message,
    required this.isError,
    required this.buttonText,
    this.onOk,
    this.onClose,
    this.customActions,
    this.buttonIcon,
    this.showCancelButton = false,
    this.cancelButtonText = "Cancel",
    this.onCancel,
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
                      color: Colors.black.withValues(alpha: 0.2),
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
                              color: primaryColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isError 
                                  ? Icons.error_outline 
                                  : Icons.check_circle_outline,
                              color: primaryColor,
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
                            // Buttons Row (Cancel + OK)
                            if (showCancelButton) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.grey[600],
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                          horizontal: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).pop(false);
                                        onCancel?.call();
                                      },
                                      child: Text(
                                        cancelButtonText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                          horizontal: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).pop(true);
                                        onOk?.call();
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (buttonIcon != null) ...[
                                            Icon(
                                              buttonIcon,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Text(
                                            buttonText,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // Default single button (old behavior)
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 32,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop(null);
                                    onOk?.call();
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (buttonIcon != null) ...[
                                        Icon(
                                          buttonIcon,
                                          size: 20,
                                          color: primaryColor,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        buttonText,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    // Close button (only for dialogs without custom actions and without cancel button)
                    if (customActions == null && !showCancelButton)
                      Positioned(
                        right: 12,
                        top: 12,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop(null);
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
                              color: titleColor.withValues(alpha: 0.6),
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