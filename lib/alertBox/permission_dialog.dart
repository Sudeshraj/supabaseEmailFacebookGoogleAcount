import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:universal_platform/universal_platform.dart';

class PermissionDialog extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const PermissionDialog({
    super.key,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    // Web platform එකට simple dialog එකක්
    if (UniversalPlatform.isWeb) {
      return AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.notifications_active, color: Color(0xFFFF6B8B)),
            SizedBox(width: 12),
            Text('Enable Notifications?'),
          ],
        ),
        content: const Text(
          'Get notified about new bookings, appointment reminders, and special offers!',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: onDeny,
            child: const Text(
              'Not Now',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: onAllow,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Allow'),
          ),
        ],
      );
    }

    // Mobile platform එකට beautiful dialog එකක්
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                FontAwesomeIcons.bell,
                color: Color(0xFFFF6B8B),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '🔔 Stay Updated!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Get instant notifications about:\n'
              '• New booking requests\n'
              '• Appointment reminders\n'
              '• Special offers & promotions\n'
              '• Payment confirmations',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDeny,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFDDDDDD)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Not Now',
                      style: TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAllow,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFFF6B8B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Allow',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}