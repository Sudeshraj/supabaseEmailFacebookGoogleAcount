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

  // ==================== ✅ STORAGE KEYS (PUBLIC - SINGLE SOURCE OF TRUTH) ====================
  // ✅ Public constants - CreateSalonScreen, Settings, හැම file එකකින්ම use කරන්න පුළුවන්
  //    ('user_timezone', 'user_currency' - typo errors නෑ)
  static const String kUserTimezone = 'user_timezone';
  static const String kUserCurrency = 'user_currency';
  static const String kCachedTimezone = 'cached_timezone'; // Legacy backup

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

  /// ✅ FIX: 3-tier priority loading
  /// 1st: 'user_timezone' (Settings වලින් set කරපු එක) - PRIMARY
  /// 2nd: 'cached_timezone' (Legacy backup)
  /// 3rd: Device timezone (First time only)
  static Future<void> _loadTimezone() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ PRIORITY 1: 'user_timezone' (Settings වලින් set කරපු එක)
      final userTimezone = prefs.getString(kUserTimezone);
      if (userTimezone != null && userTimezone.isNotEmpty) {
        if (_isValidTimezone(userTimezone)) {
          _currentTimezone = userTimezone;
          await _applyTimezone(_currentTimezone);
          // ✅ Sync both keys
          await prefs.setString(kCachedTimezone, userTimezone);
          debugPrint('✅ Timezone from USER SETTING: $_currentTimezone');
          return;
        }
      }

      // ✅ PRIORITY 2: 'cached_timezone' (Legacy backup)
      final cachedTimezone = prefs.getString(kCachedTimezone);
      if (cachedTimezone != null && cachedTimezone.isNotEmpty) {
        if (_isValidTimezone(cachedTimezone)) {
          _currentTimezone = cachedTimezone;
          await _applyTimezone(_currentTimezone);
          // ✅ Migrate to user_timezone
          await prefs.setString(kUserTimezone, cachedTimezone);
          debugPrint('✅ Timezone from CACHE: $_currentTimezone');
          return;
        }
      }

      // ✅ PRIORITY 3: Device timezone (First time only)
      final String deviceTimezone =
          (await FlutterTimezone.getLocalTimezone()).identifier;
      debugPrint('📱 Device timezone detected: $deviceTimezone');

      if (_isValidTimezone(deviceTimezone)) {
        _currentTimezone = deviceTimezone;
        await _applyTimezone(_currentTimezone);
        // ✅ Save BOTH keys (sync)
        await prefs.setString(kCachedTimezone, _currentTimezone);
        await prefs.setString(kUserTimezone, _currentTimezone);
        debugPrint('✅ Saved DEVICE timezone: $_currentTimezone');
      } else {
        _currentTimezone = 'Asia/Colombo';
        await _applyTimezone(_currentTimezone);
        await prefs.setString(kCachedTimezone, _currentTimezone);
        await prefs.setString(kUserTimezone, _currentTimezone);
      }
    } catch (e) {
      debugPrint('❌ Error detecting timezone: $e');
      _currentTimezone = 'Asia/Colombo';
      await _applyTimezone(_currentTimezone);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kCachedTimezone, _currentTimezone);
        await prefs.setString(kUserTimezone, _currentTimezone);
      } catch (_) {}
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

  // ==================== PUBLIC GETTERS (CURRENT TIMEZONE) ====================

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

  // ==================== ✅ PUBLIC GETTERS (FOR ANY TIMEZONE) ====================
  // ✅ NEW: මේවා ඕන barber_schedule_screen එකේ _getTimezoneDisplay() එකට
  //    Salon timezone එකේ info පෙන්නන්න

  /// Get flag for a specific timezone (e.g., '🇱🇰' for 'Asia/Colombo')
  static String getTimezoneFlagFor(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) {
          return tz['flag']!;
        }
      }
    }
    return '🌍';
  }

  /// Get display name for a specific timezone (e.g., 'Sri Lanka' for 'Asia/Colombo')
  static String getTimezoneNameFor(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) {
          return tz['name']!;
        }
      }
    }
    // Fallback: derive from timezone string
    if (timezone.contains('/')) {
      return timezone.split('/').last.replaceAll('_', ' ');
    }
    return timezone;
  }

  /// Get UTC offset string for a specific timezone (e.g., 'UTC+5:30')
  static String getUtcOffsetFor(String timezone) {
    try {
      final location = tz.getLocation(timezone);
      final tzNow = tz.TZDateTime.now(location);
      final offset = tzNow.timeZoneOffset;
      final hours = offset.inHours;
      final minutes = offset.inMinutes.abs() % 60;
      final sign = hours >= 0 ? '+' : '';
      return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('❌ Error getting UTC offset for $timezone: $e');
      return 'UTC+0:00';
    }
  }

  /// Get full display for a specific timezone (flag + name + offset)
  /// e.g., '🇱🇰 Sri Lanka (UTC+5:30)'
  static String getFullTimezoneDisplayFor(String timezone) {
    final flag = getTimezoneFlagFor(timezone);
    final name = getTimezoneNameFor(timezone);
    final offset = getUtcOffsetFor(timezone);
    return '$flag $name ($offset)';
  }

  /// Get country code for a specific timezone
  static String getCountryCodeFor(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) {
          return entry.key;
        }
      }
    }
    if (timezone.contains('/')) {
      return timezone.split('/').first;
    }
    return 'INT';
  }

  // ==================== SET / UPDATE TIMEZONE ====================

  /// ✅ FIX: දැන් දෙකම keys save කරනවා (sync)
  static Future<void> setTimezone(String timezone) async {
    if (!_isValidTimezone(timezone)) {
      debugPrint('❌ Invalid timezone: $timezone');
      return;
    }

    _currentTimezone = timezone;
    await _applyTimezone(timezone);

    final prefs = await SharedPreferences.getInstance();

    // ✅ Save BOTH keys - sync එකේ තියාගන්න
    await prefs.setString(kCachedTimezone, timezone);
    await prefs.setString(kUserTimezone, timezone);

    debugPrint('✏️ User changed timezone to: $timezone (saved to both keys)');
  }

  static Future<void> clearCachedTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kCachedTimezone);
    debugPrint('🗑️ Cached timezone cleared');
  }

  static Future<void> refreshTimezone() async {
    await clearCachedTimezone();
    await _loadTimezone();
    debugPrint('🔄 Timezone refreshed');
  }

  /// ✅ Reset to device timezone (clears user setting)
  static Future<void> resetToDeviceTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kUserTimezone);
    await prefs.remove(kCachedTimezone);

    // Reload from device
    final String deviceTimezone =
        (await FlutterTimezone.getLocalTimezone()).identifier;

    if (_isValidTimezone(deviceTimezone)) {
      _currentTimezone = deviceTimezone;
      await _applyTimezone(_currentTimezone);
      await prefs.setString(kUserTimezone, deviceTimezone);
      await prefs.setString(kCachedTimezone, deviceTimezone);
      debugPrint('🔄 Reset to device timezone: $deviceTimezone');
    }
  }

  // ==================== LIST HELPERS ====================

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

  // ==================== ✅ CURRENCY HELPERS ====================

  /// Get currency code from timezone
  static String getCurrencyForTimezone(String timezone) {
    if (timezone.startsWith('Asia/Colombo')) return 'LKR';
    if (timezone.startsWith('America/') || timezone.startsWith('US/')) {
      return 'USD';
    }
    if (timezone.startsWith('Asia/Kolkata') ||
        timezone.startsWith('Asia/Calcutta')) {
      return 'INR';
    }
    if (timezone.startsWith('Europe/London') ||
        timezone.startsWith('Europe/Belfast')) {
      return 'GBP';
    }
    if (timezone.startsWith('Europe/')) return 'EUR';
    if (timezone.startsWith('Australia/')) return 'AUD';
    if (timezone.startsWith('Asia/Singapore')) return 'SGD';
    if (timezone.startsWith('Asia/Dubai')) return 'AED';
    if (timezone.startsWith('Asia/Kuala_Lumpur')) return 'MYR';
    if (timezone.startsWith('Asia/Bangkok')) return 'THB';
    if (timezone.startsWith('Asia/Karachi')) return 'PKR';
    if (timezone.startsWith('Asia/Dhaka')) return 'BDT';
    if (timezone.startsWith('Asia/Kathmandu')) return 'NPR';
    if (timezone.startsWith('Asia/Tokyo')) return 'JPY';
    if (timezone.startsWith('Asia/Shanghai') ||
        timezone.startsWith('Asia/Chongqing')) {
      return 'CNY';
    }
    if (timezone.startsWith('Pacific/Auckland')) return 'NZD';
    if (timezone.startsWith('Europe/Zurich')) return 'CHF';
    if (timezone.startsWith('Canada/') ||
        timezone == 'America/Toronto' ||
        timezone == 'America/Vancouver') {
      return 'CAD';
    }
    return 'USD';
  }

  /// Get symbol for currency code
  static String getSymbolForCurrency(String code) {
    const symbols = {
      'LKR': 'Rs.',
      'USD': '\$',
      'INR': '₹',
      'GBP': '£',
      'EUR': '€',
      'AUD': 'A\$',
      'CAD': 'C\$',
      'SGD': 'S\$',
      'AED': 'د.إ',
      'MYR': 'RM',
      'THB': '฿',
      'JPY': '¥',
      'CNY': '¥',
      'NZD': 'NZ\$',
      'CHF': 'CHF',
      'PKR': '₨',
      'BDT': '৳',
      'NPR': 'रू',
    };
    return symbols[code] ?? '\$';
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

  /// ✅ Convert a TimeOfDay from one timezone to another
  /// Useful when displaying salon times in user's timezone
  static TimeOfDay convertTimeOfDayBetweenTimezones(
    TimeOfDay time, {
    required String fromTimezone,
    required String toTimezone,
  }) {
    try {
      final utcString = timeOfDayToUtcWithTimezone(time, fromTimezone);
      return utcToTimeOfDayWithTimezone(utcString, toTimezone);
    } catch (e) {
      debugPrint('❌ Error in convertTimeOfDayBetweenTimezones: $e');
      return time;
    }
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