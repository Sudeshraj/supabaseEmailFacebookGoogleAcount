import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneService {
  static bool _initialized = false;
  static String _currentTimezone = 'Asia/Colombo';
  static String _currentCountryCode = 'LK';
  static String _currentCountryName = 'Sri Lanka';
  static int _utcOffsetHours = 5;
  static int _utcOffsetMinutes = 30;

  // ==================== COUNTRY TIMEZONES MAP ====================
  static final Map<String, List<Map<String, String>>> countryTimezones = {
    'LK': [
      {
        'name': 'Sri Lanka',
        'timezone': 'Asia/Colombo',
        'offset': '+5:30',
        'flag': '🇱🇰',
      },
    ],
    'US': [
      {
        'name': 'Eastern Time',
        'timezone': 'America/New_York',
        'offset': '-5:00',
        'flag': '🇺🇸',
      },
      {
        'name': 'Central Time',
        'timezone': 'America/Chicago',
        'offset': '-6:00',
        'flag': '🇺🇸',
      },
      {
        'name': 'Mountain Time',
        'timezone': 'America/Denver',
        'offset': '-7:00',
        'flag': '🇺🇸',
      },
      {
        'name': 'Pacific Time',
        'timezone': 'America/Los_Angeles',
        'offset': '-8:00',
        'flag': '🇺🇸',
      },
    ],
    'GB': [
      {
        'name': 'United Kingdom',
        'timezone': 'Europe/London',
        'offset': '+0:00',
        'flag': '🇬🇧',
      },
    ],
    'AU': [
      {
        'name': 'Sydney',
        'timezone': 'Australia/Sydney',
        'offset': '+10:00',
        'flag': '🇦🇺',
      },
      {
        'name': 'Perth',
        'timezone': 'Australia/Perth',
        'offset': '+8:00',
        'flag': '🇦🇺',
      },
    ],
    'CA': [
      {
        'name': 'Toronto',
        'timezone': 'America/Toronto',
        'offset': '-5:00',
        'flag': '🇨🇦',
      },
      {
        'name': 'Vancouver',
        'timezone': 'America/Vancouver',
        'offset': '-8:00',
        'flag': '🇨🇦',
      },
    ],
    'IN': [
      {
        'name': 'India',
        'timezone': 'Asia/Kolkata',
        'offset': '+5:30',
        'flag': '🇮🇳',
      },
    ],
    'AE': [
      {
        'name': 'Dubai',
        'timezone': 'Asia/Dubai',
        'offset': '+4:00',
        'flag': '🇦🇪',
      },
    ],
    'SG': [
      {
        'name': 'Singapore',
        'timezone': 'Asia/Singapore',
        'offset': '+8:00',
        'flag': '🇸🇬',
      },
    ],
    'MY': [
      {
        'name': 'Malaysia',
        'timezone': 'Asia/Kuala_Lumpur',
        'offset': '+8:00',
        'flag': '🇲🇾',
      },
    ],
    'JP': [
      {
        'name': 'Japan',
        'timezone': 'Asia/Tokyo',
        'offset': '+9:00',
        'flag': '🇯🇵',
      },
    ],
    'KR': [
      {
        'name': 'South Korea',
        'timezone': 'Asia/Seoul',
        'offset': '+9:00',
        'flag': '🇰🇷',
      },
    ],
    'DE': [
      {
        'name': 'Germany',
        'timezone': 'Europe/Berlin',
        'offset': '+1:00',
        'flag': '🇩🇪',
      },
    ],
    'FR': [
      {
        'name': 'France',
        'timezone': 'Europe/Paris',
        'offset': '+1:00',
        'flag': '🇫🇷',
      },
    ],
    'IT': [
      {
        'name': 'Italy',
        'timezone': 'Europe/Rome',
        'offset': '+1:00',
        'flag': '🇮🇹',
      },
    ],
    'ES': [
      {
        'name': 'Spain',
        'timezone': 'Europe/Madrid',
        'offset': '+1:00',
        'flag': '🇪🇸',
      },
    ],
    'BR': [
      {
        'name': 'Sao Paulo',
        'timezone': 'America/Sao_Paulo',
        'offset': '-3:00',
        'flag': '🇧🇷',
      },
      {
        'name': 'Rio Branco',
        'timezone': 'America/Rio_Branco',
        'offset': '-5:00',
        'flag': '🇧🇷',
      },
    ],
    'RU': [
      {
        'name': 'Moscow',
        'timezone': 'Europe/Moscow',
        'offset': '+3:00',
        'flag': '🇷🇺',
      },
      {
        'name': 'Vladivostok',
        'timezone': 'Asia/Vladivostok',
        'offset': '+10:00',
        'flag': '🇷🇺',
      },
    ],
    'ZA': [
      {
        'name': 'South Africa',
        'timezone': 'Africa/Johannesburg',
        'offset': '+2:00',
        'flag': '🇿🇦',
      },
    ],
    'EG': [
      {
        'name': 'Egypt',
        'timezone': 'Africa/Cairo',
        'offset': '+2:00',
        'flag': '🇪🇬',
      },
    ],
    'SA': [
      {
        'name': 'Saudi Arabia',
        'timezone': 'Asia/Riyadh',
        'offset': '+3:00',
        'flag': '🇸🇦',
      },
    ],
    'TR': [
      {
        'name': 'Turkey',
        'timezone': 'Europe/Istanbul',
        'offset': '+3:00',
        'flag': '🇹🇷',
      },
    ],
    'PK': [
      {
        'name': 'Pakistan',
        'timezone': 'Asia/Karachi',
        'offset': '+5:00',
        'flag': '🇵🇰',
      },
    ],
    'BD': [
      {
        'name': 'Bangladesh',
        'timezone': 'Asia/Dhaka',
        'offset': '+6:00',
        'flag': '🇧🇩',
      },
    ],
    'NP': [
      {
        'name': 'Nepal',
        'timezone': 'Asia/Kathmandu',
        'offset': '+5:45',
        'flag': '🇳🇵',
      },
    ],
    'TH': [
      {
        'name': 'Thailand',
        'timezone': 'Asia/Bangkok',
        'offset': '+7:00',
        'flag': '🇹🇭',
      },
    ],
    'VN': [
      {
        'name': 'Vietnam',
        'timezone': 'Asia/Ho_Chi_Minh',
        'offset': '+7:00',
        'flag': '🇻🇳',
      },
    ],
    'ID': [
      {
        'name': 'Jakarta',
        'timezone': 'Asia/Jakarta',
        'offset': '+7:00',
        'flag': '🇮🇩',
      },
      {
        'name': 'Bali',
        'timezone': 'Asia/Makassar',
        'offset': '+8:00',
        'flag': '🇮🇩',
      },
    ],
    'PH': [
      {
        'name': 'Philippines',
        'timezone': 'Asia/Manila',
        'offset': '+8:00',
        'flag': '🇵🇭',
      },
    ],
    'NZ': [
      {
        'name': 'Auckland',
        'timezone': 'Pacific/Auckland',
        'offset': '+12:00',
        'flag': '🇳🇿',
      },
    ],
    'MX': [
      {
        'name': 'Mexico City',
        'timezone': 'America/Mexico_City',
        'offset': '-6:00',
        'flag': '🇲🇽',
      },
    ],
    'AR': [
      {
        'name': 'Argentina',
        'timezone': 'America/Argentina/Buenos_Aires',
        'offset': '-3:00',
        'flag': '🇦🇷',
      },
    ],
    'CL': [
      {
        'name': 'Chile',
        'timezone': 'America/Santiago',
        'offset': '-3:00',
        'flag': '🇨🇱',
      },
    ],
    'CO': [
      {
        'name': 'Colombia',
        'timezone': 'America/Bogota',
        'offset': '-5:00',
        'flag': '🇨🇴',
      },
    ],
    'PE': [
      {
        'name': 'Peru',
        'timezone': 'America/Lima',
        'offset': '-5:00',
        'flag': '🇵🇪',
      },
    ],
    'NG': [
      {
        'name': 'Nigeria',
        'timezone': 'Africa/Lagos',
        'offset': '+1:00',
        'flag': '🇳🇬',
      },
    ],
    'KE': [
      {
        'name': 'Kenya',
        'timezone': 'Africa/Nairobi',
        'offset': '+3:00',
        'flag': '🇰🇪',
      },
    ],
  };

  // ==================== INITIALIZATION ====================
  static Future<void> initialize() async {
    if (_initialized) return;

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
        debugPrint('✅ Using cached timezone: $_currentTimezone');
        return;
      }

      final String deviceTimezone = await FlutterTimezone.getLocalTimezone();
      debugPrint('📱 Device timezone detected: $deviceTimezone');

      if (_isValidTimezone(deviceTimezone)) {
        _currentTimezone = deviceTimezone;
        await _applyTimezone(_currentTimezone);
        await prefs.setString('cached_timezone', _currentTimezone);
        debugPrint('✅ Saved device timezone to cache: $_currentTimezone');
      } else {
        _currentTimezone = 'Asia/Colombo';
        await _applyTimezone(_currentTimezone);
        await prefs.setString('cached_timezone', _currentTimezone);
      }
    } catch (e) {
      debugPrint('❌ Error detecting timezone: $e');
      _currentTimezone = 'Asia/Colombo';
      await _applyTimezone(_currentTimezone);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_timezone', _currentTimezone);
    }
  }

  // ==================== VALIDATION ====================
  static bool _isValidTimezone(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) return true;
      }
    }
    try {
      tz.getLocation(timezone);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> _applyTimezone(String timezone) async {
    try {
      tz.setLocalLocation(tz.getLocation(timezone));
      _updateOffsets(timezone);
      _updateCountryInfo(timezone);
      debugPrint('🌍 Applied timezone: $timezone (${getUtcOffsetString()})');
    } catch (e) {
      debugPrint('❌ Error applying timezone: $e');
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

    if (timezone.contains('/')) {
      final parts = timezone.split('/');
      _currentCountryCode = parts[0];
      _currentCountryName = parts[1].replaceAll('_', ' ');
    } else {
      _currentCountryCode = 'INT';
      _currentCountryName = 'International';
    }
  }

  // ==================== PUBLIC GETTERS ====================

  static String getTimezoneFlag() {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == _currentTimezone) {
          return tz['flag']!;
        }
      }
    }
    return '🌍';
  }

  static String getCurrentFlag() => getTimezoneFlag();
  static String getCurrentTimezone() => _currentTimezone;
  static String getCurrentCountryCode() => _currentCountryCode;
  static String getCurrentCountryName() => _currentCountryName;
  static int getUtcOffsetHours() => _utcOffsetHours;
  static int getUtcOffsetMinutes() => _utcOffsetMinutes;
  static String getTimezoneDisplayName() => _currentCountryName;

  static String getUtcOffsetString() {
    final sign = _utcOffsetHours >= 0 ? '+' : '';
    final hours = _utcOffsetHours.abs();
    final minutes = _utcOffsetMinutes.abs();
    return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

  static String getFullTimezoneDisplay() {
    return '${getTimezoneFlag()} ${getTimezoneDisplayName()} (${getUtcOffsetString()})';
  }

  static Future<void> setTimezone(String timezone) async {
    if (!_isValidTimezone(timezone)) {
      debugPrint('❌ Invalid timezone: $timezone');
      return;
    }

    _currentTimezone = timezone;
    await _applyTimezone(timezone);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_timezone', timezone);
    debugPrint('✏️ User changed timezone to: $timezone');
  }

  static Future<void> clearCachedTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_timezone');
    debugPrint('🗑️ Cached timezone cleared');
  }

  static Future<void> refreshTimezone() async {
    await clearCachedTimezone();
    await _loadTimezone();
    debugPrint('🔄 Timezone refreshed');
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

  static List<String> getAllAvailableTimezones() {
    return tz.timeZoneDatabase.locations.keys.toList();
  }

  // ==================== DST-SAFE CONVERSIONS (WITH CURRENT TIMEZONE) ====================

  /// Convert UTC time to LOCAL DateTime using REFERENCE DATE (No DST issues)
  /// Use this for: barber schedules, lunch breaks, recurring events
  static DateTime utcToLocalDateTimeRecurring(String utcTime) {
    try {
      String timeStr = utcTime;
      if (timeStr.length > 5) timeStr = timeStr.substring(0, 5);
      final parts = timeStr.split(':');
      int utcHour = int.parse(parts[0]);
      int utcMinute = int.parse(parts[1]);

      final referenceDate = DateTime(2024, 1, 1);

      final utcDateTime = DateTime.utc(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        utcHour,
        utcMinute,
      );

      final location = tz.getLocation(_currentTimezone);
      final localDateTime = tz.TZDateTime.from(utcDateTime, location);
      return localDateTime;
    } catch (e) {
      debugPrint('❌ Error in utcToLocalDateTimeRecurring: $e');
      return DateTime(2024, 1, 1, 0, 0);
    }
  }

  /// Convert UTC time to LOCAL time string (For recurring schedules)
  static String utcToLocalTimeRecurring(String utcTime) {
    try {
      final localDateTime = utcToLocalDateTimeRecurring(utcTime);
      final period = localDateTime.hour >= 12 ? 'PM' : 'AM';
      final displayHour = localDateTime.hour % 12 == 0
          ? 12
          : localDateTime.hour % 12;
      return '$displayHour:${localDateTime.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      debugPrint('❌ Error in utcToLocalTimeRecurring: $e');
      return utcTime;
    }
  }

  /// Convert LOCAL time to UTC time using REFERENCE DATE (For recurring schedules)
  static String localToUtcTimeRecurring(String localTime) {
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

      final referenceDate = DateTime(2024, 1, 1);

      final localDateTime = tz.TZDateTime(
        location,
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        hour,
        minute,
      );

      final utcDateTime = localDateTime.toUtc();
      return '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      debugPrint('❌ Error in localToUtcTimeRecurring: $e');
      return localTime;
    }
  }
  // ==================== DST DETECTION ====================

  /// Check if DST (Daylight Saving Time) is currently active
  static bool isDST() {
    try {
      final location = tz.getLocation(_currentTimezone);

      // Current offset
      final currentOffset = tz.TZDateTime.now(location).timeZoneOffset;

      // Standard offset (January - no DST)
      final janDate = DateTime(2024, 1, 15);
      final janOffset = tz.TZDateTime(
        location,
        janDate.year,
        janDate.month,
        janDate.day,
        12,
        0,
        0,
      ).timeZoneOffset;

      // DST offset (July - DST in northern hemisphere)
      final julDate = DateTime(2024, 7, 15);
      final julOffset = tz.TZDateTime(
        location,
        julDate.year,
        julDate.month,
        julDate.day,
        12,
        0,
        0,
      ).timeZoneOffset;

      // If offsets don't differ, no DST
      if (janOffset == julOffset) {
        return false;
      }

      // Standard offset is the smaller one
      final standardOffset = janOffset < julOffset ? janOffset : julOffset;

      // DST active if current offset != standard offset
      return currentOffset != standardOffset;
    } catch (e) {
      debugPrint('❌ Error detecting DST: $e');
      return false;
    }
  }

  /// Get DST status with offset details
  static Map<String, dynamic> getDSTStatus() {
    try {
      final location = tz.getLocation(_currentTimezone);

      final currentOffset = tz.TZDateTime.now(location).timeZoneOffset;

      final janDate = DateTime(2024, 1, 15);
      final janOffset = tz.TZDateTime(
        location,
        janDate.year,
        janDate.month,
        janDate.day,
        12,
        0,
        0,
      ).timeZoneOffset;

      final julDate = DateTime(2024, 7, 15);
      final julOffset = tz.TZDateTime(
        location,
        julDate.year,
        julDate.month,
        julDate.day,
        12,
        0,
        0,
      ).timeZoneOffset;

      final usesDST = janOffset != julOffset;

      if (!usesDST) {
        return {
          'isDST': false,
          'usesDST': false,
          'currentOffset': currentOffset,
          'standardOffset': currentOffset,
          'dstOffset': currentOffset,
          'offsetDifferenceMinutes': 0,
        };
      }

      final standardOffset = janOffset < julOffset ? janOffset : julOffset;
      final dstOffset = janOffset > julOffset ? janOffset : julOffset;
      final isDSTActive = currentOffset != standardOffset;

      return {
        'isDST': isDSTActive,
        'usesDST': true,
        'currentOffset': currentOffset,
        'currentOffsetHours': currentOffset.inHours,
        'standardOffset': standardOffset,
        'standardOffsetHours': standardOffset.inHours,
        'dstOffset': dstOffset,
        'dstOffsetHours': dstOffset.inHours,
        'offsetDifferenceMinutes': (dstOffset - standardOffset).inMinutes.abs(),
      };
    } catch (e) {
      debugPrint('❌ Error getting DST status: $e');
      return {'isDST': false, 'usesDST': false};
    }
  }

  // ==================== DST-SAFE CONVERSIONS (WITH CUSTOM TIMEZONE) ====================

  /// Convert UTC time to LOCAL DateTime using REFERENCE DATE with custom timezone
  static DateTime utcToLocalDateTimeRecurringWithTimezone(
    String utcTime,
    String timezone,
  ) {
    try {
      String timeStr = utcTime;
      if (timeStr.length > 5) timeStr = timeStr.substring(0, 5);
      final parts = timeStr.split(':');
      int utcHour = int.parse(parts[0]);
      int utcMinute = int.parse(parts[1]);

      final referenceDate = DateTime(2024, 1, 1);

      final utcDateTime = DateTime.utc(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        utcHour,
        utcMinute,
      );

      final location = tz.getLocation(timezone);
      final localDateTime = tz.TZDateTime.from(utcDateTime, location);
      return localDateTime;
    } catch (e) {
      debugPrint('❌ Error in utcToLocalDateTimeRecurringWithTimezone: $e');
      return DateTime(2024, 1, 1, 0, 0);
    }
  }

  /// Convert UTC time to LOCAL time string (For recurring schedules) with custom timezone
  static String utcToLocalTimeRecurringWithTimezone(
    String utcTime,
    String timezone,
  ) {
    try {
      final localDateTime = utcToLocalDateTimeRecurringWithTimezone(
        utcTime,
        timezone,
      );
      final period = localDateTime.hour >= 12 ? 'PM' : 'AM';
      final displayHour = localDateTime.hour % 12 == 0
          ? 12
          : localDateTime.hour % 12;
      return '$displayHour:${localDateTime.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      debugPrint('❌ Error in utcToLocalTimeRecurringWithTimezone: $e');
      return utcTime;
    }
  }

  /// Convert LOCAL time to UTC time using REFERENCE DATE with custom timezone
  static String localToUtcTimeRecurringWithTimezone(
    String localTime,
    String timezone,
  ) {
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

      final location = tz.getLocation(timezone);

      final referenceDate = DateTime(2024, 1, 1);

      final localDateTime = tz.TZDateTime(
        location,
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        hour,
        minute,
      );

      final utcDateTime = localDateTime.toUtc();
      return '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      debugPrint('❌ Error in localToUtcTimeRecurringWithTimezone: $e');
      return localTime;
    }
  }

  // ==================== DST-SAFE CONVERSIONS FOR SPECIFIC DATES ====================

  /// Convert UTC time to LOCAL DateTime using SPECIFIC DATE (For appointments)
  static DateTime utcToLocalDateTimeForDate(
    String utcTime,
    DateTime specificDate,
  ) {
    try {
      String timeStr = utcTime;
      if (timeStr.length > 5) timeStr = timeStr.substring(0, 5);
      final parts = timeStr.split(':');
      int utcHour = int.parse(parts[0]);
      int utcMinute = int.parse(parts[1]);

      final utcDateTime = DateTime.utc(
        specificDate.year,
        specificDate.month,
        specificDate.day,
        utcHour,
        utcMinute,
      );

      final location = tz.getLocation(_currentTimezone);
      final localDateTime = tz.TZDateTime.from(utcDateTime, location);
      return localDateTime;
    } catch (e) {
      debugPrint('❌ Error in utcToLocalDateTimeForDate: $e');
      return specificDate;
    }
  }

  /// Convert UTC time to LOCAL time string (For specific date appointments)
  static String utcToLocalTimeForDate(String utcTime, DateTime date) {
    try {
      final localDateTime = utcToLocalDateTimeForDate(utcTime, date);
      final period = localDateTime.hour >= 12 ? 'PM' : 'AM';
      final displayHour = localDateTime.hour % 12 == 0
          ? 12
          : localDateTime.hour % 12;
      return '$displayHour:${localDateTime.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      debugPrint('❌ Error in utcToLocalTimeForDate: $e');
      return utcTime;
    }
  }

  /// Convert LOCAL time to UTC time using SPECIFIC DATE (For appointments)
  static String localToUtcTimeForDate(String localTime, DateTime selectedDate) {
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
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        hour,
        minute,
      );

      final utcDateTime = localDateTime.toUtc();
      return '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      debugPrint('❌ Error in localToUtcTimeForDate: $e');
      return localTime;
    }
  }

  // ==================== DST-SAFE CONVERSIONS FOR SPECIFIC DATES WITH CUSTOM TIMEZONE ====================

  /// Convert UTC time to LOCAL DateTime using SPECIFIC DATE with custom timezone
  static DateTime utcToLocalDateTimeForDateWithTimezone(
    String utcTime,
    DateTime specificDate,
    String timezone,
  ) {
    try {
      String timeStr = utcTime;
      if (timeStr.length > 5) timeStr = timeStr.substring(0, 5);
      final parts = timeStr.split(':');
      int utcHour = int.parse(parts[0]);
      int utcMinute = int.parse(parts[1]);

      final utcDateTime = DateTime.utc(
        specificDate.year,
        specificDate.month,
        specificDate.day,
        utcHour,
        utcMinute,
      );

      final location = tz.getLocation(timezone);
      final localDateTime = tz.TZDateTime.from(utcDateTime, location);
      return localDateTime;
    } catch (e) {
      debugPrint('❌ Error in utcToLocalDateTimeForDateWithTimezone: $e');
      return specificDate;
    }
  }

  /// Convert UTC time to LOCAL time string with custom timezone
  static String utcToLocalTimeForDateWithTimezone(
    String utcTime,
    DateTime date,
    String timezone,
  ) {
    try {
      final localDateTime = utcToLocalDateTimeForDateWithTimezone(
        utcTime,
        date,
        timezone,
      );
      final period = localDateTime.hour >= 12 ? 'PM' : 'AM';
      final displayHour = localDateTime.hour % 12 == 0
          ? 12
          : localDateTime.hour % 12;
      return '$displayHour:${localDateTime.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      debugPrint('❌ Error in utcToLocalTimeForDateWithTimezone: $e');
      return utcTime;
    }
  }

  /// Convert LOCAL time to UTC time with custom timezone
  static String localToUtcTimeForDateWithTimezone(
    String localTime,
    DateTime selectedDate,
    String timezone,
  ) {
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

      final location = tz.getLocation(timezone);
      final localDateTime = tz.TZDateTime(
        location,
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        hour,
        minute,
      );

      final utcDateTime = localDateTime.toUtc();
      return '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      debugPrint('❌ Error in localToUtcTimeForDateWithTimezone: $e');
      return localTime;
    }
  }

  // ==================== TIME CONVERSION FOR TimeOfDay ====================

  /// Convert TimeOfDay to UTC time string (using current timezone)
  static String timeOfDayToUtc(TimeOfDay localTime) {
    final timeString =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    return localToUtcTimeRecurring(timeString);
  }

  /// Convert TimeOfDay to UTC time string with custom timezone
  static String timeOfDayToUtcWithTimezone(
    TimeOfDay localTime,
    String timezone,
  ) {
    final timeString =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    return localToUtcTimeRecurringWithTimezone(timeString, timezone);
  }

  /// Convert UTC time string to TimeOfDay (using current timezone)
  static TimeOfDay utcToTimeOfDay(String utcTime) {
    final localDateTime = utcToLocalDateTimeRecurring(utcTime);
    return TimeOfDay(hour: localDateTime.hour, minute: localDateTime.minute);
  }

  /// Convert UTC time string to TimeOfDay with custom timezone
  static TimeOfDay utcToTimeOfDayWithTimezone(String utcTime, String timezone) {
    final localDateTime = utcToLocalDateTimeRecurringWithTimezone(
      utcTime,
      timezone,
    );
    return TimeOfDay(hour: localDateTime.hour, minute: localDateTime.minute);
  }

  // ==================== GET LOCAL HOUR MINUTE ====================

  /// Get local hour/minute for recurring schedules
  static Map<String, int> getLocalHourMinuteRecurring(String utcTime) {
    try {
      final localDateTime = utcToLocalDateTimeRecurring(utcTime);
      return {
        'hour': localDateTime.hour,
        'minute': localDateTime.minute,
        'dayOffset': 0,
      };
    } catch (e) {
      debugPrint('❌ Error in getLocalHourMinuteRecurring: $e');
      return {'hour': 0, 'minute': 0, 'dayOffset': 0};
    }
  }

  /// Get local hour/minute for specific date
  static Map<String, int> getLocalHourMinuteForDate(
    String utcTime,
    DateTime selectedDate,
  ) {
    try {
      final localDateTime = utcToLocalDateTimeForDate(utcTime, selectedDate);
      return {
        'hour': localDateTime.hour,
        'minute': localDateTime.minute,
        'dayOffset': localDateTime.day - selectedDate.day,
      };
    } catch (e) {
      debugPrint('❌ Error in getLocalHourMinuteForDate: $e');
      return {'hour': 0, 'minute': 0, 'dayOffset': 0};
    }
  }

  // ==================== BACKWARD COMPATIBILITY (DEPRECATED METHODS) ====================

  @Deprecated(
    'Use utcToLocalDateTimeRecurring() for recurring schedules or utcToLocalDateTimeForDate() for appointments',
  )
  static DateTime utcToLocalDateTime(String utcTime, DateTime selectedDate) {
    return utcToLocalDateTimeForDate(utcTime, selectedDate);
  }

  @Deprecated(
    'Use utcToLocalTimeRecurring() for recurring schedules or utcToLocalTimeForDate() for appointments',
  )
  static String utcToLocalTime(String utcTime, DateTime date) {
    return utcToLocalTimeForDate(utcTime, date);
  }

  @Deprecated(
    'Use getLocalHourMinuteRecurring() or getLocalHourMinuteForDate()',
  )
  static Map<String, int> getLocalHourMinute(
    String utcTime,
    DateTime selectedDate,
  ) {
    return getLocalHourMinuteForDate(utcTime, selectedDate);
  }

  @Deprecated(
    'Use localToUtcTimeRecurring() for recurring schedules or localToUtcTimeForDate() for appointments',
  )
  static String localToUtcTime(String localTime, DateTime selectedDate) {
    return localToUtcTimeForDate(localTime, selectedDate);
  }
}
