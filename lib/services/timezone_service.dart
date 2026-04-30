import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneService {
  static bool _initialized = false;
  static String _currentTimezone = 'Asia/Colombo'; // Default
  static int _utcOffsetHours = 5;
  static int _utcOffsetMinutes = 30;
  
  // Initialize timezone service
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // Initialize timezone database
    tz.initializeTimeZones();
    _initialized = true;
    
    // Load timezone
    await _loadTimezone();
  }
  
  // Load timezone from device (auto-detect)
  static Future<void> _loadTimezone() async {
    try {
      // Try to get from SharedPreferences first (cached)
      final prefs = await SharedPreferences.getInstance();
      final cachedTimezone = prefs.getString('cached_timezone');
      
      if (cachedTimezone != null) {
        _currentTimezone = cachedTimezone;
        _updateOffsets(_currentTimezone);
        print('Loaded cached timezone: $_currentTimezone');
        return;
      }
      
      // Auto-detect from device
      final String deviceTimezone = await FlutterNativeTimezone.getLocalTimezone();
      print('Device timezone: $deviceTimezone');
      
      // Validate and set
      if (_isValidTimezone(deviceTimezone)) {
        _currentTimezone = deviceTimezone;
        _updateOffsets(_currentTimezone);
        
        // Cache for next time
        await prefs.setString('cached_timezone', _currentTimezone);
        print('Saved timezone to cache: $_currentTimezone');
      } else {
        print('Timezone $deviceTimezone not supported, using default');
        _currentTimezone = 'Asia/Colombo';
        _updateOffsets(_currentTimezone);
      }
      
    } catch (e) {
      print('Error detecting timezone: $e');
      _currentTimezone = 'Asia/Colombo';
      _updateOffsets(_currentTimezone);
    }
  }
  
  // Check if timezone is supported
  static bool _isValidTimezone(String timezone) {
    final supportedTimezones = [
      'Asia/Colombo', 'Asia/Kolkata', 'Asia/Dubai', 'Asia/Singapore',
      'Asia/Kuala_Lumpur', 'Asia/Bangkok', 'Asia/Tokyo', 'Asia/Shanghai',
      'Europe/London', 'Europe/Berlin', 'Europe/Paris',
      'America/New_York', 'America/Los_Angeles', 'America/Chicago',
      'America/Toronto', 'Australia/Sydney', 'Australia/Melbourne',
    ];
    return supportedTimezones.contains(timezone);
  }
  
  // Update UTC offsets based on timezone
  static void _updateOffsets(String timezone) {
    final offsets = {
      'Asia/Colombo': {'hours': 5, 'minutes': 30},
      'Asia/Kolkata': {'hours': 5, 'minutes': 30},
      'Asia/Dubai': {'hours': 4, 'minutes': 0},
      'Asia/Singapore': {'hours': 8, 'minutes': 0},
      'Asia/Kuala_Lumpur': {'hours': 8, 'minutes': 0},
      'Asia/Bangkok': {'hours': 7, 'minutes': 0},
      'Asia/Tokyo': {'hours': 9, 'minutes': 0},
      'Asia/Shanghai': {'hours': 8, 'minutes': 0},
      'Europe/London': {'hours': 1, 'minutes': 0},
      'Europe/Berlin': {'hours': 2, 'minutes': 0},
      'Europe/Paris': {'hours': 2, 'minutes': 0},
      'America/New_York': {'hours': -4, 'minutes': 0},
      'America/Los_Angeles': {'hours': -7, 'minutes': 0},
      'America/Chicago': {'hours': -5, 'minutes': 0},
      'America/Toronto': {'hours': -4, 'minutes': 0},
      'Australia/Sydney': {'hours': 10, 'minutes': 0},
      'Australia/Melbourne': {'hours': 10, 'minutes': 0},
    };
    
    final offset = offsets[timezone];
    if (offset != null) {
      _utcOffsetHours = offset['hours']!;
      _utcOffsetMinutes = offset['minutes']!;
    } else {
      _utcOffsetHours = 5;
      _utcOffsetMinutes = 30;
    }
    
    print('UTC Offset for $_currentTimezone: $_utcOffsetHours:$_utcOffsetMinutes');
  }
  
  // Get current timezone
  static String getCurrentTimezone() {
    return _currentTimezone;
  }
  
  // Get UTC offset hours
  static int getUtcOffsetHours() {
    return _utcOffsetHours;
  }
  
  // Get UTC offset minutes
  static int getUtcOffsetMinutes() {
    return _utcOffsetMinutes;
  }
  
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
      
      return '${localHour.toString().padLeft(2, '0')}:${localMinute.toString().padLeft(2, '0')}:00';
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
    final names = {
      'Asia/Colombo': 'Sri Lanka',
      'Asia/Kolkata': 'India',
      'Asia/Dubai': 'UAE',
      'Asia/Singapore': 'Singapore',
      'Asia/Kuala_Lumpur': 'Malaysia',
      'Asia/Bangkok': 'Thailand',
      'Asia/Tokyo': 'Japan',
      'Asia/Shanghai': 'China',
      'Europe/London': 'United Kingdom',
      'Europe/Berlin': 'Germany',
      'Europe/Paris': 'France',
      'America/New_York': 'USA (East)',
      'America/Los_Angeles': 'USA (West)',
      'America/Chicago': 'USA (Central)',
      'America/Toronto': 'Canada',
      'Australia/Sydney': 'Australia',
    };
    return names[_currentTimezone] ?? _currentTimezone;
  }
  
  // Get timezone flag
  static String getTimezoneFlag() {
    final flags = {
      'Asia/Colombo': '🇱🇰',
      'Asia/Kolkata': '🇮🇳',
      'Asia/Dubai': '🇦🇪',
      'Asia/Singapore': '🇸🇬',
      'Asia/Kuala_Lumpur': '🇲🇾',
      'Asia/Bangkok': '🇹🇭',
      'Asia/Tokyo': '🇯🇵',
      'Asia/Shanghai': '🇨🇳',
      'Europe/London': '🇬🇧',
      'Europe/Berlin': '🇩🇪',
      'Europe/Paris': '🇫🇷',
      'America/New_York': '🇺🇸',
      'America/Los_Angeles': '🇺🇸',
      'America/Chicago': '🇺🇸',
      'America/Toronto': '🇨🇦',
      'Australia/Sydney': '🇦🇺',
    };
    return flags[_currentTimezone] ?? '🌍';
  }
  
  // Get UTC offset string
  static String getUtcOffsetString() {
    final sign = _utcOffsetHours >= 0 ? '+' : '';
    return 'UTC$sign$_utcOffsetHours:${_utcOffsetMinutes.toString().padLeft(2, '0')}';
  }
}