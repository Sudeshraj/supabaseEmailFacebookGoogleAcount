// lib/screens/owner/analytics_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';
import '../../services/currency_service.dart';
import '../../services/timezone_service.dart';

class AnalyticsScreen extends StatefulWidget {
  final String? salonId;
  final String role; // 'owner', 'barber'

  const AnalyticsScreen({super.key, this.salonId, required this.role});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  // ✅ Default salon timezone (DB default — NOT user timezone!)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';

  final supabase = Supabase.instance.client;

  // ==================== ✅ CURRENCY SERVICE ====================
  final CurrencyService _currencyService = CurrencyService.instance;

  // ✅ Empty initial - DB එකෙන් load වෙනකම් fallback getter use කරනවා
  String _salonCurrencyCode = '';

  // ==================== ✅ TIMEZONE ====================
  String _salonTimezone = '';
  String _userTimezone = '';

  // ✅ Effective currency code getter - DB load fail නම් fallback
  String get _effectiveCurrencyCode {
    // Priority 1: DB value (loaded)
    if (_salonCurrencyCode.isNotEmpty) {
      return _salonCurrencyCode;
    }

    // Priority 2: Derive from salon timezone
    if (_salonTimezone.isNotEmpty) {
      return TimezoneService.getCurrencyForTimezone(_salonTimezone);
    }

    // Priority 3: Absolute last resort
    return 'LKR';
  }

  // ✅ Currency getters
  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_effectiveCurrencyCode);

  // ✅ Salon timezone "now" getter - fallback to salon default (NOT device)
  DateTime get _salonNow {
    final tz = _salonTimezone.isNotEmpty
        ? _salonTimezone
        : _kDefaultSalonTimezone;
    try {
      return TimezoneService.getNowInTimezone(tz);
    } catch (e) {
      debugPrint('❌ Error getting salon now: $e');
      return DateTime.now();
    }
  }

  // ✅ Check if user timezone differs from salon timezone
  bool get _isDifferentTimezone {
    return _salonTimezone.isNotEmpty &&
        _userTimezone.isNotEmpty &&
        _salonTimezone != _userTimezone;
  }

  // Analytics data
  bool _isLoading = true;
  String? _errorMessage;
  String? _salonName;

  // Selected period
  String _selectedPeriod = 'This Month';

  // Analytics data
  Map<String, dynamic> _analyticsData = {};
  List<Map<String, dynamic>> _revenueTrend = [];
  List<Map<String, dynamic>> _appointmentTrend = [];
  List<Map<String, dynamic>> _serviceDistribution = [];
  List<Map<String, dynamic>> _barberPerformance = [];
  List<Map<String, dynamic>> _peakHours = [];

  // ✅ Responsive variables
  late bool _isWeb;
  late bool _isTablet;
  late bool _isDark;

  // ✅ Screen width for mobile detection
  double _screenWidth = 0;
  bool get _isMobile => _screenWidth < 600;

  // ✅ Scroll Controller for web
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isWeb = context.isWeb;
    _isTablet = context.isTablet;
    _isDark = context.isDarkMode;
    _screenWidth = MediaQuery.of(context).size.width;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ CURRENCY HELPERS
  // ============================================================

  /// Format price with effective currency
  String _formatPrice(dynamic price) {
    return _currencyService.format(
      price: price,
      currencyCode: _effectiveCurrencyCode,
    );
  }

  /// ✅ FIX: Compact price with 1 decimal for "k"/"M"
  String _formatCompactPrice(dynamic price) {
    final num value = (price as num?) ?? 0;

    if (value >= 1000000) {
      final millions = value / 1000000;
      return '$_salonCurrencySymbol${millions.toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      final thousands = value / 1000;
      return '$_salonCurrencySymbol${thousands.toStringAsFixed(1)}k';
    } else {
      return '$_salonCurrencySymbol${value.toStringAsFixed(0)}';
    }
  }

  // ============================================================
  // ✅ TIMEZONE HELPERS
  // ============================================================

  String _getSalonTimezoneDisplay() {
    final tz = _salonTimezone.isNotEmpty
        ? _salonTimezone
        : _kDefaultSalonTimezone;
    return TimezoneService.getFullTimezoneDisplayFor(tz);
  }

  String _getUserTimezoneDisplay() {
    return TimezoneService.getFullTimezoneDisplayFor(_userTimezone);
  }

  List<String> _extractServiceNamesList(Map<String, dynamic> appointment) {
    final result = <String>[];
    try {
      final apptServices = appointment['appointment_services'] as List?;
      if (apptServices == null || apptServices.isEmpty) return result;

      for (var aps in apptServices) {
        final apMap = aps as Map?;
        if (apMap == null) continue;

        final snapshotName = apMap['service_name'] as String?;
        if (snapshotName != null && snapshotName.isNotEmpty) {
          result.add(snapshotName);
          continue;
        }

        final svc = apMap['services'] as Map?;
        final svcName = svc?['name'] as String?;
        if (svcName != null && svcName.isNotEmpty) {
          result.add(svcName);
        }
      }
    } catch (e) {
      debugPrint('Error extracting service names list: $e');
    }
    return result;
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Please login to view analytics';
        });
        return;
      }

      // ✅ STEP 1: Load salon data
      if (widget.salonId != null) {
        final salonIdInt = int.tryParse(widget.salonId!);
        if (salonIdInt == null) {
          if (!mounted) return;
          setState(() {
            _errorMessage = 'Invalid salon ID';
          });
          return;
        }

        final salonResponse = await supabase
            .from('salons')
            .select('name, currency_code, timezone')
            .eq('id', salonIdInt)
            .maybeSingle();

        if (salonResponse != null) {
          final name = salonResponse['name'] as String?;
          if (name != null && name.isNotEmpty) {
            _salonName = name;
          }

          final currencyCode = salonResponse['currency_code'] as String?;
          if (currencyCode != null && currencyCode.isNotEmpty) {
            _salonCurrencyCode = currencyCode;
          }

          final timezone = salonResponse['timezone'] as String?;
          if (timezone != null && timezone.isNotEmpty) {
            _salonTimezone = timezone;
          }

          debugPrint('✅ Salon name: $_salonName');
          debugPrint('✅ Salon currency: $_salonCurrencyCode');
          debugPrint('✅ Salon timezone: $_salonTimezone');
        }
      }

      // ✅ STEP 2: Load user timezone
      final prefs = await SharedPreferences.getInstance();
      _userTimezone = prefs.getString(TimezoneService.kUserTimezone) ??
          TimezoneService.getCurrentTimezone();

      if (_userTimezone.isEmpty) {
        _userTimezone = _kDefaultSalonTimezone;
      }

      debugPrint('✅ User timezone: $_userTimezone');
      debugPrint('✅ Effective currency: $_effectiveCurrencyCode');

      // ✅ STEP 3: Load analytics
      if (widget.role == 'owner') {
        await _loadOwnerAnalytics(currentUser.id);
      } else if (widget.role == 'barber') {
        await _loadBarberAnalytics(currentUser.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading analytics: ${e.toString()}';
      });
    } finally {
      // ✅ ALWAYS stop loading
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // ✅ HELPER: Get date range based on period (uses SALON timezone)
  // ============================================================
  Map<String, String> _getDateRange() {
    final now = _salonNow;
    String startDate;

    switch (_selectedPeriod) {
      case 'Today':
        startDate = DateFormat('yyyy-MM-dd').format(now);
        break;
      case 'This Week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateFormat('yyyy-MM-dd').format(weekStart);
        break;
      case 'This Month':
        startDate = DateFormat('yyyy-MM-dd')
            .format(DateTime(now.year, now.month, 1));
        break;
      case 'This Year':
        startDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, 1, 1));
        break;
      default:
        startDate = DateFormat('yyyy-MM-dd')
            .format(DateTime(now.year, now.month, 1));
    }

    final endDate = DateFormat('yyyy-MM-dd').format(now);
    return {'start': startDate, 'end': endDate};
  }

  // ============================================================
  // LOAD OWNER ANALYTICS
  // ============================================================
  Future<void> _loadOwnerAnalytics(String ownerId) async {
    try {
      final salonId = widget.salonId != null
          ? int.tryParse(widget.salonId!)
          : null;

      if (salonId == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'No salon selected';
        });
        return;
      }

      final dateRange = _getDateRange();
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      // ✅ Use appointment_services instead of services!inner
      final results = await Future.wait([
        // 0: All appointments
        supabase
            .from('appointments')
            .select('status, price')
            .eq('salon_id', salonId)
            .gte('appointment_date', startDate)
            .lte('appointment_date', endDate),

        // 1: Daily data
        supabase
            .from('appointments')
            .select('appointment_date, status, price')
            .eq('salon_id', salonId)
            .gte('appointment_date', startDate)
            .lte('appointment_date', endDate)
            .order('appointment_date', ascending: true),

        // 2: Service data
        supabase
            .from('appointments')
            .select('''
              id,
              appointment_services (
                service_name,
                services (
                  name
                )
              )
            ''')
            .eq('salon_id', salonId)
            .eq('status', 'completed')
            .gte('appointment_date', startDate)
            .lte('appointment_date', endDate),

        // 3: Barber data
        supabase
            .from('appointments')
            .select('''
              barber_id,
              profiles!appointments_barber_id_fkey (
                full_name
              ),
              status,
              price
            ''')
            .eq('salon_id', salonId)
            .eq('status', 'completed')
            .gte('appointment_date', startDate)
            .lte('appointment_date', endDate),

        // 4: Hour data
        supabase
            .from('appointments')
            .select('start_time')
            .eq('salon_id', salonId)
            .eq('status', 'completed')
            .gte('appointment_date', startDate)
            .lte('appointment_date', endDate),

        // 5: Customer data
        supabase
            .from('appointments')
            .select('customer_id')
            .eq('salon_id', salonId)
            .eq('status', 'completed')
            .gte('appointment_date', startDate)
            .lte('appointment_date', endDate),
      ]);

      final allAppointments = results[0] as List;
      final dailyData = results[1] as List;
      final serviceData = results[2] as List;
      final barberData = results[3] as List;
      final hourData = results[4] as List;
      final customerData = results[5] as List;

      // ✅ FIX: double precision + revenue only from completed
      double totalRevenue = 0.0;
      int completedCount = 0;
      int pendingCount = 0;
      int cancelledCount = 0;
      int noShowCount = 0;

      for (var item in allAppointments) {
        final status = item['status'] as String? ?? 'pending';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;

        switch (status) {
          case 'completed':
            totalRevenue += price; // ✅ Revenue ONLY from completed
            completedCount++;
            break;
          case 'pending':
          case 'confirmed':
            pendingCount++;
            break;
          case 'cancelled':
            cancelledCount++;
            break;
          case 'no_show':
            noShowCount++;
            break;
        }
      }

      // ✅ Daily stats with double revenue
      final Map<String, Map<String, dynamic>> dailyStats = {};
      for (var item in dailyData) {
        final date = item['appointment_date'] as String;
        final status = item['status'] as String? ?? 'pending';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;

        if (!dailyStats.containsKey(date)) {
          dailyStats[date] = {'count': 0, 'revenue': 0.0};
        }
        dailyStats[date]!['count'] = (dailyStats[date]!['count'] as int) + 1;
        // ✅ Only completed revenue in trend
        if (status == 'completed') {
          dailyStats[date]!['revenue'] =
              (dailyStats[date]!['revenue'] as double) + price;
        }
      }

      final trendData = dailyStats.entries
          .map(
            (e) => <String, dynamic>{
              'date': e.key,
              'count': e.value['count'],
              'revenue': e.value['revenue'],
            },
          )
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      // ✅ Service distribution
      final Map<String, int> serviceCounts = {};
      for (var item in serviceData) {
        final serviceNames = _extractServiceNamesList(
          item as Map<String, dynamic>,
        );
        for (final name in serviceNames) {
          serviceCounts[name] = (serviceCounts[name] ?? 0) + 1;
        }
      }

      final serviceDistribution = serviceCounts.entries
          .map((e) => <String, dynamic>{'service': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      // ✅ Barber performance with double revenue
      final Map<String, Map<String, dynamic>> barberStats = {};
      for (var item in barberData) {
        final barberId = item['barber_id'] as String?;
        if (barberId == null) continue;

        final profile = item['profiles'] as Map?;
        final name = profile?['full_name']?.toString() ?? 'Unknown';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;

        if (!barberStats.containsKey(barberId)) {
          barberStats[barberId] = {'name': name, 'count': 0, 'revenue': 0.0};
        }
        barberStats[barberId]!['count'] =
            (barberStats[barberId]!['count'] as int) + 1;
        barberStats[barberId]!['revenue'] =
            (barberStats[barberId]!['revenue'] as double) + price;
      }

      final barberPerformance = barberStats.entries
          .map(
            (e) => <String, dynamic>{
              'barber_id': e.key,
              'barber_name': e.value['name'],
              'count': e.value['count'],
              'revenue': e.value['revenue'],
            },
          )
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      // ✅ Peak hours
      final Map<int, int> hourCounts = {};
      for (var item in hourData) {
        final time = item['start_time'] as String;
        try {
          final hour = int.parse(time.split(':')[0]);
          hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
        } catch (e) {
          continue;
        }
      }

      final peakHours = hourCounts.entries
          .map((e) => <String, dynamic>{'hour': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (a['hour'] as int).compareTo(b['hour'] as int));

      // ✅ Customer retention
      final Map<String, int> customerCounts = {};
      for (var item in customerData) {
        final customerId = item['customer_id'] as String?;
        if (customerId == null) continue;
        customerCounts[customerId] = (customerCounts[customerId] ?? 0) + 1;
      }

      final retentionData = customerCounts.values;
      int repeatCustomers = retentionData.where((count) => count > 1).length;
      int totalCustomers = retentionData.length;
      double retentionRate = totalCustomers > 0
          ? (repeatCustomers / totalCustomers) * 100
          : 0;

      if (!mounted) return;
      setState(() {
        _analyticsData = {
          'total_revenue': totalRevenue,
          'completed_count': completedCount,
          'pending_count': pendingCount,
          'cancelled_count': cancelledCount,
          'no_show_count': noShowCount,
          'total_customers': totalCustomers,
          'repeat_customers': repeatCustomers,
          'retention_rate': retentionRate,
          'avg_revenue_per_appointment': completedCount > 0
              ? totalRevenue / completedCount
              : 0.0,
        };
        _revenueTrend = trendData;
        _appointmentTrend = trendData;
        _serviceDistribution = serviceDistribution;
        _barberPerformance = barberPerformance;
        _peakHours = peakHours;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading analytics: ${e.toString()}';
      });
    }
  }

  // ============================================================
  // LOAD BARBER ANALYTICS
  // ============================================================
  Future<void> _loadBarberAnalytics(String barberId) async {
    try {
      final salonId = widget.salonId != null
          ? int.tryParse(widget.salonId!)
          : null;

      final dateRange = _getDateRange();
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      var query = supabase
          .from('appointments')
          .select('''
            status,
            price,
            appointment_date,
            start_time,
            customer_id,
            appointment_services (
              service_name,
              services (
                name
              )
            )
          ''')
          .eq('barber_id', barberId)
          .gte('appointment_date', startDate)
          .lte('appointment_date', endDate);

      if (salonId != null) {
        query = query.eq('salon_id', salonId);
      }

      final response = await query.order('appointment_date', ascending: true);

      // ✅ double precision + revenue only from completed
      double totalRevenue = 0.0;
      int completedCount = 0;
      int pendingCount = 0;
      int cancelledCount = 0;
      int noShowCount = 0;

      final Map<String, Map<String, dynamic>> dailyStats = {};
      final Map<String, int> serviceCounts = {};
      final Map<int, int> hourCounts = {};
      final Map<String, int> customerCounts = {};

      for (var item in response) {
        final status = item['status'] as String? ?? 'pending';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final date = item['appointment_date'] as String;
        final time = item['start_time'] as String;
        final customerId = item['customer_id'] as String?;

        // ✅ Only completed revenue
        if (status == 'completed') {
          totalRevenue += price;
          completedCount++;
        } else if (status == 'pending' || status == 'confirmed') {
          pendingCount++;
        } else if (status == 'cancelled') {
          cancelledCount++;
        } else if (status == 'no_show') {
          noShowCount++;
        }

        if (!dailyStats.containsKey(date)) {
          dailyStats[date] = {'count': 0, 'revenue': 0.0};
        }
        dailyStats[date]!['count'] = (dailyStats[date]!['count'] as int) + 1;
        if (status == 'completed') {
          dailyStats[date]!['revenue'] =
              (dailyStats[date]!['revenue'] as double) + price;
        }

        final serviceNames = _extractServiceNamesList(item);
        for (final name in serviceNames) {
          serviceCounts[name] = (serviceCounts[name] ?? 0) + 1;
        }

        try {
          final hour = int.parse(time.split(':')[0]);
          hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
        } catch (e) {
          // Ignore malformed time strings
        }

        if (customerId != null) {
          customerCounts[customerId] = (customerCounts[customerId] ?? 0) + 1;
        }
      }

      final trendData = dailyStats.entries
          .map(
            (e) => <String, dynamic>{
              'date': e.key,
              'count': e.value['count'],
              'revenue': e.value['revenue'],
            },
          )
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      final serviceDistribution = serviceCounts.entries
          .map((e) => <String, dynamic>{'service': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      final peakHours = hourCounts.entries
          .map((e) => <String, dynamic>{'hour': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (a['hour'] as int).compareTo(b['hour'] as int));

      final retentionData = customerCounts.values;
      int repeatCustomers = retentionData.where((count) => count > 1).length;
      int totalCustomers = retentionData.length;
      double retentionRate = totalCustomers > 0
          ? (repeatCustomers / totalCustomers) * 100
          : 0;

      if (!mounted) return;
      setState(() {
        _analyticsData = {
          'total_revenue': totalRevenue,
          'completed_count': completedCount,
          'pending_count': pendingCount,
          'cancelled_count': cancelledCount,
          'no_show_count': noShowCount,
          'total_customers': totalCustomers,
          'repeat_customers': repeatCustomers,
          'retention_rate': retentionRate,
          'avg_revenue_per_appointment': completedCount > 0
              ? totalRevenue / completedCount
              : 0.0,
        };
        _revenueTrend = trendData;
        _appointmentTrend = trendData;
        _serviceDistribution = serviceDistribution;
        _peakHours = peakHours;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading analytics: ${e.toString()}';
      });
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    _isWeb = context.isWeb;
    _isTablet = context.isTablet;
    _isDark = context.isDarkMode;
    _screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.role == 'barber' ? 'My Analytics' : 'Analytics',
              style: TextStyle(
                fontSize: _isWeb ? 20 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_salonName != null)
              Text(
                _salonName!,
                style: TextStyle(
                  fontSize: _isWeb ? 13 : 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          if (!_isLoading && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _effectiveCurrencyCode,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading analytics...',
                      style: TextStyle(
                        color: _isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: _isDark ? Colors.white30 : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color:
                                  _isDark ? Colors.white60 : Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
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

  // ✅ WEB LAYOUT
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.right,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildContent(),
    );
  }

  // ✅ CONTENT
  Widget _buildContent() {
    return Column(
      children: [
        if (_isDifferentTimezone) _buildTimezoneInfoBanner(),
        if (_isDifferentTimezone) const SizedBox(height: 12),
        _buildPeriodSelector(),
        const SizedBox(height: 16),
        _buildKPICards(),
        const SizedBox(height: 16),
        _buildRevenueTrend(),
        const SizedBox(height: 16),
        _buildAppointmentTrend(),
        const SizedBox(height: 16),
        _buildServiceDistribution(),
        const SizedBox(height: 16),
        _buildPeakHours(),
        const SizedBox(height: 16),
        _buildCustomerRetention(),
        const SizedBox(height: 16),
        if (widget.role == 'owner') _buildBarberPerformance(),
      ],
    );
  }

  // ============================================================
  // ✅ TIMEZONE INFO BANNER
  // ============================================================
  Widget _buildTimezoneInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: _isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withValues(alpha: _isDark ? 0.3 : 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: _isDark ? Colors.blue[300] : Colors.blue[700],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Salon timezone: ${_getSalonTimezoneDisplay()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isDark ? Colors.blue[300] : Colors.blue[700],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'All analytics shown in salon\'s timezone. Your timezone: ${_getUserTimezoneDisplay()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PERIOD SELECTOR
  // ============================================================
  Widget _buildPeriodSelector() {
    final periods = ['Today', 'This Week', 'This Month', 'This Year'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: periods.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPeriod = period;
                });
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (_isDark ? const Color(0xFF2A2A2A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _isDark ? 0.3 : 0.15,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    period,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: _isMobile ? 11 : 13,
                      color: isSelected
                          ? AppTheme.primary
                          : (_isDark ? Colors.white60 : Colors.grey[600]),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // KPI CARDS
  // ============================================================
  Widget _buildKPICards() {
    final data = _analyticsData;
    final revenue = data['total_revenue'] ?? 0.0;
    final completed = data['completed_count'] ?? 0;
    final pending = data['pending_count'] ?? 0;
    final cancelled = data['cancelled_count'] ?? 0;
    final noShow = data['no_show_count'] ?? 0;
    final avgRevenue = data['avg_revenue_per_appointment'] ?? 0.0;

    final children = <Widget>[
      _buildKPICard(
        title: 'Revenue',
        value: _formatPrice(revenue),
        icon: Icons.attach_money,
        iconText: _salonCurrencySymbol,
        color: Colors.green,
      ),
      _buildKPICard(
        title: 'Completed',
        value: '$completed',
        icon: Icons.check_circle,
        color: Colors.green,
      ),
      _buildKPICard(
        title: 'Pending',
        value: '$pending',
        icon: Icons.pending_actions,
        color: Colors.orange,
      ),
      _buildKPICard(
        title: 'Cancelled',
        value: '$cancelled',
        icon: Icons.cancel,
        color: Colors.red,
      ),
    ];

    if (noShow > 0) {
      children.add(
        _buildKPICard(
          title: 'No Show',
          value: '$noShow',
          icon: Icons.person_off,
          color: Colors.grey,
        ),
      );
    }

    children.add(
      _buildKPICard(
        title: 'Avg Revenue',
        value: _formatPrice(avgRevenue),
        icon: Icons.trending_up,
        iconText: _salonCurrencySymbol,
        color: Colors.purple,
      ),
    );

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _isTablet ? 4 : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: _isTablet ? 1.6 : 1.4,
      children: children,
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    IconData? icon,
    String? iconText,
    required Color color,
  }) {
    final shouldHideIconText = _isMobile && iconText != null;

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!shouldHideIconText)
              Container(
                padding: EdgeInsets.all(_isTablet ? 10 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(_isTablet ? 14.0 : 12.0),
                ),
                child: iconText != null
                    ? Center(
                        widthFactor: 1.0,
                        child: Text(
                          iconText,
                          style: TextStyle(
                            fontSize: (_isTablet ? 22 : 18) * 0.75,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      )
                    : Icon(icon!, color: color, size: _isTablet ? 32 : 28),
              )
            else
              Icon(
                icon ?? Icons.attach_money,
                color: color,
                size: _isTablet ? 32 : 28,
              ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: _isTablet ? 16 : 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: _isTablet ? 11 : 10,
                color: _isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // REVENUE TREND
  // ============================================================
  Widget _buildRevenueTrend() {
    if (_revenueTrend.isEmpty) {
      return _buildEmptyChart('No revenue data available');
    }

    // ✅ maxRevenue as double
    double maxRevenue = _revenueTrend.fold<double>(0.0, (max, item) {
      final val = (item['revenue'] as num?)?.toDouble() ?? 0.0;
      return val > max ? val : max;
    });
    if (maxRevenue == 0) maxRevenue = 1.0;
    final chartMax = maxRevenue * 1.1;

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Revenue Trend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_revenueTrend.length} days',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _revenueTrend.map((item) {
                  final revenue =
                      (item['revenue'] as num?)?.toDouble() ?? 0.0;
                  final date = item['date'] as String? ?? '';
                  final height = (revenue / chartMax) * 120;

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatCompactPrice(revenue),
                          style: TextStyle(
                            fontSize: 8,
                            color: _isDark ? Colors.white70 : Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: height > 0 ? height : 2,
                          width: 16,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppTheme.primary,
                                AppTheme.primaryLight,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateLabel(date),
                          style: TextStyle(
                            fontSize: 8,
                            color: _isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // APPOINTMENT TREND
  // ============================================================
  Widget _buildAppointmentTrend() {
    if (_appointmentTrend.isEmpty) {
      return _buildEmptyChart('No appointment data available');
    }

    final maxCount = _appointmentTrend.fold<int>(0, (max, item) {
          final val = item['count'] as int? ?? 0;
          return val > max ? val : max;
        }) +
        1;

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Appointment Trend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_appointmentTrend.length} days',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _appointmentTrend.map((item) {
                  final count = item['count'] as int? ?? 0;
                  final date = item['date'] as String? ?? '';
                  final height = (count / maxCount) * 120;

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 9,
                            color: _isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: height > 0 ? height : 2,
                          width: 16,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.blue, Colors.lightBlue],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateLabel(date),
                          style: TextStyle(
                            fontSize: 8,
                            color: _isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SERVICE DISTRIBUTION
  // ============================================================
  Widget _buildServiceDistribution() {
    if (_serviceDistribution.isEmpty) {
      return const SizedBox.shrink();
    }

    final total = _serviceDistribution.fold<int>(
      0,
      (sum, item) => sum + (item['count'] as int? ?? 0),
    );

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Service Distribution',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_serviceDistribution.length} services',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._serviceDistribution.take(5).map((item) {
              final service = item['service'] as String? ?? 'Unknown';
              final count = item['count'] as int? ?? 0;
              final percentage = total > 0
                  ? (count / total * 100).toStringAsFixed(1)
                  : '0';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        service,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isDark ? Colors.grey[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: total > 0 ? count / total : 0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.primary,
                                  AppTheme.primaryLight,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count ($percentage%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_serviceDistribution.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '+ ${_serviceDistribution.length - 5} more services',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isDark ? Colors.white70 : Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PEAK HOURS
  // ============================================================
  Widget _buildPeakHours() {
    if (_peakHours.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = _peakHours.fold<int>(0, (max, item) {
          final val = item['count'] as int? ?? 0;
          return val > max ? val : max;
        }) +
        1;

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Peak Hours',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_peakHours.length} hours',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _peakHours.map((item) {
                  final count = item['count'] as int? ?? 0;
                  final hour = item['hour'] as int? ?? 0;
                  final height = (count / maxCount) * 120;

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 9,
                            color: _isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: height > 0 ? height : 2,
                          width: 16,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.deepOrange, Colors.orange],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatHour(hour),
                          style: TextStyle(
                            fontSize: 8,
                            color: _isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CUSTOMER RETENTION
  // ============================================================
  Widget _buildCustomerRetention() {
    final totalCustomers = _analyticsData['total_customers'] ?? 0;
    final repeatCustomers = _analyticsData['repeat_customers'] ?? 0;
    final retentionRate =
        (_analyticsData['retention_rate'] as num?)?.toDouble() ?? 0.0;

    if (totalCustomers == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Customer Retention',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildRetentionStat(
                    label: 'Total Customers',
                    value: '$totalCustomers',
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildRetentionStat(
                    label: 'Repeat Customers',
                    value: '$repeatCustomers',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildRetentionStat(
                    label: 'Retention Rate',
                    value: '${retentionRate.toStringAsFixed(1)}%',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: _isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                widthFactor: (retentionRate / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.green,
                        retentionRate > 70 ? Colors.green : Colors.orange,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              retentionRate > 70
                  ? 'Excellent retention rate! 🎉'
                  : retentionRate > 50
                      ? 'Good retention rate 👍'
                      : 'Work on improving retention 💪',
              style: TextStyle(
                fontSize: 12,
                color: retentionRate > 70
                    ? Colors.green
                    : retentionRate > 50
                        ? Colors.orange
                        : (_isDark ? Colors.white70 : Colors.grey),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRetentionStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: _isTablet ? 20 : 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: _isTablet ? 11 : 10,
            color: _isDark ? Colors.white60 : Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ============================================================
  // BARBER PERFORMANCE (Owner only)
  // ============================================================
  Widget _buildBarberPerformance() {
    if (_barberPerformance.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Barber Performance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_barberPerformance.length} barbers',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._barberPerformance.map((item) {
              final name = item['barber_name'] as String? ?? 'Unknown';
              final count = item['count'] as int? ?? 0;
              final revenue = (item['revenue'] as num?)?.toDouble() ?? 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '$count appointments',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isDark
                                      ? Colors.white60
                                      : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _formatPrice(revenue),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 12,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  Widget _buildEmptyChart(String message) {
    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: _isDark
            ? BorderSide(color: Colors.grey[800]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.insert_chart_outlined,
              size: 48,
              color: _isDark ? Colors.white30 : Colors.grey[300],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateLabel(String date) {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}';
      }
      return date;
    } catch (e) {
      return date;
    }
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}