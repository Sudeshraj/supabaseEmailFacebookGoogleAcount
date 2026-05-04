import 'package:flutter/material.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneService {
  static bool _initialized = false;
  static String _currentTimezone = 'Asia/Colombo'; // Default
  static int _utcOffsetHours = 5;
  static int _utcOffsetMinutes = 30;
  static String _currentCountryCode = 'LK';
  static String _currentCountryName = 'Sri Lanka';

  // Available timezones by country
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
  };

  // Initialize timezone service
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadTimezone();
  }

  // Load timezone from device (auto-detect)
  static Future<void> _loadTimezone() async {
    try {
      // Try to get from SharedPreferences first (cached)
      final prefs = await SharedPreferences.getInstance();
      final cachedTimezone = prefs.getString('cached_timezone');

      if (cachedTimezone != null && cachedTimezone.isNotEmpty) {
        _currentTimezone = cachedTimezone;
        _updateOffsets(_currentTimezone);
        _updateCountryInfo(_currentTimezone);
        print('✅ Loaded cached timezone: $_currentTimezone');
        return;
      }

      // Auto-detect from device
      final String deviceTimezone =
          await FlutterNativeTimezone.getLocalTimezone();
      print('📍 Device timezone: $deviceTimezone');

      // Validate and set
      if (_isValidTimezone(deviceTimezone)) {
        _currentTimezone = deviceTimezone;
        _updateOffsets(_currentTimezone);
        _updateCountryInfo(_currentTimezone);

        // Cache for next time
        await prefs.setString('cached_timezone', _currentTimezone);
        print('✅ Saved timezone to cache: $_currentTimezone');
      } else {
        print('⚠️ Timezone $deviceTimezone not supported, using default');
        _currentTimezone = 'Asia/Colombo';
        _updateOffsets(_currentTimezone);
        _updateCountryInfo(_currentTimezone);
      }
    } catch (e) {
      print('❌ Error detecting timezone: $e');
      _currentTimezone = 'Asia/Colombo';
      _updateOffsets(_currentTimezone);
      _updateCountryInfo(_currentTimezone);
    }
  }

  // Update country info from timezone
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

  // Check if timezone is supported
  static bool _isValidTimezone(String timezone) {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == timezone) {
          return true;
        }
      }
    }
    return false;
  }

  // Update UTC offsets based on timezone
  static void _updateOffsets(String timezone) {
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
    _utcOffsetHours = 5;
    _utcOffsetMinutes = 30;
  }

  // Set timezone manually
  static Future<void> setTimezone(String timezone) async {
    _currentTimezone = timezone;
    _updateOffsets(timezone);
    _updateCountryInfo(timezone);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_timezone', timezone);
    print('✅ Manually set timezone: $timezone');
  }

  // Get available timezones for a country
  static List<Map<String, String>> getTimezonesForCountry(String countryCode) {
    return countryTimezones[countryCode] ?? countryTimezones['LK']!;
  }

  // Get all available countries
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

  // Get current timezone
  static String getCurrentTimezone() => _currentTimezone;

  static String getCurrentCountryCode() => _currentCountryCode;

  static String getCurrentCountryName() => _currentCountryName;

  static String getCurrentFlag() {
    for (var entry in countryTimezones.entries) {
      for (var tz in entry.value) {
        if (tz['timezone'] == _currentTimezone) {
          return tz['flag']!;
        }
      }
    }
    return '🇱🇰';
  }

  // Get UTC offset hours
  static int getUtcOffsetHours() => _utcOffsetHours;

  // Get UTC offset minutes
  static int getUtcOffsetMinutes() => _utcOffsetMinutes;

  // Convert UTC time to local time
  static String utcToLocalTime(String utcTime, DateTime date) {
    try {
      final parts = utcTime.split(':');
      if (parts.length < 2) return utcTime;

      int utcHour = int.parse(parts[0]);
      int utcMinute = int.parse(parts[1]);
      int utcSecond = parts.length >= 3 ? int.parse(parts[2]) : 0;

      // Add offset
      int localHour = utcHour + _utcOffsetHours;
      int localMinute = utcMinute + _utcOffsetMinutes;

      // Adjust minutes
      if (localMinute >= 60) {
        localMinute -= 60;
        localHour += 1;
      }
      if (localMinute < 0) {
        localMinute += 60;
        localHour -= 1;
      }

      // Adjust hours
      if (localHour >= 24) {
        localHour -= 24;
      }
      if (localHour < 0) {
        localHour += 24;
      }

      return '${localHour.toString().padLeft(2, '0')}:${localMinute.toString().padLeft(2, '0')}';
    } catch (e) {
      return utcTime;
    }
  }

  // Convert local time to UTC
  static String localToUtcTime(String localTime, DateTime date) {
    try {
      final parts = localTime.split(':');
      if (parts.length < 2) return localTime;

      int localHour = int.parse(parts[0]);
      int localMinute = int.parse(parts[1]);

      // Subtract offset
      int utcHour = localHour - _utcOffsetHours;
      int utcMinute = localMinute - _utcOffsetMinutes;

      // Adjust minutes
      if (utcMinute < 0) {
        utcMinute += 60;
        utcHour -= 1;
      }
      if (utcMinute >= 60) {
        utcMinute -= 60;
        utcHour += 1;
      }

      // Adjust hours
      if (utcHour < 0) {
        utcHour += 24;
      }
      if (utcHour >= 24) {
        utcHour -= 24;
      }

      return '${utcHour.toString().padLeft(2, '0')}:${utcMinute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      return localTime;
    }
  }

  // Get timezone display name
  static String getTimezoneDisplayName() {
    return _currentCountryName;
  }

  // Get timezone flag
  static String getTimezoneFlag() {
    return getCurrentFlag();
  }

  // Get UTC offset string
  static String getUtcOffsetString() {
    final sign = _utcOffsetHours >= 0 ? '+' : '';
    final hours = _utcOffsetHours.abs();
    final minutes = _utcOffsetMinutes.abs();
    return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }
}
