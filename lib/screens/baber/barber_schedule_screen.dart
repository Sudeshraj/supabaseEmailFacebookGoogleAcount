// lib/screens/barber/barber_schedule_view_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_theme.dart';
import '../../extensions/context_extensions.dart';

class BarberScheduleViewScreen extends StatefulWidget {
  final String? salonId;

  const BarberScheduleViewScreen({super.key, this.salonId});

  @override
  State<BarberScheduleViewScreen> createState() =>
      _BarberScheduleViewScreenState();
}

class _BarberScheduleViewScreenState extends State<BarberScheduleViewScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  String? _salonName;
  String _barberId = '';

  // Timezone
  String _salonTimezone = '';
  String _userTimezone = '';

  // Selected date
  DateTime _selectedDate = DateTime.now();

  // Data
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _regularSchedules = [];
  List<Map<String, dynamic>> _regularBreaks = [];
  List<Map<String, dynamic>> _specialSchedules = [];
  List<Map<String, dynamic>> _specialBreaks = [];

  // Grouped data by day
  Map<int, List<Map<String, dynamic>>> _groupedSchedules = {};
  Map<int, List<Map<String, dynamic>>> _groupedBreaks = {};

  // ✅ Android 16: Responsive variables
  bool _isLargeScreen = false;
  bool _isTablet = false;
  bool _isWeb = false;

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  final Map<int, String> _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    _initializeTimezones();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ✅ Android 16: Check screen size for responsive layout
  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isLarge = size.width > 800 || size.height > 800;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isLargeScreen != isLarge || _isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isLargeScreen = isLarge;
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  // ============================================================
  // TIMEZONE INITIALIZATION
  // ============================================================

  Future<void> _initializeTimezones() async {
    await TimezoneService.initialize();

    _userTimezone = TimezoneService.getCurrentTimezone();

    if (widget.salonId != null) {
      try {
        final salonIdInt = int.parse(widget.salonId!);
        final salonResponse = await supabase
            .from('salons')
            .select('name, timezone')
            .eq('id', salonIdInt)
            .maybeSingle();

        if (salonResponse != null) {
          _salonName = salonResponse['name'];
          _salonTimezone = salonResponse['timezone'] ?? _userTimezone;
        }
      } catch (e) {
        debugPrint('Error loading salon info: $e');
        _salonTimezone = _userTimezone;
      }
    }

    await _loadBarberData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadBarberData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view your schedule';
          _isLoading = false;
        });
        return;
      }

      _barberId = currentUser.id;

      if (widget.salonId != null && _salonName == null) {
        final salonResponse = await supabase
            .from('salons')
            .select('name, timezone')
            .eq('id', int.parse(widget.salonId!))
            .maybeSingle();

        if (salonResponse != null) {
          _salonName = salonResponse['name'];
          _salonTimezone = salonResponse['timezone'] ?? _userTimezone;
        }
      }

      await _loadAllData();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() {
        _errorMessage = 'Error loading data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAllData() async {
    if (_barberId.isEmpty || widget.salonId == null) return;

    final salonIdInt = int.parse(widget.salonId!);

    final schedulesResponse = await supabase
        .from('barber_schedules')
        .select()
        .eq('barber_id', _barberId)
        .eq('salon_id', salonIdInt)
        .order('day_of_week');

    _regularSchedules = List<Map<String, dynamic>>.from(schedulesResponse);

    _groupedSchedules = {};
    for (var schedule in _regularSchedules) {
      final day = schedule['day_of_week'] as int;
      if (!_groupedSchedules.containsKey(day)) {
        _groupedSchedules[day] = [];
      }
      _groupedSchedules[day]!.add(schedule);
    }

    final breaksResponse = await supabase
        .from('barber_breaks')
        .select()
        .eq('barber_id', _barberId)
        .eq('salon_id', salonIdInt)
        .order('day_of_week');

    _regularBreaks = List<Map<String, dynamic>>.from(breaksResponse);

    _groupedBreaks = {};
    for (var breakItem in _regularBreaks) {
      final day = breakItem['day_of_week'] as int;
      if (!_groupedBreaks.containsKey(day)) {
        _groupedBreaks[day] = [];
      }
      _groupedBreaks[day]!.add(breakItem);
    }

    final specialSchedulesResponse = await supabase
        .from('barber_special_schedules')
        .select()
        .eq('barber_id', _barberId)
        .eq('salon_id', salonIdInt)
        .order('schedule_date');

    _specialSchedules = List<Map<String, dynamic>>.from(
      specialSchedulesResponse,
    );

    final specialBreaksResponse = await supabase
        .from('barber_special_breaks')
        .select()
        .eq('barber_id', _barberId)
        .eq('salon_id', salonIdInt)
        .order('break_date');

    _specialBreaks = List<Map<String, dynamic>>.from(specialBreaksResponse);

    await _loadAppointments();

    debugPrint('✅ Loaded all data successfully');
    debugPrint('  - Regular Schedules: ${_regularSchedules.length}');
    debugPrint('  - Regular Breaks: ${_regularBreaks.length}');
    debugPrint('  - Special Schedules: ${_specialSchedules.length}');
    debugPrint('  - Special Breaks: ${_specialBreaks.length}');
    debugPrint('  - Appointments: ${_appointments.length}');
  }

  // ============================================================
  // LOAD APPOINTMENTS
  // ============================================================

  Future<void> _loadAppointments() async {
    try {
      if (_barberId.isEmpty || widget.salonId == null) return;

      final salonIdInt = int.parse(widget.salonId!);
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

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
            salon_id,
            queue_number,
            queue_token,
            is_vip,
            created_at,
            services!inner (
              name
            ),
            service_variants!left (
              duration,
              salon_genders!left (display_name),
              salon_age_categories!left (display_name)
            ),
            profiles!appointments_customer_id_fkey (
              full_name,
              email,
              phone,
              avatar_url
            )
          ''')
          .eq('barber_id', _barberId)
          .eq('appointment_date', dateStr)
          .eq('salon_id', salonIdInt)
          .neq('status', 'cancelled')
          .neq('status', 'no_show')
          .order('start_time', ascending: true);

      final List<Map<String, dynamic>> appointments = [];

      for (var item in response) {
        final service = item['services'] as Map?;
        final variant = item['service_variants'] as Map?;
        final customer = item['profiles'] as Map?;
        final status = item['status'] as String? ?? 'pending';
        final startTime = item['start_time'] as String;
        final endTime = item['end_time'] as String;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;

        appointments.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_avatar': customer?['avatar_url'],
          'customer_phone': customer?['phone'] ?? '',
          'customer_email': customer?['email'] ?? '',
          'service_name': service?['name'] ?? 'Unknown Service',
          'start_time': _formatUtcToLocalTime(startTime),
          'end_time': _formatUtcToLocalTime(endTime),
          'start_time_raw': startTime,
          'end_time_raw': endTime,
          'status': status,
          'price': price,
          'duration': variant?['duration'] ?? 30,
          'is_vip': item['is_vip'] ?? false,
          'queue_number': item['queue_number'],
          'queue_token': item['queue_token'],
          'gender': variant?['salon_genders']?['display_name'] ?? '',
          'age_category':
              variant?['salon_age_categories']?['display_name'] ?? '',
        });
      }

      setState(() {
        _appointments = appointments;
      });

      debugPrint('✅ Loaded ${appointments.length} appointments for $_selectedDate');
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
    }
  }

  // ============================================================
  // TIMEZONE HELPERS
  // ============================================================

  String _formatUtcToLocalTime(String? utcTime) {
    if (utcTime == null || utcTime.isEmpty) return '--:--';
    try {
      return TimezoneService.utcToLocalTimeRecurring(utcTime);
    } catch (e) {
      final parts = utcTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    }
  }

  String _getTimezoneDisplay() {
    return TimezoneService.getFullTimezoneDisplay();
  }

  // ============================================================
  // DATE NAVIGATION
  // ============================================================

  void _previousDate() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _loadAppointments();
  }

  void _nextDate() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
    _loadAppointments();
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadAppointments();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.primary,
              brightness: Theme.of(context).brightness,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadAppointments();
    }
  }

  // ============================================================
  // STATUS HELPERS
  // ============================================================

  (Color, String, IconData) _getStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return (Colors.green, 'Completed', Icons.check_circle);
      case 'confirmed':
        return (Colors.blue, 'Confirmed', Icons.confirmation_number);
      case 'pending':
        return (Colors.orange, 'Pending', Icons.pending_actions);
      case 'in_progress':
        return (Colors.purple, 'In Progress', Icons.hourglass_top);
      case 'no_show':
        return (Colors.red, 'No Show', Icons.person_off);
      default:
        return (Colors.grey, status, Icons.help);
    }
  }

  // ============================================================
  // ✅ BUILD: DETAIL CHIP
  // ============================================================

  Widget _buildDetailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: APPOINTMENT CARD
  // ============================================================

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final isDark = context.isDarkMode;
    final status = appointment['status'] as String? ?? 'pending';
    final (statusColor, statusLabel, statusIcon) = _getStatusInfo(status);
    final isVip = appointment['is_vip'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Time & Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${appointment['start_time']} - ${appointment['end_time']}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        size: 12,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Customer Info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                  backgroundImage: appointment['customer_avatar'] != null
                      ? CachedNetworkImageProvider(
                          appointment['customer_avatar'])
                      : null,
                  child: appointment['customer_avatar'] == null
                      ? Text(
                          (appointment['customer_name'] as String?)?[0]
                                  .toUpperCase() ??
                              '?',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appointment['customer_name'] ??
                                  'Unknown Customer',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVip)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 10,
                                    color: Colors.amber,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    'VIP',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      Text(
                        appointment['service_name'] ?? 'Unknown Service',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Details
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildDetailChip(
                  icon: Icons.timer,
                  label: '${appointment['duration']} min',
                  color: Colors.blue,
                ),
                _buildDetailChip(
                  icon: Icons.attach_money,
                  label: 'Rs. ${appointment['price'].toStringAsFixed(0)}',
                  color: Colors.green,
                ),
                if (appointment['gender']?.isNotEmpty ?? false)
                  _buildDetailChip(
                    icon: Icons.people,
                    label: appointment['gender'],
                    color: Colors.purple,
                  ),
                if (appointment['age_category']?.isNotEmpty ?? false)
                  _buildDetailChip(
                    icon: Icons.cake,
                    label: appointment['age_category'],
                    color: Colors.orange,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: SCHEDULE DAY ITEM
  // ============================================================

  Widget _buildScheduleDayItem(
      String dayName, List<Map<String, dynamic>> schedules) {
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              dayName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: schedules.map((schedule) {
                final isWorking = schedule['is_working'] ?? true;
                final startTime = _formatUtcToLocalTime(schedule['start_time']);
                final endTime = _formatUtcToLocalTime(schedule['end_time']);

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isWorking
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isWorking
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isWorking ? Icons.check_circle : Icons.cancel,
                        size: 12,
                        color: isWorking ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$startTime - $endTime',
                        style: TextStyle(
                          fontSize: 11,
                          color: isWorking
                              ? (isDark ? Colors.white70 : Colors.grey[700])
                              : (isDark ? Colors.white70 : Colors.grey[500]),
                          decoration:
                              isWorking ? null : TextDecoration.lineThrough,
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
    );
  }

  // ============================================================
  // ✅ BUILD: TIMEZONE INFO CARD
  // ============================================================

  Widget _buildTimezoneInfoCard() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time,
            size: 16,
            color: isDark ? Colors.white60 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⏰ Times shown in: ${_getTimezoneDisplay()}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
          ),
          if (_salonTimezone.isNotEmpty && _salonTimezone != _userTimezone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Salon: ${_salonTimezone.split('/').last}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.orange[300] : Colors.orange,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: DATE NAVIGATOR
  // ============================================================

  Widget _buildDateNavigator() {
    final isDark = context.isDarkMode;
    final isToday = _selectedDate.isAtSameMomentAs(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: _previousDate,
            color: AppTheme.primary,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _selectDate,
              child: Column(
                children: [
                  Text(
                    DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (!isToday)
                    TextButton(
                      onPressed: _goToToday,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 20),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Go to Today',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 28),
            onPressed: _nextDate,
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: APPOINTMENTS SECTION
  // ============================================================

  Widget _buildAppointmentsSection() {
    final isDark = context.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  "Today's Appointments",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_appointments.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_appointments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy,
                      size: 48,
                      color: isDark ? Colors.white30 : Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No appointments today',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _appointments.length,
              itemBuilder: (context, index) {
                final appointment = _appointments[index];
                return _buildAppointmentCard(appointment);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: REGULAR SCHEDULE SECTION
  // ============================================================

  Widget _buildRegularScheduleSection() {
    final isDark = context.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Regular Schedule',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_regularSchedules.length} days',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_regularSchedules.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No regular schedule set up yet',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _dayNames.entries.map((entry) {
                  final day = entry.key;
                  final dayName = entry.value;
                  final schedules = _groupedSchedules[day] ?? [];

                  if (schedules.isEmpty) return const SizedBox.shrink();

                  return _buildScheduleDayItem(dayName, schedules);
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: SPECIAL SCHEDULES SECTION
  // ============================================================

  Widget _buildSpecialSchedulesSection() {
    final isDark = context.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.event, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  'Special Schedules',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_specialSchedules.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _specialSchedules.map((schedule) {
                final date = DateTime.parse(schedule['schedule_date']);
                final isWorking = schedule['is_working'] ?? true;
                final reason = schedule['reason'] ?? 'Special day';
                final startTime = _formatUtcToLocalTime(schedule['start_time']);
                final endTime = _formatUtcToLocalTime(schedule['end_time']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.purple.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          DateFormat('MMM dd').format(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isWorking
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isWorking
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isWorking
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    size: 12,
                                    color: isWorking ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isWorking ? 'Working' : 'Off',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isWorking
                                          ? Colors.green[700]
                                          : Colors.red[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isWorking) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$startTime - $endTime',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.blue[300] : Colors.blue[700],
                                  ),
                                ),
                              ),
                            ],
                            if (reason.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white70 : Colors.grey[500],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: REGULAR BREAKS SECTION
  // ============================================================

  Widget _buildRegularBreaksSection() {
    final isDark = context.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.free_breakfast, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Regular Breaks',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_regularBreaks.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _dayNames.entries.map((entry) {
                final day = entry.key;
                final dayName = entry.value;
                final breaks = _groupedBreaks[day] ?? [];

                if (breaks.isEmpty) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          dayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: breaks.map((breakItem) {
                            final startTime =
                                _formatUtcToLocalTime(breakItem['start_time']);
                            final endTime =
                                _formatUtcToLocalTime(breakItem['end_time']);
                            final breakType = breakItem['break_type'] ?? 'Break';

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.coffee,
                                    size: 12,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$startTime - $endTime',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      breakType,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: isDark ? Colors.white60 : Colors.grey[600],
                                      ),
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
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: SPECIAL BREAKS SECTION
  // ============================================================

  Widget _buildSpecialBreaksSection() {
    final isDark = context.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.event_busy, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  'Special Breaks',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_specialBreaks.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _specialBreaks.map((breakItem) {
                final date = DateTime.parse(breakItem['break_date']);
                final startTime =
                    _formatUtcToLocalTime(breakItem['start_time']);
                final endTime = _formatUtcToLocalTime(breakItem['end_time']);
                final breakType = breakItem['break_type'] ?? 'custom';

                String breakTypeLabel = 'Break';
                IconData breakIcon = Icons.free_breakfast;
                switch (breakType) {
                  case 'lunch':
                    breakTypeLabel = '🍽️ Lunch';
                    breakIcon = Icons.lunch_dining;
                    break;
                  case 'tea':
                    breakTypeLabel = '☕ Tea';
                    breakIcon = Icons.coffee;
                    break;
                  default:
                    breakTypeLabel = '📝 Custom';
                    breakIcon = Icons.free_breakfast;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          DateFormat('MMM dd').format(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.teal.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    breakIcon,
                                    size: 12,
                                    color: Colors.teal,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$startTime - $endTime',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.teal[300] : Colors.teal[700],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      breakTypeLabel,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: isDark ? Colors.white60 : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: ERROR STATE
  // ============================================================

  Widget _buildErrorState() {
    final isDark = context.isDarkMode;

    return Center(
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
            onPressed: _loadBarberData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: DASHBOARD CONTENT
  // ============================================================

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timezone info
        _buildTimezoneInfoCard(),
        const SizedBox(height: 16),

        // Date Navigator
        _buildDateNavigator(),
        const SizedBox(height: 16),

        // Today's Appointments
        _buildAppointmentsSection(),
        const SizedBox(height: 16),

        // Regular Schedule (All days)
        _buildRegularScheduleSection(),
        const SizedBox(height: 16),

        // Special Schedules
        if (_specialSchedules.isNotEmpty) _buildSpecialSchedulesSection(),
        const SizedBox(height: 16),

        // Regular Breaks
        if (_regularBreaks.isNotEmpty) _buildRegularBreaksSection(),
        const SizedBox(height: 16),

        // Special Breaks
        if (_specialBreaks.isNotEmpty) _buildSpecialBreaksSection(),
      ],
    );
  }

  // ============================================================
  // ✅ BUILD METHOD - WITH WEB FRAME
  // ============================================================

  @override
  Widget build(BuildContext context) {
    _checkScreenSize();
    final isDark = context.isDarkMode;
    final isWeb = _isWeb;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          _salonName != null ? 'My Schedule - $_salonName' : 'My Schedule',
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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
          // ✅ Refresh button removed from AppBar
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading schedule...',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
            ? _buildErrorState()
            : isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
    );
  }

  // ✅ WEB LAYOUT - Centered with Scrollbar
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000),
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
}