import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:universal_platform/universal_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Supabase client
  SupabaseClient? _supabaseClient;
  SupabaseClient get supabase {
    _supabaseClient ??= Supabase.instance.client;
    return _supabaseClient!;
  }

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Web VAPID Key
  static const String _webVapidKey =
      'BFj7Eoc2BRmQQrXHBFvWXjcmeb3seAyHmOpVZEOLpKTpwbelZoo5tqci-o7KR-sr0hgO9yIYDRV1KP88vhV0l6k';

  // Platform detection
  bool get isWeb => UniversalPlatform.isWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;

  String get platformName {
    if (isWeb) return 'web';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    return 'unknown';
  }

  // ============= MAIN INITIALIZATION =============
  Future<void> init() async {
    if (isWeb) {
      await _initWebNotifications();
    } else {
      await _initMobileNotifications();
    }

    await _getTokenAndSave();
    _setupMessageListeners();
  }

  // ============= WEB INIT =============
  Future<void> _initWebNotifications() async {
    try {
      String? token = await _firebaseMessaging.getToken(vapidKey: _webVapidKey);

      if (token != null) {
        await _saveTokenToSupabase(token);
      }

      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _saveTokenToSupabase(newToken);
      });

      _setupWebMessageListeners();
    } catch (e) {
      debugPrint('❌ Web notification init error: $e');
    }
  }

  // ============= MOBILE INIT =============
  Future<void> _initMobileNotifications() async {
    await _initLocalNotifications();
  }

  // ============= WEB MESSAGE LISTENERS =============
  void _setupWebMessageListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleWebForegroundMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessage(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _handleMessage(message);
      }
    });
  }

  void _handleWebForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      _saveNotificationToDatabase(
        title: notification.title ?? 'Notification',
        body: notification.body ?? '',
        type: message.data['type'] ?? 'general',
        data: message.data,
      );
    }
  }

  // ============= LOCAL NOTIFICATIONS (Mobile) =============
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
  }

  // ============= PERMISSION METHODS =============
  Future<bool> requestWebPermission() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint('❌ Web permission error: $e');
      return false;
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

  // ============= TOKEN MANAGEMENT =============
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

  Future<void> saveTokenManually() async {
    String? token = await getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    } else {
      debugPrint('⚠️ No FCM token available');
    }
  }

  Future<void> _getTokenAndSave() async {
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

      await supabase
          .from('profiles')
          .update({
            'fcm_token': token,
            'platform': platformName,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      await _clearStoredToken();
    } catch (e) {
      debugPrint('❌ Error saving to Supabase: $e');
      await _storeTokenLocally(token);
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

  // ============= DATABASE OPERATIONS USING RPC =============

  /// Save notification to database
  Future<void> _saveNotificationToDatabase({
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase.from('notifications').insert({
        'user_id': user.id,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Error saving notification to database: $e');
    }
  }

  /// Get unread notification count (RPC)
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

  /// Get all notifications for user (RPC)
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

  // ============= ROLE-BASED NOTIFICATION METHODS (UPDATED) =============

  /// ✅ Updated: Get notifications filtered by role with status check
  Future<List<Map<String, dynamic>>> getNotificationsWithRole({
    required String userId,
    required String role,
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      // ✅ Check if user has active role
      final userRoles = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .eq('status', 'active')
          .maybeSingle();

      if (userRoles == null) {
        debugPrint('⚠️ User $userId does not have active $role role.');
        return [];
      }

      // Get all notifications via RPC
      final result = await supabase.rpc(
        'get_user_notifications',
        params: {'p_user_id': userId},
      );

      List<Map<String, dynamic>> notifications = [];
      if (result != null && result.isNotEmpty) {
        notifications = List<Map<String, dynamic>>.from(result);
      }

      // Filter by role
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

      // Apply limit
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

  /// ✅ Updated: Get unread notification count with role filter
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

  /// ✅ Updated: Send notification to specific user with role status check
  Future<void> sendNotificationWithRole({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    required String role,
  }) async {
    try {
      // ✅ Check if user has active role
      final userRoles = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .eq('status', 'active')
          .maybeSingle();

      if (userRoles == null) {
        debugPrint('⚠️ User $userId does not have active $role role. Skipping notification.');
        return;
      }

      // 1. Save to database
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': {...?data, 'role': role},
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('✅ Notification saved for $userId (role: $role)');

      // 2. Send push notification
      await _sendPushNotificationWithToken(
        userId: userId,
        title: title,
        body: body,
        data: data,
        role: role,
      );
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
    }
  }

  /// Send push notification using FCM token via Edge Function
  Future<void> _sendPushNotificationWithToken({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    required String role,
  }) async {
    try {
      // Get FCM token
      final userProfile = await supabase
          .from('profiles')
          .select('fcm_token')
          .eq('id', userId)
          .maybeSingle();

      final fcmToken = userProfile?['fcm_token'];

      if (fcmToken == null || fcmToken.toString().isEmpty) {
        debugPrint('⚠️ No FCM token for user $userId');
        return;
      }

      // Call Edge Function
      final result = await supabase.functions.invoke(
        'send-notification',
        body: {
          'userId': userId,
          'title': title,
          'body': body,
          'role': role,
          'screen': data?['screen'] ?? 'home',
          'bookingId': data?['bookingId']?.toString() ?? '',
          'extraData': data ?? {},
          'fcmToken': fcmToken,
        },
      );

      if (result.status == 200) {
        final responseData = result.data as Map<String, dynamic>?;
        if (responseData?['success'] == true) {
          debugPrint('✅ Push notification sent successfully to $userId');
        } else {
          debugPrint(
            '⚠️ Push notification failed: ${responseData?['message']}',
          );
        }
      } else {
        debugPrint('⚠️ Edge Function returned status: ${result.status}');
      }
    } catch (e) {
      debugPrint('❌ Error sending push notification: $e');
    }
  }

  // ============= NEW: BULK NOTIFICATION METHODS =============

  /// ✅ NEW: Send notification to all active users with a specific role
  Future<void> sendNotificationToActiveUsers({
    required String role,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
    int? salonId,
  }) async {
    try {
      // Get all active users with the specified role
      var query = supabase
          .from('user_roles')
          .select('user_id, profiles!inner (id, fcm_token)')
          .eq('roles.name', role)
          .eq('status', 'active');

      if (salonId != null && role == 'owner') {
        query = query.eq('salons.id', salonId);
      }

      final users = await query;

      debugPrint('📤 Sending notification to ${users.length} active $role users');

      for (var user in users) {
        final userId = user['user_id'] as String;
        final fcmToken = user['profiles']?['fcm_token'] as String?;

        if (fcmToken != null && fcmToken.isNotEmpty) {
          await sendNotificationWithRole(
            userId: userId,
            title: title,
            body: body,
            type: type,
            role: role,
            data: data,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending to active users: $e');
    }
  }

  /// ✅ NEW: Get all active users by role
  Future<List<Map<String, dynamic>>> getActiveUsersByRole({
    required String role,
    int? salonId,
  }) async {
    try {
      var query = supabase
          .from('user_roles')
          .select('''
            user_id,
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

      if (salonId != null && role == 'owner') {
        query = query.eq('salons.id', salonId);
      }

      final response = await query;

      List<Map<String, dynamic>> users = [];
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

      debugPrint('✅ Found ${users.length} active $role users');
      return users;
    } catch (e) {
      debugPrint('❌ Error getting active users: $e');
      return [];
    }
  }

  /// ✅ NEW: Check if user has active role before sending notification
  Future<bool> hasActiveRole({
    required String userId,
    required String role,
  }) async {
    try {
      final result = await supabase
          .from('user_roles')
          .select('status')
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

  // ============= MARK AS READ METHODS =============

  /// Mark notification as read (RPC)
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

  /// Fallback: Direct update without RPC
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

  /// Mark all notifications as read (RPC)
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

  /// Fallback: Direct update for mark all as read
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

  /// Delete notification (RPC)
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

      // Fallback
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

  /// Clear all notifications (RPC)
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

      // Fallback
      try {
        await supabase.from('notifications').delete().eq('user_id', userId);
        return true;
      } catch (innerError) {
        debugPrint('❌ [DIRECT] Clear error: $innerError');
        return false;
      }
    }
  }

  // ============= ROLE-SPECIFIC NOTIFICATION SENDING METHODS =============

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
        'offerId': offerId,
        'screen': 'offers',
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

  // ============= GENERIC NOTIFICATION METHODS =============

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
      type: data?['type'] ?? 'general',
      role: role,
      data: {
        'screen': data?['screen'] ?? 'home',
        'bookingId': data?['bookingId']?.toString() ?? '',
        ...?data,
      },
    );
  }

  // ============= MESSAGE HANDLING =============

  void _setupMessageListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Save to database
      _saveNotificationToDatabase(
        title: message.notification?.title ?? 'Notification',
        body: message.notification?.body ?? '',
        type: message.data['type'] ?? 'general',
        data: message.data,
      );

      // Show local notification on mobile
      if (!isWeb) {
        _showMobileNotification(message);
      }
    });

    if (!isWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessage(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        _handleMessage(message);
      }
    });
  }

  Future<void> _showMobileNotification(RemoteMessage message) async {
    if (isWeb) return;

    try {
      RemoteNotification? notification = message.notification;
      if (notification == null) return;

      final notificationType = message.data['type'] ?? 'general';
      final notificationColor = _getNotificationColor(notificationType);

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: AndroidNotificationDetails(
          'salon_channel',
          'Salon Booking Notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: notificationColor,
          styleInformation: const BigTextStyleInformation(''),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
        100000,
      );

      await _localNotifications.show(
        id: notificationId,
        title: notification.title,
        body: notification.body,
        notificationDetails: platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('❌ Show notification error: $e');
    }
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

  // ============= NAVIGATION HANDLING =============

  void _handleMessage(RemoteMessage message) {
    Map<String, dynamic> data = message.data;
    if (data.isNotEmpty) {
      _handleNavigation(jsonEncode(data));
    }
  }

  void _handleNavigation(String payload) {
    try {
      Map<String, dynamic> data = jsonDecode(payload);
      String screen = data['screen'] ?? 'home';
      String bookingId = data['bookingId'] ?? '';
      String role = data['role'] ?? 'customer';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (screen) {
          // ========== BARBER SCREENS ==========
          case 'barber_appointment':
            if (bookingId.isNotEmpty) {
              navigatorKey.currentState?.context.go(
                '/barber/appointment/$bookingId',
              );
            } else {
              navigatorKey.currentState?.context.go('/barber/appointments');
            }
            break;
          case 'barber_appointments':
            navigatorKey.currentState?.context.go('/barber/appointments');
            break;
          case 'barber_leaves':
            navigatorKey.currentState?.context.go('/barber/leaves');
            break;

          // ========== OWNER SCREENS ==========
          case 'owner_leaves':
            navigatorKey.currentState?.context.go('/owner/leaves');
            break;
          case 'owner_salon':
            navigatorKey.currentState?.context.go('/owner/salon');
            break;
          case 'owner_reviews':
            navigatorKey.currentState?.context.go('/owner/reviews');
            break;
          case 'owner_bookings':
            navigatorKey.currentState?.context.go('/owner/bookings');
            break;
          case 'owner_inventory':
            navigatorKey.currentState?.context.go('/owner/inventory');
            break;
          case 'owner_dashboard':
            navigatorKey.currentState?.context.go('/owner/dashboard');
            break;

          // ========== CUSTOMER SCREENS ==========
          case 'booking_details':
            if (bookingId.isNotEmpty) {
              navigatorKey.currentState?.context.go(
                '/customer/booking/$bookingId',
              );
            } else {
              navigatorKey.currentState?.context.go('/customer/my-bookings');
            }
            break;
          case 'vip_bookings':
            navigatorKey.currentState?.context.go('/customer/vip-bookings');
            break;
          case 'offers':
            navigatorKey.currentState?.context.go('/customer/offers');
            break;
          case 'waiting_list':
            navigatorKey.currentState?.context.go('/customer/waiting-list');
            break;
          case 'my_bookings':
            navigatorKey.currentState?.context.go('/customer/my-bookings');
            break;
          case 'reviews':
            navigatorKey.currentState?.context.go('/customer/reviews');
            break;
          case 'loyalty':
            navigatorKey.currentState?.context.go('/customer/loyalty');
            break;

          // ========== DEFAULT ==========
          default:
            if (role == 'barber') {
              navigatorKey.currentState?.context.go('/barber/dashboard');
            } else if (role == 'owner') {
              navigatorKey.currentState?.context.go('/owner/dashboard');
            } else {
              navigatorKey.currentState?.context.go('/customer/dashboard');
            }
            break;
        }
      });
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
    }
  }
}

// ============= BACKGROUND HANDLER =============
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final notificationService = NotificationService();
  if (!notificationService.isWeb) {
    await notificationService._showMobileNotification(message);

    final userId = message.data['userId'];
    if (userId != null && userId.isNotEmpty) {
      final supabase = Supabase.instance.client;
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': message.notification?.title ?? 'Notification',
        'body': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': message.data,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}