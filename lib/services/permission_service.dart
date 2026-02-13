import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  final NotificationService _notificationService = NotificationService();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // 🔥 Permission දැනටමත් අහලාද කියලා check කරගන්න
  Future<bool> hasAskedPermission() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_asked_notification_permission') ?? false;
  }

  // 🔥 Permission ඇහුවා කියලා mark කරගන්න
  Future<void> markAskedPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_asked_notification_permission', true);
  }

  // 🔥 Permission status එක check කරන්න
  Future<bool> hasPermission() async {
    return await _notificationService.hasPermission();
  }

  // 🔥 Platform එක අනුව permission request කරන්න
  // Future<bool> requestNotificationPermission() async {
  //   bool granted = false;
    
  //   if (UniversalPlatform.isWeb) {
  //     granted = await _notificationService.requestWebNotificationPermission();
  //   } else {
  //     granted = await _notificationService.requestMobileNotificationPermission();
  //   }
    
  //   await markAskedPermission();
  //   return granted;
  // }

  // 🔥 Permission card එක පෙන්වන්නද කියලා check කරන්න
  Future<bool> shouldShowPermissionCard() async {
    // Web එකේ නම් user අකමැති වෙන්න පුළුවන්, ඒ නිසා ටිකක් වෙලා බලාගෙන ඉන්න
    if (UniversalPlatform.isWeb) {
      await Future.delayed(const Duration(seconds: 3));
    }
    
    // දැනටමත් permission තියෙනවද?
    bool hasPerm = await hasPermission();
    if (hasPerm) return false;
    
    // කලින් ඇහුවාද?
    bool hasAsked = await hasAskedPermission();
    if (hasAsked) return false;
    
    return true;
  }
}