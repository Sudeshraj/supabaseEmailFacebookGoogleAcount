import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class PermissionDialog extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final String? customTitle;
  final String? customMessage;
  final bool showNotNow;

  const PermissionDialog({
    super.key,
    required this.onAllow,
    required this.onDeny,
    this.customTitle,
    this.customMessage,
    this.showNotNow = true,
  });

  @override
  Widget build(BuildContext context) {
    if (UniversalPlatform.isWeb) {
      return _buildWebDialog(context);
    }
    return _buildMobileDialog(context);
  }

  // ================================================================
  // WEB DIALOG
  // ================================================================
  Widget _buildWebDialog(BuildContext context) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final backgroundColor = context.backgroundColor;

    return AlertDialog(
      backgroundColor: isDark ? backgroundColor : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active,
              color: primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              customTitle ?? 'Enable Notifications?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        customMessage ??
        'Get notified about new bookings, appointment reminders, and special offers!',
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: secondaryTextColor,
        ),
      ),
      actions: _buildActions(context),
    );
  }

  // ================================================================
  // MOBILE DIALOG (Full)
  // ================================================================
  Widget _buildMobileDialog(BuildContext context) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? cardColor : Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const FaIcon(
                FontAwesomeIcons.bell,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              customTitle ?? '🔔 Stay Updated!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),

            // Message
            Text(
              customMessage ??
              'Get instant notifications about:\n'
              '• New booking requests\n'
              '• Appointment reminders\n'
              '• Special offers & promotions',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: secondaryTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                if (showNotNow) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDeny,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: isDark
                              ? Colors.grey[700]!
                              : const Color(0xFFDDDDDD),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        foregroundColor: isDark
                            ? Colors.grey[400]
                            : const Color(0xFF999999),
                      ),
                      child: const Text(
                        'Not Now',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                Expanded(
                  child: ElevatedButton(
                    onPressed: onAllow,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: primaryColor.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Allow',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // iOS Settings note
            if (UniversalPlatform.isIOS)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: isDark ? Colors.grey[500] : Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'You can change this later in Settings',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // BUILD ACTIONS (for web)
  // ================================================================
  List<Widget> _buildActions(BuildContext context) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;

    final List<Widget> actions = [];

    if (showNotNow) {
      actions.add(
        TextButton(
          onPressed: onDeny,
          style: TextButton.styleFrom(
            foregroundColor: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          child: const Text('Not Now'),
        ),
      );
    }

    actions.add(
      ElevatedButton(
        onPressed: onAllow,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Text('Allow'),
      ),
    );

    return actions;
  }
}

// ================================================================
// EXTENSION METHODS FOR EASY USE
// ================================================================
extension PermissionDialogExtension on BuildContext {
  Future<bool?> showPermissionDialog({
    String? title,
    String? message,
    bool showNotNow = true,
  }) {
    return showDialog<bool>(
      context: this,
      barrierDismissible: false,
      builder: (context) => PermissionDialog(
        onAllow: () => Navigator.of(context).pop(true),
        onDeny: () => Navigator.of(context).pop(false),
        customTitle: title,
        customMessage: message,
        showNotNow: showNotNow,
      ),
    );
  }
}