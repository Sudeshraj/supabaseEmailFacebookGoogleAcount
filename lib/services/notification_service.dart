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

      // ✅ FIXED: Use callback methods directly
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

  // ✅ FIXED: Static method for background
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

  // ============= DATABASE OPERATIONS (USING RPC) =============

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

  /// Get unread notification count using database function
  Future<int> getUnreadCount(String userId) async {
    try {
      final result = await supabase.rpc(
        'get_unread_notification_count',
        params: {'p_user_id': userId},
      );
      return result ?? 0;
    } catch (e) {
      debugPrint('❌ Error getting unread count: $e');
      return 0;
    }
  }

  /// Get all notifications using database function
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      final result = await supabase.rpc(
        'get_user_notifications',
        params: {'p_user_id': userId},
      );

      if (result != null && result.isNotEmpty) {
        return List<Map<String, dynamic>>.from(result);
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error getting notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(int notificationId) async {
    try {
      await supabase
          .from('notifications')
          .update({
            'is_read': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId);
     
    } catch (e) {
      debugPrint('❌ Error marking as read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead(String userId) async {
    try {
      await supabase
          .from('notifications')
          .update({
            'is_read': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_read', false);
    
    } catch (e) {
      debugPrint('❌ Error marking all as read: $e');
    }
  }

  /// Delete a single notification
  Future<void> deleteNotification(int notificationId) async {
    try {
      await supabase.from('notifications').delete().eq('id', notificationId);     
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
    }
  }

  /// Clear all notifications for a user
  Future<void> clearAllNotifications(String userId) async {
    try {
      await supabase.from('notifications').delete().eq('user_id', userId);      
    } catch (e) {
      debugPrint('❌ Error clearing notifications: $e');
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

  /// Send appointment confirmation notification
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

  /// Send appointment reminder notification
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

  /// Send appointment reassigned notification
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

  /// Send appointment moved notification
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

  /// Send appointment cancelled notification
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

  /// Send VIP booking approved notification
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

  /// Send VIP booking pending notification
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

  /// Send VIP booking rejected notification
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

  /// Send special offer notification
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

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'offers',
      bookingId: offerId.toString(),
      extraData: {
        'offerTitle': offerTitle,
        'discountText': discountText,
        'salonName': salonName,
      },
    );
  }

  /// Send waiting list available notification
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

  /// Send next appointment alert (for customers in queue)
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

  /// Send leave request notification to owner
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

  /// Send overflow notification (salon closing soon)
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

  /// Send review reminder notification
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

  /// Send birthday greeting notification
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

  /// Send loyalty points earned notification
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

  /// Send generic notification
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

  /// ✅ Generic appointment notification (Legacy support)
  /// මෙය ඔබගේ පැරණි code එකේ තිබුණු function එකයි - නිවැරදි ස්ථානයට ගෙන ඇත
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

  // ✅ Returns int directly (NOT Color object)
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

    // ✅ FIXED: Get user ID from message data (not from auth)
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
