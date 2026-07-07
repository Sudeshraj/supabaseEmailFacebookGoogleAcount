import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();
  final supabase = Supabase.instance.client;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;
  bool _isActive = false;

  // Customer Data
  String _customerName = 'Guest User';
  String _customerEmail = '';
  String? _customerImage;

  // Booking Statistics
  int _upcomingBookings = 0;
  int pendingBookings = 0;
  int _completedBookings = 0;
  int _cancelledBookings = 0;
  int _totalSpent = 0;
  int _loyaltyPoints = 0;

  // VIP Bookings
  int _vipBookings = 0;
  int _pendingVipBookings = 0;

  // Favorite Barbers
  List<Map<String, dynamic>> _favoriteBarbers = [];

  // Special Offers (from database - only followed salons)
  List<Map<String, dynamic>> _offers = [];

  // Followed Salons
  List<Map<String, dynamic>> _followedSalons = [];
  bool _isLoadingSalons = false;

  // Notification Unread Count
  int _unreadNotificationCount = 0;
  bool _isRefreshingCount = false;

  // Timezone Variables
  String _userTimezone = '';
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  // Search State
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  OverlayEntry? _searchOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTimezone();
    _loadCustomerData();
    _checkCustomerStatus(); // ✅ NEW: Check customer status
    _loadDashboardData();
    _setupNotificationListeners();
    _searchController.addListener(_onSearchTextChanged);
    debugPrint('🔄 CustomerDashboard initState completed');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkForUpdates();
    _checkTimezoneChange();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed - refreshing notification count');
      _loadUnreadCount();
      _loadDashboardData();
      _checkCustomerStatus(); // ✅ Check status on resume
    }
  }

  void _checkForUpdates() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isTimezoneLoaded) {
        _loadDashboardData();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeSearchOverlay();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ============================================================
  // ✅ CHECK CUSTOMER STATUS (NEW)
  // ============================================================

  Future<void> _checkCustomerStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isActive = false);
        return;
      }

      // ✅ Check user_roles status
      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 3) // customer role ID
          .maybeSingle();

      if (roleCheck == null || roleCheck['status'] != 'active') {
        setState(() => _isActive = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your customer profile is not active. Please contact support.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // ✅ Check profile status
      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          setState(() => _isActive = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been blocked. Please contact support.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          setState(() => _isActive = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your profile is inactive. Please contact support.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      setState(() => _isActive = true);
    } catch (e) {
      debugPrint('❌ Error checking customer status: $e');
      setState(() => _isActive = false);
    }
  }

  // ============================================================
  // TIMEZONE INITIALIZATION
  // ============================================================

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    final savedTimezone = prefs.getString('cached_timezone');

    if (savedTimezone != null && savedTimezone.isNotEmpty) {
      _userTimezone = savedTimezone;
      await TimezoneService.setTimezone(_userTimezone);
      debugPrint('✅ Using cached timezone: $_userTimezone');
    } else {
      _userTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString('cached_timezone', _userTimezone);
      debugPrint('✅ Saved device timezone to cache: $_userTimezone');
    }

    _lastTimezone = _userTimezone;

    setState(() {
      _isTimezoneLoaded = true;
    });
  }

  void _checkTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();

    if (_lastTimezone != currentTimezone && _lastTimezone.isNotEmpty) {
      _userTimezone = currentTimezone;
      await TimezoneService.setTimezone(_userTimezone);
      _loadDashboardData();
    }
    _lastTimezone = currentTimezone;
  }

  // ============================================================
  // FIXED: PARSE DATE SAFELY
  // ============================================================

  DateTime _parseDateSafely(String dateStr) {
    String processedStr = dateStr;
    if (!dateStr.contains('T') && dateStr.length == 10) {
      processedStr = '${dateStr}T00:00:00Z';
    }
    return DateTime.parse(processedStr).toUtc();
  }

  // ============================================================
  // FIXED: CHECK OFFER ACTIVE
  // ============================================================

  bool _isOfferActive(Map<String, dynamic> offer) {
    try {
      final validFromUtc = _parseDateSafely(offer['valid_from']);
      final validToUtc = _parseDateSafely(offer['valid_to']);

      final nowUtc = DateTime.now().toUtc();
      final todayUtcMidnight = DateTime.utc(
        nowUtc.year,
        nowUtc.month,
        nowUtc.day,
      );
      final validFromUtcMidnight = DateTime.utc(
        validFromUtc.year,
        validFromUtc.month,
        validFromUtc.day,
      );
      final validToUtcMidnight = DateTime.utc(
        validToUtc.year,
        validToUtc.month,
        validToUtc.day,
      );

      return !validFromUtcMidnight.isAfter(todayUtcMidnight) &&
          validToUtcMidnight.isAfter(todayUtcMidnight);
    } catch (e) {
      debugPrint('Error checking offer active: $e');
      return false;
    }
  }

  // ============================================================
  // FIXED: GET DAYS LEFT
  // ============================================================

  int _getDaysLeft(String validToUtc) {
    try {
      final utcDate = _parseDateSafely(validToUtc);
      final nowUtc = DateTime.now().toUtc();
      final todayUtcMidnight = DateTime.utc(
        nowUtc.year,
        nowUtc.month,
        nowUtc.day,
      );
      final validToUtcMidnight = DateTime.utc(
        utcDate.year,
        utcDate.month,
        utcDate.day,
      );
      return validToUtcMidnight.difference(todayUtcMidnight).inDays;
    } catch (e) {
      debugPrint('Error calculating days left: $e');
      return -1;
    }
  }

  // ============================================================
  // FIXED: TIMEZONE CONVERSION METHODS
  // ============================================================

  String _convertUtcToLocalTime(String? utcTime, DateTime referenceDate) {
    if (utcTime == null || utcTime.isEmpty) return '--:--';
    try {
      String timeStr = utcTime;
      if (timeStr.length > 5) timeStr = timeStr.substring(0, 5);
      return TimezoneService.utcToLocalTimeForDate(timeStr, referenceDate);
    } catch (e) {
      debugPrint('Error converting time: $e');
      return utcTime.length > 5 ? utcTime.substring(0, 5) : utcTime;
    }
  }

  String _getFormattedSalonHours(Map<String, dynamic> salon) {
    final openTimeUtc = salon['open_time']?.toString() ?? '09:00:00';
    final closeTimeUtc = salon['close_time']?.toString() ?? '18:00:00';
    final referenceDate = DateTime.now();

    final openLocal = _convertUtcToLocalTime(openTimeUtc, referenceDate);
    final closeLocal = _convertUtcToLocalTime(closeTimeUtc, referenceDate);

    return '$openLocal - $closeLocal';
  }

  // ============================================================
  // TIMEZONE SELECTOR WIDGET
  // ============================================================

  Widget _buildTimezoneSelector() {
    return GestureDetector(
      onTap: _showAdvancedTimezonePicker,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TimezoneService.getCurrentFlag(),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 6),
            Text(
              TimezoneService.getTimezoneDisplayName(),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TIMEZONE PICKER METHODS
  // ============================================================

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
      'America/Argentina/Buenos_Aires': 'AR',
      'America/Santiago': 'CL',
      'America/Bogota': 'CO',
      'America/Lima': 'PE',
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
      'AR': '🇦🇷',
      'CL': '🇨🇱',
      'CO': '🇨🇴',
      'PE': '🇵🇪',
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

  Future<void> _showAdvancedTimezonePicker() async {
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

      await _loadDashboardData();

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

  // ============================================================
  // SEARCH METHODS
  // ============================================================

  void _onSearchTextChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _searchSalons(query);
    } else {
      _hideSearchResults();
    }
  }

  Future<void> _searchSalons(String query) async {
    if (query.isEmpty) {
      _hideSearchResults();
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    try {
      final results = await supabase
          .from('salons')
          .select('''
            id, 
            name, 
            address, 
            open_time, 
            close_time, 
            logo_url,
            cover_url,
            phone,
            email,
            description,
            is_active
          ''')
          .ilike('name', '%$query%')
          .eq('is_active', true)
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
        _isSearching = false;
      });

      if (_searchResults.isNotEmpty && _showSearchResults) {
        _showSearchOverlay();
      } else {
        _hideSearchResults();
      }
    } catch (e) {
      debugPrint('Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  void _showSearchOverlay() {
    _removeSearchOverlay();

    _searchOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 65,
        left: 0,
        right: 0,
        child: Material(
          elevation: 4,
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF6B8B),
                        ),
                      ),
                    ),
                  )
                : _searchResults.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('No salons found')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) =>
                        _buildSearchResultTile(_searchResults[index]),
                  ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_searchOverlay!);
  }

  Widget _buildSearchResultTile(Map<String, dynamic> salon) {
    return InkWell(
      onTap: () {
        _hideSearchResults();
        _searchController.clear();
        _navigateToSalonProfile(salon);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: salon['logo_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        salon['logo_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            salon['name']?.substring(0, 1) ?? 'S',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B8B),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        salon['name']?.substring(0, 1) ?? 'S',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B8B),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon['name'] ?? 'Salon',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (salon['address'] != null)
                    Text(
                      salon['address'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 10,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _getFormattedSalonHours(salon),
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: Color(0xFFFF6B8B),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'View',
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFFFF6B8B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideSearchResults() {
    if (_searchOverlay != null) {
      _searchOverlay!.remove();
      _searchOverlay = null;
    }
    setState(() {
      _showSearchResults = false;
      _searchResults = [];
    });
  }

  void _removeSearchOverlay() {
    if (_searchOverlay != null) {
      _searchOverlay!.remove();
      _searchOverlay = null;
    }
  }

  void _navigateToSalonProfile(Map<String, dynamic> salon) {
    debugPrint('🎯 Navigating to salon profile: ${salon['name']}');
    context.push('/customer/salon-profile', extra: salon);
  }

  // ============================================================
  // LOAD CUSTOMER DATA
  // ============================================================

  Future<void> _loadCustomerData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      _customerEmail = user.email ?? '';

      final profile = await supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null) {
        setState(() {
          _customerName =
              profile['full_name'] ??
              user.email?.split('@').first ??
              'Guest User';
          _customerImage = profile['avatar_url'];
        });
      } else {
        setState(() {
          _customerName = user.email?.split('@').first ?? 'Guest User';
        });
      }

      debugPrint('✅ Loaded customer: $_customerName ($_customerEmail)');
    } catch (e) {
      debugPrint('❌ Error loading customer data: $e');
    }
  }

  // ============================================================
  // LOAD FOLLOWED SALONS
  // ============================================================

  Future<void> _loadFollowedSalons(String userId) async {
    try {
      setState(() => _isLoadingSalons = true);

      final result = await supabase.rpc(
        'get_followed_salons_with_counts',
        params: {'p_customer_id': userId},
      );

      if (result != null && result.isNotEmpty) {
        final List<Map<String, dynamic>> salons = [];

        for (final salon in result) {
          salons.add({
            'id': salon['id'],
            'name': salon['name'] ?? 'Salon',
            'logo_url': salon['logo_url'],
            'address': salon['address'] ?? 'Address not available',
            'phone': salon['phone'] ?? '',
            'open_time': salon['open_time'] ?? '09:00:00',
            'close_time': salon['close_time'] ?? '18:00:00',
            'follower_count': salon['follower_count'] ?? 0,
            'booking_count': salon['booking_count'] ?? 0,
          });
        }

        if (mounted) {
          setState(() {
            _followedSalons = salons;
          });
        }
        debugPrint('✅ Loaded ${_followedSalons.length} followed salons');
      } else {
        if (mounted) {
          setState(() {
            _followedSalons = [];
          });
        }
        debugPrint('📭 No followed salons found');
      }
    } catch (e) {
      debugPrint('❌ Error loading followed salons: $e');
      if (mounted) {
        setState(() {
          _followedSalons = [];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingSalons = false);
    }
  }

  // ============================================================
  // LOAD OFFERS FROM FOLLOWED SALONS
  // ============================================================

  Future<List<Map<String, dynamic>>> _loadOffersFromDatabase() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return [];

      final followedSalonsResult = await supabase
          .from('salon_followers')
          .select('salon_id')
          .eq('customer_id', user.id);

      if (followedSalonsResult.isEmpty) {
        debugPrint('📭 No followed salons found, no offers to show');
        return [];
      }

      final List<int> followedSalonIds = [];
      for (var item in followedSalonsResult) {
        followedSalonIds.add(item['salon_id'] as int);
      }

      debugPrint('📋 Followed salon IDs: $followedSalonIds');

      final today = DateTime.now().toIso8601String().split('T')[0];

      final result = await supabase
          .from('offers')
          .select('''
            id,
            title,
            description,
            discount_type,
            discount_value,
            points_required,
            valid_from,
            valid_to,
            image_url,
            salon_id,
            salons:salon_id (
              id,
              name,
              logo_url,
              address
            )
          ''')
          .inFilter('salon_id', followedSalonIds)
          .eq('is_active', true)
          .lte('valid_from', today)
          .gte('valid_to', today)
          .order('created_at', ascending: false)
          .limit(20);

      if (result.isNotEmpty) {
        debugPrint('✅ Loaded ${result.length} offers from followed salons');
        return List<Map<String, dynamic>>.from(result);
      } else {
        debugPrint('📭 No active offers found in followed salons');
      }
    } catch (e) {
      debugPrint('❌ Error loading offers from followed salons: $e');
    }

    return [];
  }

  // ============================================================
  // LOAD UNREAD NOTIFICATION COUNT
  // ============================================================

  Future<void> _loadUnreadCount() async {
    if (_isRefreshingCount) return;

    try {
      _isRefreshingCount = true;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final cachedCount = prefs.getInt('cached_unread_count_${user.id}') ?? 0;

      if (mounted && _unreadNotificationCount != cachedCount) {
        setState(() {
          _unreadNotificationCount = cachedCount;
        });
      }

      final count = await _notificationService.getUnreadCount(user.id);

      await prefs.setInt('cached_unread_count_${user.id}', count);

      if (mounted) {
        setState(() {
          _unreadNotificationCount = count;
        });
      }

      debugPrint('📬 Unread notifications: $_unreadNotificationCount');
    } catch (e) {
      debugPrint('❌ Error loading unread count: $e');
    } finally {
      _isRefreshingCount = false;
    }
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final count = await _notificationService.getUnreadCount(user.id);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cached_unread_count_${user.id}', count);

      if (mounted) {
        setState(() {
          _unreadNotificationCount = count;
        });
      }

      debugPrint('🔄 Refreshed unread count: $_unreadNotificationCount');
    } catch (e) {
      debugPrint('❌ Error refreshing unread count: $e');
    }
  }

  // ============================================================
  // LOAD DASHBOARD DATA
  // ============================================================

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // ✅ Check customer status first
      await _checkCustomerStatus();
      if (!_isActive) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await _loadFollowedSalons(user.id);

      final appointments = await supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            appointment_date,
            start_time,
            end_time,
            status,
            is_vip,
            vip_booking_id,
            price,
            queue_number,
            queue_token,
            barber_id,
            service_id,
            variant_id,
            services!inner (
              name
            ),
            service_variants!left (
              price,
              duration,
              salon_genders!left (display_name),
              salon_age_categories!left (display_name)
            )
          ''')
          .eq('customer_id', user.id)
          .order('appointment_date', ascending: false);

      int upcoming = 0;
      int pending = 0;
      int completed = 0;
      int cancelled = 0;
      int vip = 0;
      int pendingVip = 0;
      double totalSpent = 0.0;

      for (var apt in appointments) {
        final status = apt['status'] as String;
        final isVip = apt['is_vip'] == true;

        final double price =
            (apt['price'] as num?)?.toDouble() ??
            (apt['service_variants']?['price'] as num?)?.toDouble() ??
            0.0;

        if (status == 'confirmed' || status == 'pending') {
          final dateStr = apt['appointment_date'] as String;
          final date = DateTime.parse(dateStr);
          if (date.isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
            upcoming++;
          }
        }

        if (status == 'pending') pending++;
        if (status == 'completed') {
          completed++;
          totalSpent += price;
        }
        if (status == 'cancelled') cancelled++;

        if (isVip) {
          vip++;
          if (status == 'pending') pendingVip++;
        }
      }

      final favoriteBarbers = await _getFavoriteBarbers(user.id);
      final offers = await _loadOffersFromDatabase();

      await _loadUnreadCount();

      if (mounted) {
        setState(() {
          _upcomingBookings = upcoming;
          pendingBookings = pending;
          _completedBookings = completed;
          _cancelledBookings = cancelled;
          _vipBookings = vip;
          _pendingVipBookings = pendingVip;
          _totalSpent = totalSpent.toInt();
          _loyaltyPoints = (totalSpent / 10).round();
          _favoriteBarbers = favoriteBarbers;
          _offers = offers;
        });
      }

      _hasPermission = await _notificationService.hasPermission();
      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'customer_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      debugPrint(
        '✅ Dashboard loaded: $upcoming upcoming, ${offers.length} offers, $_unreadNotificationCount unread notifications',
      );
    } catch (e) {
      debugPrint('❌ Error loading dashboard data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // GET FAVORITE BARBERS
  // ============================================================

  Future<List<Map<String, dynamic>>> _getFavoriteBarbers(
    String customerId,
  ) async {
    try {
      final response = await supabase
          .from('appointments')
          .select('''
            barber_id,
            profiles!barber_id (
              full_name,
              avatar_url
            )
          ''')
          .eq('customer_id', customerId)
          .eq('status', 'completed');

      final Map<String, Map<String, dynamic>> barberCount = {};
      for (var apt in response) {
        final barberId = apt['barber_id'] as String;
        final barberData = apt['profiles'] as Map?;

        if (!barberCount.containsKey(barberId)) {
          barberCount[barberId] = {
            'id': barberId,
            'name': barberData?['full_name'] ?? 'Unknown',
            'avatar': barberData?['avatar_url'],
            'count': 0,
          };
        }
        barberCount[barberId]!['count'] = barberCount[barberId]!['count'] + 1;
      }

      List<Map<String, dynamic>> barbers = barberCount.values.toList();
      barbers.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      for (var barber in barbers.take(5)) {
        final reviewsResult = await supabase
            .from('reviews')
            .select('overall_rating')
            .eq('barber_id', barber['id']);

        double avgRating = 0;
        if (reviewsResult.isNotEmpty) {
          double total = 0;
          for (var review in reviewsResult) {
            total += (review['overall_rating'] as num?)?.toDouble() ?? 0;
          }
          avgRating = total / reviewsResult.length;
        }
        barber['rating'] = avgRating > 0 ? avgRating : 4.5;
      }

      return barbers.take(5).toList();
    } catch (e) {
      debugPrint('❌ Error getting favorite barbers: $e');
      return [];
    }
  }

  // ============================================================
  // NOTIFICATION LISTENERS
  // ============================================================

  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New foreground message received: ${message.data}');
        _loadUnreadCount();

        final type = message.data['type'];
        if (type == 'booking_confirmed' || type == 'vip_approved') {
          _loadDashboardData();
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('📱 App opened from notification tap');
        _loadUnreadCount();
        _handleNotificationTap(message);
      });

      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          debugPrint('📱 App launched from terminated state with notification');
          _loadUnreadCount();
          _handleNotificationTap(message);
        }
      });

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 FCM Token refreshed: $newToken');
      });
    } catch (e) {
      debugPrint('❌ Error setting up notification listeners: $e');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    try {
      final type = message.data['type'];
      final bookingId = message.data['booking_id'];

      debugPrint('🔔 Notification tapped - Type: $type, BookingId: $bookingId');

      if (type == 'booking_confirmed' || type == 'booking_update') {
        if (bookingId != null && mounted) {
          context.push('/customer/booking-details', extra: bookingId);
        } else {
          _viewMyBookings();
        }
      } else if (type == 'vip_approved' || type == 'vip_update') {
        _viewVipBookings();
      } else if (type == 'offer') {
        _viewAllOffers();
      } else {
        _viewNotifications();
      }
    } catch (e) {
      debugPrint('❌ Error handling notification tap: $e');
      _viewNotifications();
    }
  }

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
        action: 'customer_dashboard',
        customTitle: '🔔 Get Booking Updates',
        customMessage:
            'Get instant notifications for booking confirmations, VIP approvals, and special offers',
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
    await _permissionManager.markPermissionShown('customer_dashboard');
  }

  // ============================================================
  // NAVIGATION METHODS
  // ============================================================

  void _viewMyBookings() {
    context.push('/customer/my-bookings');
  }

  void _viewVipBookings() {
    context.push('/customer/vip-bookings');
  }

  void _createVipBooking() {
    context.push('/customer/vip-booking');
  }

  void _bookAppointment() {
    context.push('/customer/booking-flow');
  }

  void _viewAllOffers() {
    context.push('/customer/offers');
  }

  Future<void> _viewNotifications() async {
    debugPrint('🔔 Navigating to notifications page');

    final result = await context.push('/notifications?role=customer');

    debugPrint('🔔 Returning from notifications page, refreshing count');
    await _refreshUnreadCount();

    if (result == true) {
      debugPrint('🔔 Notifications were marked as read, refreshing dashboard');
      _loadDashboardData();
    }
  }

  void _viewLoyaltyProgram() {
    context.push('/customer/loyalty');
  }

  void _viewFavoriteBarbers() {
    context.push('/customer/favorites');
  }

  // ============================================================
  // APPLY OFFER METHOD
  // ============================================================

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  // ✅ APPLY OFFER WITH STATUS CHECK (UPDATED)
  // ============================================================

  Future<void> _applyOffer(Map<String, dynamic> offer) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          _showSnackBar('Please login to apply offers', Colors.orange);
          context.push('/login');
        }
        return;
      }

      // ✅ STEP 1: Check if customer has active role
      final customerCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 3) // customer role ID
          .maybeSingle();

      if (customerCheck == null || customerCheck['status'] != 'active') {
        if (mounted) {
          _showSnackBar(
            'Your account is not active. Please contact support.',
            Colors.red,
          );
        }
        return;
      }

      // ✅ STEP 2: Check if profile is active and not blocked
      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          if (mounted) {
            _showSnackBar(
              'Your account has been blocked. Please contact support.',
              Colors.red,
            );
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          if (mounted) {
            _showSnackBar(
              'Your profile is inactive. Please contact support.',
              Colors.red,
            );
          }
          return;
        }
      }

      // Check offer validity
      if (!_isOfferActive(offer)) {
        if (mounted) {
          _showSnackBar('This offer has expired', Colors.red);
        }
        return;
      }

      // Check points requirement
      final pointsRequired = offer['points_required'] ?? 0;
      if (pointsRequired > 0) {
        final loyaltyResult = await supabase
            .from('customer_loyalty')
            .select('current_points')
            .eq('customer_id', user.id)
            .maybeSingle();

        final userPoints = loyaltyResult?['current_points'] ?? 0;
        if (userPoints < pointsRequired) {
          if (mounted) {
            _showSnackBar(
              'You need $pointsRequired points to apply this offer',
              Colors.orange,
            );
          }
          return;
        }
      }

      // Check usage limit
      final usageLimit = offer['usage_limit'];
      final usedCount = offer['used_count'] ?? 0;
      if (usageLimit != null && usedCount >= usageLimit) {
        if (mounted) {
          _showSnackBar('This offer has reached its usage limit', Colors.red);
        }
        return;
      }

      // Check if already applied
      final existingOffer = await supabase
          .from('customer_offers')
          .select('id, status')
          .eq('customer_id', user.id)
          .eq('offer_id', offer['id'])
          .maybeSingle();

      if (existingOffer != null) {
        if (existingOffer['status'] == 'active') {
          if (mounted) {
            _showSnackBar('You have already applied this offer', Colors.orange);
          }
          return;
        } else if (existingOffer['status'] == 'used') {
          if (mounted) {
            _showSnackBar('You have already used this offer', Colors.red);
          }
          return;
        }
      }

      if (!mounted) return;

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Text(
                _getDiscountIcon(offer['discount_type']),
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  offer['title'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(offer['description'] ?? ''),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getDiscountColor(
                    offer['discount_type'],
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _getDiscountText(offer),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _getDiscountColor(offer['discount_type']),
                    ),
                  ),
                ),
              ),
              if (pointsRequired > 0) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Requires $pointsRequired loyalty points',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (mounted) {
                  Navigator.pop(dialogContext, false);
                }
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply Offer'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (confirmed != true) return;

      // Save to customer_offers table
      await supabase.from('customer_offers').insert({
        'customer_id': user.id,
        'offer_id': offer['id'],
        'claimed_at': DateTime.now().toIso8601String(),
        'expires_at': offer['valid_to'],
        'status': 'active',
      });

      // Update offer usage count
      await supabase
          .from('offers')
          .update({'used_count': (usedCount + 1)})
          .eq('id', offer['id']);

      // Deduct points if required
      if (pointsRequired > 0) {
        final loyaltyResult = await supabase
            .from('customer_loyalty')
            .select('current_points')
            .eq('customer_id', user.id)
            .maybeSingle();

        final currentPoints = loyaltyResult?['current_points'] ?? 0;
        final newPoints = currentPoints - pointsRequired;

        await supabase
            .from('customer_loyalty')
            .update({
              'current_points': newPoints,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('customer_id', user.id);

        await supabase.from('loyalty_transactions').insert({
          'customer_id': user.id,
          'points': -pointsRequired,
          'type': 'redeem',
          'source': 'offer',
          'reference_id': offer['id'].toString(),
          'description':
              'Redeemed $pointsRequired points for ${offer['title']}',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Show success message
      if (mounted) {
        _showSnackBar(
          '✅ "${offer['title']}" applied successfully!',
          Colors.green,
        );
      }

      // Navigate to booking flow
      if (mounted) {
        context.push('/customer/booking-flow', extra: {'offer': offer});
      }
    } catch (e) {
      debugPrint('Error applying offer: $e');
      if (mounted) {
        _showSnackBar('Error applying offer. Please try again.', Colors.red);
      }
    }
  }

  String _getDiscountText(Map<String, dynamic> offer) {
    if (offer['discount_type'] == 'percentage') {
      return '${offer['discount_value']}% OFF';
    } else if (offer['discount_type'] == 'fixed') {
      return 'Rs. ${offer['discount_value']} OFF';
    } else {
      return 'FREE SERVICE';
    }
  }

  String _getDiscountIcon(String? discountType) {
    switch (discountType) {
      case 'percentage':
        return '💰';
      case 'fixed':
        return '💵';
      case 'free_service':
        return '🎁';
      default:
        return '🏷️';
    }
  }

  Color _getDiscountColor(String? discountType) {
    switch (discountType) {
      case 'percentage':
        return const Color(0xFFFF6B8B);
      case 'fixed':
        return Colors.green.shade600;
      case 'free_service':
        return Colors.purple.shade600;
      default:
        return Colors.orange.shade600;
    }
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
    }
  }

  // ============================================================
  // WIDGET BUILDERS
  // ============================================================

  Widget _buildHorizontalSalonCard(Map<String, dynamic> salon) {
    final hasLogo =
        salon['logo_url'] != null && salon['logo_url'].toString().isNotEmpty;

    return GestureDetector(
      onTap: () => _navigateToSalonProfile(salon),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: hasLogo
                      ? Image.network(
                          salon['logo_url'],
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                height: 100,
                                color: const Color(
                                  0xFFFF6B8B,
                                ).withValues(alpha: 0.1),
                                child: Center(
                                  child: Text(
                                    salon['name'][0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF6B8B),
                                    ),
                                  ),
                                ),
                              ),
                        )
                      : Container(
                          height: 100,
                          color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                          child: Center(
                            child: Text(
                              salon['name'][0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B8B),
                              ),
                            ),
                          ),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people, size: 10, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '${salon['follower_count']}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          salon['name'],
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 10,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                salon['address'],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.content_cut,
                                size: 8,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${salon['booking_count']}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF6B8B,
                            ).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: Color(0xFFFF6B8B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowedSalonsSection() {
    if (_isLoadingSalons) {
      return Container(
        height: 210,
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFF6B8B),
            ),
          ),
        ),
      );
    }

    if (_followedSalons.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.store_outlined,
                size: 48,
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Followed Salons',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Follow your favorite salons to see them here',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B8B),
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'My Salons',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _followedSalons.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) =>
                _buildHorizontalSalonCard(_followedSalons[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveBookButton() {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: _bookAppointment,
        icon: const Icon(Icons.calendar_today, size: 18, color: Colors.white),
        label: const Text(
          'Book Now',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildResponsiveVipButton() {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: _createVipBooking,
        icon: const Icon(Icons.star, size: 18, color: Colors.amber),
        label: const Text(
          'VIP Booking',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.amber,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.amber, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildOffersButton() {
    return IconButton(
      icon: const Icon(Icons.local_offer_outlined, color: Colors.white),
      onPressed: _viewAllOffers,
      tooltip: 'Offers',
    );
  }

  Widget _buildNotificationIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () {
            debugPrint('🔔 Notification icon clicked!');
            _viewNotifications();
          },
          tooltip: 'Notifications',
          splashRadius: 24,
          iconSize: 24,
        ),
        if (_unreadNotificationCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: GestureDetector(
              onTap: () {
                debugPrint('🔔 Notification badge clicked!');
                _viewNotifications();
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  _unreadNotificationCount > 99
                      ? '99+'
                      : '$_unreadNotificationCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfilePhoto() {
    final hasImage = _customerImage != null && _customerImage!.isNotEmpty;

    return GestureDetector(
      onTap: _openDrawer,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          backgroundImage: hasImage ? NetworkImage(_customerImage!) : null,
          child: !hasImage
              ? Text(
                  _customerName.isNotEmpty
                      ? _customerName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildActivitySummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF6B8B).withValues(alpha: 0.05),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics,
                  color: Color(0xFFFF6B8B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Activity Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildActivityItem(
                  icon: Icons.check_circle,
                  label: 'Completed',
                  value: '$_completedBookings',
                  color: Colors.green,
                ),
              ),
              Expanded(
                child: _buildActivityItem(
                  icon: Icons.cancel,
                  label: 'Cancelled',
                  value: '$_cancelledBookings',
                  color: Colors.red,
                ),
              ),
              Expanded(
                child: _buildActivityItem(
                  icon: Icons.star,
                  label: 'VIP',
                  value: '$_vipBookings',
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActivityItem(
                  icon: Icons.currency_rupee,
                  label: 'Total Spent',
                  value: 'Rs. $_totalSpent',
                  color: Colors.purple,
                ),
              ),
              Expanded(
                child: _buildActivityItem(
                  icon: Icons.card_giftcard,
                  label: 'Points',
                  value: '$_loyaltyPoints',
                  color: Colors.blue,
                ),
              ),
              Expanded(
                child: _buildActivityItem(
                  icon: Icons.calendar_today,
                  label: 'Upcoming',
                  value: '$_upcomingBookings',
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ============================================================
  // FACEBOOK STYLE OFFER POST
  // ============================================================

  Widget _buildFacebookStyleOfferPost(Map<String, dynamic> offer, int index) {
    final salonData = offer['salons'];
    final salonName = salonData != null ? salonData['name'] : 'Special Offer';
    final salonLogo = salonData != null ? salonData['logo_url'] : null;

    final daysLeft = _getDaysLeft(offer['valid_to']);
    final discountColor = _getDiscountColor(offer['discount_type']);
    final discountText = _getDiscountText(offer);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(
                    0xFFFF6B8B,
                  ).withValues(alpha: 0.1),
                  backgroundImage: salonLogo != null
                      ? NetworkImage(salonLogo)
                      : null,
                  child: salonLogo == null
                      ? Text(
                          salonName.isNotEmpty
                              ? salonName[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B8B),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        salonName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            daysLeft <= 0 ? 'Expired' : '$daysLeft days left',
                            style: TextStyle(
                              fontSize: 11,
                              color: daysLeft <= 3
                                  ? Colors.red
                                  : Colors.grey[500],
                            ),
                          ),
                          if ((offer['points_required'] ?? 0) > 0) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.star,
                              size: 12,
                              color: Colors.amber.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${offer['points_required']} pts',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade400, Colors.orange.shade500],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    discountText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey[200], height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer['title'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  offer['description'] ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _applyOffer(offer),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: discountColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          'Apply Offer',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => _bookAppointment(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        side: BorderSide(color: Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text('Book Now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MAIN BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    if (!_isTimezoneLoaded) {
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
          actions: [_buildProfilePhoto()],
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

    // ✅ Show inactive message if not active
    if (!_isActive) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _openDrawer,
            tooltip: 'Menu',
            iconSize: 28,
          ),
          actions: [_buildProfilePhoto()],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Profile Inactive',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your customer profile is not active.\nPlease contact support for assistance.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadDashboardData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Check Status'),
              ),
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
          _buildOffersButton(),
          _buildNotificationIcon(),
          _buildProfilePhoto(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '🔍 Search for salons...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _hideSearchResults();
                          },
                          child: const Icon(Icons.close, color: Colors.white),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onTap: () {
                  if (_searchController.text.isNotEmpty &&
                      _searchResults.isNotEmpty) {
                    _showSearchOverlay();
                  }
                },
              ),
            ),
          ),
        ),
      ),
      drawer: SideMenu(
        userRole: 'customer',
        userName: _customerName,
        userEmail: _customerEmail,
        profileImageUrl: _customerImage,
        onMenuItemSelected: () => _loadDashboardData(),
      ),
      body: GestureDetector(
        onTap: () {
          _searchFocusNode.unfocus();
          _hideSearchResults();
        },
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
              )
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                color: const Color(0xFFFF6B8B),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      if (_showPermissionCard && !_hasPermission)
                        PermissionCard(
                          onEnable: _enableNotifications,
                          onNotNow: _handleNotNow,
                          title: '🔔 Get Booking Updates',
                          message:
                              'Get instant notifications for booking confirmations, VIP approvals, and special offers',
                          compact: false,
                        ),
                      const SizedBox(height: 8),
                      _buildFollowedSalonsSection(),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildResponsiveBookButton(),
                            const SizedBox(width: 12),
                            _buildResponsiveVipButton(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildStatCard(
                              'Upcoming',
                              '$_upcomingBookings',
                              Icons.calendar_today,
                              Colors.blue,
                              _viewMyBookings,
                            ),
                            const SizedBox(width: 12),
                            _buildStatCard(
                              'VIP',
                              '$_vipBookings',
                              Icons.star,
                              Colors.amber,
                              _viewVipBookings,
                            ),
                            const SizedBox(width: 12),
                            _buildStatCard(
                              'Points',
                              '$_loyaltyPoints',
                              Icons.card_giftcard,
                              Colors.green,
                              _viewLoyaltyProgram,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_pendingVipBookings > 0)
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.shade300,
                                Colors.amber.shade600,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'VIP Request Pending',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '$_pendingVipBookings VIP booking${_pendingVipBookings != 1 ? 's' : ''} waiting for approval',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _viewVipBookings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.amber.shade700,
                                ),
                                child: const Text('View'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      _buildActivitySummaryCard(),
                      const SizedBox(height: 20),
                      if (_offers.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF6B8B),
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(4),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Latest Offers',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _viewAllOffers,
                                child: const Text('View All >'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._offers.map(
                          (offer) => _buildFacebookStyleOfferPost(
                            offer,
                            _offers.indexOf(offer),
                          ),
                        ),
                      ],
                      if (_favoriteBarbers.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF6B8B),
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(4),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Favorite Barbers',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _viewFavoriteBarbers,
                                child: const Text('View All >'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _favoriteBarbers.length,
                            itemBuilder: (context, index) {
                              final barber = _favoriteBarbers[index];
                              return Container(
                                width: 160,
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withValues(alpha: 0.1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 35,
                                      backgroundColor: const Color(
                                        0xFFFF6B8B,
                                      ).withValues(alpha: 0.1),
                                      backgroundImage: barber['avatar'] != null
                                          ? NetworkImage(barber['avatar'])
                                          : null,
                                      child: barber['avatar'] == null
                                          ? Text(
                                              barber['name'][0].toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFFF6B8B),
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      barber['name'],
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          barber['rating'].toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '(${barber['count']} cuts)',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: _bookAppointment,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFFFF6B8B,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFFF6B8B),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'Book',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}