import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:universal_platform/universal_platform.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  
  // Web VAPID Key - ඔයාගේ Web Console එකෙන් ගත්ත දාන්න
  static const String _webVapidKey =
      'BFj7Eoc2BRmQQrXHBFvWXjcmeb3seAyHmOpVZEOLpKTpwbelZoo5tqci-o7KR-sr0hgO9yIYDRV1KP88vhV0l6k';

  // ============= MAIN INITIALIZATION =============
  Future<void> init() async {
    if (UniversalPlatform.isWeb) {
      await _initWebNotifications();
    } else {
      await _initMobileNotifications();
    }

    await _getToken();
    _setupMessageListeners();
  }

  // ============= 🌐 WEB PLATFORM - SILENT INIT =============
  Future<void> _initWebNotifications() async {
    print('🌐 Web: Initializing silently...');
    
    try {
      // 🔥 WEB: කිසිම permission එකක් අහන්නේ නෑ - token එක විතරක් ගන්නවා
      String? token = await _firebaseMessaging.getToken(
        vapidKey: _webVapidKey,
      );
      
      if (token != null) {
        print('✅ Web FCM Token: $token');
        await _saveTokenToServer(token);
      }
      
      // Token refresh listener
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('🔄 Web FCM Token refreshed: $newToken');
        _saveTokenToServer(newToken);
      });
      
      // Web message listeners setup
      _setupWebMessageListeners();
      
    } catch (e) {
      print('❌ Web notification init error: $e');
    }
  }

  // ============= 🌐 WEB MESSAGE LISTENERS =============
  void _setupWebMessageListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 Web foreground message: ${message.messageId}');
      _handleWebForegroundMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 Web message opened app');
      _handleMessage(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('📨 Web initial message found');
        _handleMessage(message);
      }
    });
  }

  // ============= 🌐 WEB FOREGROUND HANDLER =============
  void _handleWebForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      print('🔔 Web Notification: ${notification.title}');
    }
  }

  // ============= 🌐 WEB PERMISSION REQUEST (UI එකෙන් call කරන්න) =============
  Future<bool> requestWebPermission() async {
    try {
      print('🔔 Web: Requesting permission...');
      
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Web permission granted');
        
        // Permission දුන්නාම නැවත token එක ගන්න
        String? token = await _firebaseMessaging.getToken(
          vapidKey: _webVapidKey,
        );
        print('✅ New Web FCM Token: $token');
        
        return true;
      } else {
        print('❌ Web permission denied');
        return false;
      }
    } catch (e) {
      print('❌ Web permission error: $e');
      return false;
    }
  }

  // ============= 📱 MOBILE PLATFORM - INSTALL TIME PERMISSION =============
  Future<void> _initMobileNotifications() async {
    print('📱 Mobile: Initializing with install-time permission...');
    
    // 🔥 MOBILE: Install වෙන ගමන්ම permission අහන්න
    await _requestMobilePermissionAtInstall();
    
    // Local notifications initialize කරන්න (permission තියෙනවා නම්)
    await _initLocalNotifications();
  }

  // ============= 📱 MOBILE INSTALL TIME PERMISSION =============
  Future<bool> _requestMobilePermissionAtInstall() async {
    try {
      NotificationSettings settings;
      
      if (UniversalPlatform.isIOS) {
        // 🔥🔥 iOS - PROVISIONAL (Popup නෑ, Notification Center එකට Quietly)
        print('🍎 iOS: Requesting PROVISIONAL permission...');
        settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: true,      // 👈 iOS වලදී popup එකක් නෑ!
        );
      } else {
        // 🔥🔥 Android - NORMAL (Popup එකක් එනවා)
        print('🤖 Android: Requesting permission...');
        settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('✅ Mobile permission granted');
        return true;
      } else {
        print('❌ Mobile permission denied');
        return false;
      }
    } catch (e) {
      print('❌ Mobile permission error: $e');
      return false;
    }
  }

  // ============= 📱 LOCAL NOTIFICATIONS =============
  Future<void> _initLocalNotifications() async {
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
          InitializationSettings(
            android: androidSettings,
            iOS: iosSettings,
          );

      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null) {
            _handleNavigation(payload);
          }
        },
      );

      // Android notification channel එක create කරන්න
      if (UniversalPlatform.isAndroid) {
        await _createAndroidNotificationChannel();
      }
      
      print('✅ Local notifications initialized');
    } catch (e) {
      print('❌ Local notifications init error: $e');
    }
  }

  // ============= 🤖 ANDROID NOTIFICATION CHANNEL =============
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

  // ============= 📱 SHOW MOBILE NOTIFICATION =============
  Future<void> _showMobileNotification(RemoteMessage message) async {
    try {
      RemoteNotification? notification = message.notification;
      if (notification == null) return;

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: AndroidNotificationDetails(
          'salon_channel',
          'Salon Booking Notifications',
          channelDescription: 'Notifications for salon booking updates',
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

      int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      await _localNotifications.show(
        id: notificationId,
        title: notification.title,
        body: notification.body,
        notificationDetails: platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );

      print('✅ Mobile notification shown');
    } catch (e) {
      print('❌ Show mobile notification error: $e');
    }
  }

  // ============= 📱 BACKGROUND NOTIFICATION =============
  Future<void> _showBackgroundNotification(RemoteMessage message) async {
    try {
      RemoteNotification? notification = message.notification;
      if (notification == null) return;

      NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: AndroidNotificationDetails(
          'salon_channel',
          'Salon Booking Notifications',
          channelDescription: 'Notifications for salon booking updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      );

      int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      await _localNotifications.show(
        id: notificationId,
        title: notification.title,
        body: notification.body,
        notificationDetails: platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );

      print('✅ Background notification shown');
    } catch (e) {
      print('❌ Background notification error: $e');
    }
  }

  // ============= 🔑 FCM TOKEN MANAGEMENT =============
  Future<void> _getToken() async {
    try {
      String? token;
      
      if (UniversalPlatform.isWeb) {
        token = await _firebaseMessaging.getToken(vapidKey: _webVapidKey);
      } else {
        token = await _firebaseMessaging.getToken();
      }
      
      if (token != null) {
        print('📱 FCM Token: $token');
        await _saveTokenToServer(token);
      }

      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('🔄 FCM Token refreshed: $newToken');
        _saveTokenToServer(newToken);
      });
    } catch (e) {
      print('❌ Get token error: $e');
    }
  }

  Future<void> _saveTokenToServer(String token) async {
    String platform = UniversalPlatform.isWeb
        ? 'web'
        : UniversalPlatform.isAndroid
        ? 'android'
        : UniversalPlatform.isIOS
        ? 'ios'
        : 'unknown';
    print('💾 Saving token for platform: $platform');
  }

  // ============= 📡 MESSAGE LISTENERS =============
  void _setupMessageListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 Foreground message');
      _handleForegroundMessage(message);
    });

    if (!UniversalPlatform.isWeb) {
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

  void _handleForegroundMessage(RemoteMessage message) {
    if (UniversalPlatform.isWeb) {
      _handleWebForegroundMessage(message);
    } else {
      _showMobileNotification(message);
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

      if (screen == 'booking_details') {
        String bookingId = data['bookingId'] ?? '';
        navigatorKey.currentState?.context.go('/booking-details/$bookingId');
      } else {
        navigatorKey.currentState?.context.go('/');
      }
    } catch (e) {
      print('❌ Navigation error: $e');
    }
  }

  // ============= PUBLIC METHODS =============
  Future<bool> requestWebPermissionFromUI() async {
    if (UniversalPlatform.isWeb) {
      return await requestWebPermission();
    }
    return false;
  }

  Future<bool> hasPermission() async {
    NotificationSettings settings = await _firebaseMessaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }
}

// ============= 📱 BACKGROUND HANDLER =============
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final notificationService = NotificationService();
  await notificationService._showBackgroundNotification(message);
}