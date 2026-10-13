// lib/screens/owner/reports_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/services/currency_service.dart';
import 'package:flutter_application_1/services/timezone_service.dart';

class ReportsScreen extends StatefulWidget {
  final String? salonId;
  final String role;

  const ReportsScreen({super.key, this.salonId, required this.role});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ✅ Default salon timezone (DB default — NOT user timezone)
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

  // ✅ Currency getter
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

  // Report data
  bool _isLoading = true;
  String? _errorMessage;
  String? _salonName;

  // Date range
  DateTime? _startDate;
  DateTime? _endDate;
  String _dateRange = 'This Month';

  // Report data
  List<Map<String, dynamic>> _reportData = [];
  Map<String, dynamic> _summaryData = {};

  // Charts
  List<Map<String, dynamic>> _chartData = [];

  // Filter
  String _selectedFilter = 'All';

  // Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // Responsive
  late bool _isWeb;
  late bool _isDark;

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
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ CURRENCY HELPERS
  // ============================================================

  String _formatPrice(dynamic price) {
    return _currencyService.format(
      price: price,
      currencyCode: _effectiveCurrencyCode,
    );
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

  // ============================================================
  // ✅ DATE RANGE INITIALIZATION
  // ============================================================
  void _initializeDateRange() {
    final now = _salonNow;
    switch (_dateRange) {
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day);
        break;
      case 'This Week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        _startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        _endDate = DateTime(now.year, now.month, now.day);
        break;
      case 'This Month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day);
        break;
      case 'Custom':
        if (_startDate == null) {
          final thirtyDaysAgo = now.subtract(const Duration(days: 30));
          _startDate = DateTime(
            thirtyDaysAgo.year,
            thirtyDaysAgo.month,
            thirtyDaysAgo.day,
          );
          _endDate = DateTime(now.year, now.month, now.day);
        }
        break;
    }
  }

  // ============================================================
  // ✅ CONVERT FILTER LABEL → DB STATUS VALUE
  // ============================================================
  /// "No Show" → "no_show", "Completed" → "completed", "All" → null
  String? _filterLabelToDbStatus(String label) {
    if (label == 'All') return null;
    return label.toLowerCase().replaceAll(' ', '_');
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
          _errorMessage = 'Please login to view reports';
          _isLoading = false;
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
            _isLoading = false;
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

      // ✅ STEP 3: Initialize date range (with correct salon timezone)
      _initializeDateRange();

      // ✅ STEP 4: Load reports
      if (widget.role == 'owner') {
        await _loadOwnerReports(currentUser.id);
      } else if (widget.role == 'barber') {
        await _loadBarberReports(currentUser.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading reports: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // ✅ HELPER: Extract service names from appointment_services
  // ============================================================
  String _extractServiceName(Map<String, dynamic> appointment) {
    try {
      final apptServices = appointment['appointment_services'] as List?;
      if (apptServices == null || apptServices.isEmpty) {
        return 'Unknown';
      }

      final names = <String>[];
      for (var aps in apptServices) {
        final apMap = aps as Map?;
        if (apMap == null) continue;

        final snapshotName = apMap['service_name'] as String?;
        if (snapshotName != null && snapshotName.isNotEmpty) {
          names.add(snapshotName);
          continue;
        }

        final svc = apMap['services'] as Map?;
        final svcName = svc?['name'] as String?;
        if (svcName != null && svcName.isNotEmpty) {
          names.add(svcName);
        }
      }

      return names.isEmpty ? 'Unknown' : names.join(', ');
    } catch (e) {
      debugPrint('Error extracting service name: $e');
      return 'Unknown';
    }
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

  // ============================================================
  // LOAD OWNER REPORTS
  // ============================================================
  Future<void> _loadOwnerReports(String ownerId) async {
    try {
      final salonId =
          widget.salonId != null ? int.tryParse(widget.salonId!) : null;

      if (salonId == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'No salon selected';
          _isLoading = false;
        });
        return;
      }

      // ✅ Defensive null check
      if (_startDate == null || _endDate == null) {
        _initializeDateRange();
      }

      final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);

      var query = supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            customer_id,
            barber_id,
            appointment_date,
            start_time,
            end_time,
            status,
            price,
            salon_id,
            created_at,
            profiles!appointments_customer_id_fkey (
              full_name,
              email,
              phone
            ),
            appointment_services (
              service_name,
              services (
                name
              )
            )
          ''')
          .eq('salon_id', salonId)
          .gte('appointment_date', startStr)
          .lte('appointment_date', endStr);

      // ✅ FIX: Convert "No Show" → "no_show"
      final dbStatus = _filterLabelToDbStatus(_selectedFilter);
      if (dbStatus != null) {
        query = query.eq('status', dbStatus);
      }

      final response = await query.order('appointment_date', ascending: false);

      final List<Map<String, dynamic>> processedData = [];
      // ✅ FIX: Revenue as double
      double totalRevenue = 0.0;
      int totalAppointments = 0;
      int completedCount = 0;
      int pendingCount = 0;
      int cancelledCount = 0;
      int noShowCount = 0;

      final Map<String, int> dailyData = {};
      final Map<String, int> serviceData = {};
      final Map<String, int> barberData = {};

      for (var item in response) {
        final customer = item['profiles'] as Map?;
        // ✅ FIX: Use double, not int
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final status = item['status'] as String? ?? 'pending';
        final date = item['appointment_date'] as String;

        final serviceName = _extractServiceName(item);
        final serviceNamesList = _extractServiceNamesList(item);

        totalAppointments++;
        totalRevenue += price;

        switch (status) {
          case 'completed':
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

        dailyData[date] = (dailyData[date] ?? 0) + 1;

        for (final name in serviceNamesList) {
          serviceData[name] = (serviceData[name] ?? 0) + 1;
        }

        final barberId = item['barber_id'] as String?;
        if (barberId != null) {
          barberData[barberId] = (barberData[barberId] ?? 0) + 1;
        }

        processedData.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown',
          'customer_email': customer?['email'] ?? '',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': serviceName,
          'barber_id': item['barber_id'],
          'appointment_date': date,
          'start_time': item['start_time'],
          'end_time': item['end_time'],
          'status': status,
          'price': price,
          'created_at': item['created_at'],
        });
      }

      final barberIds = barberData.keys.toList();
      Map<String, String> barberNames = {};
      if (barberIds.isNotEmpty) {
        final barberResponse = await supabase
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', barberIds);

        for (var barber in barberResponse) {
          final id = barber['id'] as String?;
          if (id == null) continue;
          barberNames[id] = barber['full_name'] as String? ?? 'Unknown Barber';
        }
      }

      final List<Map<String, dynamic>> barberStats = [];
      barberData.forEach((id, count) {
        barberStats.add({
          'barber_id': id,
          'barber_name': barberNames[id] ?? 'Unknown',
          'count': count,
        });
      });
      barberStats.sort(
        (a, b) => (b['count'] as int).compareTo(a['count'] as int),
      );

      final chartData = dailyData.entries
          .map((e) => <String, dynamic>{'date': e.key, 'count': e.value})
          .toList()
        ..sort(
          (a, b) => (a['date'] as String).compareTo(b['date'] as String),
        );

      final serviceStats = serviceData.entries
          .map((e) => <String, dynamic>{'service': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      if (!mounted) return;
      setState(() {
        _reportData = processedData;
        _chartData = chartData;
        _summaryData = {
          'total_appointments': totalAppointments,
          'total_revenue': totalRevenue,
          'completed': completedCount,
          'pending': pendingCount,
          'cancelled': cancelledCount,
          'no_show': noShowCount,
          'service_stats': serviceStats,
          'barber_stats': barberStats,
          'date_range': '$_startDate to $_endDate',
        };
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading reports: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD BARBER REPORTS
  // ============================================================
  Future<void> _loadBarberReports(String barberId) async {
    try {
      final salonId =
          widget.salonId != null ? int.tryParse(widget.salonId!) : null;

      // ✅ Defensive null check
      if (_startDate == null || _endDate == null) {
        _initializeDateRange();
      }

      final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);

      var query = supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            customer_id,
            barber_id,
            appointment_date,
            start_time,
            end_time,
            status,
            price,
            salon_id,
            created_at,
            profiles!appointments_customer_id_fkey (
              full_name,
              email,
              phone
            ),
            appointment_services (
              service_name,
              services (
                name
              )
            )
          ''')
          .eq('barber_id', barberId)
          .gte('appointment_date', startStr)
          .lte('appointment_date', endStr);

      if (salonId != null) {
        query = query.eq('salon_id', salonId);
      }

      // ✅ FIX: Convert "No Show" → "no_show"
      final dbStatus = _filterLabelToDbStatus(_selectedFilter);
      if (dbStatus != null) {
        query = query.eq('status', dbStatus);
      }

      final response = await query.order('appointment_date', ascending: false);

      final List<Map<String, dynamic>> processedData = [];
      // ✅ FIX: Revenue as double
      double totalRevenue = 0.0;
      int totalAppointments = 0;
      int completedCount = 0;
      int pendingCount = 0;
      int cancelledCount = 0;
      int noShowCount = 0;

      final Map<String, int> dailyData = {};
      final Map<String, int> serviceData = {};

      for (var item in response) {
        final customer = item['profiles'] as Map?;
        // ✅ FIX: Use double, not int
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final status = item['status'] as String? ?? 'pending';
        final date = item['appointment_date'] as String;

        final serviceName = _extractServiceName(item);
        final serviceNamesList = _extractServiceNamesList(item);

        totalAppointments++;
        totalRevenue += price;

        switch (status) {
          case 'completed':
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

        dailyData[date] = (dailyData[date] ?? 0) + 1;

        for (final name in serviceNamesList) {
          serviceData[name] = (serviceData[name] ?? 0) + 1;
        }

        processedData.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown',
          'customer_email': customer?['email'] ?? '',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': serviceName,
          'appointment_date': date,
          'start_time': item['start_time'],
          'end_time': item['end_time'],
          'status': status,
          'price': price,
          'created_at': item['created_at'],
        });
      }

      final chartData = dailyData.entries
          .map((e) => <String, dynamic>{'date': e.key, 'count': e.value})
          .toList()
        ..sort(
          (a, b) => (a['date'] as String).compareTo(b['date'] as String),
        );

      final serviceStats = serviceData.entries
          .map((e) => <String, dynamic>{'service': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      if (!mounted) return;
      setState(() {
        _reportData = processedData;
        _chartData = chartData;
        _summaryData = {
          'total_appointments': totalAppointments,
          'total_revenue': totalRevenue,
          'completed': completedCount,
          'pending': pendingCount,
          'cancelled': cancelledCount,
          'no_show': noShowCount,
          'service_stats': serviceStats,
          'date_range': '$_startDate to $_endDate',
        };
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading reports: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // DATE RANGE PICKER
  // ============================================================
  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: _salonNow,
      initialDateRange: DateTimeRange(start: _startDate!, end: _endDate!),
    );

    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _dateRange = 'Custom';
      });
      _loadData();
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.role == 'barber' ? 'My Reports' : 'Reports',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_salonName != null)
              Text(
                _salonName!,
                style: const TextStyle(
                  fontSize: 12,
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading reports...',
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
                            color: _isDark ? Colors.white60 : Colors.grey[600],
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
              : SafeArea(
                  child: _isWeb ? _buildWebLayout() : _buildMobileLayout(),
                ),
    );
  }

  // ============================================================
  // WEB LAYOUT
  // ============================================================
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          children: [
            _buildFilters(),
            Expanded(
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
                  padding: const EdgeInsets.all(16),
                  child: _buildContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MOBILE LAYOUT
  // ============================================================
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CONTENT
  // ============================================================
  Widget _buildContent() {
    return Column(
      children: [
        if (_isDifferentTimezone) _buildTimezoneInfoBanner(),
        if (_isDifferentTimezone) const SizedBox(height: 12),
        _buildSummaryCards(),
        const SizedBox(height: 16),
        _buildChart(),
        const SizedBox(height: 16),
        _buildServiceStats(),
        const SizedBox(height: 16),
        if (widget.role == 'owner') _buildBarberStats(),
        const SizedBox(height: 16),
        _buildReportTable(),
        const SizedBox(height: 20),
      ],
    );
  }

  // ============================================================
  // TIMEZONE INFO BANNER
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
                  'All reports shown in salon\'s timezone. Your timezone: ${_getUserTimezoneDisplay()}',
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
  // FILTERS
  // ============================================================
  Widget _buildFilters() {
    final dateRanges = ['Today', 'This Week', 'This Month', 'Custom'];
    final statuses = ['All', 'Completed', 'Pending', 'Cancelled', 'No Show'];

    return Container(
      padding: const EdgeInsets.all(12),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Date:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: dateRanges.map((range) {
                      final isSelected = _dateRange == range;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            range,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.white
                                  : (_isDark
                                      ? Colors.white70
                                      : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _dateRange = range;
                              _initializeDateRange();
                              if (range == 'Custom') {
                                _selectDateRange();
                              } else {
                                _loadData();
                              }
                            });
                          },
                          backgroundColor: _isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100],
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Text(
                'Status:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: statuses.map((status) {
                      final isSelected = _selectedFilter == status;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.white
                                  : (_isDark
                                      ? Colors.white70
                                      : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilter = selected ? status : 'All';
                            });
                            _loadData();
                          },
                          backgroundColor: _isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100],
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),

          if (_dateRange == 'Custom' &&
              _startDate != null &&
              _endDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${DateFormat('MMM dd, yyyy').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w500,
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
  // SUMMARY CARDS
  // ============================================================
  Widget _buildSummaryCards() {
    final total = _summaryData['total_appointments'] ?? 0;
    final revenue = _summaryData['total_revenue'] ?? 0.0;
    final completed = _summaryData['completed'] ?? 0;
    final pending = _summaryData['pending'] ?? 0;
    final cancelled = _summaryData['cancelled'] ?? 0;
    final noShow = _summaryData['no_show'] ?? 0;

    final isMobile = MediaQuery.of(context).size.width < 600;

    final cards = [
      _buildSummaryCard(
        title: 'Total Appointments',
        value: '$total',
        icon: Icons.calendar_today,
        color: Colors.blue,
      ),
      _buildSummaryCard(
        title: 'Revenue',
        value: _formatPrice(revenue),
        icon: Icons.attach_money,
        iconText: _salonCurrencySymbol,
        color: Colors.green,
        hideIconTextOnMobile: isMobile,
      ),
      _buildSummaryCard(
        title: 'Completed',
        value: '$completed',
        icon: Icons.check_circle,
        color: Colors.green,
      ),
      _buildSummaryCard(
        title: 'Pending',
        value: '$pending',
        icon: Icons.pending_actions,
        color: Colors.orange,
      ),
    ];

    if (cancelled > 0) {
      cards.add(
        _buildSummaryCard(
          title: 'Cancelled',
          value: '$cancelled',
          icon: Icons.cancel,
          color: Colors.red,
        ),
      );
    }
    if (noShow > 0) {
      cards.add(
        _buildSummaryCard(
          title: 'No Show',
          value: '$noShow',
          icon: Icons.person_off,
          color: Colors.grey,
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _isWeb ? 4 : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: cards,
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    IconData? icon,
    String? iconText,
    required Color color,
    bool hideIconTextOnMobile = false,
  }) {
    final hasIconText = iconText != null;
    final shouldShowIcon = !(hasIconText && hideIconTextOnMobile);

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (shouldShowIcon)
              hasIconText
                  ? Text(
                      iconText,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    )
                  : Icon(icon, color: color, size: 24),
            if (shouldShowIcon) const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
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
  // CHART
  // ============================================================
  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return Card(
        elevation: 2,
        color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.show_chart, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Appointments Trend',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 150,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.insert_chart_outlined,
                      size: 48,
                      color: _isDark ? Colors.white70 : Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No data available for chart',
                      style: TextStyle(
                        color: _isDark ? Colors.white70 : Colors.grey[500],
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

    final maxValue = _chartData.fold(0, (max, item) {
          final val = item['count'] as int? ?? 0;
          return val > max ? val : max;
        }) +
        1;

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Appointments Trend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_chartData.length} days',
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
                children: _chartData.map((item) {
                  final count = item['count'] as int? ?? 0;
                  final date = item['date'] as String? ?? '';
                  final height = (count / maxValue) * 120;

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 9,
                            color: _isDark ? Colors.white60 : Colors.grey,
                          ),
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

  // ============================================================
  // SERVICE STATS
  // ============================================================
  Widget _buildServiceStats() {
    final serviceStats = _summaryData['service_stats'] as List? ?? [];

    if (serviceStats.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalServiceCount = serviceStats.fold<int>(
      0,
      (sum, item) => sum + ((item['count'] as int?) ?? 0),
    );

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.content_cut, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Service Statistics',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${serviceStats.length} services',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...serviceStats.take(5).map((item) {
              final service = item['service'] as String? ?? 'Unknown';
              final count = item['count'] as int? ?? 0;

              final percentage = totalServiceCount > 0
                  ? (count / totalServiceCount * 100).toStringAsFixed(1)
                  : '0.0';

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
                          widthFactor: totalServiceCount > 0
                              ? count / totalServiceCount
                              : 0,
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
            if (serviceStats.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '+ ${serviceStats.length - 5} more services',
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
  // BARBER STATS (Owner only)
  // ============================================================
  Widget _buildBarberStats() {
    final barberStats = _summaryData['barber_stats'] as List? ?? [];

    if (barberStats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
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
                  '${barberStats.length} barbers',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...barberStats.map((item) {
              final name = item['barber_name'] as String? ?? 'Unknown';
              final count = item['count'] as int? ?? 0;

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
                          Text(
                            '$count appointments',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  _isDark ? Colors.white70 : Colors.grey[500],
                            ),
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
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
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
  // REPORT TABLE
  // ============================================================
  Widget _buildReportTable() {
    if (_reportData.isEmpty) {
      return Card(
        elevation: 2,
        color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 48,
                color: _isDark ? Colors.white70 : Colors.grey[300],
              ),
              const SizedBox(height: 8),
              Text(
                'No appointments found',
                style: TextStyle(
                  color: _isDark ? Colors.white70 : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.table_chart, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Appointment Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_reportData.length} records',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          SizedBox(
            height: 400,
            child: ListView.builder(
              itemCount: _reportData.length,
              itemBuilder: (context, index) {
                final item = _reportData[index];
                final status = item['status'] as String? ?? 'pending';
                Color statusColor;
                switch (status) {
                  case 'completed':
                    statusColor = Colors.green;
                    break;
                  case 'pending':
                  case 'confirmed':
                    statusColor = Colors.orange;
                    break;
                  case 'cancelled':
                    statusColor = Colors.red;
                    break;
                  case 'no_show':
                    statusColor = Colors.grey;
                    break;
                  default:
                    statusColor = Colors.blue;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(
                              item['appointment_date']?.toString() ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: _isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['customer_name']?.toString() ??
                                      'Unknown',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  item['service_name']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: _isDark
                                        ? Colors.white70
                                        : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: Text(
                              _formatPrice(item['price'] ?? 0),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (index < _reportData.length - 1)
                        const Divider(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}