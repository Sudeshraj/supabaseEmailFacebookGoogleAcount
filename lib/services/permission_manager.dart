import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/notification_service.dart';

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  final NotificationService _notificationService = NotificationService();

  // Storage keys
  static const String _keyLastDenied = 'permission_last_denied';
  static const String _keyShownCount = 'permission_shown_count';
  static const String _keyLastScreen = 'permission_last_screen';
  static const String _keyLastTime = 'permission_last_time';
  static const String _keyUserAction = 'permission_user_action';
  static const String _keyPermanentDeny = 'permission_permanent_deny';
  static const String _keyPermissionGranted = 'permission_granted';

  // ===============================================================
  // 🔥 CHECK IF SHOULD SHOW PERMISSION CARD
  // ===============================================================
  Future<bool> shouldShowPermissionCard(String screen) async {
    // 1. Already has system permission?
    final hasSystemPermission = await _notificationService.hasPermission();
    print('🔍 hasSystemPermission: $hasSystemPermission');
    
    if (hasSystemPermission) {
      print('✅ Already has system permission - not showing card');
      return false;
    }

    // 2. Check stored permission
    final hasStoredPermission = await _hasStoredPermission();
    print('🔍 hasStoredPermission: $hasStoredPermission');
    
    if (hasStoredPermission) {
      print('✅ Already has stored permission - not showing card');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();

    // 3. User permanently denied?
    final permanentDeny = prefs.getBool(_keyPermanentDeny) ?? false;
    print('🔍 permanentDeny: $permanentDeny');
    
    if (permanentDeny) {
      print('🚫 User permanently denied - never showing again');
      return false;
    }

    // 4. Check if user denied recently (7-day cooldown)
    final lastDenied = prefs.getInt(_keyLastDenied);
    if (lastDenied != null) {
      final daysSinceDenied = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastDenied))
          .inDays;
      
      print('🔍 daysSinceDenied: $daysSinceDenied');
      
      if (daysSinceDenied < 7) {
        print('⏳ User denied $daysSinceDenied days ago - waiting ${7 - daysSinceDenied} more days');
        return false;
      }
    }

    // 5. Check screen-specific limits
    final shownCount = prefs.getInt('${_keyShownCount}_$screen') ?? 0;
    print('🔍 shownCount for $screen: $shownCount');

    switch (screen) {
      case 'owner_dashboard':
        if (shownCount >= 2) {
          print('📊 Already shown $shownCount times on owner dashboard - stopping');
          return false;
        }
        break;

      case 'home':
        if (shownCount >= 1) {
          print('📊 Already shown on home screen - stopping');
          return false;
        }
        break;

      case 'settings':
        if (shownCount >= 3) {
          print('📊 Already shown $shownCount times in settings - stopping');
          return false;
        }
        break;

      default:
        print('❓ Unknown screen: $screen - showing anyway');
        break;
    }

    // 6. Check cooldown period for same screen
    final lastTime = prefs.getInt('${_keyLastTime}_$screen');
    
    if (lastTime != null) {
      final hoursSince = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastTime))
          .inHours;
      
      if (hoursSince < 24) {
        print('⏳ Showed on $screen $hoursSince hours ago - 24h cooldown');
        return false;
      }
    }

    // 7. All checks passed!
    print('✅ Should show permission card on $screen');
    return true;
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
    
    print('📝 Marked permission shown on $screen (total: ${currentCount + 1})');
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
    
    print('✅ Permission granted by user');
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
      print('🚫 User permanently denied permission');
    } else {
      print('❌ User denied permission');
    }
  }

  // ===============================================================
  // 🔥 GET PERMISSION STATS (NEW)
  // ===============================================================
  Future<Map<String, dynamic>> getPermissionStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get all screen counts
    Map<String, int> screenCounts = {};
    final keys = await prefs.getKeys();
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
      'user_action': prefs.getString(_keyUserAction),
      'permanent_deny': prefs.getBool(_keyPermanentDeny) ?? false,
      'permission_granted': prefs.getBool(_keyPermissionGranted) ?? false,
    };
  }

  // ===============================================================
  // 🔥 RESET PERMISSION STATE (NEW)
  // ===============================================================
  Future<void> resetPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Remove all permission-related keys
    final keys = await prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('permission_')) {
        await prefs.remove(key);
      }
    }
    
    // Also remove screen-specific keys
    for (var key in keys) {
      if (key.startsWith(_keyShownCount) || 
          key.startsWith(_keyLastTime) ||
          key == _keyLastScreen ||
          key == _keyLastDenied ||
          key == _keyUserAction ||
          key == _keyPermanentDeny ||
          key == _keyPermissionGranted) {
        await prefs.remove(key);
      }
    }
    
    print('🔄 Permission state reset for testing');
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
      
      // Can ask again after 7 days if denied
      return daysSince >= 7;
    }
    
    // Never denied - can ask
    return true;
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
      default:
        return 'owner_dashboard';
    }
  }

  // ===============================================================
  // 🔥 CLEAR SPECIFIC SCREEN DATA (NEW)
  // ===============================================================
  Future<void> clearScreenData(String screen) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove('${_keyShownCount}_$screen');
    await prefs.remove('${_keyLastTime}_$screen');
    
    print('🗑️ Cleared permission data for screen: $screen');
  }
}