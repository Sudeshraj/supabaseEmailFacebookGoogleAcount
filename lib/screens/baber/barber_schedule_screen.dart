// lib/screens/barber/barber_schedule_view_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/timezone_service.dart';
import '../../services/currency_service.dart';
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

  // ✅ Timezone (salon + user)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';
  String _salonTimezone = _kDefaultSalonTimezone;
  String _userTimezone = '';

  // ✅ Currency
  String _salonCurrencyCode = 'LKR';

  // Selected date (in salon timezone)
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

  // ✅ Responsive
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

  // ============================================================
  // ✅ SALON "NOW" - consistent timezone reference
  // ============================================================
  DateTime get _salonNow {
    final tz =
        _salonTimezone.isNotEmpty ? _salonTimezone : _kDefaultSalonTimezone;
    try {
      return TimezoneService.getNowInTimezone(tz);
    } catch (e) {
      debugPrint('❌ Error getting salon now: $e');
      return DateTime.now();
    }
  }

  DateTime get _salonToday {
    final now = _salonNow;
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
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

  // ✅ MediaQuery.sizeOf (only reacts to size changes)
  void _checkScreenSize() {
    final size = MediaQuery.sizeOf(context);
    final isWeb = size.width > 800;

    if (_isWeb != isWeb) {
      setState(() {
        _isWeb = isWeb;
      });
    }
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    _userTimezone = TimezoneService.getCurrentTimezone();
    if (_userTimezone.isEmpty) {
      _userTimezone = _kDefaultSalonTimezone;
    }

    await _loadSalonInfo();

    // ✅ Set _selectedDate based on salon timezone
    if (!mounted) return;
    setState(() {
      _selectedDate = _salonToday;
    });

    await _loadBarberData();
  }

  /// ✅ Load salon info (name, timezone, currency)
  Future<void> _loadSalonInfo() async {
    if (widget.salonId == null) return;

    // ✅ Defaults BEFORE query so they're never empty
    _salonTimezone = _kDefaultSalonTimezone;
    _salonCurrencyCode = 'LKR';

    try {
      final salonIdInt = int.parse(widget.salonId!);
      final salonResponse = await supabase
          .from('salons')
          .select('name, timezone, currency_code')
          .eq('id', salonIdInt)
          .maybeSingle();

      if (!mounted) return;

      if (salonResponse != null) {
        setState(() {
          _salonName = salonResponse['name'];

          final tz = salonResponse['timezone'] as String?;
          if (tz != null && tz.isNotEmpty) {
            _salonTimezone = tz;
          }

          final currCode = salonResponse['currency_code'] as String?;
          if (currCode != null && currCode.isNotEmpty) {
            _salonCurrencyCode = currCode;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salon info: $e');
      // ✅ Fallbacks already set above
    }
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadBarberData() async {
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
          _errorMessage = 'Please login to view your schedule';
          _isLoading = false;
        });
        return;
      }

      _barberId = currentUser.id;

      if (widget.salonId == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Salon ID is required';
          _isLoading = false;
        });
        return;
      }

      await _loadAllData();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  /// ✅ Parallel queries (Future.wait) + mounted checks after await
  Future<void> _loadAllData() async {
    if (_barberId.isEmpty || widget.salonId == null) return;

    final salonIdInt = int.parse(widget.salonId!);

    // ✅ Parallel queries for all 4 tables
    final results = await Future.wait([
      supabase
          .from('barber_schedules')
          .select()
          .eq('barber_id', _barberId)
          .eq('salon_id', salonIdInt)
          .order('day_of_week'),
      supabase
          .from('barber_breaks')
          .select()
          .eq('barber_id', _barberId)
          .eq('salon_id', salonIdInt)
          .order('day_of_week'),
      supabase
          .from('barber_special_schedules')
          .select()
          .eq('barber_id', _barberId)
          .eq('salon_id', salonIdInt)
          .order('schedule_date'),
      supabase
          .from('barber_special_breaks')
          .select()
          .eq('barber_id', _barberId)
          .eq('salon_id', salonIdInt)
          .order('break_date'),
    ]);

    // ✅ Mounted check after await
    if (!mounted) return;

    // Regular schedules
    _regularSchedules = List<Map<String, dynamic>>.from(results[0]);
    _groupedSchedules = {};
    for (var schedule in _regularSchedules) {
      final day = schedule['day_of_week'] as int?;
      if (day != null) {
        _groupedSchedules.putIfAbsent(day, () => []).add(schedule);
      }
    }

    // Regular breaks
    _regularBreaks = List<Map<String, dynamic>>.from(results[1]);
    _groupedBreaks = {};
    for (var breakItem in _regularBreaks) {
      final day = breakItem['day_of_week'] as int?;
      if (day != null) {
        _groupedBreaks.putIfAbsent(day, () => []).add(breakItem);
      }
    }

    // Special schedules
    _specialSchedules = List<Map<String, dynamic>>.from(results[2]);

    // Special breaks
    _specialBreaks = List<Map<String, dynamic>>.from(results[3]);

    // Appointments
    await _loadAppointments();

    debugPrint('✅ Loaded all data successfully');
    debugPrint('  - Regular Schedules: ${_regularSchedules.length}');
    debugPrint('  - Regular Breaks: ${_regularBreaks.length}');
    debugPrint('  - Special Schedules: ${_specialSchedules.length}');
    debugPrint('  - Special Breaks: ${_specialBreaks.length}');
    debugPrint('  - Appointments: ${_appointments.length}');
  }

  // ============================================================
  // ✅ LOAD APPOINTMENTS
  // ✅ no_show included + specific date TZ conversion
  // ✅ mounted check after await
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
            salon_id,
            queue_number,
            queue_token,
            is_vip,
            created_at,
            appointment_services (
              service_name,
              variant_label,
              duration,
              original_price,
              discount_amount,
              final_price
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
          .order('start_time', ascending: true);

      // ✅ Mounted check after await
      if (!mounted) return;

      final List<Map<String, dynamic>> appointments = [];

      for (var item in response) {
        final appointmentServices =
            item['appointment_services'] as List? ?? [];
        final customer = item['profiles'] as Map?;
        final status = item['status'] as String? ?? 'pending';
        final startTime = item['start_time'] as String? ?? '';
        final endTime = item['end_time'] as String? ?? '';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;

        // ✅ Null-safe date parsing
        DateTime appointmentDate;
        final dateStrRaw = item['appointment_date'] as String?;
        if (dateStrRaw != null && dateStrRaw.isNotEmpty) {
          try {
            appointmentDate = DateTime.parse(dateStrRaw);
          } catch (_) {
            appointmentDate = _selectedDate;
          }
        } else {
          appointmentDate = _selectedDate;
        }

        // ✅ Multi-service name resolution
        String serviceName = 'Unknown Service';
        int totalDuration = 0;
        String variantLabel = '';

        if (appointmentServices.isNotEmpty) {
          final names = appointmentServices
              .map((s) => s['service_name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toList();

          if (names.isNotEmpty) {
            serviceName = names.length == 1
                ? names.first
                : '${names.first} +${names.length - 1} more';
          }

          for (var s in appointmentServices) {
            totalDuration += (s['duration'] as num?)?.toInt() ?? 0;
          }

          variantLabel =
              appointmentServices.first['variant_label']?.toString() ?? '';
        }

        // ✅ Specific date TZ conversion (NOT recurring)
        final localStart = _formatUtcToLocalTimeForDate(
          startTime,
          appointmentDate,
          _salonTimezone,
        );
        final localEnd = _formatUtcToLocalTimeForDate(
          endTime,
          appointmentDate,
          _salonTimezone,
        );

        appointments.add({
          'id': item['id'],
          'booking_number': item['booking_number'],
          'appointment_date': item['appointment_date'],
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_avatar': customer?['avatar_url'],
          'customer_phone': customer?['phone'] ?? '',
          'customer_email': customer?['email'] ?? '',
          'service_name': serviceName,
          'service_count': appointmentServices.length,
          'start_time': localStart,
          'end_time': localEnd,
          'start_time_raw': startTime,
          'end_time_raw': endTime,
          'status': status,
          'price': price,
          'duration': totalDuration > 0 ? totalDuration : 30,
          'is_vip': item['is_vip'] ?? false,
          'queue_number': item['queue_number'],
          'queue_token': item['queue_token'],
          'variant_label': variantLabel,
        });
      }

      if (!mounted) return;
      setState(() {
        _appointments = appointments;
      });

      debugPrint(
          '✅ Loaded ${appointments.length} appointments for $_selectedDate');
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
      if (mounted) {
        setState(() {
          _appointments = [];
        });
      }
    }
  }

  // ============================================================
  // ✅ TIMEZONE HELPERS
  // ============================================================

  /// ✅ Specific date TZ conversion (NOT recurring)
  String _formatUtcToLocalTimeForDate(
    String? utcTime,
    DateTime date,
    String? timezone,
  ) {
    if (utcTime == null || utcTime.isEmpty) return '--:--';

    final tz = timezone ??
        (_salonTimezone.isNotEmpty ? _salonTimezone : _userTimezone);

    if (tz.isEmpty) {
      // Fallback: manual parsing
      try {
        final parts = utcTime.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
      } catch (e) {
        return '--:--';
      }
    }

    try {
      return TimezoneService.utcToLocalTimeForDateWithTimezone(
        utcTime,
        date,
        tz,
      );
    } catch (e) {
      debugPrint('❌ Error converting time: $e');
      return '--:--';
    }
  }

  /// ✅ UTC → USER timezone reference (only if different)
  /// ✅ Specific date (NOT recurring)
  String _formatUtcToUserTime(String? utcTime, DateTime appointmentDate) {
    if (utcTime == null || utcTime.isEmpty) return '';
    if (_userTimezone.isEmpty) return '';
    if (_salonTimezone == _userTimezone) return '';

    try {
      return TimezoneService.utcToLocalTimeForDateWithTimezone(
        utcTime,
        appointmentDate,
        _userTimezone,
      );
    } catch (e) {
      return '';
    }
  }

  /// ✅ Salon timezone display
  String _getSalonTimezoneDisplay() {
    final tz = _salonTimezone.isNotEmpty ? _salonTimezone : _userTimezone;
    if (tz.isEmpty) return 'Unknown';
    return TimezoneService.getFullTimezoneDisplayFor(tz);
  }

  /// ✅ User timezone display
  String _getUserTimezoneDisplay() {
    if (_userTimezone.isEmpty) return '';
    return TimezoneService.getFullTimezoneDisplayFor(_userTimezone);
  }

  /// ✅ Check if user timezone differs from salon
  bool get _isDifferentTimezone {
    if (_salonTimezone.isEmpty || _userTimezone.isEmpty) return false;
    return _salonTimezone != _userTimezone;
  }

  /// ✅ Currency format helper
  String _formatPrice(dynamic price) {
    return CurrencyService.instance.format(
      price: price,
      currencyCode: _salonCurrencyCode,
    );
  }

  // ============================================================
  // DATE NAVIGATION
  // ✅ Date picker uses salon timezone bounds
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
      _selectedDate = _salonToday;
    });
    _loadAppointments();
  }

  Future<void> _selectDate() async {
    // ✅ Date picker bounds based on salon timezone
    final salonToday = _salonToday;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: salonToday.subtract(const Duration(days: 30)),
      lastDate: salonToday.add(const Duration(days: 90)),
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

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadAppointments();
    }
  }

  // ============================================================
  // STATUS HELPERS
  // ✅ no_show case is reachable (no_show NOT excluded from query)
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
  // ✅ customer_name null safety + user TZ specific date
  // ✅ null-safe date parsing
  // ============================================================

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final isDark = context.isDarkMode;
    final status = appointment['status'] as String? ?? 'pending';
    final (statusColor, statusLabel, statusIcon) = _getStatusInfo(status);
    final isVip = appointment['is_vip'] == true;

    // ✅ Null-safe date parsing
    DateTime appointmentDate;
    final dateStrRaw = appointment['appointment_date'] as String?;
    if (dateStrRaw != null && dateStrRaw.isNotEmpty) {
      try {
        appointmentDate = DateTime.parse(dateStrRaw);
      } catch (_) {
        appointmentDate = _selectedDate;
      }
    } else {
      appointmentDate = _selectedDate;
    }

    // ✅ User time reference (specific date)
    final userStartTime = _formatUtcToUserTime(
      appointment['start_time_raw'] as String?,
      appointmentDate,
    );
    final userEndTime = _formatUtcToUserTime(
      appointment['end_time_raw'] as String?,
      appointmentDate,
    );
    final hasUserTime = userStartTime.isNotEmpty && userEndTime.isNotEmpty;

    // ✅ Service count
    final serviceCount = (appointment['service_count'] as int?) ?? 0;

    // ✅ Null-safe customer name initial
    final customerName =
        (appointment['customer_name'] as String?) ?? 'Unknown Customer';
    final customerInitial = customerName.isNotEmpty
        ? customerName[0].toUpperCase()
        : '?';

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
                      Icon(statusIcon, size: 12, color: statusColor),
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

            // ✅ User time reference (only if different)
            if (hasUserTime)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Your time: $userStartTime - $userEndTime',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.blue[300] : Colors.blue[700],
                  ),
                ),
              ),
            const SizedBox(height: 8),

            // Customer Info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      isDark ? Colors.grey[800] : Colors.grey[200],
                  backgroundImage: appointment['customer_avatar'] != null
                      ? CachedNetworkImageProvider(
                          appointment['customer_avatar'])
                      : null,
                  child: appointment['customer_avatar'] == null
                      ? Text(
                          customerInitial,
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
                              customerName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white : Colors.black87,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appointment['service_name'] ??
                                  'Unknown Service',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // ✅ Service count badge
                          if (serviceCount > 1)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$serviceCount services',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
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
                  label: _formatPrice(appointment['price']),
                  color: Colors.green,
                ),
                if (appointment['variant_label']?.isNotEmpty ?? false)
                  _buildDetailChip(
                    icon: Icons.people,
                    label: appointment['variant_label'],
                    color: Colors.purple,
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
    // ✅ Use a reference date for recurring schedule TZ conversion
    final referenceDate = DateTime(2024, 1, 1);

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
                // ✅ Recurring schedules use reference date
                final startTime = _formatUtcToLocalTimeForDate(
                  schedule['start_time'] as String?,
                  referenceDate,
                  _salonTimezone,
                );
                final endTime = _formatUtcToLocalTimeForDate(
                  schedule['end_time'] as String?,
                  referenceDate,
                  _salonTimezone,
                );

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
  // ✅ Salon timezone main + user reference (only if different)
  // ============================================================

  Widget _buildTimezoneInfoCard() {
    final isDark = context.isDarkMode;
    final showUserTz = _isDifferentTimezone;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Salon timezone (MAIN)
          Row(
            children: [
              Icon(
                Icons.store,
                size: 16,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⏰ Salon times: ${_getSalonTimezoneDisplay()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),

          // ✅ User timezone reference (only if different)
          if (showUserTz) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.person,
                    size: 14,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are in: ${_getUserTimezoneDisplay()}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[700],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Main times are for salon location',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: DATE NAVIGATOR
  // ✅ isToday based on salon timezone
  // ============================================================

  Widget _buildDateNavigator() {
    final isDark = context.isDarkMode;
    final salonToday = _salonToday;
    final isToday = _selectedDate.isAtSameMomentAs(salonToday);

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
                      child: const Text(
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
  // ✅ isToday/isYesterday/isTomorrow based on salon timezone
  // ============================================================

  Widget _buildAppointmentsSection() {
    final isDark = context.isDarkMode;

    // ✅ Use salon today for relative day detection
    final salonToday = _salonToday;
    final isToday = _selectedDate.isAtSameMomentAs(salonToday);
    final isYesterday = _selectedDate.isAtSameMomentAs(
      salonToday.subtract(const Duration(days: 1)),
    );
    final isTomorrow = _selectedDate.isAtSameMomentAs(
      salonToday.add(const Duration(days: 1)),
    );

    String title;
    if (isToday) {
      title = "Today's Appointments";
    } else if (isYesterday) {
      title = "Yesterday's Appointments";
    } else if (isTomorrow) {
      title = "Tomorrow's Appointments";
    } else {
      title = '${DateFormat('MMM dd').format(_selectedDate)} Appointments';
    }

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
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                      'No appointments',
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
  // ✅ null-safe date parsing + specific date TZ conversion
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
                // ✅ null-safe date parsing
                final dateStr = schedule['schedule_date'] as String?;
                if (dateStr == null || dateStr.isEmpty) {
                  return const SizedBox.shrink();
                }

                DateTime date;
                try {
                  date = DateTime.parse(dateStr);
                } catch (_) {
                  return const SizedBox.shrink();
                }

                final isWorking = schedule['is_working'] ?? true;
                final reason = schedule['reason'] ?? 'Special day';

                // ✅ Specific date TZ conversion for special schedules
                final startTime = _formatUtcToLocalTimeForDate(
                  schedule['start_time'] as String?,
                  date,
                  _salonTimezone,
                );
                final endTime = _formatUtcToLocalTimeForDate(
                  schedule['end_time'] as String?,
                  date,
                  _salonTimezone,
                );

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
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
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
                                    color: isWorking
                                        ? Colors.green
                                        : Colors.red,
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
                            if (isWorking)
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
                                    color: isDark
                                        ? Colors.blue[300]
                                        : Colors.blue[700],
                                  ),
                                ),
                              ),
                            if (reason.isNotEmpty)
                              Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey[500],
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
  // ✅ BUILD: REGULAR BREAKS SECTION
  // ✅ Recurring TZ conversion via reference date
  // ============================================================

  Widget _buildRegularBreaksSection() {
    final isDark = context.isDarkMode;
    // ✅ Use reference date for recurring breaks
    final referenceDate = DateTime(2024, 1, 1);

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
                          children: breaks.map((breakItem) {
                            // ✅ Recurring breaks use reference date
                            final startTime = _formatUtcToLocalTimeForDate(
                              breakItem['start_time'] as String?,
                              referenceDate,
                              _salonTimezone,
                            );
                            final endTime = _formatUtcToLocalTimeForDate(
                              breakItem['end_time'] as String?,
                              referenceDate,
                              _salonTimezone,
                            );
                            final breakType =
                                breakItem['break_type'] ?? 'Break';

                            // ✅ Break type icon + label
                            IconData icon;
                            String label;
                            switch (breakType) {
                              case 'lunch':
                                icon = Icons.lunch_dining;
                                label = 'Lunch';
                                break;
                              case 'tea':
                                icon = Icons.coffee;
                                label = 'Tea';
                                break;
                              default:
                                icon = Icons.free_breakfast;
                                label = 'Custom';
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
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
                                      color: isDark
                                          ? Colors.grey[800]
                                          : Colors.grey[200],
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey[600],
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
  // ✅ null-safe date parsing + specific date TZ
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
                // ✅ null-safe date parsing
                final dateStr = breakItem['break_date'] as String?;
                if (dateStr == null || dateStr.isEmpty) {
                  return const SizedBox.shrink();
                }

                DateTime date;
                try {
                  date = DateTime.parse(dateStr);
                } catch (_) {
                  return const SizedBox.shrink();
                }

                // ✅ Specific date TZ conversion
                final startTime = _formatUtcToLocalTimeForDate(
                  breakItem['start_time'] as String?,
                  date,
                  _salonTimezone,
                );
                final endTime = _formatUtcToLocalTimeForDate(
                  breakItem['end_time'] as String?,
                  date,
                  _salonTimezone,
                );
                final breakType = breakItem['break_type'] ?? 'custom';

                String breakTypeLabel = 'Custom';
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
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
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
                                  color: Colors.teal
                                      .withValues(alpha: 0.3),
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
                                      color: isDark
                                          ? Colors.teal[300]
                                          : Colors.teal[700],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.grey[800]
                                          : Colors.grey[200],
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      breakTypeLabel,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey[600],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Something went wrong',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
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
  // ✅ BUILD: CONTENT
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

        // Appointments
        _buildAppointmentsSection(),
        const SizedBox(height: 16),

        // Regular Schedule
        _buildRegularScheduleSection(),
        const SizedBox(height: 16),

        // Special Schedules
        if (_specialSchedules.isNotEmpty) ...[
          _buildSpecialSchedulesSection(),
          const SizedBox(height: 16),
        ],

        // Regular Breaks
        if (_regularBreaks.isNotEmpty) ...[
          _buildRegularBreaksSection(),
          const SizedBox(height: 16),
        ],

        // Special Breaks
        if (_specialBreaks.isNotEmpty) _buildSpecialBreaksSection(),
      ],
    );
  }

  // ============================================================
  // ✅ BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          _salonName != null ? 'My Schedule - $_salonName' : 'My Schedule',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
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
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
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