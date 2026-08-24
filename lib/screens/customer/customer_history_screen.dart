// lib/screens/customer/customer_history_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  // Filter options
  String _selectedFilter = 'All';
  String _selectedPeriod = 'All';

  // Tab controller
  late TabController _tabController;

  // Stats
  int _totalBookings = 0;
  int _completedCount = 0;
  int _cancelledCount = 0;
  int _noShowCount = 0;
  int _totalSpent = 0;

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view your history';
          _isLoading = false;
        });
        return;
      }

      // ✅ Get customer role ID dynamically
      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'customer')
          .single();

      final customerRoleId = roleResponse['id'];

      // ✅ Check if user has active customer role
      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', currentUser.id)
          .eq('role_id', customerRoleId)
          .maybeSingle();

      if (roleCheck == null || roleCheck['status'] != 'active') {
        setState(() {
          _errorMessage = 'Your account is not active. Please contact support.';
          _isLoading = false;
        });
        return;
      }

      // Build date filter
      String? startDate;
      final now = DateTime.now();

      switch (_selectedPeriod) {
        case 'This Month':
          startDate = DateFormat(
            'yyyy-MM-dd',
          ).format(DateTime(now.year, now.month, 1));
          break;
        case 'Last 3 Months':
          startDate = DateFormat(
            'yyyy-MM-dd',
          ).format(now.subtract(const Duration(days: 90)));
          break;
        case 'This Year':
          startDate = DateFormat('yyyy-MM-dd').format(DateTime(now.year, 1, 1));
          break;
        default:
          startDate = null;
      }

      // Build query
      var query = supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            appointment_date,
            start_time,
            end_time,
            status,
            price,
            service_id,
            variant_id,
            salon_id,
            barber_id,
            cancel_reason,
            created_at,
            updated_at,
            services!inner (
              name
            ),
            salons!inner (
              id,
              name,
              logo_url
            ),
            profiles!appointments_barber_id_fkey (
              full_name
            ),
            service_variants!left (
              duration,
              salon_genders!left (display_name),
              salon_age_categories!left (display_name)
            )
          ''')
          .eq('customer_id', currentUser.id)
          .inFilter('status', ['completed', 'cancelled', 'no_show']);

      if (startDate != null) {
        query = query.gte('appointment_date', startDate);
      }

      final response = await query.order('appointment_date', ascending: false);

      final List<Map<String, dynamic>> historyList = [];

      int totalBookings = 0;
      int completedCount = 0;
      int cancelledCount = 0;
      int noShowCount = 0;
      int totalSpent = 0;

      for (var item in response) {
        final service = item['services'] as Map?;
        final salon = item['salons'] as Map?;
        final barber = item['profiles'] as Map?;
        final variant = item['service_variants'] as Map?;

        final status = item['status'] as String? ?? 'pending';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final date = item['appointment_date'] as String;

        historyList.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'service_name': service?['name']?.toString() ?? 'Unknown Service',
          'salon_name': salon?['name']?.toString() ?? 'Unknown Salon',
          'salon_logo': salon?['logo_url']?.toString(),
          'barber_name': barber?['full_name']?.toString() ?? 'Unknown Barber',
          'appointment_date': date,
          'start_time': item['start_time'],
          'end_time': item['end_time'],
          'status': status,
          'price': price,
          'duration': variant?['duration'] ?? 30,
          'cancel_reason': item['cancel_reason'],
          'created_at': item['created_at'],
          'updated_at': item['updated_at'],
          'display_date': _formatDisplayDate(date),
          'is_past': DateTime.parse(date).isBefore(DateTime.now()),
        });

        totalBookings++;
        totalSpent += price.toInt();

        switch (status) {
          case 'completed':
            completedCount++;
            break;
          case 'cancelled':
            cancelledCount++;
            break;
          case 'no_show':
            noShowCount++;
            break;
        }
      }

      setState(() {
        _history = historyList;
        _totalBookings = totalBookings;
        _completedCount = completedCount;
        _cancelledCount = cancelledCount;
        _noShowCount = noShowCount;
        _totalSpent = totalSpent;
        _isLoading = false;
      });

      debugPrint('✅ Loaded ${historyList.length} history records');
    } catch (e) {
      debugPrint('❌ Error loading history: $e');
      setState(() {
        _errorMessage = 'Error loading history: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================
  String _formatDisplayDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return 'Today';
      }

      final yesterday = now.subtract(const Duration(days: 1));
      if (date.year == yesterday.year &&
          date.month == yesterday.month &&
          date.day == yesterday.day) {
        return 'Yesterday';
      }

      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  // ============================================================
  // FILTER DATA
  // ============================================================
  List<Map<String, dynamic>> get _filteredHistory {
    var filtered = List<Map<String, dynamic>>.from(_history);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final serviceName =
            (item['service_name'] as String?)?.toLowerCase() ?? '';
        final salonName = (item['salon_name'] as String?)?.toLowerCase() ?? '';
        final barberName =
            (item['barber_name'] as String?)?.toLowerCase() ?? '';
        final bookingNumber =
            (item['booking_number'] as String?)?.toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return serviceName.contains(query) ||
            salonName.contains(query) ||
            barberName.contains(query) ||
            bookingNumber.contains(query);
      }).toList();
    }

    if (_selectedFilter != 'All') {
      filtered = filtered.where((item) {
        final status = item['status'] as String? ?? '';
        return status.toLowerCase() == _selectedFilter.toLowerCase();
      }).toList();
    }

    return filtered;
  }

  // ============================================================
  // VIEW BOOKING DETAILS - WITH DARK MODE
  // ============================================================
  void _viewBookingDetails(Map<String, dynamic> booking) {
    final isDark = context.isDarkMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _BookingDetailsSheet(booking: booking),
    );
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'My History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'History'),
            Tab(text: 'Stats'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading history...',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black87,
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
                    color: isDark ? Colors.white70 : Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loadHistory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : isWeb
          ? _buildWebLayout()
          : _buildMobileLayout(),
    );
  }

  // ✅ WEB LAYOUT
  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;
    final filteredHistory = _filteredHistory;

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              // Filters
              _buildFilters(),
              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // History Tab
                    filteredHistory.isEmpty
                        ? _buildEmptyState()
                        : Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            thickness: 8.0,
                            radius: const Radius.circular(10),
                            scrollbarOrientation: ScrollbarOrientation.right,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: filteredHistory.length,
                              itemBuilder: (context, index) {
                                final booking = filteredHistory[index];
                                return _buildHistoryCard(booking);
                              },
                            ),
                          ),
                    // Stats Tab
                    _buildStatsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    final filteredHistory = _filteredHistory;

    return Column(
      children: [
        // Filters
        _buildFilters(),
        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // History Tab
              filteredHistory.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredHistory.length,
                      itemBuilder: (context, index) {
                        final booking = filteredHistory[index];
                        return _buildHistoryCard(booking);
                      },
                    ),
              // Stats Tab
              _buildStatsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD FILTERS - WITH DARK MODE
  // ============================================================
  Widget _buildFilters() {
    final isDark = context.isDarkMode;
    final statuses = ['All', 'Completed', 'Cancelled', 'No Show'];
    final periods = ['All', 'This Month', 'Last 3 Months', 'This Year'];

    return Container(
      padding: const EdgeInsets.all(12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Column(
        children: [
          // Search
          TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search by service, salon, barber...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
              prefixIcon: Icon(
                Icons.search,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: isDark ? Colors.white70 : Colors.grey,
                        size: 18,
                      ),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),

          // Status filter
          Row(
            children: [
              Text(
                'Status:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.black87,
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
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(
                            status,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                        ? Colors.white70
                                        : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilter = selected ? status : 'All';
                            });
                          },
                          backgroundColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100],
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Period filter
          Row(
            children: [
              Text(
                'Period:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: periods.map((period) {
                      final isSelected = _selectedPeriod == period;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(
                            period,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                        ? Colors.white70
                                        : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedPeriod = selected ? period : 'All';
                            });
                            _loadHistory();
                          },
                          backgroundColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100],
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD HISTORY CARD - WITH DARK MODE
  // ============================================================
  Widget _buildHistoryCard(Map<String, dynamic> booking) {
    final isDark = context.isDarkMode;
    final status = booking['status'] as String? ?? 'pending';
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    final isNoShow = status == 'no_show';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isCompleted) {
      statusColor = Colors.green;
      statusLabel = 'Completed';
      statusIcon = Icons.check_circle;
    } else if (isCancelled) {
      statusColor = Colors.red;
      statusLabel = 'Cancelled';
      statusIcon = Icons.cancel;
    } else if (isNoShow) {
      statusColor = Colors.orange;
      statusLabel = 'No Show';
      statusIcon = Icons.person_off;
    } else {
      statusColor = Colors.grey;
      statusLabel = 'Unknown';
      statusIcon = Icons.help;
    }

    final serviceName =
        booking['service_name']?.toString() ?? 'Unknown Service';
    final salonName = booking['salon_name']?.toString() ?? 'Unknown Salon';
    final barberName = booking['barber_name']?.toString() ?? 'Unknown Barber';
    final displayDate = booking['display_date']?.toString() ?? '';
    final price = booking['price'] as double? ?? 0;
    final duration = booking['duration'] as int? ?? 30;
    final bookingNumber = booking['booking_number']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: InkWell(
        onTap: () => _viewBookingDetails(booking),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Date & Status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    displayDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Service & Salon
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      image: booking['salon_logo'] != null
                          ? DecorationImage(
                              image: NetworkImage(booking['salon_logo']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: booking['salon_logo'] == null
                        ? Center(
                            child: Text(
                              salonName.isNotEmpty
                                  ? salonName[0].toUpperCase()
                                  : 'S',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
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
                          serviceName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          salonName,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 12,
                              color: isDark ? Colors.white70 : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              barberName,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[500],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Details: Price, Duration, Booking #
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_money,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Rs. ${price.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          '$duration min',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (bookingNumber.isNotEmpty)
                    Text(
                      '#$bookingNumber',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD STATS TAB - WITH DARK MODE
  // ============================================================
  Widget _buildStatsTab() {
    final isDark = context.isDarkMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Total Bookings',
                  value: '$_totalBookings',
                  icon: Icons.calendar_today,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'Total Spent',
                  value: 'Rs. $_totalSpent',
                  icon: Icons.attach_money,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Distribution
          Card(
            elevation: 2,
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Distribution',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatusBar(
                    label: 'Completed',
                    count: _completedCount,
                    total: _totalBookings,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  _buildStatusBar(
                    label: 'Cancelled',
                    count: _cancelledCount,
                    total: _totalBookings,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 8),
                  _buildStatusBar(
                    label: 'No Show',
                    count: _noShowCount,
                    total: _totalBookings,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Recent Activity
          Card(
            elevation: 2,
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No activity yet',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._history.take(5).map((booking) {
                      final status = booking['status'] as String? ?? 'pending';
                      final service = booking['service_name']?.toString() ?? '';
                      final date = booking['display_date']?.toString() ?? '';

                      Color statusColor;
                      String statusLabel;

                      switch (status) {
                        case 'completed':
                          statusColor = Colors.green;
                          statusLabel = 'Completed';
                          break;
                        case 'cancelled':
                          statusColor = Colors.red;
                          statusLabel = 'Cancelled';
                          break;
                        case 'no_show':
                          statusColor = Colors.orange;
                          statusLabel = 'No Show';
                          break;
                        default:
                          statusColor = Colors.grey;
                          statusLabel = status;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    service,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    date,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
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
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isDark = context.isDarkMode;

    return Card(
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar({
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final isDark = context.isDarkMode;
    final percentage = total > 0 ? (count / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              '$count (${percentage.toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: (percentage / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD EMPTY STATE - WITH DARK MODE
  // ============================================================
  Widget _buildEmptyState() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: isDark ? Colors.white30 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No history found matching "$_searchQuery"'
                : 'No booking history yet',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your past bookings will appear here',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
          ),
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
              },
              child: Text(
                'Clear Search',
                style: TextStyle(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// BOOKING DETAILS SHEET - WITH DARK MODE
// ============================================================
class _BookingDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> booking;

  const _BookingDetailsSheet({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final serviceName = booking['service_name']?.toString() ?? 'Unknown';
    final salonName = booking['salon_name']?.toString() ?? 'Unknown';
    final barberName = booking['barber_name']?.toString() ?? 'Unknown';
    final bookingNumber = booking['booking_number']?.toString() ?? '';
    final startTime = booking['start_time']?.toString() ?? '';
    final endTime = booking['end_time']?.toString() ?? '';
    final price = booking['price'] as double? ?? 0;
    final duration = booking['duration'] as int? ?? 30;
    final status = booking['status'] as String? ?? 'pending';
    final cancelReason = booking['cancel_reason']?.toString();
    final displayDate = booking['display_date']?.toString() ?? '';

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusLabel = 'Completed';
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusLabel = 'Cancelled';
        break;
      case 'no_show':
        statusColor = Colors.orange;
        statusLabel = 'No Show';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = status;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      image: booking['salon_logo'] != null
                          ? DecorationImage(
                              image: NetworkImage(booking['salon_logo']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: booking['salon_logo'] == null
                        ? Center(
                            child: Text(
                              salonName.isNotEmpty
                                  ? salonName[0].toUpperCase()
                                  : 'S',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
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
                          salonName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          serviceName,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            if (bookingNumber.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                '#$bookingNumber',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(),

              // Details
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // ✅ Pass context to each call
                    _buildDetailRow(
                      context, // ← Pass context
                      icon: Icons.calendar_today,
                      label: 'Date',
                      value: displayDate,
                    ),
                    _buildDetailRow(
                      context, // ← Pass context
                      icon: Icons.access_time,
                      label: 'Time',
                      value: '$startTime - $endTime',
                    ),
                    _buildDetailRow(
                      context, // ← Pass context
                      icon: Icons.person,
                      label: 'Barber',
                      value: barberName,
                    ),
                    _buildDetailRow(
                      context, // ← Pass context
                      icon: Icons.timer,
                      label: 'Duration',
                      value: '$duration minutes',
                    ),
                    _buildDetailRow(
                      context, // ← Pass context
                      icon: Icons.attach_money,
                      label: 'Price',
                      value: 'Rs. ${price.toStringAsFixed(0)}',
                      valueColor: Colors.green,
                    ),
                    if (cancelReason != null && cancelReason.isNotEmpty)
                      _buildDetailRow(
                        context, // ← Pass context
                        icon: Icons.info_outline,
                        label: 'Cancellation Reason',
                        value: cancelReason,
                        valueColor: Colors.red,
                      ),
                  ],
                ),
              ),

              // Close button
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ✅ Fixed: Add context parameter
  Widget _buildDetailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[500],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color:
                        valueColor ??
                        (isDark ? Colors.white : Colors.grey[800]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
