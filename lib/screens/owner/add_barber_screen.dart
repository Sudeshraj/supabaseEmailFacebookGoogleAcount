import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/ip_helper.dart';
import '../../services/timezone_service.dart';
import '../../extensions/context_extensions.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class AddBarberScreen extends StatefulWidget {
  final bool refresh;

  const AddBarberScreen({super.key, this.refresh = false});

  @override
  State<AddBarberScreen> createState() => _AddBarberScreenState();
}

class _AddBarberScreenState extends State<AddBarberScreen>
    with RouteAware, AutomaticKeepAliveClientMixin {
  // ==================== CONTROLLERS ====================
  final TextEditingController _searchController = TextEditingController();

  // ==================== DATA LISTS ====================
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _ownerSalons = [];
  List<Map<String, dynamic>> _services = [];

  final Map<String, List<int>> _selectedItems = {};

  // ==================== SELECTED ITEMS ====================
  String? _selectedBarberId;
  String? _selectedSalonId;
  Map<String, dynamic>? _selectedSalonDetails;

  // ==================== TIMEZONE VARIABLES ====================
  String _deviceTimezone = '';
  String _salonTimezone = '';
  bool _isTimezoneLoaded = false;
  String _salonOpenTimeUtc = '09:00:00';
  String _salonCloseTimeUtc = '18:00:00';

  // ==================== UI STATES ====================
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isLoadingSalons = false;
  bool _isLoadingServices = true;
  bool _isLoadingSalonData = false;

  // ==================== IP ADDRESS ====================
  String? _currentIp;
  bool _isLoadingIp = false;

  // ==================== EXPANSION STATE ====================
  final Set<String> _expandedServices = {};

  // ==================== CATEGORY TAB STATE ====================
  String? _selectedCategoryTab;

  // ==================== BARBER ASSIGNED SERVICES ====================
  // Tracks which services/variants are already assigned to the currently
  // selected barber, so we can disable just those items instead of
  // disabling the whole barber.
  Set<int> _barberAssignedVariantIds = {};
  Set<String> _barberAssignedServiceIds = {};
  bool _isLoadingBarberServices = false;

  // ==================== TIMERS ====================
  Timer? _debounceTimer;

  // ==================== SUPABASE CLIENT ====================
  final supabase = Supabase.instance.client;

  // ==================== RESPONSIVE HELPERS ====================
  late bool _isWeb;

  // ✅ Alternating card colors - using theme-aware alpha blending
  // These are palette variations; base colors come from AppTheme.primary
  final List<Color> _cardColorTints = [
    const Color(0xFFE3F2FD), // Light Blue tint
    const Color(0xFFFCE4EC), // Light Pink tint
    const Color(0xFFE8F5E9), // Light Green tint
    const Color(0xFFFFF3E0), // Light Orange tint
    const Color(0xFFF3E5F5), // Light Purple tint
    const Color(0xFFE0F7FA), // Light Cyan tint
    const Color(0xFFFFEBEE), // Light Red tint
    const Color(0xFFE8EAF6), // Light Indigo tint
  ];

  // ==================== COMPUTED PROPERTIES ====================
  int get _totalSelectedItems {
    int total = 0;
    _selectedItems.forEach((serviceId, variantList) {
      if (variantList.isEmpty) {
        total += 1;
      } else {
        total += variantList.length;
      }
    });
    return total;
  }

  int get _totalSelectedServices => _selectedItems.keys.length;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeAllData();
    _searchController.addListener(_onSearchChanged);

    if (widget.refresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshData();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshData();
  }

  // ============================================================
  // DST-SAFE TIMEZONE CONVERSION
  // ============================================================

  String _localTimeToUtcString(TimeOfDay localTime, String timezone) {
    return TimezoneService.timeOfDayToUtcWithTimezone(localTime, timezone);
  }

  // ============================================================
  // INITIALIZE ALL DATA
  // ============================================================

  Future<void> _initializeAllData() async {
    try {
      await TimezoneService.initialize();

      final prefs = await SharedPreferences.getInstance();
      final cachedTimezone = prefs.getString('cached_timezone');

      if (cachedTimezone != null && cachedTimezone.isNotEmpty) {
        _deviceTimezone = cachedTimezone;
      } else {
        _deviceTimezone = TimezoneService.getCurrentTimezone();
        await prefs.setString('cached_timezone', _deviceTimezone);
      }

      if (mounted) {
        setState(() => _isTimezoneLoaded = true);
      }

      await _loadIpAddress();
      await _loadOwnerSalons();
    } catch (e) {
      debugPrint('❌ Error in initialization: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingServices = false;
          _isTimezoneLoaded = true;
        });
        _showSnackBar('Error initializing: ${e.toString()}', Colors.red);
      }
    }
  }

  // ============================================================
  // LOAD SALON TIMEZONE AND HOURS
  // ============================================================

  Future<void> _loadSalonTimezoneAndHours() async {
    if (_selectedSalonId == null) return;

    try {
      final salonIdInt = int.parse(_selectedSalonId!);
      final response = await supabase
          .from('salons')
          .select('open_time, close_time, timezone')
          .eq('id', salonIdInt)
          .single();

      setState(() {
        _salonTimezone = response['timezone'] ?? 'Asia/Colombo';
        _salonOpenTimeUtc = response['open_time'] ?? '09:00:00';
        _salonCloseTimeUtc = response['close_time'] ?? '18:00:00';
      });

      debugPrint('✅ Loaded salon timezone: $_salonTimezone');
    } catch (e) {
      debugPrint('❌ Error loading salon timezone: $e');
      setState(() {
        _salonTimezone = 'Asia/Colombo';
        _salonOpenTimeUtc = '09:00:00';
        _salonCloseTimeUtc = '18:00:00';
      });
    }
  }

  // ============================================================
  // LOAD BARBER LUNCH BREAKS
  // ============================================================

  Future<Map<int, Map<String, String>>> _loadBarberLunchBreaks() async {
    final Map<int, Map<String, String>> lunchBreaks = {};

    try {
      final salonIdInt = int.parse(_selectedSalonId!);
      final currentDate = DateTime.now();
      int currentDayOfWeek = currentDate.weekday;

      for (int dayOfWeek = 1; dayOfWeek <= 7; dayOfWeek++) {
        DateTime targetDate = currentDate.add(
          Duration(days: dayOfWeek - currentDayOfWeek),
        );
        String dateStr = targetDate.toIso8601String().split('T')[0];

        final specialBreak = await supabase
            .from('barber_special_breaks')
            .select('start_time, end_time')
            .eq('barber_id', _selectedBarberId!)
            .eq('salon_id', salonIdInt)
            .eq('break_date', dateStr)
            .eq('break_type', 'lunch')
            .maybeSingle();

        if (specialBreak != null) {
          lunchBreaks[dayOfWeek] = {
            'start': specialBreak['start_time'] as String,
            'end': specialBreak['end_time'] as String,
            'source': 'special',
            'date': dateStr,
          };
          continue;
        }

        final regularBreak = await supabase
            .from('barber_breaks')
            .select('start_time, end_time')
            .eq('barber_id', _selectedBarberId!)
            .eq('salon_id', salonIdInt)
            .eq('day_of_week', dayOfWeek)
            .eq('break_type', 'lunch')
            .maybeSingle();

        if (regularBreak != null) {
          lunchBreaks[dayOfWeek] = {
            'start': regularBreak['start_time'] as String,
            'end': regularBreak['end_time'] as String,
            'source': 'regular',
          };
          continue;
        }

        final defaultStartUtc = _localTimeToUtcString(
          const TimeOfDay(hour: 12, minute: 0),
          _salonTimezone,
        );
        final defaultEndUtc = _localTimeToUtcString(
          const TimeOfDay(hour: 13, minute: 0),
          _salonTimezone,
        );

        lunchBreaks[dayOfWeek] = {
          'start': defaultStartUtc,
          'end': defaultEndUtc,
          'source': 'default',
        };
      }

      return lunchBreaks;
    } catch (e) {
      debugPrint('❌ Error loading lunch breaks: $e');
      final Map<int, Map<String, String>> defaultBreaks = {};
      for (int day = 1; day <= 7; day++) {
        defaultBreaks[day] = {
          'start': _localTimeToUtcString(
            const TimeOfDay(hour: 12, minute: 0),
            _salonTimezone,
          ),
          'end': _localTimeToUtcString(
            const TimeOfDay(hour: 13, minute: 0),
            _salonTimezone,
          ),
          'source': 'default_error',
        };
      }
      return defaultBreaks;
    }
  }

  // ============================================================
  // CREATE BARBER LUNCH BREAKS
  // ============================================================

  Future<void> _createBarberLunchBreaks() async {
    try {
      final salonIdInt = int.parse(_selectedSalonId!);
      final lunchBreaks = await _loadBarberLunchBreaks();

      int createdCount = 0;
      int updatedCount = 0;
      int specialCreatedCount = 0;

      final currentDate = DateTime.now();
      int currentDayOfWeek = currentDate.weekday;

      for (int dayOfWeek = 1; dayOfWeek <= 7; dayOfWeek++) {
        final lunchBreak = lunchBreaks[dayOfWeek];
        if (lunchBreak == null) continue;

        final startTime = lunchBreak['start']!;
        final endTime = lunchBreak['end']!;
        final source = lunchBreak['source']!;

        DateTime targetDate = currentDate.add(
          Duration(days: dayOfWeek - currentDayOfWeek),
        );
        String dateStr = targetDate.toIso8601String().split('T')[0];

        if (source == 'special') {
          final existingSpecial = await supabase
              .from('barber_special_breaks')
              .select('id')
              .eq('barber_id', _selectedBarberId!)
              .eq('salon_id', salonIdInt)
              .eq('break_date', dateStr)
              .eq('break_type', 'lunch')
              .maybeSingle();

          if (existingSpecial == null) {
            await supabase.from('barber_special_breaks').insert({
              'barber_id': _selectedBarberId!,
              'salon_id': salonIdInt,
              'break_date': dateStr,
              'start_time': startTime,
              'end_time': endTime,
              'break_type': 'lunch',
              'reason': 'Auto-created from special break',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
            specialCreatedCount++;
          }
        } else if (source == 'regular') {
          final existingRegular = await supabase
              .from('barber_breaks')
              .select('id')
              .eq('barber_id', _selectedBarberId!)
              .eq('salon_id', salonIdInt)
              .eq('day_of_week', dayOfWeek)
              .eq('break_type', 'lunch')
              .maybeSingle();

          if (existingRegular == null) {
            await supabase.from('barber_breaks').insert({
              'barber_id': _selectedBarberId!,
              'salon_id': salonIdInt,
              'day_of_week': dayOfWeek,
              'start_time': startTime,
              'end_time': endTime,
              'break_type': 'lunch',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
            createdCount++;
          } else {
            await supabase
                .from('barber_breaks')
                .update({
                  'start_time': startTime,
                  'end_time': endTime,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', existingRegular['id']);
            updatedCount++;
          }
        } else {
          final existingRegular = await supabase
              .from('barber_breaks')
              .select('id')
              .eq('barber_id', _selectedBarberId!)
              .eq('salon_id', salonIdInt)
              .eq('day_of_week', dayOfWeek)
              .eq('break_type', 'lunch')
              .maybeSingle();

          if (existingRegular == null) {
            await supabase.from('barber_breaks').insert({
              'barber_id': _selectedBarberId!,
              'salon_id': salonIdInt,
              'day_of_week': dayOfWeek,
              'start_time': startTime,
              'end_time': endTime,
              'break_type': 'lunch',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            });
            createdCount++;
          }
        }
      }

      debugPrint(
        '📊 Lunch Break: Created=$createdCount, Special=$specialCreatedCount, Updated=$updatedCount',
      );
    } catch (e) {
      debugPrint('❌ Error creating lunch breaks: $e');
    }
  }

  // ============================================================
  // IP ADDRESS LOADING
  // ============================================================

  Future<void> _loadIpAddress() async {
    if (_isLoadingIp) return;
    if (mounted) setState(() => _isLoadingIp = true);
    try {
      _currentIp = await IpHelper.getPublicIp();
    } catch (e) {
      debugPrint('❌ Error loading IP: $e');
    } finally {
      if (mounted) setState(() => _isLoadingIp = false);
    }
  }

  // ============================================================
  // LOG OWNER ACTIVITY
  // ============================================================

  Future<void> _logOwnerActivity({
    required String actionType,
    required String targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final ownerId = supabase.auth.currentUser?.id;
      if (ownerId == null) return;
      final ip = _currentIp ?? await IpHelper.getPublicIp();
      await supabase.from('owner_activity_log').insert({
        'owner_id': ownerId,
        'action_type': actionType,
        'target_type': targetType,
        'target_id': targetId,
        'details': details ?? {},
        'ip_address': ip,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Error logging activity: $e');
    }
  }

  // ============================================================
  // LOAD DATA METHODS
  // ============================================================

  Future<void> _refreshData() async {
    if (!mounted) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      await Future.wait([_loadOwnerSalons(), _loadIpAddress()]);
      if (_selectedSalonId != null) {
        await _loadSalonSpecificData();
      }
    } catch (e) {
      debugPrint('❌ Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Data refreshed!', context.successColor);
      }
    }
  }

  Future<void> _loadOwnerSalons() async {
    if (mounted) setState(() => _isLoadingSalons = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _ownerSalons = [];
            _isLoadingSalons = false;
            _isLoading = false;
            _isLoadingServices = false;
          });
        }
        return;
      }

      final response = await supabase
          .from('salons')
          .select(
            'id, name, address, logo_url, is_active, open_time, close_time, timezone',
          )
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('name');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          _isLoadingSalons = false;
        });

        if (_ownerSalons.isNotEmpty) {
          _selectedSalonId = _ownerSalons[0]['id'].toString();
          _selectedSalonDetails = _ownerSalons[0];
          await _loadSalonTimezoneAndHours();
          await _loadSalonSpecificData();
        } else {
          setState(() {
            _isLoading = false;
            _isLoadingServices = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading salons: $e');
      if (mounted) {
        setState(() {
          _ownerSalons = [];
          _isLoadingSalons = false;
          _isLoading = false;
          _isLoadingServices = false;
        });
        _showSnackBar('Error loading salons: ${e.toString()}', Colors.red);
      }
    }
  }

  Future<bool> _isBarberAlreadyInSalon(String barberId, int salonId) async {
    try {
      final response = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('barber_id', barberId)
          .eq('salon_id', salonId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      debugPrint('❌ Error checking barber in salon: $e');
      return false;
    }
  }

  // ============================================================
  // LOAD BARBER'S ALREADY-ASSIGNED SERVICES (for this salon)
  // ============================================================

  Future<void> _loadBarberAssignedServices(String barberId) async {
    if (_selectedSalonId == null) {
      if (mounted) {
        setState(() {
          _barberAssignedVariantIds = {};
          _barberAssignedServiceIds = {};
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoadingBarberServices = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('barber_id', barberId)
          .maybeSingle();

      if (salonBarberResponse == null) {
        if (mounted) {
          setState(() {
            _barberAssignedVariantIds = {};
            _barberAssignedServiceIds = {};
            _isLoadingBarberServices = false;
          });
        }
        return;
      }

      final salonBarberId = salonBarberResponse['id'];

      final existingServices = await supabase
          .from('barber_services')
          .select('service_id, variant_id')
          .eq('salon_barber_id', salonBarberId);

      final Set<int> variantIds = {};
      final Set<String> fullServiceIds = {};

      for (var row in existingServices) {
        if (row['variant_id'] != null) {
          variantIds.add(row['variant_id'] as int);
        } else {
          fullServiceIds.add(row['service_id'].toString());
        }
      }

      if (mounted) {
        setState(() {
          _barberAssignedVariantIds = variantIds;
          _barberAssignedServiceIds = fullServiceIds;
          _isLoadingBarberServices = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading barber assigned services: $e');
      if (mounted) {
        setState(() {
          _barberAssignedVariantIds = {};
          _barberAssignedServiceIds = {};
          _isLoadingBarberServices = false;
        });
      }
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _selectedBarberId = null;
          _selectedItems.clear();
          _barberAssignedVariantIds = {};
          _barberAssignedServiceIds = {};
        });
      }
      return;
    }

    if (_selectedSalonId == null) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        _showSnackBar('Please select a salon first', Colors.orange);
      }
      return;
    }

    if (query.length >= 2) {
      if (mounted) setState(() => _isSearching = true);
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _searchUsers(query);
      });
    } else {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) return;
    if (_selectedSalonId == null) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }

    try {
      if (mounted) setState(() => _isSearching = true);
      final response = await supabase.rpc(
        'get_all_barbers',
        params: {'search_query': query},
      );

      if (response.isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
          _showSnackBar('No barbers found matching "$query"', Colors.orange);
        }
        return;
      }

      final List<Map<String, dynamic>> results = [];
      for (var barber in response) {
        final alreadyInSalon = await _isBarberAlreadyInSalon(
          barber['user_id'],
          int.parse(_selectedSalonId!),
        );
        results.add({
          'id': barber['user_id'],
          'full_name': barber['full_name'] ?? 'Unknown',
          'email': barber['email'] ?? '',
          'avatar_url': barber['avatar_url'],
          'already_in_salon': alreadyInSalon,
        });
      }

      results.sort((a, b) {
        if (a['already_in_salon'] == b['already_in_salon']) return 0;
        return a['already_in_salon'] ? 1 : -1;
      });

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Search error: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        _showSnackBar('Error searching barbers: ${e.toString()}', Colors.red);
      }
    }
  }

  // ============================================================
  // LOAD SALON SPECIFIC DATA
  // ============================================================

  Future<void> _loadSalonSpecificData() async {
    if (_selectedSalonId == null) {
      if (mounted) {
        setState(() {
          _isLoadingSalonData = false;
          _isLoadingServices = false;
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoadingSalonData = true);
    try {
      if (mounted) setState(() => _isLoadingSalonData = false);
      await _loadServicesWithVariants();
      if (mounted) {
        setState(() {
          _searchController.clear();
          _searchResults = [];
          _selectedBarberId = null;
          _isSearching = false;
          _selectedCategoryTab = null;
          _barberAssignedVariantIds = {};
          _barberAssignedServiceIds = {};
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salon data: $e');
      if (mounted) {
        setState(() {
          _isLoadingSalonData = false;
          _isLoadingServices = false;
          _isLoading = false;
        });
        _showSnackBar('Error loading salon data: ${e.toString()}', Colors.red);
      }
    }
  }

  // ============================================================
  // LOAD SERVICES WITH VARIANTS
  // ============================================================

  Future<void> _loadServicesWithVariants() async {
    if (_selectedSalonId == null) {
      if (mounted) {
        setState(() {
          _isLoadingServices = false;
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoadingServices = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            category_id,
            icon_name,
            is_active
          ''')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('name');

      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final Map<int, Map<String, dynamic>> categoryMap = {};
      for (var cat in categoriesResponse) {
        categoryMap[cat['id']] = cat;
      }

      final serviceIds = servicesResponse.map((s) => s['id'] as int).toList();
      List<Map<String, dynamic>> variantsResponse = [];

      if (serviceIds.isNotEmpty) {
        variantsResponse = await supabase
            .from('service_variants')
            .select('''
              id,
              service_id,
              price,
              duration,
              is_active,
              salon_gender_id,
              salon_age_category_id
            ''')
            .inFilter('service_id', serviceIds)
            .eq('is_active', true);
      }

      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final ageCategoriesResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final Map<int, String> genderMap = {};
      for (var g in gendersResponse) {
        genderMap[g['id']] = g['display_name'];
      }

      final Map<int, Map<String, dynamic>> ageMap = {};
      for (var a in ageCategoriesResponse) {
        ageMap[a['id']] = {
          'display_name': a['display_name'],
          'min_age': a['min_age'],
          'max_age': a['max_age'],
        };
      }

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }
        final genderId = variant['salon_gender_id'];
        final ageId = variant['salon_age_category_id'];
        final genderName = genderMap[genderId] ?? 'Unknown';
        final ageData =
            ageMap[ageId] ??
            {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
        final ageName =
            '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';
        variantsByService[serviceId]!.add({
          'id': variant['id'],
          'price': (variant['price'] as num?)?.toDouble() ?? 0.0,
          'duration': variant['duration'] ?? 0,
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_category_name': ageName,
          'display_text': '$genderName • $ageName',
        });
      }

      final List<Map<String, dynamic>> processedServices = [];
      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final categoryId = service['category_id'];
        final category =
            categoryMap[categoryId] ??
            {'display_name': 'Other', 'icon_name': 'build', 'color': '#FF6B8B'};
        final variants = variantsByService[serviceId] ?? [];

        variants.sort((a, b) {
          final genderCompare = a['gender_name'].compareTo(b['gender_name']);
          if (genderCompare != 0) return genderCompare;
          return a['age_category_name'].compareTo(b['age_category_name']);
        });

        double minPrice = 0;
        double maxPrice = 0;
        if (variants.isNotEmpty) {
          final prices = variants
              .map<double>((v) => v['price'] as double)
              .toList();
          minPrice = prices.reduce((a, b) => a < b ? a : b);
          maxPrice = prices.reduce((a, b) => a > b ? a : b);
        }

        processedServices.add({
          'id': serviceId.toString(),
          'name': service['name']?.toString() ?? 'Unknown Service',
          'description': service['description']?.toString() ?? '',
          'category_id': categoryId,
          'category_name': category['display_name'],
          'icon': _getIconFromName(
            service['icon_name']?.toString() ??
                category['icon_name'] ??
                'build',
          ),
          'icon_name':
              service['icon_name']?.toString() ??
              category['icon_name'] ??
              'build',
          'color': category['color'] ?? '#FF6B8B',
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variant_count': variants.length,
          'min_price': minPrice,
          'max_price': maxPrice,
        });
      }

      if (mounted) {
        setState(() {
          _services = processedServices;
          _isLoadingServices = false;
          _isLoading = false;
          _expandedServices.clear();
          for (var service in processedServices) {
            final serviceId = service['id'] as String;
            if (service['hasVariants'] == true) {
              _expandedServices.add(serviceId);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      if (mounted) {
        setState(() {
          _isLoadingServices = false;
          _isLoading = false;
          _services = [];
        });
        _showSnackBar('Error loading services: ${e.toString()}', Colors.red);
      }
    }
  }

  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'content_cut':
        return Icons.content_cut;
      case 'face':
        return Icons.face;
      case 'face_retouching_natural':
        return Icons.face_retouching_natural;
      case 'spa':
        return Icons.spa;
      case 'handshake':
        return Icons.handshake;
      case 'build':
        return Icons.build;
      case 'brush':
        return Icons.brush;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'massage':
        return Icons.message;
      case 'health_and_safety':
        return Icons.health_and_safety;
      case 'cut':
        return Icons.cut;
      case 'shower':
        return Icons.shower;
      case 'masks':
        return Icons.masks;
      case 'palette':
        return Icons.palette;
      case 'spa_outlined':
        return Icons.spa_outlined;
      default:
        return Icons.category;
    }
  }

  // ============================================================
  // SELECTION METHODS
  // ============================================================

  void _toggleSelection(String serviceId, [int? variantId]) {
    // Guard: never allow toggling a service/variant already assigned to
    // the selected barber.
    if (variantId != null && _isVariantAssigned(variantId)) return;
    if (variantId == null && _barberAssignedServiceIds.contains(serviceId)) {
      return;
    }
    setState(() {
      if (variantId == null) {
        if (_selectedItems.containsKey(serviceId)) {
          _selectedItems.remove(serviceId);
        } else {
          _selectedItems[serviceId] = [];
        }
      } else {
        if (!_selectedItems.containsKey(serviceId)) {
          _selectedItems[serviceId] = [];
        }
        if (_selectedItems[serviceId]!.contains(variantId)) {
          _selectedItems[serviceId]!.remove(variantId);
          if (_selectedItems[serviceId]!.isEmpty) {
            _selectedItems.remove(serviceId);
          }
        } else {
          _selectedItems[serviceId]!.add(variantId);
        }
      }
    });
  }

  void _toggleExpand(String serviceId) {
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
      }
    });
  }

  bool _isSelected(String serviceId, [int? variantId]) {
    if (variantId == null) {
      return _selectedItems.containsKey(serviceId) &&
          _selectedItems[serviceId]!.isEmpty;
    } else {
      return _selectedItems[serviceId]?.contains(variantId) ?? false;
    }
  }

  int _getSelectedCount(String serviceId) {
    return _selectedItems[serviceId]?.length ?? 0;
  }

  bool _isVariantAssigned(int variantId) {
    return _barberAssignedVariantIds.contains(variantId);
  }

  bool _isServiceFullyAssigned(Map<String, dynamic> service) {
    final hasVariants = service['hasVariants'] as bool;
    if (hasVariants) {
      final variants = service['variants'] as List;
      if (variants.isEmpty) return false;
      return variants.every((v) => _barberAssignedVariantIds.contains(v['id']));
    } else {
      return _barberAssignedServiceIds.contains(service['id']);
    }
  }

  Map<String, dynamic>? _findVariantById(String serviceId, int variantId) {
    try {
      for (var s in _services) {
        if (s['id'].toString() == serviceId) {
          for (var v in s['variants']) {
            if (v['id'] == variantId) return v;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error finding variant: $e');
      return null;
    }
  }

  String _getBarberName() {
    final barber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
      orElse: () => {},
    );
    return barber['full_name'] ?? barber['email'] ?? 'Barber';
  }

  List<Widget> _buildSelectedServicesList() {
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final List<Widget> widgets = [];
    for (var entry in _selectedItems.entries) {
      final serviceId = entry.key;
      final variantIds = entry.value;
      Map<String, dynamic>? service;
      for (var s in _services) {
        if (s['id'].toString() == serviceId) {
          service = s;
          break;
        }
      }
      if (service == null) continue;

      if (variantIds.isEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: context.successColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service['name'] ?? 'Service',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final variantWidgets = <Widget>[];
        for (var variantId in variantIds) {
          final variant = _findVariantById(serviceId, variantId);
          if (variant != null) {
            variantWidgets.add(
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: context.successColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        variant['display_text']?.toString() ?? 'Variant',
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        if (variantWidgets.isNotEmpty) {
          widgets.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    service['name'] ?? 'Service',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...variantWidgets,
              ],
            ),
          );
        }
      }
    }
    return widgets;
  }

  // ============================================================
  // ADD BARBER
  // ============================================================

  Future<void> _addBarber() async {
    if (_selectedBarberId == null) {
      _showSnackBar('Please select a barber', context.errorColor);
      return;
    }
    if (_selectedSalonId == null) {
      _showSnackBar('Please select a salon', context.errorColor);
      return;
    }
    if (_totalSelectedItems == 0) {
      _showSnackBar('Please select at least one service', context.errorColor);
      return;
    }

    final isActive = await _isBarberActive(_selectedBarberId!);
    if (!isActive) {
      _showSnackBar(
        'This barber account is inactive. Please reactivate before adding.',
        Colors.orange,
      );
      return;
    }

    if (!mounted) return;

    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Fully custom Dialog — full manual control over layout so
        // Flutter's internal AlertDialog / OverflowBar sizing quirks
        // (which can silently force extra height on narrow screens)
        // never cause an overflow again.
        final screenHeight = MediaQuery.of(dialogContext).size.height;
        final maxDialogHeight = screenHeight * 0.85;

        return Dialog(
          backgroundColor: context.backgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxDialogHeight,
              maxWidth: _isWeb ? 450 : 420,
            ),
            // ✅ The ENTIRE dialog (title + content + actions) scrolls as
            // one unit. This is the only 100%-safe approach: even if the
            // available height is smaller than the title+actions' own
            // minimum size, the dialog just scrolls instead of overflowing.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------- TITLE ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Confirm Add Barber',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ---------- CONTENT (plain — outer scrollview handles scrolling) ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person,
                                color: primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Add ${_getBarberName()} to ${_selectedSalonDetails?['name'] ?? 'salon'}?',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoBox(
                          icon: Icons.schedule,
                          color: Colors.green,
                          title: 'Auto Schedule',
                          subtitle:
                              'All days (Mon-Sun) will be set as working days with salon hours',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoBox(
                          icon: Icons.restaurant,
                          color: Colors.orange,
                          title: 'Lunch Break',
                          subtitle:
                              'Loaded from: Special → Regular → Default (12-1 PM)',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoBox(
                          icon: Icons.access_time,
                          color: Colors.blue,
                          title: 'Timezone',
                          subtitle:
                              'Business hours saved in UTC. Salon: ${_salonTimezone.split('/').last}',
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Selected Services:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildSelectedServicesList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  // ---------- ACTIONS (fixed row, always horizontal) ----------
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Confirm Add',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );

    if (confirm != true) return;
    if (mounted) setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);
      final openTimeUtc = _salonOpenTimeUtc;
      final closeTimeUtc = _salonCloseTimeUtc;
      final List<int> weekDays = [1, 2, 3, 4, 5, 6, 7];
      final Map<int, String> dayNames = {
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      };

      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('barber_id', _selectedBarberId!)
          .maybeSingle();

      int salonBarberId;
      if (salonBarberResponse == null) {
        final newSalonBarber = await supabase
            .from('salon_barbers')
            .insert({
              'salon_id': salonIdInt,
              'barber_id': _selectedBarberId!,
              'status': 'active',
            })
            .select('id')
            .single();
        salonBarberId = newSalonBarber['id'];
      } else {
        salonBarberId = salonBarberResponse['id'];
        await supabase
            .from('salon_barbers')
            .update({'status': 'active'})
            .eq('id', salonBarberId);
      }

      int createdCount = 0, updatedCount = 0;
      List<String> errorDays = [];

      for (int dayOfWeek in weekDays) {
        try {
          final existingSchedule = await supabase
              .from('barber_schedules')
              .select('id')
              .eq('barber_id', _selectedBarberId!)
              .eq('salon_id', salonIdInt)
              .eq('day_of_week', dayOfWeek)
              .maybeSingle();

          if (existingSchedule == null) {
            await supabase.from('barber_schedules').insert({
              'barber_id': _selectedBarberId!,
              'salon_id': salonIdInt,
              'day_of_week': dayOfWeek,
              'start_time': openTimeUtc,
              'end_time': closeTimeUtc,
              'is_working': true,
            });
            createdCount++;
          } else {
            await supabase
                .from('barber_schedules')
                .update({
                  'is_working': true,
                  'start_time': openTimeUtc,
                  'end_time': closeTimeUtc,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', existingSchedule['id']);
            updatedCount++;
          }
        } catch (e) {
          errorDays.add(dayNames[dayOfWeek] ?? 'Day $dayOfWeek');
        }
      }

      await _createBarberLunchBreaks();

      final selectedServicesList = [];
      int servicesAddedCount = 0, variantsAddedCount = 0;

      for (var entry in _selectedItems.entries) {
        final serviceId = int.parse(entry.key);
        final variantIds = entry.value;

        Map<String, dynamic>? service;
        for (var s in _services) {
          if (s['id'] == entry.key) {
            service = s;
            break;
          }
        }
        if (service == null) continue;

        if (variantIds.isEmpty) {
          selectedServicesList.add({
            'service_id': serviceId,
            'service_name': service['name'] ?? 'Unknown',
            'type': 'full_service',
          });

          final existing = await supabase
              .from('barber_services')
              .select()
              .eq('salon_barber_id', salonBarberId)
              .eq('service_id', serviceId)
              .filter('variant_id', 'is', null);

          if (existing.isEmpty) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': salonBarberId,
              'service_id': serviceId,
              'variant_id': null,
            });
            servicesAddedCount++;
          }
        } else {
          for (var variantId in variantIds) {
            final variant = _findVariantById(entry.key, variantId);
            selectedServicesList.add({
              'service_id': serviceId,
              'service_name': service['name'] ?? 'Unknown',
              'variant_id': variantId,
              'variant_details': variant != null
                  ? (variant['display_text'] ?? 'Variant')
                  : 'Variant',
              'type': 'variant',
            });

            final existing = await supabase
                .from('barber_services')
                .select()
                .eq('salon_barber_id', salonBarberId)
                .eq('variant_id', variantId);

            if (existing.isEmpty) {
              await supabase.from('barber_services').insert({
                'salon_barber_id': salonBarberId,
                'service_id': serviceId,
                'variant_id': variantId,
              });
              variantsAddedCount++;
            }
          }
        }
      }

      final userRoleCheck = await supabase
          .from('user_roles')
          .select('id, status')
          .eq('user_id', _selectedBarberId!)
          .eq('role_id', 2)
          .maybeSingle();

      if (userRoleCheck == null) {
        final roleResponse = await supabase
            .from('roles')
            .select('id')
            .eq('name', 'barber')
            .maybeSingle();

        if (roleResponse != null) {
          await supabase.from('user_roles').insert({
            'user_id': _selectedBarberId!,
            'role_id': roleResponse['id'],
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      } else if (userRoleCheck['status'] != 'active') {
        await supabase
            .from('user_roles')
            .update({
              'status': 'active',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userRoleCheck['id']);
      }

      await _logOwnerActivity(
        actionType: 'add_barber',
        targetType: 'barber',
        targetId: _selectedBarberId,
        details: {
          'barber_name': _getBarberName(),
          'barber_id': _selectedBarberId,
          'salon_id': salonIdInt,
          'salon_name': _selectedSalonDetails?['name'],
          'salon_timezone': _salonTimezone,
          'selected_services_count': _totalSelectedItems,
          'selected_services': selectedServicesList,
          'device_timezone': _deviceTimezone,
          'schedules_created': createdCount,
          'schedules_updated': updatedCount,
          'services_added': servicesAddedCount,
          'variants_added': variantsAddedCount,
          'role_status': 'active',
        },
      );

      if (mounted) {
        _showSnackBar(
          'Barber added successfully!\n'
          '• $createdCount schedules created\n'
          '• Lunch breaks configured\n'
          '• $servicesAddedCount services, $variantsAddedCount variants added\n'
          '• Salon timezone: ${_salonTimezone.split('/').last}',
          context.successColor,
        );

        setState(() {
          _selectedBarberId = null;
          _selectedItems.clear();
          _expandedServices.clear();
          _searchController.clear();
          _searchResults = [];
          _isSearching = false;
          _selectedCategoryTab = null;
          _barberAssignedVariantIds = {};
          _barberAssignedServiceIds = {};
        });
      }
    } catch (e) {
      debugPrint('❌ Error adding barber: $e');
      if (mounted) _showSnackBar('Error: ${e.toString()}', context.errorColor);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _isBarberActive(String barberId) async {
    try {
      final response = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', barberId)
          .eq('role_id', 2)
          .maybeSingle();

      if (response == null) return true;
      return response['status'] == 'active';
    } catch (e) {
      debugPrint('❌ Error checking barber status: $e');
      return false;
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ============================================================
  // UI BUILDERS
  // ============================================================

  Widget _buildInfoBox({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, bool isSelected, VoidCallback onTap) {
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final cardColor = context.cardColor;
    final isDark = context.isDarkMode;

    return FilterChip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? primaryColor : textColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: primaryColor.withValues(alpha: 0.2),
      checkmarkColor: primaryColor,
      backgroundColor: isDark ? cardColor : Colors.grey[100],
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.transparent,
          width: 1,
        ),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;

    final serviceId = service['id'] as String;
    final hasVariants = service['hasVariants'] as bool;
    final variants = service['variants'] as List;
    final selectedCount = _getSelectedCount(serviceId);
    final isExpanded = _expandedServices.contains(serviceId);
    final isFullyAssigned =
        _selectedBarberId != null && _isServiceFullyAssigned(service);

    // Use theme card color with tint
    final tintColor = isDark
        ? cardColor.withValues(alpha: 0.3)
        : _cardColorTints[index % _cardColorTints.length].withValues(
            alpha: 0.4,
          );

    return Card(
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selectedCount > 0 ? primaryColor : borderColor,
          width: selectedCount > 0 ? 2 : 1,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: tintColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      service['icon'] ?? Icons.build,
                      color: primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] ?? 'Service',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              service['category_name'],
                              style: TextStyle(
                                fontSize: 11,
                                color: secondaryTextColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasVariants)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${variants.length} options',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ),
                            if (isFullyAssigned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Already Assigned',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (selectedCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (hasVariants)
                    IconButton(
                      icon: AnimatedRotation(
                        duration: const Duration(milliseconds: 300),
                        turns: isExpanded ? 0.5 : 0.0,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: secondaryTextColor,
                        ),
                      ),
                      onPressed: () => _toggleExpand(serviceId),
                    ),
                ],
              ),
            ),
            if (service['description'] != null &&
                service['description'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service['description'],
                  style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasVariants) ...[
                    if (isExpanded) ...[
                      Divider(color: borderColor),
                      const SizedBox(height: 8),
                      Text(
                        'Select Options:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...variants.map(
                        (variant) => _buildVariantCard(serviceId, variant),
                      ),
                    ] else if (selectedCount > 0) ...[
                      Divider(color: borderColor),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: context.successColor,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$selectedCount option${selectedCount > 1 ? 's' : ''} selected',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: context.successColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    Divider(color: borderColor),
                    const SizedBox(height: 12),
                    if (_selectedBarberId != null &&
                        _barberAssignedServiceIds.contains(serviceId))
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.lock, size: 18),
                          label: const Text(
                            'Already Assigned',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: isDark
                                ? Colors.grey[700]
                                : Colors.grey[300],
                            disabledForegroundColor: secondaryTextColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleSelection(serviceId),
                          icon: Icon(
                            _isSelected(serviceId)
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            size: 18,
                          ),
                          label: Text(
                            _isSelected(serviceId)
                                ? 'Selected'
                                : 'Select Service',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isSelected(serviceId)
                                ? context.successColor
                                : primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantCard(String serviceId, Map<String, dynamic> variant) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final dividerColor = context.dividerColor;

    final isSelected = _isSelected(serviceId, variant['id']);
    final isAssigned = _isVariantAssigned(variant['id'] as int);

    return GestureDetector(
      onTap: isAssigned
          ? null
          : () => _toggleSelection(serviceId, variant['id']),
      child: Opacity(
        opacity: isAssigned ? 0.55 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAssigned
                ? (isDark ? Colors.grey[850] : Colors.grey[200])
                : isSelected
                ? primaryColor.withValues(alpha: 0.1)
                : cardColor.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isSelected && !isAssigned) ? primaryColor : dividerColor,
              width: (isSelected && !isAssigned) ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isSelected && !isAssigned)
                      ? primaryColor.withValues(alpha: 0.2)
                      : (isDark ? const Color(0xFF2A2A2A) : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  variant['gender_name'].toLowerCase().contains('male')
                      ? Icons.male
                      : variant['gender_name'].toLowerCase().contains(
                          'female',
                        )
                      ? Icons.female
                      : Icons.people,
                  color: (isSelected && !isAssigned)
                      ? primaryColor
                      : secondaryTextColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          variant['display_text'] ??
                              '${variant['gender_name']} • ${variant['age_category_name']}',
                          style: TextStyle(
                            fontWeight: (isSelected && !isAssigned)
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 13,
                            color: (isSelected && !isAssigned)
                                ? primaryColor
                                : textColor,
                          ),
                        ),
                        if (isAssigned)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Already Assigned',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blueGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.currency_rupee,
                              size: 12,
                              color: secondaryTextColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${variant['price']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer,
                              size: 12,
                              color: secondaryTextColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${variant['duration']} min',
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isAssigned)
                Icon(Icons.lock, size: 18, color: secondaryTextColor)
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? primaryColor : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? primaryColor : dividerColor,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServicesSection() {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;

    if (_services.isEmpty && !_isLoadingServices) {
      return Card(
        elevation: _isWeb ? 4 : 2,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.build_circle_outlined,
                size: 64,
                color: isDark ? Colors.white30 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No services available',
                style: TextStyle(
                  fontSize: _isWeb ? 18 : 16,
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please add services to this salon first',
                style: TextStyle(
                  fontSize: _isWeb ? 14 : 12,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_services.isEmpty && _isLoadingServices) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              Text('Loading services...', style: TextStyle(color: textColor)),
            ],
          ),
        ),
      );
    }

    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    final List<String> categories = groupedServices.keys.toList();
    if (_selectedCategoryTab == null && categories.isNotEmpty) {
      _selectedCategoryTab = categories.first;
    }

    List<Map<String, dynamic>> servicesToShow = [];
    if (_selectedCategoryTab == null) {
      for (var services in groupedServices.values) {
        servicesToShow.addAll(services);
      }
    } else {
      servicesToShow = groupedServices[_selectedCategoryTab] ?? [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.build_circle_outlined,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Select Services',
                  style: TextStyle(
                    fontSize: _isWeb ? 22 : 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_totalSelectedServices > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_totalSelectedServices service${_totalSelectedServices > 1 ? 's' : ''} selected',
                    style: TextStyle(
                      fontSize: _isWeb ? 14 : 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 45,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildCategoryChip('All', _selectedCategoryTab == null, () {
                setState(() => _selectedCategoryTab = null);
              }),
              const SizedBox(width: 8),
              ...categories.map(
                (category) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildCategoryChip(
                    category,
                    _selectedCategoryTab == category,
                    () => setState(() => _selectedCategoryTab = category),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isWeb)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: servicesToShow.length,
            itemBuilder: (context, index) =>
                _buildServiceCard(servicesToShow[index], index),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: servicesToShow.length,
            itemBuilder: (context, index) =>
                _buildServiceCard(servicesToShow[index], index),
          ),
      ],
    );
  }

  Widget _buildSalonSection() {
    final isWeb = context.isWeb;
    final isDark = context.isDarkMode; // ✅ Keep this
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final cardColor = context.cardColor;

    return Card(
      elevation: isWeb ? 4 : 2,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isWeb ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.store, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select Salon',
                    style: TextStyle(
                      fontSize: isWeb ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_ownerSalons.isEmpty && !_isLoadingSalons)
              _buildNoSalonWarning()
            else if (_ownerSalons.isEmpty && _isLoadingSalons)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      // ✅ Use isDark for progress indicator
                      CircularProgressIndicator(
                        color: isDark ? primaryColor : primaryColor,
                      ),
                      const SizedBox(height: 12),
                      // ✅ Use isDark for text color
                      Text(
                        'Loading salons...',
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ownerSalons.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final salon = _ownerSalons[index];
                  final isSelected = _selectedSalonId == salon['id'].toString();
                  return _buildSalonTile(salon, isSelected);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSalonWarning() {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final primaryColor = context.primaryColor;
    final cardColor = context.cardColor;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        // ✅ Use isDark for border color
        border: Border.all(
          color: isDark
              ? Colors.orange.withValues(alpha: 0.4)
              : Colors.orange[200]!,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            // ✅ Use isDark for icon color
            color: isDark ? Colors.orange[300] : Colors.orange[700],
          ),
          const SizedBox(height: 12),
          Text(
            'No Salons Found',
            style: TextStyle(
              fontSize: _isWeb ? 18 : 16,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You need to create a salon first before adding barbers.',
            style: TextStyle(
              fontSize: _isWeb ? 14 : 12,
              color: secondaryTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.push('/owner/salon/create'),
            icon: const Icon(Icons.add_business),
            label: const Text('Create Salon'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalonTile(Map<String, dynamic> salon, bool isSelected) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;

    return InkWell(
      onTap: () async {
        if (mounted) {
          setState(() {
            _selectedSalonId = salon['id'].toString();
            _selectedSalonDetails = salon;
            _selectedBarberId = null;
            _selectedItems.clear();
            _searchController.clear();
            _searchResults = [];
            _isSearching = false;
            _selectedCategoryTab = null;
            _barberAssignedVariantIds = {};
            _barberAssignedServiceIds = {};
          });
        }
        await _loadSalonTimezoneAndHours();
        await _loadSalonSpecificData();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.05) : cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isSelected
                  ? primaryColor
                  : (isDark ? Colors.grey[800] : Colors.grey[100]),
              backgroundImage: salon['logo_url'] != null
                  ? NetworkImage(salon['logo_url'])
                  : null,
              child: salon['logo_url'] == null
                  ? Icon(
                      Icons.store,
                      color: isSelected ? Colors.white : secondaryTextColor,
                      size: 20,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon['name'] ?? 'Unnamed Salon',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 15,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (salon['address'] != null)
                    Text(
                      salon['address'],
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: primaryColor, size: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    final isWeb = context.isWeb;
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final dividerColor = context.dividerColor;

    return Card(
      elevation: isWeb ? 4 : 2,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isWeb ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.search, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search Barbers',
                    style: TextStyle(
                      fontSize: isWeb ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              enabled: _selectedSalonId != null,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: _selectedSalonId != null
                    ? 'Type name or email to search...'
                    : 'Select a salon first',
                prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: secondaryTextColor),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _isSearching = false;
                            _selectedBarberId = null;
                            _selectedItems.clear();
                            _barberAssignedVariantIds = {};
                            _barberAssignedServiceIds = {};
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: isWeb ? 16 : 12,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
              ),
            ),
            if (_selectedSalonId == null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Text(
                  '⚠️ Please select a salon first to search barbers',
                  style: TextStyle(
                    fontSize: isWeb ? 13 : 12,
                    color: Colors.orange[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (_searchController.text.isNotEmpty &&
                _searchController.text.length < 2)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Text(
                  '🔍 Type at least 2 characters to search',
                  style: TextStyle(
                    fontSize: isWeb ? 13 : 12,
                    color: secondaryTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (_isSearching) ...[
              const SizedBox(height: 16),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: primaryColor),
                      const SizedBox(height: 12),
                      Text(
                        'Searching for barbers...',
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                separatorBuilder: (_, _) =>
                    Divider(color: dividerColor, height: 1),
                itemBuilder: (context, index) {
                  final barber = _searchResults[index];
                  final isSelected = _selectedBarberId == barber['id'];
                  return _buildBarberTile(barber, isSelected);
                },
              ),
            ] else if (_searchController.text.isNotEmpty &&
                _searchController.text.length >= 2 &&
                !_isSearching) ...[
              const SizedBox(height: 16),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_search,
                        size: 48,
                        color: isDark ? Colors.white30 : Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No barbers found',
                        style: TextStyle(
                          fontSize: isWeb ? 16 : 14,
                          color: secondaryTextColor,
                        ),
                      ),
                      Text(
                        'Try a different name or email',
                        style: TextStyle(
                          fontSize: isWeb ? 12 : 11,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBarberTile(Map<String, dynamic> barber, bool isSelected) {
    final isWeb = context.isWeb;
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    final alreadyInSalon = barber['already_in_salon'] == true;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isSelected
            ? primaryColor
            : (isDark ? Colors.grey[800] : Colors.grey[200]),
        backgroundImage: barber['avatar_url'] != null
            ? NetworkImage(barber['avatar_url'])
            : null,
        child: barber['avatar_url'] == null
            ? Text(
                barber['full_name']?[0]?.toUpperCase() ?? '?',
                style: TextStyle(
                  color: isSelected ? Colors.white : secondaryTextColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              )
            : null,
      ),
      title: Text(
        barber['full_name'] ?? 'Unknown',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: isWeb ? 16 : 14,
          color: textColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            barber['email'] ?? '',
            style: TextStyle(
              fontSize: isWeb ? 14 : 12,
              color: secondaryTextColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // ℹ️ Informational only — no longer disables the barber tile.
          // Selecting an existing barber now lets you add any services
          // they don't already have (those specific ones get disabled
          // further down, in the services list).
          if (alreadyInSalon)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue, width: 0.5),
                ),
                child: const Text(
                  'Already in this salon',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
      trailing: SizedBox(
        width: 28,
        child: isSelected
            ? Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              )
            : Icon(Icons.radio_button_unchecked, color: secondaryTextColor),
      ),
      onTap: () {
        setState(() {
          _selectedBarberId = barber['id'];
          _selectedItems.clear();
          _barberAssignedVariantIds = {};
          _barberAssignedServiceIds = {};
        });
        _loadBarberAssignedServices(barber['id']);
      },
    );
  }

  Widget _buildSelectedBarber() {
    final isWeb = context.isWeb;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    final barber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
      orElse: () => {},
    );

    return Container(
      padding: EdgeInsets.all(isWeb ? 20 : 16),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: isWeb ? 32 : 28,
            backgroundColor: primaryColor,
            backgroundImage: barber['avatar_url'] != null
                ? NetworkImage(barber['avatar_url'])
                : null,
            child: barber['avatar_url'] == null
                ? Text(
                    barber['full_name']?[0]?.toUpperCase() ?? '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isWeb ? 20 : 16,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected Barber',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                Text(
                  barber['full_name'] ?? 'Unknown',
                  style: TextStyle(
                    fontSize: isWeb ? 20 : 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  barber['email'] ?? '',
                  style: TextStyle(
                    fontSize: isWeb ? 14 : 12,
                    color: secondaryTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isLoadingBarberServices)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    final isWeb = context.isWeb;
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWeb ? 0 : 16, vertical: 8),
      // ✅ On web, don't force the button to stretch full width — align it
      // and let minimumSize control its (small, fixed) size instead.
      alignment: isWeb ? Alignment.centerLeft : null,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _addBarber,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: Size(isWeb ? 320 : double.infinity, isWeb ? 54 : 54),
          maximumSize: Size(isWeb ? 420 : double.infinity, isWeb ? 60 : 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          shadowColor: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.3),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isWeb ? 'Add Barber to Selected Salon' : 'Add Barber',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primaryColor = context.primaryColor;
    final backgroundColor = context.backgroundColor;
    final textColor = context.textColor;

    _isWeb = context.isWeb;

    final isLoading =
        _isLoading ||
        _isLoadingServices ||
        _isLoadingSalons ||
        _isLoadingSalonData ||
        !_isTimezoneLoaded;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Add New Barber',
          style: TextStyle(
            fontSize: _isWeb ? 20 : 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: _isWeb,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
          splashRadius: 24,
        ),
        actions: [
          if (_totalSelectedItems > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '$_totalSelectedItems',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          if (_selectedBarberId != null &&
              _selectedSalonId != null &&
              _totalSelectedItems > 0 &&
              !isLoading)
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: _isLoading ? null : _addBarber,
              tooltip: 'Add Barber',
              splashRadius: 24,
            ),
        ],
      ),
      // ✅ EDGE-TO-EDGE: SafeArea added
      body: SafeArea(
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: primaryColor),
                    const SizedBox(height: 16),
                    Text(
                      _isTimezoneLoaded
                          ? 'Loading salons...'
                          : 'Loading timezone...',
                      style: TextStyle(color: textColor),
                    ),
                  ],
                ),
              )
            : _isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildWebLayout() {
    final backgroundColor = context.backgroundColor;
    final dividerColor = context.dividerColor;

    return Container(
      color: backgroundColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 380,
            margin: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildSalonSection(),
                  const SizedBox(height: 16),
                  _buildSearchSection(),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: MediaQuery.of(context).size.height - 80,
            color: dividerColor,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedBarberId != null) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: _buildSelectedBarber(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  _buildServicesSection(),
                  const SizedBox(height: 24),
                  if (_selectedBarberId != null &&
                      _selectedSalonId != null &&
                      _totalSelectedItems > 0)
                    _buildAddButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    final backgroundColor = context.backgroundColor;

    return Container(
      color: backgroundColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSalonSection(),
            const SizedBox(height: 24),
            _buildSearchSection(),
            const SizedBox(height: 24),
            if (_selectedBarberId != null) _buildSelectedBarber(),
            const SizedBox(height: 24),
            _buildServicesSection(),
            const SizedBox(height: 24),
            if (_selectedBarberId != null &&
                _selectedSalonId != null &&
                _totalSelectedItems > 0)
              _buildAddButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}