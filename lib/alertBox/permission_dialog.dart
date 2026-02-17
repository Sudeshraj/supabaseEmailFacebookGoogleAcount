import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:universal_platform/universal_platform.dart';

class PermissionDialog extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onDeny;
  final String? customTitle;
  final String? customMessage;
  final bool showNotNow; // Option to hide "Not Now" button

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
    // Web platform එකට simple dialog එකක්
    if (UniversalPlatform.isWeb) {
      return _buildWebDialog(context);
    }

    // Mobile platform එකට beautiful dialog එකක්
    return _buildMobileDialog(context);
  }

  // ===============================================================
  // WEB DIALOG
  // ===============================================================
  Widget _buildWebDialog(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active,
              color: Color(0xFFFF6B8B),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              customTitle ?? 'Enable Notifications?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Text(
        customMessage ?? 
        'Get notified about new bookings, appointment reminders, and special offers!',
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actions: _buildActions(context),
    );
  }

  // ===============================================================
  // MOBILE DIALOG (Full)
  // ===============================================================
  Widget _buildMobileDialog(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B8B), Color(0xFFFF8A9F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B8B).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                FontAwesomeIcons.bell,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            
            // Title
            Text(
              customTitle ?? '🔔 Stay Updated!',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
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
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            
            // Buttons
            Row(
              children: [
                // Not Now button (if enabled)
                if (showNotNow) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDeny,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFDDDDDD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Not Now',
                        style: TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                
                // Allow button
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAllow,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0xFFFF6B8B).withOpacity(0.3),
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
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'You can change this later in Settings',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
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

  // ===============================================================
  // BUILD ACTIONS (for web)
  // ===============================================================
  List<Widget> _buildActions(BuildContext context) {
    final List<Widget> actions = [];

    if (showNotNow) {
      actions.add(
        TextButton(
          onPressed: onDeny,
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey[600],
          ),
          child: const Text('Not Now'),
        ),
      );
    }

    actions.add(
      ElevatedButton(
        onPressed: onAllow,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
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

// ===============================================================
// EXTENSION METHODS FOR EASY USE
// ===============================================================
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