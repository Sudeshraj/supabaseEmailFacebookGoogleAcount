import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/permission_dialog.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  final NotificationService _notificationService = NotificationService();

  bool get isWeb => UniversalPlatform.isWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;

  // ===============================================================
  // 🔥 OPEN APP SETTINGS
  // ===============================================================
  Future<void> openAppSettings() async {
    debugPrint('📱 Opening app settings...');
    
    try {
      if (isWeb) {
        _showWebSettingsInstructions();
      } else {
        await AppSettings.openAppSettings();
        debugPrint('✅ App settings opened');
      }
    } catch (e) {
      debugPrint('❌ Error opening app settings: $e');
      
      if (!isWeb) {
        _showManualSettingsDialog();
      }
    }
  }

  // ===============================================================
  // 🔥 OPEN NOTIFICATION SETTINGS
  // ===============================================================
  Future<void> openNotificationSettings() async {
    debugPrint('📱 Opening notification settings...');
    
    try {
      if (isWeb) {
        _showWebSettingsInstructions();
      } else {
        await AppSettings.openAppSettings(type: AppSettingsType.notification);
        debugPrint('✅ Notification settings opened');
      }
    } catch (e) {
      debugPrint('❌ Error opening notification settings: $e');
      await openAppSettings();
    }
  }

  // ===============================================================
  // 🔥 WEB SETTINGS INSTRUCTIONS
  // ===============================================================
  void _showWebSettingsInstructions() {
    debugPrint('🌐 Web: Please enable notifications from browser settings');
  }

  // ===============================================================
  // 🔥 MANUAL SETTINGS DIALOG (FALLBACK)
  // ===============================================================
  void _showManualSettingsDialog() {
    debugPrint('📱 Please manually enable notifications from device settings');
  }

  // ===============================================================
  // 🔥 REQUEST PERMISSION AT ACTION
  // ===============================================================
  Future<void> requestPermissionAtAction({
    required BuildContext context,
    required String action,
    String? customTitle,
    String? customMessage,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    
    final hasPermission = await _notificationService.hasPermission();
    if (hasPermission) {
      debugPrint('✅ Already has permission');
      onGranted?.call();
      return;
    }

    final canAsk = await canAskAgain();
    if (!canAsk) {
      if (context.mounted) {
        _showCooldownDialog(context);
      }
      onDenied?.call();
      return;
    }

    await _trackPermissionRequest(action);

    bool? result;
    if (context.mounted) {
      result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PermissionDialog(
          onAllow: () => Navigator.of(dialogContext).pop(true),
          onDeny: () => Navigator.of(dialogContext).pop(false),
          customTitle: customTitle ?? '🔔 Enable Notifications',
          customMessage: customMessage ??
              'Stay updated with your appointments and offers',
        ),
      );
    }

    if (!context.mounted) {
      debugPrint('⚠️ Context is not mounted after dialog');
      return;
    }

    if (result == true) {
      await _requestSystemPermission(
        context: context,
        onGranted: onGranted,
        onDenied: onDenied,
      );
    } else {
      debugPrint('❌ User denied soft ask');
      await _saveDenyTime();
      onDenied?.call();
    }
  }

  // ===============================================================
  // 🔥 SHOW COOLDOWN DIALOG
  // ===============================================================
  void _showCooldownDialog(BuildContext context) {
    if (!context.mounted) {
      debugPrint('⚠️ Context is not mounted, cannot show cooldown dialog');
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('⏳ Too Many Attempts'),
        content: const Text(
          'You have denied notifications multiple times. '
          'Please wait 7 days before trying again, '
          'or enable manually from settings.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
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
  // 🔥 REQUEST SYSTEM PERMISSION - UPDATED
  // ===============================================================
  Future<void> _requestSystemPermission({
    required BuildContext context,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    
    bool granted = false;

    try {
      if (isWeb) {
        debugPrint('🌐 Requesting web permission from user action...');
        granted = await _notificationService.requestWebPermission();
        debugPrint('🌐 Web permission result: $granted');
        
        if (granted) {
          await _saveAskTime();
          await _notificationService.saveTokenManually();
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Notifications enabled in browser!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
          onGranted?.call();
        } else {
          final status = await _notificationService.getWebPermissionStatus();
          debugPrint('🌐 Web permission status: $status');
          
          if (status == 'denied') {
            await _saveDenyTime();
            if (context.mounted) {
              _showWebPermissionDeniedHelp(context);
            }
          } else {
            // User clicked "Not Now" or closed the prompt
            await _saveDenyTime();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You can enable notifications later from browser settings'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
          onDenied?.call();
        }
      } else if (isIOS) {
        granted = await _notificationService.requestIOSPermission();
        if (granted) {
          await _saveAskTime();
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
          await _saveDenyTime();
          if (context.mounted) {
            _showPermissionDeniedHelp(context);
          }
          onDenied?.call();
        }
      } else if (isAndroid) {
        granted = await _notificationService.requestAndroidPermission();
        if (granted) {
          await _saveAskTime();
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
          await _saveDenyTime();
          if (context.mounted) {
            _showPermissionDeniedHelp(context);
          }
          onDenied?.call();
        }
      }
    } catch (e) {
      debugPrint('❌ System permission error: $e');
      
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
  // 🔥 WEB PERMISSION DENIED HELP - UPDATED
  // ===============================================================
  void _showWebPermissionDeniedHelp(BuildContext context) {
    if (!context.mounted) {
      debugPrint('⚠️ Context is not mounted, cannot show web permission help');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Text('🌐'),
            SizedBox(width: 8),
            Text('Browser Notification Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To enable notifications, please follow these steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStep('1', 'Click the 🔒 lock icon in the address bar'),
            const SizedBox(height: 8),
            _buildStep('2', 'Click "Site settings" or "Permissions"'),
            const SizedBox(height: 8),
            _buildStep('3', 'Find "Notifications" and select "Allow"'),
            const SizedBox(height: 8),
            _buildStep('4', 'Refresh the page'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Once enabled, you\'ll receive notifications even when the tab is not active',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              // ✅ Web refresh using public method
              refreshWebPage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Page'),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // 🔥 WEB REFRESH - PUBLIC METHOD (NEW)
  // ===============================================================
  
  /// Refresh the web page using url_launcher
  /// This is a public method that can be called from anywhere
  Future<void> refreshWebPage() async {
    if (!isWeb) {
      debugPrint('⚠️ refreshWebPage called but not on web');
      return;
    }
    
    try {
      await _reloadPageWithUrlLauncher();
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      _showManualRefreshInstruction();
    }
  }

  // ===============================================================
  // 🔥 WEB REFRESH - INTERNAL METHOD
  // ===============================================================

  // ===============================================================
  // 🔥 RELOAD PAGE USING URL LAUNCHER - UPDATED
  // ===============================================================
  Future<void> _reloadPageWithUrlLauncher() async {
    try {
      final currentUrl = Uri.base.toString();
      debugPrint('🌐 Current URL: $currentUrl');
      
      // ✅ Add a cache-busting parameter to force reload
      final uri = Uri.parse(currentUrl);
      final newUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          '_t': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      
      debugPrint('🌐 Reloading with: $newUri');
      
      if (await canLaunchUrl(newUri)) {
        await launchUrl(
          newUri,
          mode: LaunchMode.platformDefault,
        );
        debugPrint('✅ Page refreshed using url_launcher');
      } else {
        debugPrint('❌ Cannot launch URL');
        _showManualRefreshInstruction();
      }
    } catch (e) {
      debugPrint('❌ Refresh error: $e');
      _showManualRefreshInstruction();
    }
  }

  // ===============================================================
  // 🔥 MANUAL REFRESH INSTRUCTION - UPDATED
  // ===============================================================
  void _showManualRefreshInstruction() {
    // Try to get context from navigator key
    try {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please refresh the page manually (F5 or Ctrl+R)'),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        debugPrint('⚠️ Cannot show snackbar - context not available');
      }
    } catch (e) {
      debugPrint('❌ Could not show snackbar: $e');
    }
  }

  // ===============================================================
  // 🔥 SHOW HELP WHEN PERMISSION DENIED (Mobile)
  // ===============================================================
  void _showPermissionDeniedHelp(BuildContext context) {
    if (!context.mounted) {
      debugPrint('⚠️ Context is not mounted, cannot show permission denied help');
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          if (!isWeb)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
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
  // 🔥 BUILD STEP WIDGET
  // ===============================================================
  Widget _buildStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B8B).withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  // ===============================================================
  // 🔥 TRACK PERMISSION REQUESTS
  // ===============================================================
  Future<void> _trackPermissionRequest(String action) async {
    final prefs = await SharedPreferences.getInstance();
    
    final requests = prefs.getStringList('permission_requests') ?? [];
    requests.add('$action:${DateTime.now().toIso8601String()}');
    
    if (requests.length > 10) {
      requests.removeAt(0);
    }
    
    await prefs.setStringList('permission_requests', requests);
    
    debugPrint('📊 Tracked permission request: $action');
  }

  // ===============================================================
  // 🔥 SAVE ASK TIME
  // ===============================================================
  Future<void> _saveAskTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_permission_ask', DateTime.now().millisecondsSinceEpoch);
    debugPrint('💾 Saved ask time');
  }

  // ===============================================================
  // 🔥 SAVE DENY TIME
  // ===============================================================
  Future<void> _saveDenyTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_permission_deny', DateTime.now().millisecondsSinceEpoch);
    debugPrint('💾 Saved deny time');
  }

  // ===============================================================
  // 🔥 CHECK IF CAN ASK AGAIN
  // ===============================================================
  Future<bool> canAskAgain() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDeny = prefs.getInt('last_permission_deny');
    
    if (lastDeny == null) return true;
    
    final daysSince = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastDeny))
        .inDays;
    
    debugPrint('📊 Days since last deny: $daysSince');
    
    // ✅ Web users get shorter cooldown (3 days)
    final cooldownDays = isWeb ? 3 : 7;
    return daysSince >= cooldownDays;
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
    
    debugPrint('🔄 Permission state reset');
  }

  // ===============================================================
  // 🔥 CHECK WEB PERMISSION STATUS (Convenience method)
  // ===============================================================
  Future<String> getWebPermissionStatus() async {
    if (!isWeb) return 'not_applicable';
    return await _notificationService.getWebPermissionStatus();
  }

  // ===============================================================
  // 🔥 HAS PERMISSION (Convenience method)
  // ===============================================================
  Future<bool> hasPermission() async {
    return await _notificationService.hasPermission();
  }
}