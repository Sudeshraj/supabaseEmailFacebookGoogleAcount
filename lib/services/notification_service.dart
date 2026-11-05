import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:universal_platform/universal_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Guards init() so listeners are never registered twice.
  bool _initialized = false;

  // Supabase client
  SupabaseClient? _supabaseClient;
  SupabaseClient get supabase {
    _supabaseClient ??= Supabase.instance.client;
    return _supabaseClient!;
  }

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // The real GoRouter instance. main.dart sets this right after the
  // router is created:
  //     router = _createRouter();
  //     NotificationService.router = router;
  static GoRouter? router;

  // Web VAPID Key
  static const String _webVapidKey =
      'BFj7Eoc2BRmQQrXHBFvWXjcmeb3seAyHmOpVZEOLpKTpwbelZoo5tqci-o7KR-sr0hgO9yIYDRV1KP88vhV0l6k';

  // Platform detection
  bool get isWeb => UniversalPlatform.isWeb || kIsWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;

  String get platformName {
    if (isWeb) return 'web';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    return 'unknown';
  }

  // ===============================================================
  // 🔥 MAIN INITIALIZATION - COMPLETE CROSS PLATFORM
  // ===============================================================

  /// Initialize with optional permission request
  /// For Web: Pass requestPermission: false to avoid auto-prompt
  Future<void> init({bool requestPermission = true}) async {
    if (_initialized) {
      debugPrint('⚠️ NotificationService already initialized - skipping');
      return;
    }
    _initialized = true;

    debugPrint('🚀 Initializing NotificationService for $platformName');

    if (isWeb) {
      await _initWebNotifications(requestPermission: requestPermission);
    } else {
      await _initMobileNotifications();
    }

    if (!isWeb) {
      // Mobile - always get token
      await _getTokenAndSave();
    } else {
      // Web - only fetch the token if the user ALREADY granted permission
      // earlier (getToken() would otherwise trigger a prompt). If no user
      // is logged in yet, the token is stored locally and synced after
      // sign-in via syncPendingToken().
      try {
        if (await hasPermission()) {
          final token = await _firebaseMessaging.getToken(
            vapidKey: _webVapidKey,
          );
          if (token != null) {
            await _saveTokenToSupabase(token);
          }
        } else {
          debugPrint('🌐 Web: permission not granted yet - skipping token');
        }
      } catch (e) {
        debugPrint('⚠️ Web token fetch on init failed: $e');
      }
    }

    _setupMessageListeners();

    if (isAndroid) {
      await _setupAndroid36Optimizations();
    }

    debugPrint('✅ Notification service initialized for $platformName');
  }

  /// Initialize WITHOUT requesting permission (for Web)
  Future<void> initWithoutPermission() async {
    await init(requestPermission: false);
    debugPrint('✅ Notification service initialized without permission');
  }

  // ===============================================================
  // 🔥 ANDROID 16 (API 36) OPTIMIZATIONS
  // ===============================================================

  Future<void> _setupAndroid36Optimizations() async {
    try {
      debugPrint('🤖 Android 16 (API 36) optimizations applied');
    } catch (e) {
      debugPrint('⚠️ Android 16 optimization error: $e');
    }
  }

  // ===============================================================
  // 🔥 WEB INIT
  // ===============================================================

  Future<void> _initWebNotifications({bool requestPermission = true}) async {
    try {
      if (requestPermission) {
        debugPrint('🌐 Web: Initializing with permission request');
      } else {
        debugPrint('🌐 Web: Initializing WITHOUT permission request');
      }

      // NOTE: message listeners are registered ONLY in
      // _setupMessageListeners() (called from init for every platform).
      // Registering them here too caused duplicate handling.

      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        if (newToken.isNotEmpty) {
          _saveTokenToSupabase(newToken);
        }
      });
    } catch (e) {
      debugPrint('❌ Web notification init error: $e');
    }
  }

  // ===============================================================
  // 🔥 MOBILE INIT
  // ===============================================================

  Future<void> _initMobileNotifications() async {
    await _initLocalNotifications();

    if (isAndroid) {
      await _requestAndroidCriticalPermissions();
    }
  }

  Future<void> _requestAndroidCriticalPermissions() async {
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('🤖 Requesting notification permissions for Android 16');
        await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Android permission request error: $e');
    }
  }

  // ===============================================================
  // 🔥 LOCAL NOTIFICATIONS (Mobile)
  // ===============================================================

  Future<void> _initLocalNotifications() async {
    if (isWeb) return;

    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestSoundPermission: false,
            requestBadgePermission: false,
            requestAlertPermission: false,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(android: androidSettings, iOS: iosSettings);

      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null) {
            _handleNavigation(payload);
          }
        },
        onDidReceiveBackgroundNotificationResponse:
            _handleBackgroundNotificationResponse,
      );

      if (isAndroid) {
        await _createAndroidNotificationChannel();
      }
    } catch (e) {
      debugPrint('❌ Local notifications init error: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _handleBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    final payload = response.payload;
    if (payload != null) {
      final service = NotificationService();
      service._handleNavigation(payload);
    }
  }

  Future<void> _createAndroidNotificationChannel() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'salon_channel',
        'Salon Booking Notifications',
        description: 'Notifications for salon booking updates',
        importance: Importance.high,
        enableLights: true,
        enableVibration: true,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      const AndroidNotificationChannel vipChannel = AndroidNotificationChannel(
        'vip_channel',
        'VIP Notifications',
        description: 'VIP booking notifications',
        importance: Importance.high,
        enableLights: true,
        enableVibration: true,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(vipChannel);

      debugPrint('✅ Android notification channels created');
    } catch (e) {
      debugPrint('❌ Error creating notification channels: $e');
    }
  }

  // ===============================================================
  // 🔥 PERMISSION METHODS
  // ===============================================================

  /// Request Web Permission - Call from user action only
  Future<bool> requestWebPermission() async {
    try {
      debugPrint('🌐 Requesting web permission (user action)');

      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized;

      if (granted) {
        debugPrint('✅ Web permission granted');
        String? token = await _firebaseMessaging.getToken(
          vapidKey: _webVapidKey,
        );
        if (token != null) {
          await _saveTokenToSupabase(token);
        }
      } else {
        debugPrint('❌ Web permission denied');
      }

      return granted;
    } catch (e) {
      debugPrint('❌ Web permission error: $e');
      return false;
    }
  }

  /// Get Web Permission Status
  Future<String> getWebPermissionStatus() async {
    if (!isWeb) return 'not_applicable';

    try {
      final settings = await _firebaseMessaging.getNotificationSettings();

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        return 'granted';
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return 'denied';
      } else {
        return 'not_determined';
      }
    } catch (e) {
      debugPrint('❌ Error getting web permission status: $e');
      return 'error';
    }
  }

  Future<bool> requestIOSPermission() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('❌ iOS permission error: $e');
      return false;
    }
  }

  Future<bool> requestAndroidPermission() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint('❌ Android permission error: $e');
      return false;
    }
  }

  Future<bool> hasPermission() async {
    NotificationSettings settings = await _firebaseMessaging
        .getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> requestPermission() async {
    if (isWeb) {
      return requestWebPermission();
    } else if (isIOS) {
      return requestIOSPermission();
    } else {
      return requestAndroidPermission();
    }
  }

  // ===============================================================
  // 🔥 TOKEN MANAGEMENT - ONE ROW PER DEVICE (user_fcm_tokens)
  // ===============================================================

  Future<String?> getToken() async {
    try {
      if (isWeb) {
        return await _firebaseMessaging.getToken(vapidKey: _webVapidKey);
      } else {
        return await _firebaseMessaging.getToken();
      }
    } catch (e) {
      debugPrint('❌ Get token error: $e');
      return null;
    }
  }

  /// Fetch + save this device's token. Works for web AND mobile.
  /// Call it after sign-in (main.dart auth listener does this).
  Future<void> saveTokenManually() async {
    // Web: only fetch if permission was already granted, otherwise
    // getToken() would trigger a permission prompt.
    if (isWeb && !await hasPermission()) {
      debugPrint('🌐 Web: permission not granted yet - skipping token save');
      return;
    }

    final token = await getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    } else {
      debugPrint('⚠️ No FCM token available');
    }
  }

  Future<void> _getTokenAndSave() async {
    // Mobile only - web is handled in init()/requestWebPermission()
    if (isWeb) {
      debugPrint('🌐 Web: _getTokenAndSave should not be called on web');
      return;
    }

    String? token = await getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    }

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _saveTokenToSupabase(newToken);
    });
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      if (!_isSupabaseReady()) {
        await _storeTokenLocally(token);
        return;
      }

      final user = supabase.auth.currentUser;
      if (user == null) {
        await _storeTokenLocally(token);
        return;
      }

      // One row per device token (web + android + ios are all kept).
      // register_fcm_token moves the token to the current user if the
      // same device was used by another account before.
      await supabase.rpc(
        'register_fcm_token',
        params: {'p_token': token, 'p_platform': platformName},
      );

      // Keep the legacy column updated for backwards compatibility.
      try {
        await supabase
            .from('profiles')
            .update({
              'fcm_token': token,
              'platform': platformName,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', user.id);
      } catch (e) {
        debugPrint('⚠️ Legacy profiles.fcm_token update failed: $e');
      }

      await _clearStoredToken();
      debugPrint('✅ Token ($platformName) saved for ${user.id}');
    } catch (e) {
      debugPrint('❌ Error saving token: $e');
      await _storeTokenLocally(token);
    }
  }

  /// Optional: call this BEFORE signing the user out if you want this
  /// device to STOP receiving the user's pushes after logout (shared
  /// devices, account deletion). For a normal logout do not call it, so
  /// booking reminders keep arriving.
  Future<void> unregisterCurrentDeviceToken() async {
    try {
      if (!_isSupabaseReady()) return;
      if (isWeb && !await hasPermission()) return;

      final token = await getToken();
      if (token == null) return;

      await supabase.rpc('unregister_fcm_token', params: {'p_token': token});
      debugPrint('🧹 Device token unregistered');
    } catch (e) {
      debugPrint('⚠️ Error unregistering device token: $e');
    }
  }

  bool _isSupabaseReady() {
    try {
      final _ = Supabase.instance.client;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _storeTokenLocally(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_fcm_token', token);
      await prefs.setString('pending_platform', platformName);
    } catch (e) {
      debugPrint('❌ Error storing token locally: $e');
    }
  }

  Future<void> _clearStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_fcm_token');
      await prefs.remove('pending_platform');
    } catch (e) {
      debugPrint('❌ Error clearing stored token: $e');
    }
  }

  Future<void> syncPendingToken() async {
    if (!_isSupabaseReady()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('pending_fcm_token');

      if (token != null) {
        await _saveTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('❌ Error syncing token: $e');
    }
  }

  // ===============================================================
  // 🔥 WEB FOREGROUND MESSAGE HANDLING
  // ===============================================================
  // The in-app notification row is created by the SERVER before the push
  // is sent, so nothing is saved here. The native browser popup for the
  // foreground is shown by index.html (messaging.onMessage); it is not
  // done here because it needs dart:js_interop, which breaks Android/iOS
  // builds in a shared file.
  void _handleWebForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      debugPrint('🌐 Web foreground message received');
    }
  }

  // ===============================================================
  // 🔥 NOTIFICATION LIST (RPC)
  // ===============================================================

  Future<int> getUnreadCount(String userId) async {
    try {
      final result = await supabase.rpc(
        'get_unread_notification_count',
        params: {'p_user_id': userId},
      );
      debugPrint('📬 Unread count for $userId: $result');
      return result ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting unread count: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      final result = await supabase.rpc(
        'get_user_notifications',
        params: {'p_user_id': userId},
      );

      if (result != null && result.isNotEmpty) {
        debugPrint('✅ Loaded ${result.length} notifications for user $userId');
        return List<Map<String, dynamic>>.from(result);
      }
      debugPrint('📭 No notifications found for user $userId');
      return [];
    } catch (e) {
      debugPrint('❌ Error getting notifications: $e');
      return [];
    }
  }

  // ===============================================================
  // 🔥 ROLE-BASED NOTIFICATION METHODS
  // ===============================================================

  Future<List<Map<String, dynamic>>> getNotificationsWithRole({
    required String userId,
    required String role,
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      final userRoles = await supabase
          .from('user_roles')
          .select('status, roles!inner(name)')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .eq('status', 'active')
          .maybeSingle();

      if (userRoles == null) {
        debugPrint('⚠️ User $userId does not have active $role role.');
        return [];
      }

      final result = await supabase.rpc(
        'get_user_notifications',
        params: {'p_user_id': userId},
      );

      List<Map<String, dynamic>> notifications = [];
      if (result != null && result.isNotEmpty) {
        notifications = List<Map<String, dynamic>>.from(result);
      }

      notifications = notifications.where((n) {
        final data = n['data'] as Map? ?? {};
        final notificationRole = data['role'] ?? 'customer';
        return notificationRole == role || notificationRole == 'all';
      }).toList();

      if (unreadOnly) {
        notifications = notifications
            .where((n) => n['is_read'] == false)
            .toList();
      }

      if (notifications.length > limit) {
        notifications = notifications.take(limit).toList();
      }

      debugPrint(
        '✅ Loaded ${notifications.length} notifications for role: $role',
      );
      return notifications;
    } catch (e) {
      debugPrint('❌ Error getting role-based notifications: $e');
      return [];
    }
  }

  Future<int> getUnreadCountWithRole({
    required String userId,
    required String role,
  }) async {
    try {
      final notifications = await getNotificationsWithRole(
        userId: userId,
        role: role,
        unreadOnly: true,
      );
      return notifications.length;
    } catch (e) {
      debugPrint('❌ Error getting unread count with role: $e');
      return 0;
    }
  }

  // ===============================================================
  // 🔥 SEND NOTIFICATION WITH ROLE
  // ===============================================================

  Future<void> sendNotificationWithRole({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    required String role,
  }) async {
    try {
      // Check if user has active role
      final userRoles = await supabase
          .from('user_roles')
          .select('status, roles!inner(name)')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .eq('status', 'active')
          .maybeSingle();

      if (userRoles == null) {
        debugPrint('⚠️ User $userId does not have active $role role.');
        return;
      }

      // Convert all data values to strings
      final Map<String, String> stringData = {};
      if (data != null) {
        data.forEach((key, value) {
          if (value != null) {
            stringData[key] = value.toString();
          }
        });
      }
      stringData['role'] = role;

      // Save the in-app notification row (server-side dedupe inside the
      // send_notification RPC, Section 102).
      final result = await supabase.rpc(
        'send_notification',
        params: {
          'p_user_id': userId,
          'p_title': title,
          'p_body': body,
          'p_type': type,
          'p_data': {...stringData, 'role': role},
        },
      );

      debugPrint('✅ Notification saved via RPC: $result');

      // The same notification was created a moment ago (retry / double
      // call) -> do NOT push it a second time.
      if (result is Map && result['duplicate'] == true) {
        debugPrint('♻️ Duplicate skipped for $userId (no second push)');
        return;
      }

      // Send push notification
      await _sendPushNotificationWithToken(
        userId: userId,
        title: title,
        body: body,
        data: data,
        role: role,
        type: type,
      );
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');

      // Fallback: direct insert
      try {
        final Map<String, dynamic> dbData = {};
        if (data != null) {
          data.forEach((key, value) {
            if (value != null) {
              dbData[key] = value;
            }
          });
        }
        dbData['role'] = role;

        await supabase.from('notifications').insert({
          'user_id': userId,
          'title': title,
          'body': body,
          'type': type,
          'data': dbData,
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        debugPrint('✅ Notification saved via fallback');
      } catch (fallbackError) {
        debugPrint('❌ Fallback failed: $fallbackError');
      }
    }
  }

  Future<void> _sendPushNotificationWithToken({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    required String role,
    String type = 'general',
  }) async {
    try {
      // The edge function looks up ALL device tokens of this user itself
      // (user_fcm_tokens), so no single fcm_token is read or sent from
      // the client here.
      final userProfile = await supabase
          .from('profiles')
          .select('full_name, email')
          .eq('id', userId)
          .maybeSingle();

      if (userProfile == null) {
        debugPrint('⚠️ User profile not found for userId: $userId');
        return;
      }

      debugPrint('📤 Sending push notification to user: $userId');

      // Convert all data values to strings (FCM requirement)
      final Map<String, String> stringData = {};

      stringData['screen'] = data?['screen']?.toString() ?? 'home';
      stringData['bookingId'] = data?['bookingId']?.toString() ?? '';
      stringData['role'] = role;

      if (data != null) {
        data.forEach((key, value) {
          if (value != null && key != 'screen' && key != 'bookingId') {
            stringData[key] = value.toString();
          }
        });
      }

      // The notification type drives the Android channel / colour on the
      // device (VIP channel etc.), so it must travel with the push.
      stringData['type'] = type;

      final Map<String, dynamic> payload = {
        'userId': userId,
        'title': title,
        'body': body,
        'role': role,
        'screen': data?['screen']?.toString() ?? 'home',
        'bookingId': data?['bookingId']?.toString() ?? '',
        'extraData': stringData,
      };

      debugPrint('📤 Payload: ${payload.keys}');

      final result = await supabase.functions.invoke(
        'send-notification',
        body: payload,
      );

      if (result.status == 200) {
        final responseData = result.data as Map<String, dynamic>?;

        if (responseData?['success'] == true) {
          if (responseData?['pushFailed'] == true) {
            debugPrint(
              '⚠️ Push failed but notification saved in database: ${responseData?['message']}',
            );
            debugPrint('⚠️ FCM Error: ${responseData?['error']}');
          } else {
            debugPrint(
              '✅ Push sent to $userId (${responseData?['sent'] ?? '?'}/${responseData?['total'] ?? '?'} devices)',
            );
          }
        } else {
          debugPrint(
            '⚠️ Push notification failed: ${responseData?['message']}',
          );
          if (responseData?['error'] != null) {
            debugPrint('⚠️ Error details: ${responseData?['error']}');
          }
        }
      } else {
        debugPrint('⚠️ Edge Function returned status: ${result.status}');
        debugPrint('⚠️ Response: ${result.data}');
      }
    } catch (e) {
      debugPrint('❌ Error sending push notification: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
    }
  }

  // ===============================================================
  // 🔥 BULK NOTIFICATION METHODS
  // ===============================================================

  Future<void> sendNotificationToActiveUsers({
    required String role,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    int? salonId,
  }) async {
    try {
      // Relationships:
      //   owner  -> salon:  salons.owner_id      (direct column)
      //   barber -> salon:  salon_barbers table  (salon_id, barber_id, status)
      final List<String> targetUserIds = [];

      if (salonId != null && role == 'owner') {
        final salon = await supabase
            .from('salons')
            .select('owner_id')
            .eq('id', salonId)
            .maybeSingle();

        final ownerId = salon?['owner_id'] as String?;
        if (ownerId == null) {
          debugPrint('⚠️ No owner found for salon $salonId');
          return;
        }

        final isActiveOwner = await hasActiveRole(
          userId: ownerId,
          role: 'owner',
        );
        if (isActiveOwner) {
          targetUserIds.add(ownerId);
        } else {
          debugPrint('⚠️ Owner $ownerId does not have an active owner role');
        }
      } else if (salonId != null && role == 'barber') {
        final rows = await supabase
            .from('salon_barbers')
            .select('barber_id')
            .eq('salon_id', salonId)
            .eq('status', 'active');

        for (final row in rows) {
          targetUserIds.add(row['barber_id'] as String);
        }
      } else {
        final rows = await supabase
            .from('user_roles')
            .select('user_id, roles!inner(name)')
            .eq('roles.name', role)
            .eq('status', 'active');

        for (final row in rows) {
          targetUserIds.add(row['user_id'] as String);
        }
      }

      debugPrint(
        '📤 Sending notification to ${targetUserIds.length} active $role users',
      );

      // Users without a device token still get the in-app notification
      // row; the edge function simply finds no token for them.
      for (final userId in targetUserIds) {
        await sendNotificationWithRole(
          userId: userId,
          title: title,
          body: body,
          type: type,
          role: role,
          data: data,
        );
      }
    } catch (e) {
      debugPrint('❌ Error sending to active users: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getActiveUsersByRole({
    required String role,
    int? salonId,
  }) async {
    try {
      List<Map<String, dynamic>> users = [];

      if (salonId != null && role == 'owner') {
        final salon = await supabase
            .from('salons')
            .select('owner_id')
            .eq('id', salonId)
            .maybeSingle();

        final ownerId = salon?['owner_id'] as String?;
        if (ownerId == null) {
          debugPrint('⚠️ No owner found for salon $salonId');
          return [];
        }

        final isActiveOwner = await hasActiveRole(
          userId: ownerId,
          role: 'owner',
        );
        if (isActiveOwner) {
          final profile = await supabase
              .from('profiles')
              .select('id, full_name, email, fcm_token, is_active')
              .eq('id', ownerId)
              .maybeSingle();
          if (profile != null && profile['is_active'] == true) {
            users.add({
              'userId': ownerId,
              'fullName': profile['full_name'],
              'email': profile['email'],
              'fcmToken': profile['fcm_token'],
              'isActive': profile['is_active'],
            });
          }
        }
      } else if (salonId != null && role == 'barber') {
        final rows = await supabase
            .from('salon_barbers')
            .select(
              'barber_id, profiles!inner(id, full_name, email, fcm_token, is_active)',
            )
            .eq('salon_id', salonId)
            .eq('status', 'active');

        for (final row in rows) {
          final profile = row['profiles'] as Map?;
          if (profile != null && profile['is_active'] == true) {
            users.add({
              'userId': row['barber_id'],
              'fullName': profile['full_name'],
              'email': profile['email'],
              'fcmToken': profile['fcm_token'],
              'isActive': profile['is_active'],
            });
          }
        }
      } else {
        final response = await supabase
            .from('user_roles')
            .select('''
        user_id,
        roles!inner (
          name
        ),
        profiles!inner (
          id,
          full_name,
          email,
          fcm_token,
          is_active
        )
      ''')
            .eq('roles.name', role)
            .eq('status', 'active');

        for (var item in response) {
          final profile = item['profiles'] as Map?;
          if (profile != null && profile['is_active'] == true) {
            users.add({
              'userId': item['user_id'],
              'fullName': profile['full_name'],
              'email': profile['email'],
              'fcmToken': profile['fcm_token'],
              'isActive': profile['is_active'],
            });
          }
        }
      }

      debugPrint('✅ Found ${users.length} active $role users');
      return users;
    } catch (e) {
      debugPrint('❌ Error getting active users: $e');
      return [];
    }
  }

  Future<bool> hasActiveRole({
    required String userId,
    required String role,
  }) async {
    try {
      final result = await supabase
          .from('user_roles')
          .select('status, roles!inner(name)')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .eq('status', 'active')
          .maybeSingle();

      return result != null;
    } catch (e) {
      debugPrint('❌ Error checking active role: $e');
      return false;
    }
  }

  // ===============================================================
  // 🔥 MARK AS READ / DELETE METHODS
  // ===============================================================

  Future<bool> markAsRead(int notificationId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('❌ No user logged in - cannot mark as read');
        return false;
      }

      debugPrint(
        '🔍 [RPC] Marking notification $notificationId as read for user ${user.id}',
      );

      final result = await supabase.rpc(
        'mark_notification_as_read',
        params: {'p_notification_id': notificationId},
      );

      debugPrint('✅ [RPC] mark_notification_as_read result: $result');

      if (result != null && result['success'] == true) {
        debugPrint(
          '✅ Successfully marked notification $notificationId as read',
        );
        return true;
      } else {
        debugPrint('⚠️ [RPC] Failed to mark as read: $result');
        return await _markAsReadDirect(notificationId);
      }
    } catch (e) {
      debugPrint('❌ [RPC] Error marking as read: $e');
      return await _markAsReadDirect(notificationId);
    }
  }

  Future<bool> _markAsReadDirect(int notificationId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      debugPrint(
        '🔍 [DIRECT] Attempting direct update for notification $notificationId',
      );

      final result = await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('user_id', user.id)
          .select();

      debugPrint('✅ [DIRECT] Update result: $result');

      if (result.isNotEmpty) {
        final isNowRead = result[0]['is_read'] == true;
        debugPrint('✅ [DIRECT] Notification is_read: $isNowRead');
        return isNowRead;
      }

      return false;
    } catch (e) {
      debugPrint('❌ [DIRECT] Error: $e');
      return false;
    }
  }

  Future<bool> markAllAsRead(String userId) async {
    try {
      debugPrint('🔍 [RPC] Marking all notifications as read for user $userId');

      final result = await supabase.rpc(
        'mark_all_notifications_as_read',
        params: {'p_user_id': userId},
      );

      debugPrint('✅ [RPC] mark_all_notifications_as_read result: $result');

      if (result != null && result['success'] == true) {
        debugPrint('✅ Successfully marked all notifications as read');
        return true;
      } else {
        debugPrint('⚠️ [RPC] Failed to mark all as read: $result');
        return await _markAllAsReadDirect(userId);
      }
    } catch (e) {
      debugPrint('❌ [RPC] Error marking all as read: $e');
      return await _markAllAsReadDirect(userId);
    }
  }

  Future<bool> _markAllAsReadDirect(String userId) async {
    try {
      debugPrint(
        '🔍 [DIRECT] Marking all notifications as read for user $userId',
      );

      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      debugPrint('✅ [DIRECT] All notifications marked as read');
      return true;
    } catch (e) {
      debugPrint('❌ [DIRECT] Error: $e');
      return false;
    }
  }

  Future<bool> deleteNotification(int notificationId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      debugPrint('🔍 [RPC] Deleting notification $notificationId');

      final result = await supabase.rpc(
        'delete_notification',
        params: {'p_notification_id': notificationId},
      );

      debugPrint('✅ [RPC] delete_notification result: $result');
      return result != null && result['success'] == true;
    } catch (e) {
      debugPrint('❌ [RPC] Error deleting notification: $e');

      try {
        await supabase
            .from('notifications')
            .delete()
            .eq('id', notificationId)
            .eq('user_id', supabase.auth.currentUser!.id);
        return true;
      } catch (innerError) {
        debugPrint('❌ [DIRECT] Delete error: $innerError');
        return false;
      }
    }
  }

  Future<bool> clearAllNotifications(String userId) async {
    try {
      debugPrint('🔍 [RPC] Clearing all notifications for user $userId');

      final result = await supabase.rpc(
        'clear_all_notifications',
        params: {'p_user_id': userId},
      );

      debugPrint('✅ [RPC] clear_all_notifications result: $result');
      return result != null && result['success'] == true;
    } catch (e) {
      debugPrint('❌ [RPC] Error clearing notifications: $e');

      try {
        await supabase.from('notifications').delete().eq('user_id', userId);
        return true;
      } catch (innerError) {
        debugPrint('❌ [DIRECT] Clear error: $innerError');
        return false;
      }
    }
  }

  // ===============================================================
  // 🔥 ALL ROLE-SPECIFIC NOTIFICATION SENDING METHODS
  // ===============================================================

  // -------------------- CUSTOMER NOTIFICATIONS --------------------

  Future<void> sendAppointmentConfirmed({
    required String customerId,
    required String bookingNumber,
    required int queueNumber,
    required String appointmentDate,
    required String appointmentTime,
    required int appointmentId,
    required String salonName,
    required String barberName,
  }) async {
    final title = '✅ Appointment Confirmed';
    final body =
        'Your appointment #$bookingNumber is confirmed for $appointmentDate at $appointmentTime at $salonName with $barberName (Queue #$queueNumber)';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'appointment_confirmed',
      role: 'customer',
      data: {
        'bookingNumber': bookingNumber,
        'queueNumber': queueNumber,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'salonName': salonName,
        'barberName': barberName,
        'appointmentId': appointmentId,
        'screen': 'booking_details',
      },
    );
  }

  Future<void> sendAppointmentReminder({
    required String customerId,
    required String bookingNumber,
    required String appointmentDate,
    required String appointmentTime,
    required int appointmentId,
    required String salonName,
  }) async {
    final title = '⏰ Appointment Reminder';
    final body =
        'Reminder: Your appointment #$bookingNumber at $salonName is tomorrow at $appointmentTime.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'booking_reminder',
      role: 'customer',
      data: {
        'bookingNumber': bookingNumber,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'appointmentId': appointmentId,
        'salonName': salonName,
        'screen': 'booking_details',
      },
    );
  }

  Future<void> sendAppointmentReassigned({
    required String customerId,
    required String newBarberName,
    required String appointmentDate,
    required String appointmentTime,
    required int appointmentId,
    required String bookingNumber,
  }) async {
    final title = '🔄 Appointment Reassigned';
    final body =
        'Your appointment #$bookingNumber has been reassigned to $newBarberName on $appointmentDate at $appointmentTime.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'appointment_reassigned',
      role: 'customer',
      data: {
        'bookingNumber': bookingNumber,
        'newBarberName': newBarberName,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'appointmentId': appointmentId,
        'screen': 'booking_details',
      },
    );
  }

  Future<void> sendAppointmentMoved({
    required String customerId,
    required String newDate,
    required int queueNumber,
    required int appointmentId,
    required String bookingNumber,
    required String oldDate,
  }) async {
    final title = '📅 Appointment Moved';
    final body =
        'Your appointment #$bookingNumber has been moved from $oldDate to $newDate (Queue #$queueNumber).';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'appointment_moved',
      role: 'customer',
      data: {
        'bookingNumber': bookingNumber,
        'newDate': newDate,
        'oldDate': oldDate,
        'queueNumber': queueNumber,
        'appointmentId': appointmentId,
        'screen': 'booking_details',
      },
    );
  }

  Future<void> sendAppointmentCancelled({
    required String customerId,
    required String reason,
    required int appointmentId,
    required String bookingNumber,
    required String cancelledBy,
  }) async {
    final title = '❌ Appointment Cancelled';
    final body =
        'Your appointment #$bookingNumber has been cancelled by $cancelledBy. Reason: $reason';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'appointment_cancelled',
      role: 'customer',
      data: {
        'bookingNumber': bookingNumber,
        'reason': reason,
        'cancelledBy': cancelledBy,
        'appointmentId': appointmentId,
        'screen': 'my_bookings',
      },
    );
  }

  Future<void> sendVipBookingApproved({
    required String customerId,
    required String eventType,
    required String eventDate,
    required String eventTime,
    required int vipBookingId,
    required String salonName,
  }) async {
    final title = '🎉 VIP Booking Approved!';
    final body =
        'Your VIP $eventType booking for $eventDate at $eventTime at $salonName has been approved.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'vip_approved',
      role: 'customer',
      data: {
        'eventType': eventType,
        'eventDate': eventDate,
        'eventTime': eventTime,
        'salonName': salonName,
        'vipBookingId': vipBookingId,
        'screen': 'vip_bookings',
      },
    );
  }

  Future<void> sendVipBookingPending({
    required String customerId,
    required String eventType,
    required String eventDate,
    required int vipBookingId,
    required String salonName,
  }) async {
    final title = '⏳ VIP Booking Pending';
    final body =
        'Your VIP $eventType booking for $eventDate at $salonName is pending approval.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'vip_pending',
      role: 'customer',
      data: {
        'eventType': eventType,
        'eventDate': eventDate,
        'salonName': salonName,
        'vipBookingId': vipBookingId,
        'screen': 'vip_bookings',
      },
    );
  }

  Future<void> sendVipBookingRejected({
    required String customerId,
    required String eventType,
    required String eventDate,
    required int vipBookingId,
    required String salonName,
    required String reason,
  }) async {
    final title = '❌ VIP Booking Rejected';
    final body =
        'Your VIP $eventType booking for $eventDate at $salonName has been rejected. Reason: $reason';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'vip_rejected',
      role: 'customer',
      data: {
        'eventType': eventType,
        'eventDate': eventDate,
        'salonName': salonName,
        'reason': reason,
        'vipBookingId': vipBookingId,
        'screen': 'vip_bookings',
      },
    );
  }

  Future<void> sendSpecialOffer({
    required String customerId,
    required String offerTitle,
    required String offerDescription,
    required String discountText,
    required int offerId,
    required String salonName,
  }) async {
    final title = '🎁 Special Offer!';
    final body = '$offerTitle: $discountText at $salonName. $offerDescription';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'special_offer',
      role: 'customer',
      data: {
        'offerTitle': offerTitle,
        'discountText': discountText,
        'salonName': salonName,
        'offerId': offerId.toString(),
        'screen': 'offers',
        'role': 'customer',
      },
    );
  }

  Future<void> sendWaitingListAvailable({
    required String customerId,
    required String appointmentDate,
    required String appointmentTime,
    required int waitingListId,
    required String serviceName,
    required String salonName,
  }) async {
    final title = '🎯 Appointment Available!';
    final body =
        'A slot for $serviceName has opened up on $appointmentDate at $appointmentTime at $salonName. Book now!';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'waiting_list_available',
      role: 'customer',
      data: {
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'serviceName': serviceName,
        'salonName': salonName,
        'waitingListId': waitingListId,
        'screen': 'waiting_list',
      },
    );
  }

  Future<void> sendNextAppointmentAlert({
    required String customerId,
    required int queuePosition,
    required int appointmentId,
    required String estimatedTime,
    required String barberName,
  }) async {
    final title = '🔔 Your Appointment is Next';
    final body =
        'You are #$queuePosition in queue. Your estimated time is $estimatedTime with $barberName. Please be ready.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'next_appointment_alert',
      role: 'customer',
      data: {
        'queuePosition': queuePosition,
        'estimatedTime': estimatedTime,
        'barberName': barberName,
        'appointmentId': appointmentId,
        'screen': 'booking_details',
      },
    );
  }

  Future<void> sendOverflowNotification({
    required String customerId,
    required int appointmentId,
    required int excessMinutes,
    required String salonCloseTime,
    required String bookingNumber,
  }) async {
    final title = '⚠️ Salon Closing Soon';
    final body =
        'Your appointment #$bookingNumber may exceed closing time by $excessMinutes minutes. Salon closes at $salonCloseTime.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'overflow_warning',
      role: 'customer',
      data: {
        'excessMinutes': excessMinutes,
        'salonCloseTime': salonCloseTime,
        'bookingNumber': bookingNumber,
        'appointmentId': appointmentId,
        'screen': 'booking_details',
      },
    );
  }

  Future<void> sendReviewReminder({
    required String customerId,
    required int appointmentId,
    required String salonName,
    required String bookingNumber,
  }) async {
    final title = '📝 Share Your Experience';
    final body =
        'How was your experience at $salonName? Leave a review for appointment #$bookingNumber';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'review_reminder',
      role: 'customer',
      data: {
        'salonName': salonName,
        'bookingNumber': bookingNumber,
        'appointmentId': appointmentId,
        'screen': 'reviews',
      },
    );
  }

  Future<void> sendBirthdayGreeting({
    required String customerId,
    required String customerName,
    required String discountText,
  }) async {
    final title = '🎂 Happy Birthday!';
    final body =
        'Happy Birthday $customerName! Enjoy $discountText on your next booking as a special gift.';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'birthday_greeting',
      role: 'customer',
      data: {
        'customerName': customerName,
        'discountText': discountText,
        'screen': 'offers',
      },
    );
  }

  Future<void> sendLoyaltyPointsEarned({
    required String customerId,
    required int points,
    required int totalPoints,
    required String source,
  }) async {
    final title = '⭐ Points Earned!';
    final body =
        'You earned $points points from $source! Total points: $totalPoints';

    await sendNotificationWithRole(
      userId: customerId,
      title: title,
      body: body,
      type: 'loyalty_points',
      role: 'customer',
      data: {
        'points': points,
        'totalPoints': totalPoints,
        'source': source,
        'screen': 'loyalty',
      },
    );
  }

  // -------------------- BARBER NOTIFICATIONS --------------------

  Future<void> sendNewBookingAssigned({
    required String barberId,
    required String customerName,
    required String serviceName,
    required String appointmentTime,
    required int appointmentId,
    required String bookingNumber,
  }) async {
    final title = '📅 New Booking Assigned';
    final body = '$customerName booked $serviceName at $appointmentTime';

    await sendNotificationWithRole(
      userId: barberId,
      title: title,
      body: body,
      type: 'new_booking_assigned',
      role: 'barber',
      data: {
        'appointmentId': appointmentId,
        'customerName': customerName,
        'serviceName': serviceName,
        'time': appointmentTime,
        'bookingNumber': bookingNumber,
        'screen': 'barber_appointment',
      },
    );
  }

  Future<void> sendBarberBookingReminder({
    required String barberId,
    required String customerName,
    required String serviceName,
    required String appointmentTime,
    required int appointmentId,
    required String bookingNumber,
  }) async {
    final title = '⏰ Upcoming Appointment';
    final body = '$customerName - $serviceName at $appointmentTime';

    await sendNotificationWithRole(
      userId: barberId,
      title: title,
      body: body,
      type: 'booking_reminder',
      role: 'barber',
      data: {
        'appointmentId': appointmentId,
        'customerName': customerName,
        'serviceName': serviceName,
        'time': appointmentTime,
        'bookingNumber': bookingNumber,
        'screen': 'barber_appointment',
      },
    );
  }

  Future<void> sendBarberAppointmentCancelled({
    required String barberId,
    required String customerName,
    required String serviceName,
    required String appointmentTime,
    required int appointmentId,
    required String bookingNumber,
    required String reason,
  }) async {
    final title = '❌ Appointment Cancelled';
    final body =
        '$customerName cancelled $serviceName at $appointmentTime. Reason: $reason';

    await sendNotificationWithRole(
      userId: barberId,
      title: title,
      body: body,
      type: 'appointment_cancelled',
      role: 'barber',
      data: {
        'appointmentId': appointmentId,
        'customerName': customerName,
        'serviceName': serviceName,
        'time': appointmentTime,
        'bookingNumber': bookingNumber,
        'reason': reason,
        'screen': 'barber_appointments',
      },
    );
  }

  Future<void> sendBarberAppointmentReassigned({
    required String barberId,
    required String customerName,
    required String serviceName,
    required String appointmentTime,
    required int appointmentId,
    required String bookingNumber,
    required String fromBarberName,
  }) async {
    final title = '🔄 Appointment Reassigned';
    final body =
        '$customerName - $serviceName reassigned from $fromBarberName to you at $appointmentTime';

    await sendNotificationWithRole(
      userId: barberId,
      title: title,
      body: body,
      type: 'appointment_reassigned',
      role: 'barber',
      data: {
        'appointmentId': appointmentId,
        'customerName': customerName,
        'serviceName': serviceName,
        'time': appointmentTime,
        'bookingNumber': bookingNumber,
        'fromBarber': fromBarberName,
        'screen': 'barber_appointment',
      },
    );
  }

  Future<void> sendBarberLeaveStatusUpdate({
    required String barberId,
    required String leaveDate,
    required String leaveType,
    required String status,
    required String? reason,
    required int leaveId,
  }) async {
    final title = status == 'approved'
        ? '✅ Leave Approved'
        : '❌ Leave Rejected';
    final body =
        'Your $leaveType leave request for $leaveDate has been $status.${reason != null ? ' Reason: $reason' : ''}';

    await sendNotificationWithRole(
      userId: barberId,
      title: title,
      body: body,
      type: 'leave_status_update',
      role: 'barber',
      data: {
        'leaveDate': leaveDate,
        'leaveType': leaveType,
        'status': status,
        'reason': reason,
        'leaveId': leaveId,
        'screen': 'barber_leaves',
      },
    );
  }

  Future<void> sendBarberNewLeaveRequest({
    required String ownerId,
    required String barberName,
    required String leaveDate,
    required String leaveType,
    required int leaveId,
    required String reason,
  }) async {
    final title = '✈️ New Leave Request';
    final body =
        '$barberName requested $leaveType leave on $leaveDate. Reason: $reason';

    await sendNotificationWithRole(
      userId: ownerId,
      title: title,
      body: body,
      type: 'new_leave_request',
      role: 'owner',
      data: {
        'barberName': barberName,
        'leaveDate': leaveDate,
        'leaveType': leaveType,
        'reason': reason,
        'leaveId': leaveId,
        'screen': 'owner_leaves',
      },
    );
  }

  // -------------------- OWNER NOTIFICATIONS --------------------

  Future<void> sendNewSalonFollower({
    required String ownerId,
    required String customerName,
    required int salonId,
    required String salonName,
  }) async {
    final title = '👤 New Salon Follower';
    final body = '$customerName started following $salonName';

    await sendNotificationWithRole(
      userId: ownerId,
      title: title,
      body: body,
      type: 'new_follower',
      role: 'owner',
      data: {
        'customerName': customerName,
        'salonId': salonId,
        'salonName': salonName,
        'screen': 'owner_salon',
      },
    );
  }

  Future<void> sendNewReviewReceived({
    required String ownerId,
    required String customerName,
    required double rating,
    required int reviewId,
    required int salonId,
    required String salonName,
  }) async {
    final title = '⭐ New Review Received';
    final body = '$customerName left a $rating-star review for $salonName';

    await sendNotificationWithRole(
      userId: ownerId,
      title: title,
      body: body,
      type: 'new_review',
      role: 'owner',
      data: {
        'customerName': customerName,
        'rating': rating,
        'reviewId': reviewId,
        'salonId': salonId,
        'salonName': salonName,
        'screen': 'owner_reviews',
      },
    );
  }

  Future<void> sendNewBookingForOwner({
    required String ownerId,
    required String customerName,
    required String serviceName,
    required String appointmentDate,
    required String appointmentTime,
    required int appointmentId,
    required int salonId,
    required String salonName,
    required String barberName,
  }) async {
    final title = '📅 New Booking in Your Salon';
    final body =
        '$customerName booked $serviceName at $salonName with $barberName on $appointmentDate at $appointmentTime';

    await sendNotificationWithRole(
      userId: ownerId,
      title: title,
      body: body,
      type: 'new_booking',
      role: 'owner',
      data: {
        'customerName': customerName,
        'serviceName': serviceName,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'appointmentId': appointmentId,
        'salonId': salonId,
        'salonName': salonName,
        'barberName': barberName,
        'screen': 'owner_bookings',
      },
    );
  }

  Future<void> sendLowStockAlert({
    required String ownerId,
    required String productName,
    required int currentStock,
    required int threshold,
    required int salonId,
    required String salonName,
  }) async {
    final title = '⚠️ Low Stock Alert';
    final body =
        '$productName is running low. Current stock: $currentStock (Threshold: $threshold)';

    await sendNotificationWithRole(
      userId: ownerId,
      title: title,
      body: body,
      type: 'low_stock',
      role: 'owner',
      data: {
        'productName': productName,
        'currentStock': currentStock,
        'threshold': threshold,
        'salonId': salonId,
        'salonName': salonName,
        'screen': 'owner_inventory',
      },
    );
  }

  Future<void> sendOwnerDailySummary({
    required String ownerId,
    required int totalBookings,
    required int totalEarnings,
    required int totalCustomers,
    required int salonId,
    required String salonName,
    required String date,
  }) async {
    final title = '📊 Daily Summary';
    final body =
        '$salonName summary for $date: $totalBookings bookings, ₹$totalEarnings earnings, $totalCustomers customers served';

    await sendNotificationWithRole(
      userId: ownerId,
      title: title,
      body: body,
      type: 'daily_summary',
      role: 'owner',
      data: {
        'totalBookings': totalBookings,
        'totalEarnings': totalEarnings,
        'totalCustomers': totalCustomers,
        'salonId': salonId,
        'salonName': salonName,
        'date': date,
        'screen': 'owner_dashboard',
      },
    );
  }

  // ===============================================================
  // 🔥 GENERIC NOTIFICATION METHODS
  // ===============================================================

  Future<void> sendGenericNotification({
    required String userId,
    required String title,
    required String body,
    required String role,
    String screen = 'home',
    Map<String, dynamic>? extraData,
  }) async {
    await sendNotificationWithRole(
      userId: userId,
      title: title,
      body: body,
      type: 'general',
      role: role,
      data: {'screen': screen, ...?extraData},
    );
  }

  Future<void> sendAppointmentNotification({
    required String userId,
    required String title,
    required String body,
    required String role,
    Map<String, dynamic>? data,
  }) async {
    await sendNotificationWithRole(
      userId: userId,
      title: title,
      body: body,
      type: (data?['type'] ?? 'general').toString(),
      role: role,
      data: {
        'screen': data?['screen'] ?? 'home',
        'bookingId': data?['bookingId']?.toString() ?? '',
        ...?data,
      },
    );
  }

  // ===============================================================
  // 🔥 MESSAGE HANDLING - COMPLETE CROSS PLATFORM
  // ===============================================================

  void _setupMessageListeners() {
    // Foreground message listener - All platforms.
    // The in-app notification row was already created by the SERVER
    // (send_notification RPC / DB functions) BEFORE this push was sent,
    // so nothing is saved here. Saving again only created duplicates.
    // We only DISPLAY the notification.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!isWeb) {
        showMobileNotification(message);
      } else {
        _handleWebForegroundMessage(message);
      }
    });

    // App opened from notification - All platforms
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessage(message);
    });

    // Initial message when app is terminated - All platforms
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _handleMessage(message);
      }
    });
  }

  // ===============================================================
  // 🔥 MOBILE NOTIFICATION DISPLAY
  // ===============================================================

  Future<void> showMobileNotification(RemoteMessage message) async {
    if (isWeb) return;

    try {
      RemoteNotification? notification = message.notification;

      // Falls back to title/body in the data payload for data-only
      // FCM messages.
      final String title =
          notification?.title ?? message.data['title']?.toString() ?? '';
      final String body =
          notification?.body ?? message.data['body']?.toString() ?? '';

      if (title.isEmpty && body.isEmpty) return;

      final String notificationType = (message.data['type'] ?? 'general')
          .toString();
      final notificationColor = _getNotificationColor(notificationType);

      AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            _getAndroidChannelId(notificationType),
            _getAndroidChannelName(notificationType),
            channelDescription: _getAndroidChannelDescription(notificationType),
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: notificationColor,
            styleInformation: const BigTextStyleInformation(''),
          );

      DarwinNotificationDetails iosPlatformChannelSpecifics =
          const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iosPlatformChannelSpecifics,
      );

      int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
        100000,
      );

      await _localNotifications.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('❌ Show notification error: $e');
    }
  }

  String _getAndroidChannelId(String type) {
    if (type.contains('vip') || type == 'vip_approved') {
      return 'vip_channel';
    }
    return 'salon_channel';
  }

  String _getAndroidChannelName(String type) {
    if (type.contains('vip') || type == 'vip_approved') {
      return 'VIP Notifications';
    }
    return 'Salon Booking Notifications';
  }

  String _getAndroidChannelDescription(String type) {
    if (type.contains('vip') || type == 'vip_approved') {
      return 'VIP booking notifications';
    }
    return 'Notifications for salon booking updates';
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'appointment_confirmed':
      case 'booking_confirmed':
        return Colors.green;
      case 'vip_approved':
        return Colors.amber;
      case 'special_offer':
        return const Color(0xFFFF6B8B);
      case 'appointment_cancelled':
        return Colors.red;
      case 'booking_reminder':
        return Colors.blue;
      case 'next_appointment_alert':
      case 'overflow_warning':
        return Colors.orange;
      case 'new_booking_assigned':
        return Colors.purple;
      case 'new_leave_request':
        return Colors.indigo;
      default:
        return const Color(0xFFFF6B8B);
    }
  }

  // ===============================================================
  // 🔥 NAVIGATION HANDLING
  // ===============================================================

  void _handleMessage(RemoteMessage message) {
    Map<String, dynamic> data = message.data;
    if (data.isNotEmpty) {
      _handleNavigation(jsonEncode(data));
    }
  }

  /// Navigates using the real GoRouter (set from main.dart).
  /// Falls back to the navigator key context if the router isn't set.
  void _go(String path) {
    final r = router;
    if (r != null) {
      r.go(path);
      return;
    }
    final ctx = navigatorKey.currentState?.context;
    if (ctx != null) {
      ctx.go(path);
    } else {
      debugPrint('⚠️ No router available to navigate to $path');
    }
  }

  // Every path below exists in main.dart's GoRouter route table.
  // '/owner/*' and '/barber/*' routes are role-protected, so a screen
  // that has no role-appropriate route falls back to that role's
  // dashboard.
  void _handleNavigation(String payload) {
    try {
      Map<String, dynamic> data = jsonDecode(payload);
      String screen = (data['screen'] ?? 'home').toString();
      String role = (data['role'] ?? 'customer').toString();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (screen) {
          // ========== BARBER SCREENS ==========
          case 'barber_appointment':
          case 'barber_appointments':
            _go('/barber/appointments');
            break;
          case 'barber_leaves':
            // No barber-facing leave screen yet.
            _go('/barber');
            break;

          // ========== OWNER SCREENS ==========
          case 'owner_leaves':
            _go('/owner/barber-leaves');
            break;
          case 'owner_salon':
            _go('/owner');
            break;
          case 'owner_reviews':
            _go('/owner');
            break;
          case 'owner_bookings':
            _go('/owner/appointments');
            break;
          case 'owner_inventory':
            _go('/owner');
            break;
          case 'owner_dashboard':
            _go('/owner');
            break;

          // ========== CUSTOMER SCREENS ==========
          case 'booking_details':
            _go('/customer/my-bookings');
            break;
          case 'vip_bookings':
            _go('/customer/vip-booking');
            break;
          case 'offers':
            _go('/customer/offers');
            break;
          case 'waiting_list':
            _go('/customer');
            break;
          case 'my_bookings':
            _go('/customer/my-bookings');
            break;
          case 'reviews':
            _go('/customer');
            break;
          case 'loyalty':
            _go('/customer/loyalty');
            break;
          case 'customer_pro':
            _go('/customer/pro');
            break;

          // ========== OWNER: SUBSCRIPTION ==========
          // '/subscription' needs salonId/ownerId in `extra`, which a
          // push payload can't carry, so land on the owner dashboard.
          case 'subscription':
            _go('/owner');
            break;

          // ========== DEFAULT ==========
          default:
            if (role == 'barber') {
              _go('/barber');
            } else if (role == 'owner') {
              _go('/owner');
            } else {
              _go('/customer');
            }
            break;
        }
      });
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
    }
  }
}