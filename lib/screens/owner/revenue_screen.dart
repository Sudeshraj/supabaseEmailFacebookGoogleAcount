// lib/screens/owner/revenue_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

class RevenueScreen extends StatefulWidget {
  final String? salonId;
  final String role; // 'owner', 'barber'

  const RevenueScreen({
    super.key,
    this.salonId,
    required this.role,
  });

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  final supabase = Supabase.instance.client;

  // Revenue data
  int _todayRevenue = 0;
  int _weekRevenue = 0;
  int _monthRevenue = 0;
  int _totalRevenue = 0;
  int _todayAppointments = 0;
  int _weekAppointments = 0;
  int _monthAppointments = 0;
  int _totalAppointments = 0;

  // Charts data
  List<Map<String, dynamic>> _dailyRevenue = [];
  List<Map<String, dynamic>> _weeklyRevenue = [];
  List<Map<String, dynamic>> _monthlyRevenue = [];

  bool _isLoading = true;
  String? _errorMessage;
  String _selectedPeriod = 'Today'; // Today, Week, Month

  // Salon name
  String? _salonName;

  // ✅ Responsive variables
  late bool _isWeb;
  late bool _isDark;

  // ✅ Scroll Controller for web
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view revenue';
          _isLoading = false;
        });
        return;
      }

      // Get salon name
      if (widget.salonId != null) {
        final salonResponse = await supabase
            .from('salons')
            .select('name')
            .eq('id', int.parse(widget.salonId!))
            .maybeSingle();

        if (salonResponse != null) {
          _salonName = salonResponse['name'];
        }
      }

      if (widget.role == 'owner') {
        await _loadOwnerRevenue(currentUser.id);
      } else if (widget.role == 'barber') {
        await _loadBarberRevenue(currentUser.id);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading revenue: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD OWNER REVENUE
  // ============================================================
  Future<void> _loadOwnerRevenue(String ownerId) async {
    try {
      final salonId = widget.salonId != null ? int.parse(widget.salonId!) : null;

      if (salonId == null) {
        setState(() {
          _errorMessage = 'No salon selected';
          _isLoading = false;
        });
        return;
      }

      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);

      final monthStart = DateTime(today.year, today.month, 1);
      final monthStartStr = DateFormat('yyyy-MM-dd').format(monthStart);

      final allTimeStart = DateTime(2000, 1, 1);
      final allTimeStartStr = DateFormat('yyyy-MM-dd').format(allTimeStart);

      final results = await Future.wait([
        supabase
            .from('appointments')
            .select('price, status')
            .eq('salon_id', salonId)
            .eq('appointment_date', todayStr)
            .eq('status', 'completed'),

        supabase
            .from('appointments')
            .select('price, status')
            .eq('salon_id', salonId)
            .gte('appointment_date', weekStartStr)
            .eq('status', 'completed'),

        supabase
            .from('appointments')
            .select('price, status')
            .eq('salon_id', salonId)
            .gte('appointment_date', monthStartStr)
            .eq('status', 'completed'),

        supabase
            .from('appointments')
            .select('price, status')
            .eq('salon_id', salonId)
            .gte('appointment_date', allTimeStartStr)
            .eq('status', 'completed'),

        supabase
            .from('appointments')
            .select('appointment_date, price, status')
            .eq('salon_id', salonId)
            .gte('appointment_date', weekStartStr)
            .eq('status', 'completed'),

        supabase
            .from('appointments')
            .select('appointment_date, price, status')
            .eq('salon_id', salonId)
            .eq('status', 'completed'),
      ]);

      final todayData = results[0] as List;
      final weekData = results[1] as List;
      final monthData = results[2] as List;
      final allTimeData = results[3] as List;
      final dailyData = results[4] as List;
      final allData = results[5] as List;

      _todayRevenue = todayData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _todayAppointments = todayData.length;

      _weekRevenue = weekData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _weekAppointments = weekData.length;

      _monthRevenue = monthData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _monthAppointments = monthData.length;

      _totalRevenue = allTimeData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _totalAppointments = allTimeData.length;

      final Map<String, int> dailyMap = {};
      for (var item in dailyData) {
        final date = item['appointment_date'] as String;
        final price = (item['price'] as num?)?.toInt() ?? 0;
        dailyMap[date] = (dailyMap[date] ?? 0) + price;
      }
      _dailyRevenue = dailyMap.entries
          .map((e) => <String, dynamic>{
                'date': e.key,
                'revenue': e.value,
              })
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      final Map<String, int> monthlyMap = {};
      for (var item in allData) {
        final date = item['appointment_date'] as String;
        final month = date.substring(0, 7);
        final price = (item['price'] as num?)?.toInt() ?? 0;
        monthlyMap[month] = (monthlyMap[month] ?? 0) + price;
      }
      _monthlyRevenue = monthlyMap.entries
          .map((e) => <String, dynamic>{
                'month': e.key,
                'revenue': e.value,
              })
          .toList()
        ..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));

      final Map<String, int> weeklyMap = {};
      for (var item in weekData) {
        final date = item['appointment_date'] as String;
        final dateObj = DateTime.parse(date);
        final weekKey = DateFormat('yyyy-ww').format(dateObj);
        final price = (item['price'] as num?)?.toInt() ?? 0;
        weeklyMap[weekKey] = (weeklyMap[weekKey] ?? 0) + price;
      }
      _weeklyRevenue = weeklyMap.entries
          .map((e) => <String, dynamic>{
                'week': e.key,
                'revenue': e.value,
              })
          .toList()
        ..sort((a, b) => (a['week'] as String).compareTo(b['week'] as String));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading revenue: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD BARBER REVENUE
  // ============================================================
  Future<void> _loadBarberRevenue(String barberId) async {
    try {
      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);

      final monthStart = DateTime(today.year, today.month, 1);
      final monthStartStr = DateFormat('yyyy-MM-dd').format(monthStart);

      final allTimeStart = DateTime(2000, 1, 1);
      final allTimeStartStr = DateFormat('yyyy-MM-dd').format(allTimeStart);

      final salonId = widget.salonId != null ? int.parse(widget.salonId!) : null;

      PostgrestFilterBuilder<PostgrestList> buildBaseQuery() {
        var q = supabase
            .from('appointments')
            .select('price, status, appointment_date')
            .eq('barber_id', barberId)
            .eq('status', 'completed');

        if (salonId != null) {
          q = q.eq('salon_id', salonId);
        }
        return q;
      }

      final results = await Future.wait([
        buildBaseQuery().eq('appointment_date', todayStr),
        buildBaseQuery().gte('appointment_date', weekStartStr),
        buildBaseQuery().gte('appointment_date', monthStartStr),
        buildBaseQuery().gte('appointment_date', allTimeStartStr),
        buildBaseQuery().gte('appointment_date', weekStartStr),
        buildBaseQuery(),
      ]);

      final todayData = results[0] as List;
      final weekData = results[1] as List;
      final monthData = results[2] as List;
      final allTimeData = results[3] as List;
      final dailyData = results[4] as List;
      final allData = results[5] as List;

      _todayRevenue = todayData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _todayAppointments = todayData.length;

      _weekRevenue = weekData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _weekAppointments = weekData.length;

      _monthRevenue = monthData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _monthAppointments = monthData.length;

      _totalRevenue = allTimeData.fold(0, (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0));
      _totalAppointments = allTimeData.length;

      final Map<String, int> dailyMap = {};
      for (var item in dailyData) {
        final date = item['appointment_date'] as String;
        final price = (item['price'] as num?)?.toInt() ?? 0;
        dailyMap[date] = (dailyMap[date] ?? 0) + price;
      }
      _dailyRevenue = dailyMap.entries
          .map((e) => <String, dynamic>{
                'date': e.key,
                'revenue': e.value,
              })
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      final Map<String, int> monthlyMap = {};
      for (var item in allData) {
        final date = item['appointment_date'] as String;
        final month = date.substring(0, 7);
        final price = (item['price'] as num?)?.toInt() ?? 0;
        monthlyMap[month] = (monthlyMap[month] ?? 0) + price;
      }
      _monthlyRevenue = monthlyMap.entries
          .map((e) => <String, dynamic>{
                'month': e.key,
                'revenue': e.value,
              })
          .toList()
        ..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading revenue: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // BUILD METHODS
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
              widget.role == 'barber' ? 'My Revenue' : 'Revenue',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_salonName != null)
              Text(
                _salonName!,
                style: TextStyle(
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
                      'Loading revenue data...',
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
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: _isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
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

  // ============================================================
  // ✅ WEB LAYOUT - Dashboard Style
  // ============================================================
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

  // ============================================================
  // ✅ MOBILE LAYOUT
  // ============================================================
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildContent(),
    );
  }

  // ============================================================
  // ✅ CONTENT
  // ============================================================
  Widget _buildContent() {
    return Column(
      children: [
        _buildPeriodSelector(),
        const SizedBox(height: 16),
        _buildRevenueStats(),
        const SizedBox(height: 16),
        _buildRevenueChart(),
        const SizedBox(height: 16),
        _buildAppointmentsStats(),
        const SizedBox(height: 16),
        _buildAdditionalInfo(),
      ],
    );
  }

  // ============================================================
  // BUILD PERIOD SELECTOR
  // ============================================================
  Widget _buildPeriodSelector() {
    final periods = ['Today', 'Week', 'Month'];
    final isDark = _isDark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: periods.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPeriod = period;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? AppTheme.primary
                          : (isDark ? Colors.white60 : Colors.grey[600]),
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
  // BUILD REVENUE STATS
  // ============================================================
  Widget _buildRevenueStats() {
    final isDark = _isDark;
    int revenue = 0;
    int appointments = 0;
    String periodLabel = '';

    switch (_selectedPeriod) {
      case 'Today':
        revenue = _todayRevenue;
        appointments = _todayAppointments;
        periodLabel = 'Today';
        break;
      case 'Week':
        revenue = _weekRevenue;
        appointments = _weekAppointments;
        periodLabel = 'This Week';
        break;
      case 'Month':
        revenue = _monthRevenue;
        appointments = _monthAppointments;
        periodLabel = 'This Month';
        break;
    }

    return Card(
      elevation: 3,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  periodLabel,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.trending_up,
                        size: 14,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '+$appointments',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.green[300] : Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Rs. ',
                  style: TextStyle(
                    fontSize: 24,
                    color: isDark ? Colors.white60 : Colors.grey,
                  ),
                ),
                Text(
                  revenue.toString(),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$appointments appointments completed',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD REVENUE CHART (Simple Bar Chart)
  // ============================================================
  Widget _buildRevenueChart() {
    final isDark = _isDark;
    List<Map<String, dynamic>> data = [];
    String title = '';
    String valueKey = '';
    String labelKey = '';

    switch (_selectedPeriod) {
      case 'Today':
        data = _dailyRevenue;
        title = 'Daily Revenue';
        valueKey = 'revenue';
        labelKey = 'date';
        break;
      case 'Week':
        data = _weeklyRevenue;
        title = 'Weekly Revenue';
        valueKey = 'revenue';
        labelKey = 'week';
        break;
      case 'Month':
        data = _monthlyRevenue;
        title = 'Monthly Revenue';
        valueKey = 'revenue';
        labelKey = 'month';
        break;
    }

    if (data.isEmpty) {
      return Card(
        elevation: 2,
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.show_chart,
                      color: isDark ? Colors.white : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
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
                      color: isDark ? Colors.white30 : Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No revenue data available',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[500],
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

    final maxValue = data.fold(0, (max, item) {
          final val = item[valueKey] as int? ?? 0;
          return val > max ? val : max;
        }) +
        100;

    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.show_chart,
                    color: isDark ? Colors.white : AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${data.length} entries',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((item) {
                  final value = item[valueKey] as int? ?? 0;
                  final label = item[labelKey] as String? ?? '';
                  final height = (value / maxValue) * 160;

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Rs.${(value / 1000).toStringAsFixed(1)}k',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: height,
                          width: 20,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                isDark ? Colors.white : AppTheme.primary,
                                isDark ? Colors.white60 : const Color(0xFFFF8A9F),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatLabel(label),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white60 : Colors.grey[600],
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

  String _formatLabel(String label) {
    try {
      if (label.contains('-')) {
        final parts = label.split('-');
        if (parts.length == 3) {
          return '${parts[2]}/${parts[1]}';
        } else if (parts.length == 2) {
          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          final month = int.parse(parts[1]) - 1;
          return months[month];
        }
      }
      return label;
    } catch (e) {
      return label;
    }
  }

  // ============================================================
  // BUILD APPOINTMENTS STATS
  // ============================================================
  Widget _buildAppointmentsStats() {
    final isDark = _isDark;

    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Appointments Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    label: 'Today',
                    value: '$_todayAppointments',
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: 'This Week',
                    value: '$_weekAppointments',
                    color: Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: 'This Month',
                    value: '$_monthAppointments',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: 'Total',
                    value: '$_totalAppointments',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required Color color,
  }) {
    final isDark = _isDark;

    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? color : color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD ADDITIONAL INFO
  // ============================================================
  Widget _buildAdditionalInfo() {
    final isDark = _isDark;

    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Revenue Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Total Revenue', 'Rs. $_totalRevenue'),
            const Divider(),
            _buildInfoRow('Total Appointments', '$_totalAppointments'),
            const Divider(),
            _buildInfoRow(
              'Average per Appointment',
              _totalAppointments > 0
                  ? 'Rs. ${(_totalRevenue / _totalAppointments).toStringAsFixed(0)}'
                  : 'Rs. 0',
            ),
            const Divider(),
            _buildInfoRow('Best Month', _getBestMonth()),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final isDark = _isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _getBestMonth() {
    if (_monthlyRevenue.isEmpty) return 'No data';

    final best = _monthlyRevenue.reduce((a, b) {
      final aVal = a['revenue'] as int? ?? 0;
      final bVal = b['revenue'] as int? ?? 0;
      return aVal > bVal ? a : b;
    });

    final month = best['month'] as String? ?? '';
    final revenue = best['revenue'] as int? ?? 0;

    if (month.isEmpty) return 'No data';

    try {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final parts = month.split('-');
      if (parts.length == 2) {
        final monthNum = int.parse(parts[1]) - 1;
        return '${months[monthNum]} ${parts[0]} (Rs. $revenue)';
      }
    } catch (e) {
      return '$month (Rs. $revenue)';
    }
    return '$month (Rs. $revenue)';
  }
}