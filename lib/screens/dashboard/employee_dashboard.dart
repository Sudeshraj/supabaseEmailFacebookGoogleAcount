import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/widgets/dashboard_stat_card.dart';
import 'package:flutter_application_1/widgets/booking_tile.dart';
import 'package:flutter_application_1/widgets/section_header.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> with RouteAware {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();
  final supabase = Supabase.instance.client;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Employee Dashboard Data
  int _todaysAppointments = 0;
  int _completedToday = 0;
  int _pendingAppointments = 0;
  int _totalCustomers = 0;
  int _todayEarnings = 0;
  int _monthlyEarnings = 0;
  double _rating = 0.0;
  String _employeeName = 'Loading...';
  String _employeeId = '';
  String _employeeEmail = '';
  String _employeeAvatar = '';

  // Salon information
  List<Map<String, dynamic>> _assignedSalons = [];
  int? _selectedSalonId;
  String _selectedSalonName = '';

  // Break status
  bool _isOnBreak = false;

  // Appointments list
  List<Map<String, dynamic>> _todaysAppointmentsList = [];

  // Notification count
  int _unreadNotificationCount = 0;

  // ==================== TIMEZONE VARIABLES ====================
  String _userTimezone = '';
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeTimezone();
    await _loadEmployeeData();
    await _loadData();
    _setupNotificationListeners();
    debugPrint('🔄 EmployeeDashboard initState completed');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    _checkTimezoneChange();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('🔄 Returning to EmployeeDashboard - Auto refresh');
    _loadData();
  }

  // ==================== TIMEZONE INITIALIZATION ====================

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    String cachedTimezone = prefs.getString('cached_timezone') ?? '';

    if (cachedTimezone.isNotEmpty) {
      _userTimezone = cachedTimezone;
    } else {
      _userTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString('cached_timezone', _userTimezone);
    }

    await TimezoneService.setTimezone(_userTimezone);
    _lastTimezone = _userTimezone;

    setState(() {
      _isTimezoneLoaded = true;
    });

    debugPrint('✅ User timezone: $_userTimezone');
  }

  void _checkTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();

    if (_lastTimezone != currentTimezone && _lastTimezone.isNotEmpty) {
      _userTimezone = currentTimezone;
      await TimezoneService.setTimezone(_userTimezone);
    }
    _lastTimezone = currentTimezone;
  }

  // ==================== UTC TO LOCAL CONVERSION ====================

  String _utcToLocalTimeString(String utcTime) {
    try {
      return TimezoneService.utcToLocalTimeRecurring(utcTime);
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      return _formatTimeString(utcTime);
    }
  }

  String _formatTimeString(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  String _formatDateDisplay(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return 'Today';
      }

      final tomorrow = now.add(const Duration(days: 1));
      if (date.year == tomorrow.year &&
          date.month == tomorrow.month &&
          date.day == tomorrow.day) {
        return 'Tomorrow';
      }

      final dayDiff = date.difference(now).inDays;
      if (dayDiff <= 7) {
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return weekdays[date.weekday - 1];
      }

      return '${date.day}/${date.month}';
    } catch (e) {
      return dateStr;
    }
  }

  String _getMonthName() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[DateTime.now().month - 1];
  }

  // ==================== LOAD BREAK STATUS ====================

  Future<void> _loadBreakStatus() async {
    if (_employeeId.isEmpty) return;

    try {
      final today = DateTime.now().toIso8601String().split('T').first;

      final specialBreak = await supabase
          .from('barber_special_breaks')
          .select('''
            id,
            break_date,
            start_time,
            end_time,
            break_type,
            reason
          ''')
          .eq('barber_id', _employeeId)
          .eq('break_date', today)
          .eq('break_type', 'lunch')
          .maybeSingle();

      if (specialBreak != null) {
        final startTime = specialBreak['start_time'] as String;
        final endTime = specialBreak['end_time'] as String;
        final now = DateTime.now();
        final nowStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';

        final isOnBreakNow =
            nowStr.compareTo(startTime) >= 0 && nowStr.compareTo(endTime) < 0;

        setState(() {
          _isOnBreak = isOnBreakNow;
        });

        debugPrint('✅ Loaded SPECIAL break');
        return;
      }

      final dayOfWeek = DateTime.now().weekday;

      final regularBreak = await supabase
          .from('barber_breaks')
          .select('''
            id,
            day_of_week,
            start_time,
            end_time,
            break_type
          ''')
          .eq('barber_id', _employeeId)
          .eq('day_of_week', dayOfWeek)
          .eq('break_type', 'lunch')
          .maybeSingle();

      if (regularBreak != null) {
        final startTime = regularBreak['start_time'] as String;
        final endTime = regularBreak['end_time'] as String;
        final now = DateTime.now();
        final nowStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';

        final isOnBreakNow =
            nowStr.compareTo(startTime) >= 0 && nowStr.compareTo(endTime) < 0;

        setState(() {
          _isOnBreak = isOnBreakNow;
        });

        debugPrint('✅ Loaded REGULAR break');
        return;
      }

      setState(() {
        _isOnBreak = false;
      });

      debugPrint('ℹ️ No break found - Working');
    } catch (e) {
      debugPrint('❌ Error loading break status: $e');
      setState(() {
        _isOnBreak = false;
      });
    }
  }

  // ==================== LOAD NOTIFICATION COUNT ====================

  Future<void> _loadNotificationCount() async {
    if (_employeeId.isEmpty) return;

    try {
      final count = await _notificationService.getUnreadCountWithRole(
        userId: _employeeId,
        role: 'barber',
      );
      setState(() {
        _unreadNotificationCount = count;
      });
      debugPrint('✅ Unread notifications: $count');
    } catch (e) {
      debugPrint('❌ Error loading notification count: $e');
    }
  }

  // ==================== TIMEZONE PICKER METHODS ====================

  Future<void> _showTimezonePickerDialog() async {
    final allTimezones = TimezoneService.getAllAvailableTimezones();
    final continentGroups = _groupTimezonesByContinent(allTimezones);

    final List<Map<String, dynamic>> searchableList = [];
    for (var entry in continentGroups.entries) {
      final continent = entry.key;
      for (final tz in entry.value) {
        final displayName = tz.split('/').last.replaceAll('_', ' ');
        final countryCode = _extractCountryCode(tz);
        final flag = _getFlagByCountryCode(countryCode);

        final searchText = [
          continent.toLowerCase(),
          displayName.toLowerCase(),
          tz.toLowerCase(),
          countryCode.toLowerCase(),
          displayName.toLowerCase(),
        ].join(' ');

        searchableList.add({
          'timezone': tz,
          'displayName': displayName,
          'continent': continent,
          'flag': flag,
          'searchText': searchText,
        });
      }
    }

    TextEditingController searchController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String searchQuery = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<Map<String, dynamic>> filteredList = searchableList;
            if (searchQuery.isNotEmpty) {
              final query = searchQuery.toLowerCase();
              filteredList = searchableList
                  .where((item) => item['searchText'].contains(query))
                  .toList();
            }

            Map<String, List<Map<String, dynamic>>> filteredGroups = {};
            for (var item in filteredList) {
              final continent = item['continent'];
              if (!filteredGroups.containsKey(continent)) {
                filteredGroups[continent] = [];
              }
              filteredGroups[continent]!.add(item);
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.85,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDialogHeader(),
                    const Divider(),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      child: TextField(
                        controller: searchController,
                        autofocus: false,
                        onChanged: (value) {
                          setDialogState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText:
                              '🔍 Search by country, city, or timezone...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {
                                      searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Found ${filteredList.length} timezone${filteredList.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    Expanded(
                      child: searchQuery.isEmpty
                          ? DefaultTabController(
                              length: continentGroups.keys.length,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 45,
                                    child: TabBar(
                                      isScrollable: true,
                                      labelColor: const Color(0xFFFF6B8B),
                                      unselectedLabelColor: Colors.grey,
                                      indicatorColor: const Color(0xFFFF6B8B),
                                      labelStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      tabs: continentGroups.keys
                                          .map(
                                            (continent) => Tab(text: continent),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: TabBarView(
                                      children: continentGroups.values.map((
                                        timezones,
                                      ) {
                                        return ListView.builder(
                                          itemCount: timezones.length,
                                          itemBuilder: (context, index) {
                                            final tz = timezones[index];
                                            final displayName = tz
                                                .split('/')
                                                .last
                                                .replaceAll('_', ' ');
                                            final countryCode =
                                                _extractCountryCode(tz);
                                            final flag = _getFlagByCountryCode(
                                              countryCode,
                                            );
                                            return _buildTimezoneTile(
                                              tz,
                                              displayName,
                                              flag,
                                            );
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filteredList.isNotEmpty
                          ? ListView.builder(
                              itemCount: filteredGroups.keys.length,
                              itemBuilder: (context, index) {
                                final continent = filteredGroups.keys.elementAt(
                                  index,
                                );
                                final items = filteredGroups[continent]!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            _getContinentEmoji(continent),
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            continent,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${items.length}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...items.map(
                                      (item) => _buildTimezoneTile(
                                        item['timezone'],
                                        item['displayName'],
                                        item['flag'],
                                      ),
                                    ),
                                    if (index != filteredGroups.keys.length - 1)
                                      const Divider(),
                                  ],
                                );
                              },
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No timezones found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try "Sri Lanka", "Tokyo", "London", or "New York"',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildCurrentTimezoneInfo(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && result != _userTimezone) {
      await _applyTimezoneChange(result);
    }
  }

  Future<void> _applyTimezoneChange(String newTimezone) async {
    setState(() => _isLoading = true);

    try {
      await TimezoneService.setTimezone(newTimezone);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_timezone', newTimezone);

      _userTimezone = newTimezone;
      _lastTimezone = newTimezone;

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Timezone changed to ${newTimezone.split('/').last.replaceAll('_', ' ')}',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error changing timezone: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing timezone: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== TIMEZONE HELPER METHODS ====================

  String _extractCountryCode(String timezone) {
    final countryMap = {
      'Asia/Colombo': 'LK',
      'Asia/Tokyo': 'JP',
      'Asia/Seoul': 'KR',
      'Asia/Shanghai': 'CN',
      'Asia/Hong_Kong': 'HK',
      'Asia/Taipei': 'TW',
      'Asia/Kolkata': 'IN',
      'Asia/Dubai': 'AE',
      'Asia/Singapore': 'SG',
      'Asia/Kuala_Lumpur': 'MY',
      'Asia/Bangkok': 'TH',
      'Asia/Jakarta': 'ID',
      'Asia/Manila': 'PH',
      'Asia/Ho_Chi_Minh': 'VN',
      'Asia/Dhaka': 'BD',
      'Asia/Karachi': 'PK',
      'Asia/Kathmandu': 'NP',
      'Asia/Riyadh': 'SA',
      'Asia/Kuwait': 'KW',
      'Asia/Doha': 'QA',
      'Europe/London': 'GB',
      'Europe/Paris': 'FR',
      'Europe/Berlin': 'DE',
      'Europe/Rome': 'IT',
      'Europe/Madrid': 'ES',
      'Europe/Amsterdam': 'NL',
      'Europe/Zurich': 'CH',
      'Europe/Moscow': 'RU',
      'America/New_York': 'US',
      'America/Chicago': 'US',
      'America/Denver': 'US',
      'America/Los_Angeles': 'US',
      'America/Toronto': 'CA',
      'America/Vancouver': 'CA',
      'America/Mexico_City': 'MX',
      'America/Sao_Paulo': 'BR',
      'Australia/Sydney': 'AU',
      'Australia/Melbourne': 'AU',
      'Australia/Perth': 'AU',
      'Australia/Adelaide': 'AU',
      'Pacific/Auckland': 'NZ',
      'Africa/Johannesburg': 'ZA',
      'Africa/Cairo': 'EG',
      'Africa/Lagos': 'NG',
      'Africa/Nairobi': 'KE',
    };
    if (countryMap.containsKey(timezone)) return countryMap[timezone]!;
    for (var entry in countryMap.entries) {
      if (timezone.contains(entry.key) || entry.key.contains(timezone)) {
        return entry.value;
      }
    }
    return '';
  }

  String _getFlagByCountryCode(String countryCode) {
    final flags = {
      'LK': '🇱🇰',
      'JP': '🇯🇵',
      'KR': '🇰🇷',
      'CN': '🇨🇳',
      'HK': '🇭🇰',
      'TW': '🇹🇼',
      'IN': '🇮🇳',
      'AE': '🇦🇪',
      'SG': '🇸🇬',
      'MY': '🇲🇾',
      'TH': '🇹🇭',
      'ID': '🇮🇩',
      'PH': '🇵🇭',
      'VN': '🇻🇳',
      'BD': '🇧🇩',
      'PK': '🇵🇰',
      'NP': '🇳🇵',
      'SA': '🇸🇦',
      'KW': '🇰🇼',
      'QA': '🇶🇦',
      'GB': '🇬🇧',
      'FR': '🇫🇷',
      'DE': '🇩🇪',
      'IT': '🇮🇹',
      'ES': '🇪🇸',
      'NL': '🇳🇱',
      'CH': '🇨🇭',
      'RU': '🇷🇺',
      'US': '🇺🇸',
      'CA': '🇨🇦',
      'MX': '🇲🇽',
      'BR': '🇧🇷',
      'AU': '🇦🇺',
      'NZ': '🇳🇿',
      'ZA': '🇿🇦',
      'EG': '🇪🇬',
      'NG': '🇳🇬',
      'KE': '🇰🇪',
    };
    return flags[countryCode] ?? '🌐';
  }

  String _getContinentEmoji(String continent) {
    final emojis = {
      'Asia': '🌏',
      'Europe': '🌍',
      'Africa': '🌍',
      'America': '🌎',
      'Australia': '🇦🇺',
      'Pacific': '🌏',
      'UTC': '🌐',
    };
    return emojis[continent] ?? '🌐';
  }

  Map<String, List<String>> _groupTimezonesByContinent(List<String> timezones) {
    final groups = <String, List<String>>{};
    for (final tz in timezones) {
      final parts = tz.split('/');
      if (parts.length >= 2) {
        final continent = parts[0];
        if (!groups.containsKey(continent)) groups[continent] = [];
        groups[continent]!.add(tz);
      } else {
        if (!groups.containsKey('UTC')) groups['UTC'] = [];
        groups['UTC']!.add(tz);
      }
    }
    for (final key in groups.keys) {
      groups[key]!.sort();
    }
    return groups;
  }

  Widget _buildTimezoneTile(String tz, String displayName, String flag) {
    final isSelected = tz == _userTimezone;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: isSelected
              ? const Color(0xFFFF6B8B)
              : Colors.grey[200],
          child: Text(flag, style: const TextStyle(fontSize: 16)),
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFFFF6B8B) : null,
          ),
        ),
        subtitle: Text(
          tz,
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Color(0xFFFF6B8B))
            : null,
        onTap: () => Navigator.of(context).pop(tz),
      ),
    );
  }

  Widget _buildCurrentTimezoneInfo() {
    final displayName = _userTimezone.split('/').last.replaceAll('_', ' ');
    final offset = TimezoneService.getUtcOffsetString();
    final flag = TimezoneService.getCurrentFlag();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current: $displayName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _userTimezone,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              offset,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.access_time,
              color: Color(0xFFFF6B8B),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Select Your Timezone',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ==================== TIMEZONE SELECTOR ====================

  Widget _buildTimezoneSelector() {
    final isDSTActive = TimezoneService.isDST();
    final flag = TimezoneService.getCurrentFlag();
    final displayName = TimezoneService.getTimezoneDisplayName();

    return GestureDetector(
      onTap: _showTimezonePickerDialog,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: isDSTActive
              ? Border.all(color: Colors.amber, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isDSTActive) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'DST',
                  style: TextStyle(
                    fontSize: 7,
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ==================== PROFILE IMAGE ====================

  Widget _buildProfileImage() {
    return GestureDetector(
      onTap: () {
        context.push('/profile');
      },
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          backgroundImage: _employeeAvatar.isNotEmpty
              ? NetworkImage(_employeeAvatar)
              : null,
          child: _employeeAvatar.isEmpty
              ? Text(
                  _employeeName.isNotEmpty
                      ? _employeeName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ==================== LOAD EMPLOYEE DATA ====================

  Future<void> _loadEmployeeData() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ No user logged in');
        return;
      }

      _employeeId = currentUser.id;
      _employeeEmail = currentUser.email ?? '';
      debugPrint(
        '📋 Loading employee data for user: $_employeeId, email: $_employeeEmail',
      );

      // ✅ STEP 1: Check if user has ACTIVE barber role
      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
          role_id,
          status,
          roles!inner (
            id,
            name
          )
        ''')
          .eq('user_id', _employeeId);

      bool isActiveBarber = false;
      String? roleStatus;
      for (var role in userRolesResponse) {
        final roleData = role['roles'] as Map?;
        final status = role['status'] as String? ?? 'active';
        if (roleData != null && roleData['name'] == 'barber') {
          roleStatus = status;
          if (status == 'active') {
            isActiveBarber = true;
          }
          break;
        }
      }

      // ✅ Check if role exists but inactive
      if (!isActiveBarber && roleStatus != null) {
        if (mounted) {
          String message = 'Your barber account is ';
          switch (roleStatus) {
            case 'inactive':
              message += 'deactivated';
              break;
            case 'scheduled_for_deletion':
              message += 'scheduled for deletion';
              break;
            case 'deleted':
              message += 'deleted';
              break;
            default:
              message += 'not active';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ $message. Please contact support.'),
              backgroundColor: Colors.orange,
            ),
          );

          // Redirect to login after showing message
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              context.go('/');
            }
          });
          return;
        }
      }

      // ✅ Check if user has barber role at all (from SessionManager fallback)
      if (!isActiveBarber) {
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          final roles = profile['roles'] as List? ?? [];
          if (roles.contains('barber')) {
            // Role exists in session but maybe not in DB - try to reactivate
            isActiveBarber = true;
            debugPrint(
              '✅ Found barber role in SessionManager, but DB check failed',
            );
          }
        }

        if (!isActiveBarber) {
          debugPrint('❌ User does not have barber role');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'You do not have a barber role. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
            context.go('/');
          }
          return;
        }
      }

      // ✅ Load profile
      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, email, avatar_url, is_active, is_blocked')
          .eq('id', _employeeId)
          .maybeSingle();

      // ✅ Check if profile is blocked or inactive
      if (profileResponse != null) {
        if (profileResponse['is_blocked'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been blocked. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
            context.go('/');
          }
          return;
        }

        if (profileResponse['is_active'] == false) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your profile is inactive. Please contact support.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            context.go('/');
          }
          return;
        }
      }

      if (profileResponse != null) {
        setState(() {
          _employeeName =
              profileResponse['full_name'] ??
              currentUser.email?.split('@').first ??
              'Barber';
          if (profileResponse['email'] != null &&
              profileResponse['email'].toString().isNotEmpty) {
            _employeeEmail = profileResponse['email'].toString();
          }
          _employeeAvatar = profileResponse['avatar_url'] ?? '';
        });
        debugPrint(
          '✅ Profile loaded: name=$_employeeName, email=$_employeeEmail',
        );
      } else {
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          setState(() {
            _employeeName = profile['name'] ?? _employeeEmail.split('@').first;
            _employeeAvatar = profile['avatar'] ?? '';
          });
          debugPrint(
            '✅ Profile loaded from SessionManager: name=$_employeeName',
          );
        }
      }

      // ✅ Load assigned salons
      await _loadAssignedSalons();
    } catch (e) {
      debugPrint('❌ Error loading employee data: $e');

      try {
        final email = await SessionManager.getCurrentUserEmail();
        if (email != null) {
          final profile = await SessionManager.getProfileByEmail(email);
          if (profile != null) {
            setState(() {
              _employeeEmail = email;
              _employeeName = profile['name'] ?? email.split('@').first;
              _employeeAvatar = profile['avatar'] ?? '';
            });
            debugPrint(
              '✅ Fallback profile loaded: name=$_employeeName, email=$_employeeEmail',
            );
          }
        }
      } catch (fallbackError) {
        debugPrint('❌ Fallback also failed: $fallbackError');
      }
    }
  }

  // Load assigned salons for the barber
  Future<void> _loadAssignedSalons() async {
    try {
      final response = await supabase
          .from('salon_barbers')
          .select('''
            id,
            salon_id,
            status,
            salons!inner (
              id,
              name,
              address,
              phone,
              logo_url,
              cover_url,
              open_time,
              close_time,
              is_active
            )
          ''')
          .eq('barber_id', _employeeId)
          .eq('status', 'active');

      debugPrint('📊 Found ${response.length} assigned salons');

      final List<Map<String, dynamic>> salons = [];

      for (var item in response) {
        final salonData = item['salons'] as Map?;
        if (salonData != null) {
          final salon = {
            'id': salonData['id'],
            'name': salonData['name'],
            'address': salonData['address'],
            'phone': salonData['phone'],
            'logo_url': salonData['logo_url'],
            'cover_url': salonData['cover_url'],
            'open_time': salonData['open_time'],
            'close_time': salonData['close_time'],
            'is_active': salonData['is_active'],
            'barber_salon_id': item['id'],
          };
          salons.add(salon);

          // First active salon becomes selected
          if (_selectedSalonId == null && salonData['is_active'] == true) {
            _selectedSalonId = salonData['id'];
            _selectedSalonName = salonData['name'];
          }
        }
      }

      setState(() {
        _assignedSalons = salons;
        if (_selectedSalonId == null && salons.isNotEmpty) {
          _selectedSalonId = salons[0]['id'] as int;
          _selectedSalonName = salons[0]['name'] ?? '';
        } else if (salons.isNotEmpty) {
          final selected = salons.firstWhere(
            (s) => s['id'] == _selectedSalonId,
            orElse: () => {},
          );
          _selectedSalonName = selected['name'] ?? '';
        }
      });

      debugPrint(
        '✅ Selected salon: $_selectedSalonName (ID: $_selectedSalonId)',
      );
      debugPrint('✅ Total assigned salons: ${_assignedSalons.length}');
    } catch (e) {
      debugPrint('❌ Error loading assigned salons: $e');
    }
  }

  // ==================== SALON SELECTION ====================

  void _selectSalon(int salonId) {
    setState(() {
      _selectedSalonId = salonId;
      final selected = _assignedSalons.firstWhere(
        (s) => s['id'] == salonId,
        orElse: () => {},
      );
      _selectedSalonName = selected['name'] ?? '';
    });
    _loadDataForSelectedSalon();
  }

  Future<void> _loadDataForSelectedSalon() async {
    if (_selectedSalonId == null) return;

    setState(() => _isLoading = true);

    try {
      await _loadAppointments();
      await _loadStatistics();
      await _loadBreakStatus();
      await _loadNotificationCount();

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ Data loaded for salon: $_selectedSalonName');
      }
    } catch (e) {
      debugPrint('❌ Error loading data for salon: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ==================== LOAD DASHBOARD DATA - MAIN ====================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📊 Loading employee dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'employee_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      if (_employeeId.isNotEmpty) {
        await _loadAppointments();
        await _loadStatistics();
        await _loadBreakStatus();
        await _loadNotificationCount();
      }

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ Employee data loaded successfully');
        debugPrint(
          '📊 Today: $_todaysAppointments, Pending: $_pendingAppointments, Monthly: $_monthlyEarnings, Customers: $_totalCustomers',
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading employee data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // =====================================================
  // ✅ LOAD APPOINTMENTS - DIRECT QUERY (NO RPC)
  // =====================================================
  Future<void> _loadAppointments() async {
    try {
      final salonId = _selectedSalonId;

      if (salonId == null) {
        debugPrint('⚠️ No salon selected');
        setState(() {
          _todaysAppointmentsList = [];
          _todaysAppointments = 0;
          _completedToday = 0;
          _pendingAppointments = 0;
          _todayEarnings = 0;
        });
        return;
      }

      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T').first;
      final futureDate = today.add(const Duration(days: 30));
      final futureStr = futureDate.toIso8601String().split('T').first;

      debugPrint('📊 Loading appointments from $todayStr to $futureStr');

      // ✅ DIRECT QUERY - NO RPC
      final response = await supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            customer_id,
            appointment_date,
            start_time,
            end_time,
            status,
            price,
            service_id,
            variant_id,
            salon_id,
            queue_number,
            queue_token,
            is_vip,
            salons!inner (
              id,
              name
            ),
            services!inner (
              name
            ),
            service_variants!left (
              price,
              duration,
              salon_genders!left (display_name),
              salon_age_categories!left (display_name)
            ),
            profiles!appointments_customer_id_fkey (
              full_name,
              email,
              phone
            )
          ''')
          .eq('barber_id', _employeeId)
          .eq('salon_id', salonId)
          .gte('appointment_date', todayStr)
          .lte('appointment_date', futureStr)
          .neq('status', 'cancelled')
          .neq('status', 'no_show')
          .order('appointment_date', ascending: true)
          .order('start_time', ascending: true);

      debugPrint('📊 Found ${response.length} appointments');

      final List<Map<String, dynamic>> allAppointments = [];

      // Counters
      int todayTotal = 0;
      int todayCompleted = 0;
      int todayEarnings = 0;
      int totalPendingAll = 0;

      for (var apt in response) {
        final service = apt['services'] as Map?;
        final variant = apt['service_variants'] as Map?;
        final customer = apt['profiles'] as Map?;
        final salon = apt['salons'] as Map?;

        final status = apt['status'] as String? ?? 'pending';
        final aptDate = apt['appointment_date'] as String;
        final isToday = aptDate == todayStr;

        final price =
            (apt['price'] as num?)?.toDouble() ??
            (variant?['price'] as num?)?.toDouble() ??
            0.0;

        final startTimeLocal = _utcToLocalTimeString(apt['start_time']);
        final endTimeLocal = _utcToLocalTimeString(apt['end_time']);

        // Count TODAY's appointments
        if (isToday) {
          todayTotal++;
          if (status == 'completed') {
            todayCompleted++;
            todayEarnings += price.toInt();
          }
        }

        // Count ALL PENDING (today + future)
        if (status == 'pending' ||
            status == 'confirmed' ||
            status == 'in_progress') {
          totalPendingAll++;
        }

        allAppointments.add({
          'id': apt['id'],
          'booking_number': apt['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': service?['name'] ?? 'Unknown Service',
          'salon_name': salon?['name'] ?? 'Unknown Salon',
          'appointment_date': aptDate,
          'is_today': isToday,
          'display_date': _formatDateDisplay(aptDate),
          'start_time': startTimeLocal,
          'end_time': endTimeLocal,
          'status': status,
          'price': price,
          'duration': variant?['duration'] ?? 30,
          'is_vip': apt['is_vip'] ?? false,
          'queue_number': apt['queue_number'],
          'queue_token': apt['queue_token'],
        });
      }

      setState(() {
        _todaysAppointmentsList = allAppointments;
        _todaysAppointments = todayTotal;
        _completedToday = todayCompleted;
        _pendingAppointments = totalPendingAll;
        _todayEarnings = todayEarnings;
      });

      debugPrint('✅ Today: $_todaysAppointments appointments');
      debugPrint('✅ Today Completed: $_completedToday');
      debugPrint('✅ TOTAL Pending (All dates): $_pendingAppointments');
      debugPrint('✅ Total appointments in list: ${allAppointments.length}');
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
      setState(() {
        _todaysAppointmentsList = [];
        _todaysAppointments = 0;
        _completedToday = 0;
        _pendingAppointments = 0;
        _todayEarnings = 0;
      });
    }
  }

  // =====================================================
  // ✅ LOAD STATISTICS - DIRECT QUERY (NO RPC)
  // =====================================================
  Future<void> _loadStatistics() async {
    try {
      final salonId = _selectedSalonId;

      if (salonId == null) {
        debugPrint('⚠️ No salon selected for statistics');
        setState(() {
          _totalCustomers = 0;
          _monthlyEarnings = 0;
          _rating = 0.0;
        });
        return;
      }

      debugPrint('📊 Loading statistics for salon: $salonId');

      // 1. TOTAL CUSTOMERS SERVED
      final customersResponse = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .eq('salon_id', salonId);

      final uniqueCustomers = customersResponse
          .map((a) => a['customer_id'])
          .toSet()
          .length;

      // 2. MONTHLY EARNINGS
      final firstDayOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      final firstDayStr = firstDayOfMonth.toIso8601String().split('T').first;

      final lastDayOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month + 1,
        0,
      );
      final lastDayStr = lastDayOfMonth.toIso8601String().split('T').first;

      final monthlyResponse = await supabase
          .from('appointments')
          .select('price')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .eq('salon_id', salonId)
          .gte('appointment_date', firstDayStr)
          .lte('appointment_date', lastDayStr);

      int monthlyTotal = 0;
      for (var apt in monthlyResponse) {
        monthlyTotal += (apt['price'] as num?)?.toInt() ?? 0;
      }

      // 3. AVERAGE RATING
      final reviewsResponse = await supabase
          .from('reviews')
          .select('overall_rating')
          .eq('barber_id', _employeeId)
          .eq('salon_id', salonId);

      double avgRating = 0.0;
      if (reviewsResponse.isNotEmpty) {
        double totalRating = 0;
        for (var review in reviewsResponse) {
          totalRating += (review['overall_rating'] as num?)?.toDouble() ?? 0;
        }
        avgRating = totalRating / reviewsResponse.length;
      }

      setState(() {
        _totalCustomers = uniqueCustomers;
        _monthlyEarnings = monthlyTotal;
        _rating = avgRating;
      });

      debugPrint(
        '✅ Stats - Customers: $uniqueCustomers, Monthly: $monthlyTotal, Rating: $avgRating',
      );
    } catch (e) {
      debugPrint('❌ Error loading statistics: $e');
      setState(() {
        _totalCustomers = 0;
        _monthlyEarnings = 0;
        _rating = 0.0;
      });
    }
  }

  // ==================== NOTIFICATION SETUP ====================

  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New message: ${message.data}');

        if (message.data['type'] == 'new_booking_assigned') {
          _showNewAssignmentAlert(message);
          _loadData();
        } else if (message.data['type'] == 'booking_reminder') {
          _showReminderAlert(message);
        }
      });
    } catch (e) {
      debugPrint('❌ Error setting up notification listeners: $e');
    }
  }

  void _showNewAssignmentAlert(RemoteMessage message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_add, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Text('New Booking Assigned!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.notification?.title ?? 'New Appointment'),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ?? 'You have a new booking assigned',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewMySchedule();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  void _showReminderAlert(RemoteMessage message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message.notification?.body ?? 'Upcoming appointment'),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: _viewMySchedule,
        ),
      ),
    );
  }

  // ==================== PERMISSIONS ====================

  Future<void> _enableNotifications() async {
    setState(() => _showPermissionCard = false);

    try {
      final canAsk = await _permissionManager.canAskSystemPermission();

      if (!canAsk) {
        _showSettingsDialog();
        return;
      }
      if (!mounted) return;
      await _permissionService.requestPermissionAtAction(
        context: context,
        action: 'employee_dashboard',
        customTitle: '🔔 Get Booking Updates',
        customMessage:
            'Get instant notifications for new bookings, reminders, and schedule changes',
        onGranted: () async {
          await _permissionManager.markPermissionGranted();
          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Notifications enabled!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        onDenied: () async {
          await _permissionManager.markPermissionDenied(permanent: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can enable later from settings'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error enabling notifications: $e');
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔔 Notifications Disabled'),
        content: const Text(
          'To enable notifications, please go to your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _permissionService.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('employee_dashboard');
  }

  // ==================== NAVIGATION ====================

  void _viewMySchedule() {
    context.push('/barber/appointments');
  }

  void _viewMyCustomers() {
    context.push('/employee/customers');
  }

  void _viewTodayEarnings() {
    context.push('/employee/earnings');
  }

  void _viewUpcomingAppointments() {
    context.push('/employee/appointments');
  }

  void _viewNotifications() {
    context.push('/notifications?role=barber');
  }

  void _viewBookingDetails(String customerName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing $customerName\'s booking'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _markAppointmentComplete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Appointment'),
        content: const Text('Mark this appointment as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Appointment marked as completed'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

  void _openDrawer() {
    try {
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
      } else {
        Scaffold.of(context).openDrawer();
      }
    } catch (e) {
      debugPrint('❌ Error opening drawer: $e');
      _showMenuDialog();
    }
  }

  void _showMenuDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Menu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.dashboard, color: Colors.blue),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.green),
                title: const Text('My Schedule'),
                onTap: () {
                  Navigator.pop(context);
                  _viewMySchedule();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people, color: Colors.purple),
                title: const Text('My Customers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewMyCustomers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: const Text('Earnings'),
                onTap: () {
                  Navigator.pop(context);
                  _viewTodayEarnings();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/employee/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(context);
                  _logout(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    showLogoutConfirmation(
      context,
      onLogoutConfirmed: () async {
        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
          ),
        );

        try {
          await SessionManager.logoutForContinue();
          appState.refreshState();

          if (context.mounted) {
            Navigator.pop(context);
            context.go('/');
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Logout failed: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // ==================== SALON SELECTOR DIALOG ====================

  Future<void> _showSalonSelectorDialog() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Salon',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a salon to view its data',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ..._assignedSalons.map((salon) {
              final isSelected = salon['id'] == _selectedSalonId;
              return ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: isSelected
                      ? const Color(0xFFFF6B8B)
                      : Colors.grey[200],
                  backgroundImage: salon['logo_url'] != null
                      ? NetworkImage(salon['logo_url'])
                      : null,
                  child: salon['logo_url'] == null
                      ? Icon(
                          Icons.store,
                          color: isSelected ? Colors.white : Colors.grey[600],
                          size: 20,
                        )
                      : null,
                ),
                title: Text(
                  salon['name'] ?? 'Unknown Salon',
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  salon['address'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFFFF6B8B))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _selectSalon(salon['id'] as int);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // ✅ BUILD METHOD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Employee Dashboard'),
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF6B8B)),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer,
          tooltip: 'Menu',
          iconSize: 28,
        ),
        actions: [
          _buildTimezoneSelector(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, size: 22),
                onPressed: _viewNotifications,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (_unreadNotificationCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _unreadNotificationCount > 99
                          ? '99+'
                          : '$_unreadNotificationCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          _buildProfileImage(),
        ],
      ),
      drawer: SideMenu(
        userRole: 'barber',
        userName: _employeeName,
        userEmail: _employeeEmail,
        profileImageUrl: _employeeAvatar.isNotEmpty ? _employeeAvatar : null,
        onMenuItemSelected: () => _loadData(),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFFFF6B8B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: _enableNotifications,
                        onNotNow: _handleNotNow,
                        title: '🔔 Get Booking Updates',
                        message:
                            'Get instant notifications for new bookings and schedule changes',
                        compact: false,
                      ),

                    // Welcome Section
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Welcome, ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    _employeeName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Barber',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.purple[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _assignedSalons.length > 1
                                        ? _showSalonSelectorDialog
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.store,
                                            size: 10,
                                            color: Colors.blue[700],
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            _selectedSalonName.isNotEmpty
                                                ? _selectedSalonName
                                                : 'No Salon',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (_assignedSalons.length > 1)
                                            const Icon(
                                              Icons.arrow_drop_down,
                                              size: 14,
                                              color: Colors.blue,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Status indicator
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isOnBreak
                                          ? Colors.orange.withValues(alpha: 0.1)
                                          : Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: _isOnBreak
                                                ? Colors.orange
                                                : Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          _isOnBreak ? 'Break' : 'Working',
                                          style: TextStyle(
                                            fontSize: 8,
                                            color: _isOnBreak
                                                ? Colors.orange
                                                : Colors.green,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),

                    // Rating Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.withValues(alpha: 0.1),
                            Colors.orange.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your Rating',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _rating > 0
                                        ? _rating.toStringAsFixed(1)
                                        : '0.0',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '/ 5.0',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  color: Colors.green,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '12%',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats Cards - Row 1
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Today\'s Appointments',
                              value: '$_todaysAppointments',
                              icon: Icons.calendar_today,
                              color: Colors.blue,
                              subtitle: '$_completedToday completed',
                              onTap: _viewMySchedule,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Pending',
                              value: '$_pendingAppointments',
                              icon: Icons.pending_actions,
                              color: Colors.orange,
                              subtitle: 'Awaiting service',
                              onTap: _viewUpcomingAppointments,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Stats Cards - Row 2
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Today\'s Earnings',
                              value: 'Rs. $_todayEarnings',
                              icon: Icons.currency_rupee,
                              color: Colors.green,
                              onTap: _viewTodayEarnings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Monthly Earnings',
                              value: 'Rs. $_monthlyEarnings',
                              icon: Icons.trending_up,
                              color: Colors.purple,
                              subtitle:
                                  '${_getMonthName()} ${DateTime.now().year}',
                              onTap: _viewTodayEarnings,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Stats Cards - Row 3
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DashboardStatCard(
                        title: 'Total Customers Served',
                        value: '$_totalCustomers',
                        icon: Icons.people,
                        color: Colors.teal,
                        fullWidth: true,
                        subtitle: 'All time',
                        onTap: _viewMyCustomers,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Actions
                    const SectionHeader(title: 'Quick Actions', actionText: ''),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.check_circle_outline,
                              label: 'Complete',
                              color: Colors.green,
                              onTap: _markAppointmentComplete,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.schedule_outlined,
                              label: 'My Schedule',
                              color: Colors.blue,
                              onTap: _viewMySchedule,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.message_outlined,
                              label: 'Notify Customer',
                              color: Colors.purple,
                              onTap: () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '📱 Customer notification sent',
                                      ),
                                      backgroundColor: Colors.purple,
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Today's Schedule
                    const SectionHeader(
                      title: 'Today\'s Schedule',
                      actionText: 'View All',
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child:
                          _todaysAppointmentsList
                              .where((a) => a['is_today'] == true)
                              .isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text(
                                  'No appointments today',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          : Column(
                              children: _todaysAppointmentsList
                                  .where((a) => a['is_today'] == true)
                                  .map((apt) {
                                    Color statusColor;
                                    switch (apt['status']) {
                                      case 'completed':
                                        statusColor = Colors.green;
                                        break;
                                      case 'confirmed':
                                        statusColor = Colors.blue;
                                        break;
                                      case 'cancelled':
                                        statusColor = Colors.red;
                                        break;
                                      default:
                                        statusColor = Colors.orange;
                                    }
                                    return BookingTile(
                                      customerName: apt['customer_name'],
                                      serviceName: apt['service_name'],
                                      time: apt['start_time'],
                                      status: apt['status'],
                                      statusColor: statusColor,
                                      barberName: 'You',
                                      price: apt['price'],
                                      salonName: apt['salon_name'],
                                      isVip: apt['is_vip'] ?? false,
                                      queueNumber: apt['queue_number'],
                                      queueToken: apt['queue_token'],
                                      showActions: apt['status'] != 'completed',
                                      onTap: () => _viewBookingDetails(
                                        apt['customer_name'],
                                      ),
                                      onComplete: _markAppointmentComplete,
                                    );
                                  })
                                  .toList(),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Performance Card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Today\'s Performance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPerformanceItem(
                                  label: 'Completed',
                                  value: '$_completedToday',
                                  icon: Icons.check_circle,
                                  color: Colors.green,
                                ),
                              ),
                              Expanded(
                                child: _buildPerformanceItem(
                                  label: 'No-show',
                                  value: '0',
                                  icon: Icons.cancel,
                                  color: Colors.red,
                                ),
                              ),
                              Expanded(
                                child: _buildPerformanceItem(
                                  label: 'On Time',
                                  value: '100%',
                                  icon: Icons.timer,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
