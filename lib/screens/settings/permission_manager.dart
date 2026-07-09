import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:universal_platform/universal_platform.dart';

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  final NotificationService _notificationService = NotificationService();

  // Platform detection
  bool get isWeb => UniversalPlatform.isWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;
  bool get isMobile => !isWeb;

  // Storage keys
  static const String _keyLastDenied = 'permission_last_denied';
  static const String _keyShownCount = 'permission_shown_count';
  static const String _keyLastScreen = 'permission_last_screen';
  static const String _keyLastTime = 'permission_last_time';
  static const String _keyUserAction = 'permission_user_action';
  static const String _keyPermanentDeny = 'permission_permanent_deny';
  static const String _keyPermissionGranted = 'permission_granted';
  static const String _keyLastAskTime = 'permission_last_ask_time';

  // ===============================================================
  // 🔥 IMPORTANT ACTIONS - Contextual permission triggers
  // ===============================================================
  static const List<String> importantActions = [
    'booking',
    'vip',
    'offer',
    'notification',
    'barber',
    'appointment',
    'payment',
  ];

  // ===============================================================
  // 🔥 CHECK IF SHOULD SHOW PERMISSION CARD - WITH CONTEXT
  // ===============================================================
  Future<bool> shouldShowPermissionCard({
    required String screen,
    String? action, // 'booking', 'vip', 'offer', 'notification', etc.
  }) async {
    // 1. Already has system permission?
    final hasSystemPermission = await _notificationService.hasPermission();
    debugPrint('🔍 hasSystemPermission: $hasSystemPermission');
    
    if (hasSystemPermission) {
      debugPrint('✅ Already has system permission - not showing card');
      return false;
    }

    // 2. Check stored permission
    final hasStoredPermission = await _hasStoredPermission();
    debugPrint('🔍 hasStoredPermission: $hasStoredPermission');
    
    if (hasStoredPermission) {
      debugPrint('✅ Already has stored permission - not showing card');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();

    // 3. User permanently denied?
    final permanentDeny = prefs.getBool(_keyPermanentDeny) ?? false;
    debugPrint('🔍 permanentDeny: $permanentDeny');
    
    if (permanentDeny) {
      debugPrint('🚫 User permanently denied - never showing again');
      return false;
    }

    // 4. Check if user denied recently
    final lastDenied = prefs.getInt(_keyLastDenied);
    if (lastDenied != null) {
      final daysSinceDenied = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastDenied))
          .inDays;
      
      debugPrint('🔍 daysSinceDenied: $daysSinceDenied');
      
      // ✅ Web: 3 days, Mobile: 7 days
      final cooldownDays = isWeb ? 3 : 7;
      if (daysSinceDenied < cooldownDays) {
        debugPrint('⏳ User denied $daysSinceDenied days ago - waiting ${cooldownDays - daysSinceDenied} more days');
        return false;
      }
    }

    // 5. Check if we asked recently (cooldown between asks)
    final lastAskTime = prefs.getInt(_keyLastAskTime);
    if (lastAskTime != null) {
      final daysSinceAsk = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastAskTime))
          .inDays;
      
      // ✅ Web: 2 days, Mobile: 3 days
      final askCooldown = isWeb ? 2 : 3;
      if (daysSinceAsk < askCooldown) {
        debugPrint('⏳ Asked $daysSinceAsk days ago - waiting ${askCooldown - daysSinceAsk} more days');
        return false;
      }
    }

    // 6. Check screen-specific limits
    final shownCount = prefs.getInt('${_keyShownCount}_$screen') ?? 0;
    debugPrint('🔍 shownCount for $screen: $shownCount');

    // ✅ Web users get more attempts
    final maxAttempts = isWeb ? 5 : 3;

    // ✅ If max attempts reached, only show on important actions
    if (shownCount >= maxAttempts) {
      if (action == null || !importantActions.contains(action)) {
        debugPrint('📊 Max attempts reached ($shownCount/$maxAttempts) - not showing');
        return false;
      }
      debugPrint('📊 Max attempts reached but important action: $action - showing');
    }

    // 7. Check cooldown period for same screen
    final lastTime = prefs.getInt('${_keyLastTime}_$screen');
    
    if (lastTime != null) {
      final hoursSince = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastTime))
          .inHours;
      
      // ✅ Web: 6 hours, Mobile: 12 hours
      final cooldownHours = isWeb ? 6 : 12;
      
      // ✅ If still in cooldown, only show on important actions
      if (hoursSince < cooldownHours) {
        if (action == null || !importantActions.contains(action)) {
          debugPrint('⏳ Cooldown active ($hoursSince/${cooldownHours}h) - not showing');
          return false;
        }
        debugPrint('⏳ Cooldown active but important action: $action - showing');
      }
    }

    // 8. All checks passed!
    debugPrint('✅ Should show permission card on $screen${action != null ? " (action: $action)" : ""}');
    return true;
  }

  // ===============================================================
  // 🔥 LEGACY METHOD - Keep for backward compatibility
  // ===============================================================
  Future<bool> shouldShowPermissionCardLegacy(String screen) async {
    return shouldShowPermissionCard(screen: screen, action: null);
  }

  // ===============================================================
  // 🔥 CHECK STORED PERMISSION
  // ===============================================================
  Future<bool> _hasStoredPermission() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPermissionGranted) ?? false;
  }

  // ===============================================================
  // 🔥 MARK PERMISSION AS SHOWN
  // ===============================================================
  Future<void> markPermissionShown(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    
    final countKey = '${_keyShownCount}_$screen';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
    
    await prefs.setInt('${_keyLastTime}_$screen', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_keyLastScreen, screen);
    await prefs.setInt(_keyLastAskTime, DateTime.now().millisecondsSinceEpoch);
    
    debugPrint('📝 Marked permission shown on $screen (total: ${currentCount + 1})');
  }

  // ===============================================================
  // 🔥 MARK PERMISSION AS GRANTED
  // ===============================================================
  Future<void> markPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString(_keyUserAction, 'granted');
    await prefs.setBool(_keyPermissionGranted, true);
    
    // Clear deny flags
    await prefs.remove(_keyLastDenied);
    await prefs.remove(_keyPermanentDeny);
    
    debugPrint('✅ Permission granted by user');
  }

  // ===============================================================
  // 🔥 MARK PERMISSION AS DENIED
  // ===============================================================
  Future<void> markPermissionDenied({bool permanent = false}) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setInt(_keyLastDenied, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_keyUserAction, 'denied');
    
    if (permanent) {
      await prefs.setBool(_keyPermanentDeny, true);
      debugPrint('🚫 User permanently denied permission');
    } else {
      debugPrint('❌ User denied permission');
    }
  }

  // ===============================================================
  // 🔥 CAN ASK SYSTEM PERMISSION?
  // ===============================================================
  Future<bool> canAskSystemPermission() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (await _notificationService.hasPermission()) {
      return false;
    }
    
    final lastDenied = prefs.getInt(_keyLastDenied);
    if (lastDenied != null) {
      final daysSince = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastDenied))
          .inDays;
      
      // ✅ Web: 3 days, Mobile: 7 days
      final cooldownDays = isWeb ? 3 : 7;
      return daysSince >= cooldownDays;
    }
    
    // Never denied - can ask
    return true;
  }

  // ===============================================================
  // 🔥 GET PERMISSION STATS
  // ===============================================================
  Future<Map<String, dynamic>> getPermissionStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get all screen counts
    Map<String, int> screenCounts = {};
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('${_keyShownCount}_')) {
        final screen = key.replaceFirst('${_keyShownCount}_', '');
        screenCounts[screen] = prefs.getInt(key) ?? 0;
      }
    }
    
    return {
      'has_system_permission': await _notificationService.hasPermission(),
      'has_stored_permission': await _hasStoredPermission(),
      'screen_counts': screenCounts,
      'last_screen': prefs.getString(_keyLastScreen),
      'last_time': prefs.getInt(_keyLastTime) != null
          ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_keyLastTime)!)
          : null,
      'last_denied': prefs.getInt(_keyLastDenied) != null
          ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_keyLastDenied)!)
          : null,
      'last_ask_time': prefs.getInt(_keyLastAskTime) != null
          ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_keyLastAskTime)!)
          : null,
      'user_action': prefs.getString(_keyUserAction),
      'permanent_deny': prefs.getBool(_keyPermanentDeny) ?? false,
      'permission_granted': prefs.getBool(_keyPermissionGranted) ?? false,
      'is_web': isWeb,
      'is_android': isAndroid,
      'is_ios': isIOS,
      'can_ask_again': await canAskSystemPermission(),
    };
  }

  // ===============================================================
  // 🔥 RESET PERMISSION STATE
  // ===============================================================
  Future<void> resetPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Remove all permission-related keys
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('permission_') || 
          key.startsWith(_keyShownCount) || 
          key.startsWith(_keyLastTime) ||
          key == _keyLastScreen ||
          key == _keyLastDenied ||
          key == _keyUserAction ||
          key == _keyPermanentDeny ||
          key == _keyPermissionGranted ||
          key == _keyLastAskTime) {
        await prefs.remove(key);
      }
    }
    
    debugPrint('🔄 Permission state reset for testing');
  }

  // ===============================================================
  // 🔥 GET NEXT SUGGESTED SCREEN
  // ===============================================================
  Future<String?> getNextSuggestedScreen() async {
    if (await _notificationService.hasPermission()) return null;
    if (await _hasStoredPermission()) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final lastScreen = prefs.getString(_keyLastScreen);
    
    // Suggest different screen than last shown
    switch (lastScreen) {
      case 'owner_dashboard':
        return 'settings';
      case 'settings':
        return 'home';
      case 'home':
        return 'owner_dashboard';
      case 'customer_dashboard':
        return 'settings';
      default:
        return 'owner_dashboard';
    }
  }

  // ===============================================================
  // 🔥 CLEAR SPECIFIC SCREEN DATA
  // ===============================================================
  Future<void> clearScreenData(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove('${_keyShownCount}_$screen');
    await prefs.remove('${_keyLastTime}_$screen');
    
    debugPrint('🗑️ Cleared permission data for screen: $screen');
  }

  // ===============================================================
  // 🔥 GET PERMISSION STATUS FOR CURRENT PLATFORM
  // ===============================================================
  Future<Map<String, dynamic>> getPlatformPermissionStatus() async {
    final hasPermission = await _notificationService.hasPermission();
    
    if (isWeb) {
      final webStatus = await _notificationService.getWebPermissionStatus();
      return {
        'platform': 'web',
        'has_permission': hasPermission,
        'web_permission_status': webStatus,
        'can_ask': await canAskSystemPermission(),
      };
    } else if (isAndroid) {
      return {
        'platform': 'android',
        'has_permission': hasPermission,
        'can_ask': await canAskSystemPermission(),
      };
    } else if (isIOS) {
      return {
        'platform': 'ios',
        'has_permission': hasPermission,
        'can_ask': await canAskSystemPermission(),
      };
    } else {
      return {
        'platform': 'unknown',
        'has_permission': hasPermission,
        'can_ask': await canAskSystemPermission(),
      };
    }
  }

  // ===============================================================
  // 🔥 SHOULD SHOW WEB PERMISSION HELP
  // ===============================================================
  Future<bool> shouldShowWebPermissionHelp() async {
    if (!isWeb) return false;
    
    final status = await _notificationService.getWebPermissionStatus();
    return status == 'denied';
  }

  // ===============================================================
  // 🔥 GET PERMISSION CARD MESSAGE
  // ===============================================================
  String getPermissionCardMessage({String? action}) {
    // ✅ Contextual messages based on action
    if (action != null) {
      switch (action) {
        case 'booking':
          return isWeb
              ? 'Get instant updates about your bookings.\n\nℹ️ You will be asked to allow notifications in your browser.'
              : 'Get instant updates about your bookings.';
        case 'vip':
          return isWeb
              ? 'Get VIP booking approvals and updates.\n\nℹ️ You will be asked to allow notifications in your browser.'
              : 'Get VIP booking approvals and updates.';
        case 'offer':
          return isWeb
              ? 'Get notified about special offers and discounts.\n\nℹ️ You will be asked to allow notifications in your browser.'
              : 'Get notified about special offers and discounts.';
        case 'notification':
          return isWeb
              ? 'Get real-time notifications for all updates.\n\nℹ️ You will be asked to allow notifications in your browser.'
              : 'Get real-time notifications for all updates.';
        default:
          return isWeb
              ? 'Get instant notifications for booking confirmations, VIP approvals, and special offers.\n\nℹ️ You will be asked to allow notifications in your browser.'
              : 'Get instant notifications for booking confirmations, VIP approvals, and special offers.';
      }
    }
    
    return isWeb
        ? 'Get instant notifications for booking confirmations, VIP approvals, and special offers.\n\nℹ️ You will be asked to allow notifications in your browser.'
        : 'Get instant notifications for booking confirmations, VIP approvals, and special offers.';
  }

  // ===============================================================
  // 🔥 GET PERMISSION CARD TITLE
  // ===============================================================
  String getPermissionCardTitle({String? action}) {
    // ✅ Contextual titles based on action
    if (action != null) {
      switch (action) {
        case 'booking':
          return isWeb ? '🌐 Get Booking Updates' : '🔔 Get Booking Updates';
        case 'vip':
          return isWeb ? '🌐 VIP Notifications' : '⭐ VIP Notifications';
        case 'offer':
          return isWeb ? '🌐 Special Offers' : '🎁 Special Offers';
        case 'notification':
          return isWeb ? '🌐 Real-time Updates' : '🔔 Real-time Updates';
        default:
          return isWeb ? '🌐 Enable Browser Notifications' : '🔔 Enable Notifications';
      }
    }
    
    return isWeb ? '🌐 Enable Browser Notifications' : '🔔 Enable Notifications';
  }

  // ===============================================================
  // 🔥 GET PERMISSION CARD ICON
  // ===============================================================
  String getPermissionCardIcon({String? action}) {
    if (action != null) {
      switch (action) {
        case 'booking':
          return '📅';
        case 'vip':
          return '⭐';
        case 'offer':
          return '🎁';
        case 'notification':
          return '🔔';
        default:
          return isWeb ? '🌐' : '🔔';
      }
    }
    return isWeb ? '🌐' : '🔔';
  }
}