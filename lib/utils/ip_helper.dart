// lib/utils/ip_helper.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class IpHelper {
  static String? _cachedIp;
  static DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  // Get public IP address with caching
  static Future<String?> getPublicIp() async {
    // Return cached IP if available and not expired
    if (_cachedIp != null && _lastFetchTime != null) {
      final age = DateTime.now().difference(_lastFetchTime!);
      if (age < _cacheDuration) {
        return _cachedIp;
      }
    }
    
    try {
      // Multiple IP services for reliability
      final services = [
        'https://api.ipify.org',
        'https://api.myip.com',
        'https://ipapi.co/ip/',
        'https://api.ip.sb/ip',
        'https://icanhazip.com',
      ];
      
      for (var service in services) {
        try {
          final response = await http.get(
            Uri.parse(service),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 3));
          
          if (response.statusCode == 200) {
            String ip = response.body.trim();
            
            // Try to parse JSON if needed
            if (ip.startsWith('{')) {
              try {
                final jsonData = jsonDecode(ip);
                ip = jsonData['ip'] ?? jsonData['address'] ?? ip;
              } catch (e) {
                // Not JSON, use as is
              }
            }
            
            // Validate IP format (basic check)
            if (_isValidIp(ip)) {
              _cachedIp = ip;
              _lastFetchTime = DateTime.now();
              debugPrint('✅ Got IP: $ip from $service');
              return ip;
            }
          }
        } catch (e) {
          debugPrint('⚠️ IP service failed: $service');
          continue;
        }
      }
      
      // Fallback
      debugPrint('⚠️ Using fallback IP');
      return '0.0.0.0';
    } catch (e) {
      debugPrint('❌ Error getting IP: $e');
      return null;
    }
  }
  
  // Validate IP address format
  static bool _isValidIp(String ip) {
    // IPv4
    if (RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(ip)) {
      final parts = ip.split('.');
      for (var part in parts) {
        final num = int.tryParse(part);
        if (num == null || num < 0 || num > 255) return false;
      }
      return true;
    }
    
    // IPv6 (simplified check)
    if (RegExp(r'^[0-9a-fA-F:]+$').hasMatch(ip)) {
      return ip.contains(':') && ip.length >= 3;
    }
    
    return false;
  }
  
  // Get client IP from headers (for server-side)
  static String? getIpFromHeaders(Map<String, String> headers) {
    final possibleHeaders = [
      'x-forwarded-for',
      'x-real-ip',
      'cf-connecting-ip',
      'remote-addr',
      'client-ip',
      'x-client-ip',
    ];
    
    for (var header in possibleHeaders) {
      if (headers.containsKey(header)) {
        var ip = headers[header]!.split(',').first.trim();
        if (ip.isNotEmpty && _isValidIp(ip)) return ip;
      }
    }
    
    return null;
  }
  
  // Clear cache
  static void clearCache() {
    _cachedIp = null;
    _lastFetchTime = null;
  }
  
  // Get cached IP without fetching
  static String? getCachedIp() => _cachedIp;
}