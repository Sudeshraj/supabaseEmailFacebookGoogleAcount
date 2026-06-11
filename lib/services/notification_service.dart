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

  /// ✅ RPC: Get unread notification count
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

  /// ✅ RPC: Get all notifications for user
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

  /// ✅ RPC: Mark notification as read (UPDATED - RELIABLE VERSION)
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

      // ✅ Call RPC function
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
        return false;
      }
    } catch (e) {
      debugPrint('❌ [RPC] Error marking as read: $e');

      // ✅ Fallback: Direct update if RPC fails
      return await _markAsReadDirect(notificationId);
    }
  }

  /// ✅ Fallback method: Direct update without RPC
  /// ✅ Fallback method: Direct update without RPC (NO updated_at)
  Future<bool> _markAsReadDirect(int notificationId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      debugPrint(
        '🔍 [DIRECT] Attempting direct update for notification $notificationId',
      );

      // ✅ Remove updated_at - it doesn't exist in your table
      final result = await supabase
          .from('notifications')
          .update({
            'is_read': true,
            // 'updated_at': DateTime.now().toIso8601String(), // ❌ REMOVE THIS LINE
          })
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

  /// ✅ RPC: Mark all notifications as read
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

  /// ✅ Fallback: Direct update for mark all as read
  Future<bool> _markAllAsReadDirect(String userId) async {
    try {
      debugPrint(
        '🔍 [DIRECT] Marking all notifications as read for user $userId',
      );

      await supabase
          .from('notifications')
          .update({
            'is_read': true,
            // 'updated_at': DateTime.now().toIso8601String(), // ❌ REMOVE THIS LINE
          })
          .eq('user_id', userId)
          .eq('is_read', false);

      debugPrint('✅ [DIRECT] All notifications marked as read');
      return true;
    } catch (e) {
      debugPrint('❌ [DIRECT] Error: $e');
      return false;
    }
  }

  /// ✅ RPC: Delete a single notification
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

  /// ✅ RPC: Clear all notifications for a user
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

  // ============= PUSH NOTIFICATION VIA EDGE FUNCTION =============

  /// Send push notification via Supabase Edge Function
  Future<void> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    String screen = 'home',
    String bookingId = '',
    Map<String, dynamic>? extraData,
  }) async {
    try {
      // First save to database
      await _saveNotificationToDatabase(
        title: title,
        body: body,
        type: _getNotificationType(screen),
        data: {'screen': screen, 'bookingId': bookingId, ...?extraData},
      );
    } catch (e) {
      debugPrint('❌ Push notification error: $e');
    }
  }

  String _getNotificationType(String screen) {
    switch (screen) {
      case 'booking_details':
        return 'appointment_confirmed';
      case 'vip_bookings':
        return 'vip_approved';
      case 'offers':
        return 'special_offer';
      default:
        return 'general';
    }
  }

  // ============= NOTIFICATION SENDING METHODS =============

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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
      extraData: {
        'bookingNumber': bookingNumber,
        'queueNumber': queueNumber,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'salonName': salonName,
        'barberName': barberName,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
      extraData: {
        'bookingNumber': bookingNumber,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
      extraData: {
        'bookingNumber': bookingNumber,
        'newBarberName': newBarberName,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
      extraData: {
        'bookingNumber': bookingNumber,
        'newDate': newDate,
        'oldDate': oldDate,
        'queueNumber': queueNumber,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'my_bookings',
      bookingId: appointmentId.toString(),
      extraData: {
        'bookingNumber': bookingNumber,
        'reason': reason,
        'cancelledBy': cancelledBy,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'vip_bookings',
      bookingId: vipBookingId.toString(),
      extraData: {
        'eventType': eventType,
        'eventDate': eventDate,
        'eventTime': eventTime,
        'salonName': salonName,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'vip_bookings',
      bookingId: vipBookingId.toString(),
      extraData: {
        'eventType': eventType,
        'eventDate': eventDate,
        'salonName': salonName,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'vip_bookings',
      bookingId: vipBookingId.toString(),
      extraData: {
        'eventType': eventType,
        'eventDate': eventDate,
        'salonName': salonName,
        'reason': reason,
      },
    );
  }

  // ============= SPECIAL OFFER NOTIFICATION =============

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

    // 1. Save to database
    await _saveNotificationToDatabase(
      title: title,
      body: body,
      type: 'special_offer',
      data: {
        'offerTitle': offerTitle,
        'discountText': discountText,
        'salonName': salonName,
        'offerId': offerId,
      },
    );

    // 2. Direct Edge Function call
    try {
      final userProfile = await supabase
          .from('profiles')
          .select('fcm_token')
          .eq('id', customerId)
          .maybeSingle();

      final fcmToken = userProfile?['fcm_token'];

      if (fcmToken == null || fcmToken.toString().isEmpty) {
        debugPrint('⚠️ No FCM token for user $customerId');
        return;
      }

      final result = await supabase.functions.invoke(
        'send-notification',
        body: {
          'token': fcmToken,
          'title': title,
          'body': body,
          'data': {
            'screen': 'offers',
            'bookingId': offerId.toString(),
            'type': 'special_offer',
            'offerTitle': offerTitle,
            'discountText': discountText,
            'salonName': salonName,
          },
        },
      );

      debugPrint('✅ Special offer push notification sent: $result');
    } catch (e) {
      debugPrint('❌ Error sending special offer push notification: $e');
    }
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'waiting_list',
      bookingId: waitingListId.toString(),
      extraData: {
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'serviceName': serviceName,
        'salonName': salonName,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
      extraData: {
        'queuePosition': queuePosition,
        'estimatedTime': estimatedTime,
        'barberName': barberName,
      },
    );
  }

  Future<void> sendLeaveRequestToOwner({
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

    await sendPushNotification(
      userId: ownerId,
      title: title,
      body: body,
      screen: 'owner_leaves',
      bookingId: leaveId.toString(),
      extraData: {
        'barberName': barberName,
        'leaveDate': leaveDate,
        'leaveType': leaveType,
        'reason': reason,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
      extraData: {
        'excessMinutes': excessMinutes,
        'salonCloseTime': salonCloseTime,
        'bookingNumber': bookingNumber,
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'reviews',
      bookingId: appointmentId.toString(),
      extraData: {'salonName': salonName, 'bookingNumber': bookingNumber},
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'offers',
      bookingId: '',
      extraData: {'customerName': customerName, 'discountText': discountText},
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'loyalty',
      bookingId: '',
      extraData: {
        'points': points,
        'totalPoints': totalPoints,
        'source': source,
      },
    );
  }

  Future<void> sendGenericNotification({
    required String customerId,
    required String title,
    required String body,
    String screen = 'home',
    Map<String, dynamic>? extraData,
  }) async {
    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: screen,
      bookingId: '',
      extraData: extraData,
    );
  }

  Future<void> sendAppointmentNotification({
    required String customerId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: data?['screen'] ?? 'home',
      bookingId: data?['bookingId']?.toString() ?? '',
      extraData: data,
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
      case 'cancellation':
        return Colors.red;
      case 'booking_reminder':
        return Colors.blue;
      case 'next_appointment_alert':
      case 'overflow_warning':
        return Colors.orange;
      default:
        return const Color(0xFFFF6B8B);
    }
  }

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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (screen) {
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
          case 'owner_leaves':
            navigatorKey.currentState?.context.go('/owner/leaves');
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
          default:
            navigatorKey.currentState?.context.go('/customer/dashboard');
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
