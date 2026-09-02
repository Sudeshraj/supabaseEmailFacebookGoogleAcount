import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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
  bool showCancelButton = false,
  String cancelButtonText = "Cancel",
  VoidCallback? onCancel,
}) async {
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
    // ✅ All variables - ALL USED
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final errorColor = context.errorColor;
    final backgroundColor = context.backgroundColor;
    final surfaceColor = context.surfaceColor;
    final cardColor = context.cardColor;
    final dividerColor = context.dividerColor;

    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;
    final isWeb = screenWidth > 800;

    // Theme based colors
    final dialogBackgroundColor = isDark ? backgroundColor : Colors.white;
    final titleColor = isDark ? textColor : Colors.black87;
    final messageColor = isDark ? secondaryTextColor : Colors.black54;
    final dialogPrimaryColor = isError ? errorColor : primaryColor;

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
                  // ✅ backgroundColor used
                  color: dialogBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  // ✅ surfaceColor used in gradient
                  gradient: isDark ? null : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      surfaceColor.withValues(alpha: 0.3),
                    ],
                  ),
                  // ✅ cardColor used in border
                  border: Border.all(
                    color: isDark 
                        ? dividerColor.withValues(alpha: 0.3)
                        : dividerColor,
                    width: isWeb ? 1.5 : 1,
                  ),
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
                      padding: EdgeInsets.fromLTRB(
                        isWeb ? 32 : 24, 
                        32, 
                        isWeb ? 32 : 24, 
                        20
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Icon
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: dialogPrimaryColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              // ✅ surfaceColor used in border
                              border: Border.all(
                                color: surfaceColor.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Icon(
                              isError 
                                  ? Icons.error_outline 
                                  : Icons.check_circle_outline,
                              color: dialogPrimaryColor,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Title - ✅ textColor used
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isWeb ? 20 : 18,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Message - ✅ secondaryTextColor used
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isWeb ? 16 : 15,
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
                            if (showCancelButton) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        // ✅ secondaryTextColor used
                                        foregroundColor: secondaryTextColor,
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
                                        // ✅ primaryColor or errorColor used
                                        backgroundColor: dialogPrimaryColor,
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
                              // Default single button
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    // ✅ dialogPrimaryColor used
                                    foregroundColor: dialogPrimaryColor,
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
                                          color: dialogPrimaryColor,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        buttonText,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: isWeb ? 16 : 15,
                                          color: dialogPrimaryColor,
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

                    // Close button
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
                              color: isDark 
                                  ? secondaryTextColor.withValues(alpha: 0.1)
                                  : Colors.black12,
                              shape: BoxShape.circle,
                              // ✅ cardColor used in border
                              border: Border.all(
                                color: cardColor.withValues(alpha: 0.1),
                              ),
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