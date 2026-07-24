// lib/screens/owner/reports_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends StatefulWidget {
  final String? salonId;
  final String role; // 'owner', 'barber'

  const ReportsScreen({
    super.key,
    this.salonId,
    required this.role,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final supabase = Supabase.instance.client;

  // Report data
  bool _isLoading = true;
  String? _errorMessage;
  String? _salonName;
 
  // Date range
  DateTime? _startDate;
  DateTime? _endDate;
  String _dateRange = 'This Month'; // Today, This Week, This Month, Custom

  // Report data
  List<Map<String, dynamic>> _reportData = [];
  Map<String, dynamic> _summaryData = {};

  // Charts
  List<Map<String, dynamic>> _chartData = [];

  // Filter
  String _selectedFilter = 'All'; // All, Completed, Pending, Cancelled

  @override
  void initState() {
    super.initState();
    _initializeDateRange();
    _loadData();
  }

  void _initializeDateRange() {
    final now = DateTime.now();
    switch (_dateRange) {
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day);
        break;
      case 'This Week':
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _endDate = now;
        break;
      case 'This Month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
        break;
      case 'Custom':
        // Keep existing or set default
        if (_startDate == null) {
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
        }
        break;
    }
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
          _errorMessage = 'Please login to view reports';
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
        await _loadOwnerReports(currentUser.id);
      } else if (widget.role == 'barber') {
        await _loadBarberReports(currentUser.id);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading reports: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD OWNER REPORTS
  // ============================================================
  Future<void> _loadOwnerReports(String ownerId) async {
    try {
      final salonId = widget.salonId != null ? int.parse(widget.salonId!) : null;

      if (salonId == null) {
        setState(() {
          _errorMessage = 'No salon selected';
          _isLoading = false;
        });
        return;
      }

      final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);

      // Base query
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
            service_id,
            salon_id,
            created_at,
            profiles!appointments_customer_id_fkey (
              full_name,
              email,
              phone
            ),
            services!inner (
              name
            )
          ''')
          .eq('salon_id', salonId)
          .gte('appointment_date', startStr)
          .lte('appointment_date', endStr);

      // Apply status filter
      if (_selectedFilter != 'All') {
        query = query.eq('status', _selectedFilter.toLowerCase());
      }

      final response = await query.order('appointment_date', ascending: false);

      // Process data
      final List<Map<String, dynamic>> processedData = [];
      int totalRevenue = 0;
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
        final service = item['services'] as Map?;
        final price = (item['price'] as num?)?.toInt() ?? 0;
        final status = item['status'] as String? ?? 'pending';
        final date = item['appointment_date'] as String;

        totalAppointments++;
        totalRevenue += price;

        // Status counts
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

        // Daily data
        dailyData[date] = (dailyData[date] ?? 0) + 1;

        // Service data
        final serviceName = service?['name']?.toString() ?? 'Unknown';
        serviceData[serviceName] = (serviceData[serviceName] ?? 0) + 1;

        // Barber data
        final barberId = item['barber_id'] as String;
        barberData[barberId] = (barberData[barberId] ?? 0) + 1;

        processedData.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown',
          'customer_email': customer?['email'] ?? '',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': service?['name'] ?? 'Unknown',
          'barber_id': item['barber_id'],
          'appointment_date': date,
          'start_time': item['start_time'],
          'end_time': item['end_time'],
          'status': status,
          'price': price,
          'created_at': item['created_at'],
        });
      }

      // Get barber names
      final barberIds = barberData.keys.toList();
      Map<String, String> barberNames = {};
      if (barberIds.isNotEmpty) {
        final barberResponse = await supabase
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', barberIds);

        for (var barber in barberResponse) {
          barberNames[barber['id']] = barber['full_name'] ?? 'Unknown Barber';
        }
      }

      // Update barber data with names
      final List<Map<String, dynamic>> barberStats = [];
      barberData.forEach((id, count) {
        barberStats.add({
          'barber_id': id,
          'barber_name': barberNames[id] ?? 'Unknown',
          'count': count,
        });
      });
      barberStats.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      // Prepare chart data
      final chartData = dailyData.entries
          .map((e) => <String, dynamic>{
                'date': e.key,
                'count': e.value,
              })
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      // Service stats
      final serviceStats = serviceData.entries
          .map((e) => <String, dynamic>{
                'service': e.key,
                'count': e.value,
              })
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

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
      final salonId = widget.salonId != null ? int.parse(widget.salonId!) : null;

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
            service_id,
            salon_id,
            created_at,
            profiles!appointments_customer_id_fkey (
              full_name,
              email,
              phone
            ),
            services!inner (
              name
            )
          ''')
          .eq('barber_id', barberId)
          .gte('appointment_date', startStr)
          .lte('appointment_date', endStr);

      if (salonId != null) {
        query = query.eq('salon_id', salonId);
      }

      if (_selectedFilter != 'All') {
        query = query.eq('status', _selectedFilter.toLowerCase());
      }

      final response = await query.order('appointment_date', ascending: false);

      // Process data
      final List<Map<String, dynamic>> processedData = [];
      int totalRevenue = 0;
      int totalAppointments = 0;
      int completedCount = 0;
      int pendingCount = 0;
      int cancelledCount = 0;
      int noShowCount = 0;

      final Map<String, int> dailyData = {};
      final Map<String, int> serviceData = {};

      for (var item in response) {
        final customer = item['profiles'] as Map?;
        final service = item['services'] as Map?;
        final price = (item['price'] as num?)?.toInt() ?? 0;
        final status = item['status'] as String? ?? 'pending';
        final date = item['appointment_date'] as String;

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

        final serviceName = service?['name']?.toString() ?? 'Unknown';
        serviceData[serviceName] = (serviceData[serviceName] ?? 0) + 1;

        processedData.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown',
          'customer_email': customer?['email'] ?? '',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': service?['name'] ?? 'Unknown',
          'appointment_date': date,
          'start_time': item['start_time'],
          'end_time': item['end_time'],
          'status': status,
          'price': price,
          'created_at': item['created_at'],
        });
      }

      final chartData = dailyData.entries
          .map((e) => <String, dynamic>{
                'date': e.key,
                'count': e.value,
              })
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      final serviceStats = serviceData.entries
          .map((e) => <String, dynamic>{
                'service': e.key,
                'count': e.value,
              })
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

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
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _startDate!,
        end: _endDate!,
      ),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _dateRange = 'Custom';
      });
      _loadData();
    }
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.role == 'barber' ? 'My Reports' : 'Reports',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading reports...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Filters
                    _buildFilters(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Summary Cards
                            _buildSummaryCards(),
                            const SizedBox(height: 16),

                            // Chart
                            _buildChart(),
                            const SizedBox(height: 16),

                            // Service Stats
                            _buildServiceStats(),
                            const SizedBox(height: 16),

                            // Barber Stats (Owner only)
                            if (widget.role == 'owner') _buildBarberStats(),
                            const SizedBox(height: 16),

                            // Report Table
                            _buildReportTable(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  // ============================================================
  // BUILD FILTERS
  // ============================================================
  Widget _buildFilters() {
    final dateRanges = ['Today', 'This Week', 'This Month', 'Custom'];
    final statuses = ['All', 'Completed', 'Pending', 'Cancelled', 'No Show'];

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          // Date range selector
          Row(
            children: [
              const Text(
                'Date:',
                style: TextStyle(fontWeight: FontWeight.w500),
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
                              color: isSelected ? Colors.white : Colors.grey[700],
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
                          backgroundColor: Colors.grey[100],
                          selectedColor: const Color(0xFFFF6B8B),
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

          // Status filter
          Row(
            children: [
              const Text(
                'Status:',
                style: TextStyle(fontWeight: FontWeight.w500),
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
                              color: isSelected ? Colors.white : Colors.grey[700],
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilter = selected ? status : 'All';
                            });
                            _loadData();
                          },
                          backgroundColor: Colors.grey[100],
                          selectedColor: const Color(0xFFFF6B8B),
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

          // Date range display for custom
          if (_dateRange == 'Custom')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${DateFormat('MMM dd, yyyy').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF6B8B),
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
  // BUILD SUMMARY CARDS
  // ============================================================
  Widget _buildSummaryCards() {
    final total = _summaryData['total_appointments'] ?? 0;
    final revenue = _summaryData['total_revenue'] ?? 0;
    final completed = _summaryData['completed'] ?? 0;
    final pending = _summaryData['pending'] ?? 0;
    final cancelled = _summaryData['cancelled'] ?? 0;
    final noShow = _summaryData['no_show'] ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildSummaryCard(
          title: 'Total Appointments',
          value: '$total',
          icon: Icons.calendar_today,
          color: Colors.blue,
        ),
        _buildSummaryCard(
          title: 'Revenue',
          value: 'Rs. $revenue',
          icon: Icons.attach_money,
          color: Colors.green,
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
        if (cancelled > 0)
          _buildSummaryCard(
            title: 'Cancelled',
            value: '$cancelled',
            icon: Icons.cancel,
            color: Colors.red,
          ),
        if (noShow > 0)
          _buildSummaryCard(
            title: 'No Show',
            value: '$noShow',
            icon: Icons.person_off,
            color: Colors.grey,
          ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD CHART
  // ============================================================
  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.show_chart, color: Color(0xFFFF6B8B)),
                  SizedBox(width: 8),
                  Text(
                    'Appointments Trend',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No data available for chart',
                      style: TextStyle(
                        color: Colors.grey[500],
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ FIXED: removed `const` — this Row contains a dynamic
            // Text('${_chartData.length} days') which is not a compile-time constant.
            Row(
              children: [
                const Icon(Icons.show_chart, color: Color(0xFFFF6B8B)),
                const SizedBox(width: 8),
                const Text(
                  'Appointments Trend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_chartData.length} days',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
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
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: height > 0 ? height : 2,
                          width: 16,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF6B8B),
                                Color(0xFFFF8A9F),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateLabel(date),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.grey,
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
  // BUILD SERVICE STATS
  // ============================================================
  Widget _buildServiceStats() {
    final serviceStats = _summaryData['service_stats'] as List? ?? [];

    if (serviceStats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ FIXED: removed `const` — Text('${serviceStats.length} services')
            // depends on a runtime value, so the Row can't be const.
            Row(
              children: [
                const Icon(Icons.content_cut, color: Color(0xFFFF6B8B)),
                const SizedBox(width: 8),
                const Text(
                  'Service Statistics',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${serviceStats.length} services',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...serviceStats.take(5).map((item) {
              final service = item['service'] as String? ?? 'Unknown';
              final count = item['count'] as int? ?? 0;
              final percentage = _reportData.isNotEmpty
                  ? (count / _reportData.length * 100).toStringAsFixed(1)
                  : '0';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        service,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: count / (_reportData.isNotEmpty ? _reportData.length : 1),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF6B8B), Color(0xFFFF8A9F)],
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
                        color: Colors.grey[600],
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
                      color: Colors.grey[500],
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
  // BUILD BARBER STATS (Owner only)
  // ============================================================
  Widget _buildBarberStats() {
    final barberStats = _summaryData['barber_stats'] as List? ?? [];

    if (barberStats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ FIXED: removed `const` — Text('${barberStats.length} barbers')
            // depends on a runtime value, so the Row can't be const.
            Row(
              children: [
                const Icon(Icons.people, color: Color(0xFFFF6B8B)),
                const SizedBox(width: 8),
                const Text(
                  'Barber Performance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${barberStats.length} barbers',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
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
                        color: const Color(0xFFFF6B8B),
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
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$count appointments',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
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
                        color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B8B),
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
  // BUILD REPORT TABLE
  // ============================================================
  Widget _buildReportTable() {
    if (_reportData.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 48,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 8),
              Text(
                'No appointments found',
                style: TextStyle(
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ FIXED: removed `const` from Padding — its child Row contains
          // Text('${_reportData.length} records'), a runtime value.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.table_chart, color: Color(0xFFFF6B8B)),
                const SizedBox(width: 8),
                const Text(
                  'Appointment Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_reportData.length} records',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Date
                          SizedBox(
                            width: 70,
                            child: Text(
                              item['appointment_date']?.toString() ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Customer
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['customer_name']?.toString() ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  item['service_name']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Price
                          SizedBox(
                            width: 60,
                            child: Text(
                              'Rs. ${item['price'] ?? 0}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF6B8B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Status
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