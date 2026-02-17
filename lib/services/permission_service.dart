import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/permission_dialog.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:app_settings/app_settings.dart'; // මේක add කරන්න

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  final NotificationService _notificationService = NotificationService();

  // Platform detection
  bool get isWeb => UniversalPlatform.isWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;

  // ===============================================================
  // 🔥 OPEN APP SETTINGS (NEW METHOD)
  // ===============================================================
  Future<void> openAppSettings() async {
    print('📱 Opening app settings...');
    
    try {
      if (isWeb) {
        _showWebSettingsInstructions();
      } else {
        // Open app settings using app_settings package
        await AppSettings.openAppSettings();
        print('✅ App settings opened');
      }
    } catch (e) {
      print('❌ Error opening app settings: $e');
      
      // Fallback for when app_settings fails
      if (!isWeb) {
        _showManualSettingsDialog();
      }
    }
  }

  // ===============================================================
  // 🔥 OPEN NOTIFICATION SETTINGS (SPECIFIC)
  // ===============================================================
  Future<void> openNotificationSettings() async {
    print('📱 Opening notification settings...');
    
    try {
      if (isWeb) {
        _showWebSettingsInstructions();
      } else {
        await AppSettings.openAppSettings(type: AppSettingsType.notification);
        print('✅ Notification settings opened');
      }
    } catch (e) {
      print('❌ Error opening notification settings: $e');
      // Fallback to general settings
      await openAppSettings();
    }
  }

  // ===============================================================
  // 🔥 WEB SETTINGS INSTRUCTIONS
  // ===============================================================
  void _showWebSettingsInstructions() {
    print('🌐 Web: Please enable notifications from browser settings');
    
    // This will be called from the dialog in OwnerDashboard
  }

  // ===============================================================
  // 🔥 MANUAL SETTINGS DIALOG (FALLBACK)
  // ===============================================================
  void _showManualSettingsDialog() {
    // This is just a print - actual dialog will be shown from OwnerDashboard
    print('📱 Please manually enable notifications from device settings');
  }

  // ===============================================================
  // 🔥 REQUEST PERMISSION AT ACTION (Main method) - FIXED VERSION
  // ===============================================================
  Future<void> requestPermissionAtAction({
    required BuildContext context,
    required String action,
    String? customTitle,
    String? customMessage,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    
    // Check if already has permission
    if (await _notificationService.hasPermission()) {
      print('✅ Already has permission');
      onGranted?.call();
      return;
    }

    // Check if we can ask again
    if (!await canAskAgain()) {
      _showCooldownDialog(context);
      onDenied?.call();
      return;
    }

    // Track this request
    await _trackPermissionRequest(action);

    // ✅ FIXED: Show custom dialog with correct parameter names
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PermissionDialog(
        onAllow: () => Navigator.of(dialogContext).pop(true),
        onDeny: () => Navigator.of(dialogContext).pop(false),
        customTitle: customTitle ?? '🔔 Enable Notifications',  // 🔥 FIXED: customTitle
        customMessage: customMessage ??                         // 🔥 FIXED: customMessage
            'Stay updated with your appointments and offers',
      ),
    );

    if (result == true) {
      // User wants to allow - request system permission
      await _requestSystemPermission(
        context: context,
        onGranted: onGranted,
        onDenied: onDenied,
      );
    } else {
      // User denied the soft ask
      print('❌ User denied soft ask');
      
      // Save the deny time
      await _saveDenyTime();
      
      onDenied?.call();
    }
  }

  // ===============================================================
  // 🔥 REQUEST SYSTEM PERMISSION (Platform specific)
  // ===============================================================
  Future<void> _requestSystemPermission({
    required BuildContext context,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    
    bool granted = false;

    try {
      if (isWeb) {
        granted = await _notificationService.requestWebPermission();
      } else if (isIOS) {
        granted = await _notificationService.requestIOSPermission();
      } else if (isAndroid) {
        granted = await _notificationService.requestAndroidPermission();
      }

      if (granted) {
        // Save last ask time
        await _saveAskTime();
        
        // Get and save token
        await _notificationService.saveTokenManually();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Notifications enabled!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        onGranted?.call();
      } else {
        // Save deny time
        await _saveDenyTime();
        
        if (context.mounted) {
          _showPermissionDeniedHelp(context);
        }
        onDenied?.call();
      }
    } catch (e) {
      print('❌ System permission error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      onDenied?.call();
    }
  }

  // ===============================================================
  // 🔥 SHOW COOLDOWN DIALOG
  // ===============================================================
  void _showCooldownDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⏳ Too Many Attempts'),
        content: const Text(
          'You have denied notifications multiple times. '
          'Please wait 7 days before trying again, '
          'or enable manually from settings.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // 🔥 SHOW HELP WHEN PERMISSION DENIED (UPDATED)
  // ===============================================================
  void _showPermissionDeniedHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔕 Notifications Disabled'),
        content: Text(
          isWeb
              ? 'To enable notifications in Chrome:\n\n'
                  '1. Click the lock icon in address bar\n'
                  '2. Click "Site settings"\n'
                  '3. Find "Notifications" and select "Allow"'
              : 'You can enable notifications anytime from:\n\n'
                  '• Android: Settings → Apps → MySalon → Notifications\n'
                  '• iOS: Settings → MySalon → Notifications',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          if (!isWeb)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
              ),
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }

  // ===============================================================
  // 🔥 TRACK PERMISSION REQUESTS
  // ===============================================================
  Future<void> _trackPermissionRequest(String action) async {
    final prefs = await SharedPreferences.getInstance();
    
    final requests = prefs.getStringList('permission_requests') ?? [];
    requests.add('$action:${DateTime.now().toIso8601String()}');
    
    // Keep only last 10 requests
    if (requests.length > 10) {
      requests.removeAt(0);
    }
    
    await prefs.setStringList('permission_requests', requests);
    
    print('📊 Tracked permission request: $action');
  }

  // ===============================================================
  // 🔥 SAVE ASK TIME
  // ===============================================================
  Future<void> _saveAskTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_permission_ask', DateTime.now().millisecondsSinceEpoch);
    print('💾 Saved ask time');
  }

  // ===============================================================
  // 🔥 SAVE DENY TIME
  // ===============================================================
  Future<void> _saveDenyTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_permission_deny', DateTime.now().millisecondsSinceEpoch);
    print('💾 Saved deny time');
  }

  // ===============================================================
  // 🔥 CHECK IF CAN ASK AGAIN (IMPROVED)
  // ===============================================================
  Future<bool> canAskAgain() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDeny = prefs.getInt('last_permission_deny');
    
    if (lastDeny == null) return true;
    
    final daysSince = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastDeny))
        .inDays;
    
    print('📊 Days since last deny: $daysSince');
    
    return daysSince >= 7; // Can ask again after 7 days
  }

  // ===============================================================
  // 🔥 GET PERMISSION STATS
  // ===============================================================
  Future<Map<String, dynamic>> getPermissionStats() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPermission = await _notificationService.hasPermission();
    
    return {
      'has_permission': hasPermission,
      'is_web': isWeb,
      'is_android': isAndroid,
      'is_ios': isIOS,
      'last_ask': prefs.getInt('last_permission_ask'),
      'last_deny': prefs.getInt('last_permission_deny'),
      'requests': prefs.getStringList('permission_requests') ?? [],
      'can_ask_again': await canAskAgain(),
    };
  }

  // ===============================================================
  // 🔥 RESET PERMISSION STATE (for testing)
  // ===============================================================
  Future<void> resetPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove('last_permission_ask');
    await prefs.remove('last_permission_deny');
    await prefs.remove('permission_requests');
    
    print('🔄 Permission state reset');
  }
}