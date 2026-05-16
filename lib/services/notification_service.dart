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
    print('📱 Initializing notifications for $platformName');

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
    print('🌐 Web: Initializing silently...');

    try {
      String? token = await _firebaseMessaging.getToken(vapidKey: _webVapidKey);

      if (token != null) {
        print('✅ Web FCM Token: $token');
        await _saveTokenToSupabase(token);
      }

      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('🔄 Web FCM Token refreshed: $newToken');
        _saveTokenToSupabase(newToken);
      });

      _setupWebMessageListeners();
    } catch (e) {
      print('❌ Web notification init error: $e');
    }
  }

  // ============= MOBILE INIT =============
  Future<void> _initMobileNotifications() async {
    print('📱 Mobile: Initializing...');
    await _initLocalNotifications();
  }

  // ============= WEB MESSAGE LISTENERS =============
  void _setupWebMessageListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 Web foreground message: ${message.messageId}');
      _handleWebForegroundMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 Web message opened app');
      _handleMessage(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        print('📨 Web initial message found');
        _handleMessage(message);
      }
    });
  }

  void _handleWebForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      print('🔔 Web Notification: ${notification.title}');
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

      print('✅ Local notifications initialized');
    } catch (e) {
      print('❌ Local notifications init error: $e');
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

    print('✅ Android notification channel created');
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
      print('❌ Web permission error: $e');
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
      print('❌ iOS permission error: $e');
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
      print('❌ Android permission error: $e');
      return false;
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
      print('❌ Get token error: $e');
      return null;
    }
  }

  /// Save token manually (called from outside)
  Future<void> saveTokenManually() async {
    print('🔧 Manually saving FCM token...');
    String? token = await getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    } else {
      print('⚠️ No FCM token available');
    }
  }

  Future<void> _getTokenAndSave() async {
    String? token = await getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    }

    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print('🔄 Token refreshed: $newToken');
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

      print('✅ Token saved to Supabase');
      await _clearStoredToken();
    } catch (e) {
      print('❌ Error saving to Supabase: $e');
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
      print('💾 Token stored locally');
    } catch (e) {
      print('❌ Error storing token locally: $e');
    }
  }

  Future<void> _clearStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_fcm_token');
      await prefs.remove('pending_platform');
    } catch (e) {
      print('❌ Error clearing stored token: $e');
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
  }) async {
    try {
      // First save to database
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': 'appointment_update',
        'data': {'screen': screen, 'bookingId': bookingId},
        'created_at': DateTime.now().toIso8601String(),
      });

      // ✅ FIXED: Use named parameter 'body'
      final response = await supabase.functions.invoke(
        'send-notification',
        body: {
          'userId': userId,
          'title': title,
          'body': body,
          'screen': screen,
          'bookingId': bookingId,
        },
      );

      print('✅ Push notification sent: ${response.data}');
    } catch (e) {
      print('❌ Push notification error: $e');
    }
  }

  // ============= NOTIFICATION SENDING METHODS (UPDATED WITH PUSH) =============

  /// Send appointment confirmation notification
  Future<void> sendAppointmentConfirmed({
    required String customerId,
    required String bookingNumber,
    required int queueNumber,
    required String appointmentDate,
    required String appointmentTime,
    required int appointmentId,
  }) async {
    final title = '✅ Appointment Confirmed';
    final body =
        'Your appointment #$bookingNumber is confirmed for $appointmentDate at $appointmentTime (Queue #$queueNumber)';

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
    );
  }

  /// Send appointment reassigned notification
  Future<void> sendAppointmentReassigned({
    required String customerId,
    required String newBarberName,
    required String appointmentDate,
    required String appointmentTime,
    required int appointmentId,
  }) async {
    final title = '🔄 Appointment Reassigned';
    final body =
        'Your appointment has been reassigned to $newBarberName on $appointmentDate at $appointmentTime.';

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
    );
  }

  /// Send appointment moved to next day notification
  Future<void> sendAppointmentMoved({
    required String customerId,
    required String newDate,
    required int queueNumber,
    required int appointmentId,
  }) async {
    final title = '📅 Appointment Moved';
    final body =
        'Your appointment has been moved to $newDate (Queue #$queueNumber).';

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'booking_details',
      bookingId: appointmentId.toString(),
    );
  }

  /// Send appointment cancelled notification
  Future<void> sendAppointmentCancelled({
    required String customerId,
    required String reason,
    required int appointmentId,
  }) async {
    final title = '❌ Appointment Cancelled';
    final body = 'Your appointment has been cancelled. Reason: $reason';

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'home',
      bookingId: appointmentId.toString(),
    );
  }

  /// Send VIP booking approved notification
  Future<void> sendVipBookingApproved({
    required String customerId,
    required String eventType,
    required String eventDate,
    required String eventTime,
    required int vipBookingId,
  }) async {
    final title = '🎉 VIP Booking Approved!';
    final body =
        'Your $eventType booking for $eventDate at $eventTime has been approved.';

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'vip_bookings',
      bookingId: vipBookingId.toString(),
    );
  }

  /// Send waiting list notification
  Future<void> sendWaitingListAvailable({
    required String customerId,
    required String appointmentDate,
    required String appointmentTime,
    required int waitingListId,
  }) async {
    final title = '🎯 Appointment Available!';
    final body =
        'A slot has opened up on $appointmentDate at $appointmentTime. Book now!';

    await sendPushNotification(
      userId: customerId,
      title: title,
      body: body,
      screen: 'waiting_list',
      bookingId: waitingListId.toString(),
    );
  }

  /// Send leave request notification to owner
  Future<void> sendLeaveRequestToOwner({
    required String ownerId,
    required String barberName,
    required String leaveDate,
    required String leaveType,
    required int leaveId,
  }) async {
    final title = '✈️ New Leave Request';
    final body = '$barberName requested $leaveType leave on $leaveDate';

    await sendPushNotification(
      userId: ownerId,
      title: title,
      body: body,
      screen: 'owner_leaves',
      bookingId: leaveId.toString(),
    );
  }

  /// Generic method to send appointment notification (legacy support)
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
    );
  }

  // ============= MESSAGE HANDLING =============
  void _setupMessageListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 Foreground message');
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
      print('👆 Message opened app');
      _handleMessage(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        print('📬 Initial message');
        _handleMessage(message);
      }
    });
  }

  Future<void> _showMobileNotification(RemoteMessage message) async {
    if (isWeb) return;

    try {
      RemoteNotification? notification = message.notification;
      if (notification == null) return;

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: AndroidNotificationDetails(
          'salon_channel',
          'Salon Booking Notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFFF6B8B),
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

      print('✅ Mobile notification shown');
    } catch (e) {
      print('❌ Show notification error: $e');
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
      String type = data['type'] ?? 'home';
      String screen = data['screen'] ?? 'home';

      switch (screen) {
        case 'booking_details':
          String bookingId = data['bookingId'] ?? '';
          navigatorKey.currentState?.context.go('/booking-details/$bookingId');
          break;

        case 'vip_bookings':
          navigatorKey.currentState?.context.go('/vip-bookings');
          break;

        case 'waiting_list':
          navigatorKey.currentState?.context.go('/waiting-list');
          break;

        case 'owner_leaves':
          navigatorKey.currentState?.context.go('/owner/leaves');
          break;

        case 'my_bookings':
          navigatorKey.currentState?.context.go('/my-bookings');
          break;

        default:
          navigatorKey.currentState?.context.go('/');
          break;
      }
    } catch (e) {
      print('❌ Navigation error: $e');
    }
  }

  // ============= PUBLIC METHODS =============
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

  Future<void> syncPendingToken() async {
    if (!_isSupabaseReady()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('pending_fcm_token');

      if (token != null) {
        print('🔄 Syncing pending token...');
        await _saveTokenToSupabase(token);
      }
    } catch (e) {
      print('❌ Error syncing token: $e');
    }
  }
}

// ============= BACKGROUND HANDLER =============
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📨 Background message: ${message.messageId}');

  final notificationService = NotificationService();
  if (!notificationService.isWeb) {
    await notificationService._showMobileNotification(message);
  }
}
