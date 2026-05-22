// lib/services/timezone_service.dart

import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneService {
  static bool _initialized = false;
  static String _currentTimezone = 'Asia/Colombo';
  static String _currentCountryCode = 'LK';
  static String _currentCountryName = 'Sri Lanka';
  static int _utcOffsetHours = 5;
  static int _utcOffsetMinutes = 30;

  // Available timezones by country (for UI)
  static final Map<String, List<Map<String, String>>> countryTimezones = {
    'LK': [{'name': 'Sri Lanka', 'timezone': 'Asia/Colombo', 'offset': '+5:30', 'flag': '🇱🇰'}],
    'US': [
      {'name': 'Eastern Time', 'timezone': 'America/New_York', 'offset': '-5:00', 'flag': '🇺🇸'},
      {'name': 'Central Time', 'timezone': 'America/Chicago', 'offset': '-6:00', 'flag': '🇺🇸'},
      {'name': 'Mountain Time', 'timezone': 'America/Denver', 'offset': '-7:00', 'flag': '🇺🇸'},
      {'name': 'Pacific Time', 'timezone': 'America/Los_Angeles', 'offset': '-8:00', 'flag': '🇺🇸'},
    ],
    'GB': [{'name': 'United Kingdom', 'timezone': 'Europe/London', 'offset': '+0:00', 'flag': '🇬🇧'}],
    'AU': [
      {'name': 'Sydney', 'timezone': 'Australia/Sydney', 'offset': '+10:00', 'flag': '🇦🇺'},
      {'name': 'Perth', 'timezone': 'Australia/Perth', 'offset': '+8:00', 'flag': '🇦🇺'},
    ],
    'CA': [
      {'name': 'Toronto', 'timezone': 'America/Toronto', 'offset': '-5:00', 'flag': '🇨🇦'},
      {'name': 'Vancouver', 'timezone': 'America/Vancouver', 'offset': '-8:00', 'flag': '🇨🇦'},
    ],
    'IN': [{'name': 'India', 'timezone': 'Asia/Kolkata', 'offset': '+5:30', 'flag': '🇮🇳'}],
    'AE': [{'name': 'Dubai', 'timezone': 'Asia/Dubai', 'offset': '+4:00', 'flag': '🇦🇪'}],
    'SG': [{'name': 'Singapore', 'timezone': 'Asia/Singapore', 'offset': '+8:00', 'flag': '🇸🇬'}],
    'MY': [{'name': 'Malaysia', 'timezone': 'Asia/Kuala_Lumpur', 'offset': '+8:00', 'flag': '🇲🇾'}],
    'JP': [{'name': 'Japan', 'timezone': 'Asia/Tokyo', 'offset': '+9:00', 'flag': '🇯🇵'}],
    'KR': [{'name': 'South Korea', 'timezone': 'Asia/Seoul', 'offset': '+9:00', 'flag': '🇰🇷'}],
  };

  // Initialize timezone service
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // Initialize timezone database
    tz.initializeTimeZones();
    _initialized = true;
    
    await _loadTimezone();
  }

  static Future<void> _loadTimezone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedTimezone = prefs.getString('cached_timezone');

      if (cachedTimezone != null && cachedTimezone.isNotEmpty) {
        _currentTimezone = cachedTimezone;
        await _applyTimezone(_currentTimezone);      
        return;
      }

      // Auto-detect from device
      final String deviceTimezone = await FlutterNativeTimezone.getLocalTimezone();   

      if (_isValidTimezone(deviceTimezone)) {
        _currentTimezone = deviceTimezone;
        await _applyTimezone(_currentTimezone);
        await prefs.setString('cached_timezone', _currentTimezone);
       
      } else {
       
        _currentTimezone = 'Asia/Colombo';
        await _applyTimezone(_currentTimezone);
      }
    } catch (e) {
      debugPrint('❌ Error detecting timezone: $e');
      _currentTimezone = 'Asia/Colombo';
      await _applyTimezone(_currentTimezone);
    }
  }

  static Future<void> _applyTimezone(String timezone) async {
    try {
      tz.setLocalLocation(tz.getLocation(timezone));
      _updateOffsets(timezone);
      _updateCountryInfo(timezone);
    } catch (e) {
      debugPrint('Error applying timezone: $e');
    }
  }

  static void _updateOffsets(String timezone) {
    try {
      final location = tz.getLocation(timezone);
      final tzNow = tz.TZDateTime.now(location);
      final offset = tzNow.timeZoneOffset;
      _utcOffsetHours = offset.inHours;
      _utcOffsetMinutes = offset.inMinutes.abs() % 60;
    } catch (e) {
      // Fallback to manual offsets
      for (var entry in countryTimezones.entries) {
        for (var tz in entry.value) {
          if (tz['timezone'] == timezone) {
            final offsetStr = tz['offset']!;
            final isNegative = offsetStr.startsWith('-');
            final parts = offsetStr.replaceAll(RegExp(r'[+-]'), '').split(':');
            int hours = int.parse(parts[0]);
            int minutes = parts.length > 1 ? int.parse(parts[1]) : 0;
            if (isNegative) {
              _utcOffsetHours = -hours;
              _utcOffsetMinutes = -minutes;
            } else {
              _utcOffsetHours = hours;
              _utcOffsetMinutes = minutes;
            }
            return;
          }
        }
      }
    }
  }

  static void _updateCountryInfo(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) {
          _currentCountryCode = entry.key;
          _currentCountryName = tz['name']!;
          return;
        }
      }
    }
    _currentCountryCode = 'LK';
    _currentCountryName = 'Sri Lanka';
  }

  static bool _isValidTimezone(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) return true;
      }
    }
    return false;
  }

  static Future<void> setTimezone(String timezone) async {
    _currentTimezone = timezone;
    await _applyTimezone(timezone);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_timezone', timezone);
   
  }

  static List<Map<String, String>> getTimezonesForCountry(String countryCode) {
    return countryTimezones[countryCode] ?? countryTimezones['LK']!;
  }

  static List<Map<String, String>> getAllCountries() {
    final countries = <Map<String, String>>[];
    for (var entry in countryTimezones.entries) {
      final firstTz = entry.value.first;
      countries.add({
        'code': entry.key,
        'name': firstTz['name']!,
        'flag': firstTz['flag']!,
        'timezone': firstTz['timezone']!,
      });
    }
    return countries;
  }

  static String getCurrentTimezone() => _currentTimezone;
  static String getCurrentCountryCode() => _currentCountryCode;
  static String getCurrentCountryName() => _currentCountryName;
  static String getCurrentFlag() {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == _currentTimezone) return tz['flag']!;
      }
    }
    return '🇱🇰';
  }

  static int getUtcOffsetHours() => _utcOffsetHours;
  static int getUtcOffsetMinutes() => _utcOffsetMinutes;

  // ==================== UTC TO LOCAL (Using timezone package) ====================
  
  static DateTime utcToLocalDateTime(String utcTime, DateTime selectedDate) {
    try {
      String timeStr = utcTime;
      if (timeStr.length > 5) timeStr = timeStr.substring(0, 5);
      final parts = timeStr.split(':');
      int utcHour = int.parse(parts[0]);
      int utcMinute = int.parse(parts[1]);

      final utcDateTime = DateTime.utc(
        selectedDate.year, selectedDate.month, selectedDate.day,
        utcHour, utcMinute,
      );
      
      final location = tz.getLocation(_currentTimezone);
      final localDateTime = tz.TZDateTime.from(utcDateTime, location);
      return localDateTime;
    } catch (e) {
      return selectedDate;
    }
  }

  static String utcToLocalTime(String utcTime, DateTime date) {
    try {
      final localDateTime = utcToLocalDateTime(utcTime, date);
      final period = localDateTime.hour >= 12 ? 'PM' : 'AM';
      final displayHour = localDateTime.hour % 12 == 0 ? 12 : localDateTime.hour % 12;
      return '$displayHour:${localDateTime.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return utcTime;
    }
  }

  static Map<String, int> getLocalHourMinute(String utcTime, DateTime selectedDate) {
    try {
      final localDateTime = utcToLocalDateTime(utcTime, selectedDate);
      return {
        'hour': localDateTime.hour,
        'minute': localDateTime.minute,
        'dayOffset': localDateTime.day - selectedDate.day,
      };
    } catch (e) {
      return {'hour': 0, 'minute': 0, 'dayOffset': 0};
    }
  }

  // ==================== LOCAL TO UTC ====================
  
  static String localToUtcTime(String localTime, DateTime selectedDate) {
    try {
      bool is12Hour = localTime.contains('AM') || localTime.contains('PM');
      
      int hour = 0, minute = 0;
      if (is12Hour) {
        final timeParts = localTime.split(' ');
        final hourMinute = timeParts[0].split(':');
        final period = timeParts[1];
        hour = int.parse(hourMinute[0]);
        minute = int.parse(hourMinute[1]);
        if (period == 'PM' && hour != 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
      } else {
        final parts = localTime.split(':');
        hour = int.parse(parts[0]);
        minute = int.parse(parts[1]);
      }
      
      final location = tz.getLocation(_currentTimezone);
      final localDateTime = tz.TZDateTime(
        location,
        selectedDate.year, selectedDate.month, selectedDate.day,
        hour, minute,
      );
      
      final utcDateTime = localDateTime.toUtc();
      return '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      return localTime;
    }
  }

  // ==================== UI HELPERS ====================
  
  static String getTimezoneDisplayName() => _currentCountryName;
  static String getTimezoneFlag() => getCurrentFlag();
  
  static String getUtcOffsetString() {
    final sign = _utcOffsetHours >= 0 ? '+' : '';
    final hours = _utcOffsetHours.abs();
    final minutes = _utcOffsetMinutes.abs();
    return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }
}