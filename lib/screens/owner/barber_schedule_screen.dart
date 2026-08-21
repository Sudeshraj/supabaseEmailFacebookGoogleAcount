import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class BarberScheduleScreen extends StatefulWidget {
  final String? salonId;

  const BarberScheduleScreen({super.key, this.salonId});

  @override
  State<BarberScheduleScreen> createState() => _BarberScheduleScreenState();
}

class _BarberScheduleScreenState extends State<BarberScheduleScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _barbers = [];
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _specialSchedules = [];
  List<Map<String, dynamic>> _specialBreaks = [];
  Map<String, List<Map<String, dynamic>>> _groupedSchedules = {};
  Map<String, List<Map<String, dynamic>>> _groupedBreaks = {};
  Map<String, List<Map<String, dynamic>>> _groupedSpecialSchedules = {};
  Map<String, List<Map<String, dynamic>>> _groupedSpecialBreaks = {};

  // ============================================
  // TIMEZONE VARIABLES
  // ============================================
  String _salonTimezone = '';
  String _userTimezone = '';

  // Salon default times (Local for display)
  TimeOfDay? _salonOpenTimeLocal;
  TimeOfDay? _salonCloseTimeLocal;

  // ============================================
  // RESPONSIVE VARIABLES
  // ============================================
  bool _isWeb = false;
  bool _isDark = false;

  // Days of week mapping
  final Map<int, String> _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  // Break types
  final List<Map<String, dynamic>> _breakTypes = [
    {'id': 'lunch', 'name': '🍽️ Lunch Break', 'icon': Icons.lunch_dining},
    {'id': 'tea', 'name': '☕ Tea Break', 'icon': Icons.coffee},
    {'id': 'custom', 'name': '📝 Custom Break', 'icon': Icons.free_breakfast},
  ];

  // ============================================
  // SCROLL CONTROLLER FOR WEB
  // ============================================
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeTimezones();
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

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================

  Future<void> _initializeTimezones() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString('user_timezone') ??
        TimezoneService.getCurrentTimezone();

    debugPrint('✅ User timezone: $_userTimezone');

    await _loadData();
  }

  // ============================================
  // TIMEZONE CONVERSION
  // ============================================

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

  TimeOfDay _utcToLocalTimeOfDay(String utcTime) {
    return TimezoneService.utcToTimeOfDayWithTimezone(utcTime, _salonTimezone);
  }

  String _getTimezoneDisplay() {
    return TimezoneService.getFullTimezoneDisplay();
  }

  // ============================================
  // LOAD DATA
  // ============================================

  Future<void> _loadSalonTimes() async {
    if (widget.salonId == null) return;

    try {
      final salonIdInt = int.parse(widget.salonId!);
      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time, timezone')
          .eq('id', salonIdInt)
          .maybeSingle();

      if (salonResponse != null) {
        _salonTimezone =
            salonResponse['timezone'] ?? TimezoneService.getCurrentTimezone();

        final openTimeStr = salonResponse['open_time'] as String?;
        if (openTimeStr != null) {
          _salonOpenTimeLocal = _utcToLocalTimeOfDay(openTimeStr);
        }

        final closeTimeStr = salonResponse['close_time'] as String?;
        if (closeTimeStr != null) {
          _salonCloseTimeLocal = _utcToLocalTimeOfDay(closeTimeStr);
        }
      }
    } catch (e) {
      debugPrint('Error loading salon times: $e');
    }
  }

  Future<void> _loadData() async {
    if (widget.salonId == null) {
      setState(() {
        _barbers = [];
        _schedules = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId!);
      await _loadSalonTimes();

      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('''
          id,
          barber_id,
          status,
          profiles!inner (
            id,
            full_name,
            email,
            avatar_url,
            user_roles!inner (
              status
            )
          )
        ''')
          .eq('salon_id', salonIdInt)
          .eq('status', 'active')
          .eq('profiles.user_roles.role_id', 2)
          .eq('profiles.user_roles.status', 'active');

      if (salonBarbersResponse.isEmpty) {
        setState(() {
          _barbers = [];
          _schedules = [];
          _isLoading = false;
        });
        return;
      }

      final List<Map<String, dynamic>> barbersList = [];
      for (var sb in salonBarbersResponse) {
        final profile = sb['profiles'] as Map?;
        if (profile == null) continue;

        final userRoles = profile['user_roles'] as List? ?? [];
        bool isActive = false;
        for (var role in userRoles) {
          if (role['status'] == 'active') {
            isActive = true;
            break;
          }
        }

        if (!isActive) continue;

        barbersList.add({
          'id': profile['id'],
          'salon_barber_id': sb['id'],
          'name': profile['full_name'] ?? 'Unknown',
          'email': profile['email'],
          'avatar': profile['avatar_url'],
          'status': sb['status'],
        });
      }

      _barbers = barbersList;

      if (_barbers.isNotEmpty) {
        await _loadAllDataForBarbers(salonIdInt);
      }
    } catch (e) {
      debugPrint('Error loading schedules: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _isDark ? Colors.red[700] : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAllDataForBarbers(int salonIdInt) async {
    final schedulesResponse = await supabase
        .from('barber_schedules')
        .select()
        .eq('salon_id', salonIdInt)
        .order('day_of_week');

    _schedules = List<Map<String, dynamic>>.from(schedulesResponse);
    _groupedSchedules = {};
    for (var schedule in _schedules) {
      final barberId = schedule['barber_id'] as String;
      if (!_groupedSchedules.containsKey(barberId)) {
        _groupedSchedules[barberId] = [];
      }
      _groupedSchedules[barberId]!.add(schedule);
    }

    final breaksResponse = await supabase
        .from('barber_breaks')
        .select()
        .eq('salon_id', salonIdInt)
        .order('day_of_week');

    _groupedBreaks = {};
    for (var breakItem in breaksResponse) {
      final barberId = breakItem['barber_id'] as String;
      if (!_groupedBreaks.containsKey(barberId)) {
        _groupedBreaks[barberId] = [];
      }
      _groupedBreaks[barberId]!.add(breakItem);
    }

    final specialSchedulesResponse = await supabase
        .from('barber_special_schedules')
        .select()
        .eq('salon_id', salonIdInt)
        .order('schedule_date');

    _specialSchedules = List<Map<String, dynamic>>.from(
      specialSchedulesResponse,
    );
    _groupedSpecialSchedules = {};
    for (var ss in _specialSchedules) {
      final barberId = ss['barber_id'] as String;
      if (!_groupedSpecialSchedules.containsKey(barberId)) {
        _groupedSpecialSchedules[barberId] = [];
      }
      _groupedSpecialSchedules[barberId]!.add(ss);
    }

    final specialBreaksResponse = await supabase
        .from('barber_special_breaks')
        .select()
        .eq('salon_id', salonIdInt)
        .order('break_date');

    _specialBreaks = List<Map<String, dynamic>>.from(specialBreaksResponse);
    _groupedSpecialBreaks = {};
    for (var sb in _specialBreaks) {
      final barberId = sb['barber_id'] as String;
      if (!_groupedSpecialBreaks.containsKey(barberId)) {
        _groupedSpecialBreaks[barberId] = [];
      }
      _groupedSpecialBreaks[barberId]!.add(sb);
    }
  }

  // ==================== UPDATE SINGLE BARBER DATA ====================

  Future<void> _updateBarberData(String barberId) async {
    try {
      final salonIdInt = int.parse(widget.salonId!);

      final schedulesResponse = await supabase
          .from('barber_schedules')
          .select()
          .eq('salon_id', salonIdInt)
          .eq('barber_id', barberId)
          .order('day_of_week');

      final breaksResponse = await supabase
          .from('barber_breaks')
          .select()
          .eq('salon_id', salonIdInt)
          .eq('barber_id', barberId)
          .order('day_of_week');

      final specialSchedulesResponse = await supabase
          .from('barber_special_schedules')
          .select()
          .eq('salon_id', salonIdInt)
          .eq('barber_id', barberId)
          .order('schedule_date');

      final specialBreaksResponse = await supabase
          .from('barber_special_breaks')
          .select()
          .eq('salon_id', salonIdInt)
          .eq('barber_id', barberId)
          .order('break_date');

      setState(() {
        _groupedSchedules[barberId] = List<Map<String, dynamic>>.from(
          schedulesResponse,
        );
        _groupedBreaks[barberId] = List<Map<String, dynamic>>.from(
          breaksResponse,
        );
        _groupedSpecialSchedules[barberId] = List<Map<String, dynamic>>.from(
          specialSchedulesResponse,
        );
        _groupedSpecialBreaks[barberId] = List<Map<String, dynamic>>.from(
          specialBreaksResponse,
        );

        final otherSchedules = _schedules
            .where((s) => s['barber_id'] != barberId)
            .toList();
        _schedules = [...otherSchedules, ..._groupedSchedules[barberId]!];

        final otherSpecialSchedules = _specialSchedules
            .where((ss) => ss['barber_id'] != barberId)
            .toList();
        _specialSchedules = [
          ...otherSpecialSchedules,
          ..._groupedSpecialSchedules[barberId]!,
        ];

        final otherSpecialBreaks = _specialBreaks
            .where((sb) => sb['barber_id'] != barberId)
            .toList();
        _specialBreaks = [
          ...otherSpecialBreaks,
          ..._groupedSpecialBreaks[barberId]!,
        ];
      });
    } catch (e) {
      debugPrint('Error updating barber data: $e');
      await _loadAllDataForBarbers(int.parse(widget.salonId!));
      if (mounted) setState(() {});
    }
  }

  // ==================== REGULAR SCHEDULE CRUD ====================

  Future<void> _addSchedule(String barberId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddScheduleDialog(
        barberId: barberId,
        salonId: widget.salonId!,
        salonTimezone: _salonTimezone,
        existingSchedules: _groupedSchedules[barberId] ?? [],
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(barberId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule added successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _addBreak(String barberId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddBreakDialog(
        barberId: barberId,
        salonId: widget.salonId!,
        salonTimezone: _salonTimezone,
        existingBreaks: _groupedBreaks[barberId] ?? [],
        breakTypes: _breakTypes,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(barberId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Break added successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _editSchedule(Map<String, dynamic> schedule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditScheduleDialog(
        schedule: schedule,
        salonTimezone: _salonTimezone,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(schedule['barber_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _editBreak(Map<String, dynamic> breakItem) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditBreakDialog(
        breakItem: breakItem,
        salonTimezone: _salonTimezone,
        breakTypes: _breakTypes,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(breakItem['barber_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Break updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleWorkingStatus(Map<String, dynamic> schedule) async {
    final bool newStatus = !(schedule['is_working'] ?? true);

    setState(() {
      final barberId = schedule['barber_id'] as String;
      if (_groupedSchedules.containsKey(barberId)) {
        final scheduleIndex = _groupedSchedules[barberId]!.indexWhere(
          (s) => s['id'] == schedule['id'],
        );
        if (scheduleIndex != -1) {
          _groupedSchedules[barberId]![scheduleIndex]['is_working'] = newStatus;
        }
      }
    });

    try {
      await supabase
          .from('barber_schedules')
          .update({'is_working': newStatus})
          .eq('id', schedule['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus ? 'Working day enabled' : 'Working day disabled',
            ),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      await _updateBarberData(schedule['barber_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Schedule',
          style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Are you sure you want to delete this schedule?',
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: _isDark ? Colors.red[300] : Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('barber_schedules')
            .delete()
            .eq('id', schedule['id']);
        await _updateBarberData(schedule['barber_id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule deleted'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting schedule: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteBreak(Map<String, dynamic> breakItem) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Break',
          style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Are you sure you want to delete this break?',
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: _isDark ? Colors.red[300] : Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('barber_breaks').delete().eq('id', breakItem['id']);
        await _updateBarberData(breakItem['barber_id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Break deleted'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting break: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ==================== SPECIAL SCHEDULE CRUD ====================

  Future<void> _addSpecialSchedule(String barberId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddSpecialScheduleDialog(
        barberId: barberId,
        salonId: widget.salonId!,
        salonTimezone: _salonTimezone,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(barberId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Special schedule added successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _addSpecialBreak(String barberId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddSpecialBreakDialog(
        barberId: barberId,
        salonId: widget.salonId!,
        salonTimezone: _salonTimezone,
        breakTypes: _breakTypes,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(barberId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Special break added successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _editSpecialSchedule(Map<String, dynamic> schedule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditSpecialScheduleDialog(
        schedule: schedule,
        salonTimezone: _salonTimezone,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(schedule['barber_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Special schedule updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _editSpecialBreak(Map<String, dynamic> breakItem) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditSpecialBreakDialog(
        breakItem: breakItem,
        salonTimezone: _salonTimezone,
        breakTypes: _breakTypes,
        defaultOpenTime: _salonOpenTimeLocal,
        defaultCloseTime: _salonCloseTimeLocal,
        isDark: _isDark,
      ),
    );

    if (result != null && result['success'] == true) {
      await _updateBarberData(breakItem['barber_id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Special break updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _deleteSpecialSchedule(Map<String, dynamic> schedule) async {
    final date = DateTime.parse(schedule['schedule_date']);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Special Schedule',
          style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Delete special schedule for ${DateFormat('yyyy-MM-dd').format(date)}?',
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: _isDark ? Colors.red[300] : Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('barber_special_schedules')
            .delete()
            .eq('id', schedule['id']);
        await _updateBarberData(schedule['barber_id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Special schedule deleted'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting special schedule: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteSpecialBreak(Map<String, dynamic> breakItem) async {
    final date = DateTime.parse(breakItem['break_date']);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Special Break',
          style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Delete special break for ${DateFormat('yyyy-MM-dd').format(date)}?',
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: _isDark ? Colors.red[300] : Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('barber_special_breaks')
            .delete()
            .eq('id', breakItem['id']);
        await _updateBarberData(breakItem['barber_id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Special break deleted'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting special break: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ==================== UI HELPERS ====================

  String _formatTime(String? time) {
    return _formatUtcToLocalTime(time);
  }

  // ==================== BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final double padding = _isWeb ? 24.0 : 0.0;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Barber Schedules',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
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
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading schedules...',
                    style: TextStyle(
                      color: _isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : _barbers.isEmpty
          ? _buildEmptyState(padding)
          : SafeArea(
              child: _isWeb
                  ? _buildWebView(padding, screenWidth)
                  : _buildMobileView(),
            ),
    );
  }

  Widget _buildEmptyState(double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: _isWeb ? 80 : 64,
              color: _isDark ? Colors.white30 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No barbers found',
              style: TextStyle(
                fontSize: 18,
                color: _isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add barbers first to manage schedules',
              style: TextStyle(
                color: _isDark ? Colors.white70 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimezoneInfoCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              size: 16,
              color: _isDark ? Colors.white70 : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⏰ Times shown in: ${_getTimezoneDisplay()}',
                style: TextStyle(
                  fontSize: 12,
                  color: _isDark ? Colors.white60 : Colors.grey,
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
                  style: const TextStyle(fontSize: 10, color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(double padding, double screenWidth) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimezoneInfoCard(),
          Card(
            color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _buildStatItem(
                    Icons.people,
                    'Barbers',
                    _barbers.length,
                    AppTheme.primary,
                  ),
                  _buildStatItem(
                    Icons.schedule,
                    'Schedules',
                    _schedules.length,
                    Colors.green,
                  ),
                  _buildStatItem(
                    Icons.free_breakfast,
                    'Breaks',
                    _groupedBreaks.values.expand((i) => i).length,
                    Colors.orange,
                  ),
                  _buildStatItem(
                    Icons.event,
                    'Special Schedules',
                    _specialSchedules.length,
                    Colors.purple,
                  ),
                  _buildStatItem(
                    Icons.event_busy,
                    'Special Breaks',
                    _specialBreaks.length,
                    Colors.teal,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: screenWidth > 1200 ? 3 : 2,
              childAspectRatio: 1.3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _barbers.length,
            itemBuilder: (context, index) {
              final barber = _barbers[index];
              final barberSchedules = _groupedSchedules[barber['id']] ?? [];
              final barberBreaks = _groupedBreaks[barber['id']] ?? [];
              final barberSpecialSchedules =
                  _groupedSpecialSchedules[barber['id']] ?? [];
              final barberSpecialBreaks =
                  _groupedSpecialBreaks[barber['id']] ?? [];
              return _buildBarberCard(
                barber,
                barberSchedules,
                barberBreaks,
                barberSpecialSchedules,
                barberSpecialBreaks,
                true,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: _isDark ? Colors.white60 : Colors.grey,
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _buildTimezoneInfoCard(),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _barbers.length,
            itemBuilder: (context, index) {
              final barber = _barbers[index];
              return _buildMobileBarberCard(barber);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBarberCard(
    Map<String, dynamic> barber,
    List<Map<String, dynamic>> schedules,
    List<Map<String, dynamic>> breaks,
    List<Map<String, dynamic>> specialSchedules,
    List<Map<String, dynamic>> specialBreaks,
    bool isWeb,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: isWeb
          ? _buildWebBarberCard(
              barber,
              schedules,
              breaks,
              specialSchedules,
              specialBreaks,
            )
          : _buildMobileBarberCard(barber),
    );
  }

  Widget _buildWebBarberCard(
    Map<String, dynamic> barber,
    List<Map<String, dynamic>> schedules,
    List<Map<String, dynamic>> breaks,
    List<Map<String, dynamic>> specialSchedules,
    List<Map<String, dynamic>> specialBreaks,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                backgroundImage: barber['avatar'] != null
                    ? NetworkImage(barber['avatar'])
                    : null,
                child: barber['avatar'] == null
                    ? Text(
                        barber['name'][0].toUpperCase(),
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
                      barber['name'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${schedules.where((s) => s['is_working'] == true).length} Working / ${schedules.length} Regular',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Tooltip(
                    message: 'Add Special Break',
                    child: IconButton(
                      icon: Icon(Icons.event_busy, color: Colors.teal),
                      onPressed: () => _addSpecialBreak(barber['id']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  Tooltip(
                    message: 'Add Special Schedule',
                    child: IconButton(
                      icon: Icon(Icons.event, color: Colors.purple),
                      onPressed: () => _addSpecialSchedule(barber['id']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  Tooltip(
                    message: 'Add Break',
                    child: IconButton(
                      icon: Icon(Icons.free_breakfast, color: Colors.orange),
                      onPressed: () => _addBreak(barber['id']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  Tooltip(
                    message: 'Add Schedule',
                    child: IconButton(
                      icon: Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () => _addSchedule(barber['id']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (specialSchedules.isNotEmpty) ...[
                    _buildSectionHeader(
                      '🌟 Special Schedules',
                      Colors.purple,
                      Icons.event,
                    ),
                    ...specialSchedules.map(
                      (ss) => _buildSpecialScheduleItem(ss),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (specialBreaks.isNotEmpty) ...[
                    _buildSectionHeader(
                      '⏰ Special Breaks',
                      Colors.teal,
                      Icons.event_busy,
                    ),
                    ...specialBreaks.map((sb) => _buildSpecialBreakItem(sb)),
                    const SizedBox(height: 8),
                  ],
                  if (schedules.isNotEmpty) ...[
                    _buildSectionHeader(
                      '📅 Regular Schedules',
                      Colors.green,
                      Icons.schedule,
                    ),
                    ...schedules.map(
                      (schedule) => _buildScheduleItem(schedule),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (breaks.isNotEmpty) ...[
                    _buildSectionHeader(
                      '☕ Regular Breaks',
                      Colors.orange,
                      Icons.free_breakfast,
                    ),
                    ...breaks.map((breakItem) => _buildBreakItem(breakItem)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialScheduleItem(Map<String, dynamic> schedule) {
    final date = DateTime.parse(schedule['schedule_date']);
    final startTime = _formatTime(schedule['start_time']);
    final endTime = _formatTime(schedule['end_time']);
    final isWorking = schedule['is_working'] ?? true;
    final reason = schedule['reason'] ?? 'Special day';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.purple.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMM dd, yyyy').format(date),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  reason,
                  style: TextStyle(fontSize: 9, color: Colors.purple[600]),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$startTime - $endTime',
              style: TextStyle(
                fontSize: 11,
                color: _isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          if (!isWorking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Off',
                style: TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.edit,
              size: 14,
              color: _isDark ? Colors.white60 : Colors.grey,
            ),
            onPressed: () => _editSpecialSchedule(schedule),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.delete, size: 14, color: Colors.red),
            onPressed: () => _deleteSpecialSchedule(schedule),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialBreakItem(Map<String, dynamic> breakItem) {
    final date = DateTime.parse(breakItem['break_date']);
    final startTime = _formatTime(breakItem['start_time']);
    final endTime = _formatTime(breakItem['end_time']);
    final breakType = breakItem['break_type'] ?? 'custom';
    final breakTypeData = _breakTypes.firstWhere(
      (b) => b['id'] == breakType,
      orElse: () => _breakTypes.last,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.teal.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMM dd, yyyy').format(date),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  breakTypeData['name'],
                  style: TextStyle(fontSize: 9, color: Colors.teal[600]),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$startTime - $endTime',
              style: TextStyle(
                fontSize: 11,
                color: _isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.edit,
              size: 14,
              color: _isDark ? Colors.white60 : Colors.grey,
            ),
            onPressed: () => _editSpecialBreak(breakItem),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.delete, size: 14, color: Colors.red),
            onPressed: () => _deleteSpecialBreak(breakItem),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItem(Map<String, dynamic> schedule) {
    final dayName = _dayNames[schedule['day_of_week']] ?? 'Unknown';
    final startTime = _formatTime(schedule['start_time']);
    final endTime = _formatTime(schedule['end_time']);
    final isWorking = schedule['is_working'] ?? true;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isWorking
            ? Colors.green.withValues(alpha: 0.05)
            : Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWorking
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: isMobile ? 3 : 2,
            child: Row(
              children: [
                Icon(
                  isWorking ? Icons.check_circle : Icons.cancel,
                  size: isMobile ? 12 : 14,
                  color: isWorking ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  isMobile ? dayName.substring(0, 3) : dayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 11 : 12,
                    color: isWorking
                        ? (_isDark ? Colors.white : Colors.black87)
                        : (_isDark ? Colors.white70 : Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            Expanded(
              flex: 3,
              child: Text(
                '$startTime - $endTime',
                style: TextStyle(
                  fontSize: 11,
                  color: isWorking
                      ? (_isDark ? Colors.white70 : Colors.grey[700])
                      : (_isDark ? Colors.white70 : Colors.grey[500]),
                  decoration: isWorking ? null : TextDecoration.lineThrough,
                ),
              ),
            )
          else
            Expanded(
              flex: 4,
              child: Text(
                '$startTime - $endTime',
                style: TextStyle(
                  fontSize: 10,
                  color: isWorking
                      ? (_isDark ? Colors.white70 : Colors.grey[700])
                      : (_isDark ? Colors.white70 : Colors.grey[500]),
                  decoration: isWorking ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
          SizedBox(
            width: isMobile ? 35 : 40,
            height: isMobile ? 25 : 30,
            child: Transform.scale(
              scale: isMobile ? 0.6 : 0.7,
              child: Switch(
                value: isWorking,
                onChanged: (_) => _toggleWorkingStatus(schedule),
                activeThumbColor: Colors.green,
                inactiveThumbColor: Colors.red,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.edit,
              size: isMobile ? 16 : 18,
              color: _isDark ? Colors.white60 : Colors.grey,
            ),
            onPressed: () => _editSchedule(schedule),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(
              Icons.delete,
              size: isMobile ? 16 : 18,
              color: Colors.red,
            ),
            onPressed: () => _deleteSchedule(schedule),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakItem(Map<String, dynamic> breakItem) {
    final dayName = _dayNames[breakItem['day_of_week']] ?? 'Unknown';
    final startTime = _formatTime(breakItem['start_time']);
    final endTime = _formatTime(breakItem['end_time']);
    final breakType = breakItem['break_type'] ?? 'custom';
    final breakTypeData = _breakTypes.firstWhere(
      (b) => b['id'] == breakType,
      orElse: () => _breakTypes.last,
    );
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: isMobile ? 3 : 2,
            child: Row(
              children: [
                Icon(
                  breakTypeData['icon'],
                  size: isMobile ? 12 : 14,
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  isMobile ? dayName.substring(0, 3) : dayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 11 : 12,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$startTime - $endTime',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isDark ? Colors.white70 : Colors.grey,
                    ),
                  ),
                  Text(
                    breakTypeData['name'],
                    style: TextStyle(fontSize: 10, color: Colors.orange),
                  ),
                ],
              ),
            )
          else
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$startTime - $endTime',
                    style: TextStyle(
                      fontSize: 10,
                      color: _isDark ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  Text(
                    breakTypeData['name'],
                    style: const TextStyle(fontSize: 9, color: Colors.orange),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.edit,
              size: isMobile ? 16 : 18,
              color: _isDark ? Colors.white60 : Colors.grey,
            ),
            onPressed: () => _editBreak(breakItem),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(
              Icons.delete,
              size: isMobile ? 16 : 18,
              color: Colors.red,
            ),
            onPressed: () => _deleteBreak(breakItem),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBarberCard(Map<String, dynamic> barber) {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = screenWidth < 400
        ? 16.0
        : (screenWidth < 600 ? 18.0 : 20.0);

    return Card(
      margin: const EdgeInsets.all(0),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: InkWell(
        onTap: () {
          _showBarberScheduleDialog(barber);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: screenWidth < 400 ? 30 : 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: screenWidth < 400 ? 40 : 50,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                backgroundImage: barber['avatar'] != null
                    ? NetworkImage(barber['avatar'])
                    : null,
                child: barber['avatar'] == null
                    ? Text(
                        barber['name'][0].toUpperCase(),
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize + 8,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                barber['name'],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize,
                  color: _isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.arrow_forward,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBarberScheduleDialog(Map<String, dynamic> barber) {
    final schedules = _groupedSchedules[barber['id']] ?? [];
    final breaks = _groupedBreaks[barber['id']] ?? [];
    final specialSchedules = _groupedSpecialSchedules[barber['id']] ?? [];
    final specialBreaks = _groupedSpecialBreaks[barber['id']] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _isDark ? Colors.white12 : Colors.grey[200]!,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primary.withValues(
                          alpha: 0.1,
                        ),
                        backgroundImage: barber['avatar'] != null
                            ? NetworkImage(barber['avatar'])
                            : null,
                        child: barber['avatar'] == null
                            ? Text(
                                barber['name'][0].toUpperCase(),
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
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
                              barber['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              '${schedules.where((s) => s['is_working'] == true).length} Working / ${schedules.length} Regular',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: _isDark ? Colors.white : Colors.grey,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildActionChip(
                            'Special Break',
                            Icons.event_busy,
                            Colors.teal,
                            () => _addSpecialBreak(barber['id']),
                          ),
                          _buildActionChip(
                            'Special Schedule',
                            Icons.event,
                            Colors.purple,
                            () => _addSpecialSchedule(barber['id']),
                          ),
                          _buildActionChip(
                            'Break',
                            Icons.free_breakfast,
                            Colors.orange,
                            () => _addBreak(barber['id']),
                          ),
                          _buildActionChip(
                            'Schedule',
                            Icons.add,
                            Colors.green,
                            () => _addSchedule(barber['id']),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (specialSchedules.isNotEmpty) ...[
                        _buildSectionHeader(
                          '🌟 Special Schedules',
                          Colors.purple,
                          Icons.event,
                        ),
                        const SizedBox(height: 8),
                        ...specialSchedules.map(
                          (ss) => _buildSpecialScheduleItem(ss),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (specialBreaks.isNotEmpty) ...[
                        _buildSectionHeader(
                          '⏰ Special Breaks',
                          Colors.teal,
                          Icons.event_busy,
                        ),
                        const SizedBox(height: 8),
                        ...specialBreaks.map(
                          (sb) => _buildSpecialBreakItem(sb),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (schedules.isNotEmpty) ...[
                        _buildSectionHeader(
                          '📅 Regular Schedules',
                          Colors.green,
                          Icons.schedule,
                        ),
                        const SizedBox(height: 8),
                        ...schedules.map(
                          (schedule) => _buildScheduleItem(schedule),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (breaks.isNotEmpty) ...[
                        _buildSectionHeader(
                          '☕ Regular Breaks',
                          Colors.orange,
                          Icons.free_breakfast,
                        ),
                        const SizedBox(height: 8),
                        ...breaks.map(
                          (breakItem) => _buildBreakItem(breakItem),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionChip(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
      ),
      onPressed: onPressed,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}

// ============================================
// ✅ ALL DIALOGS WITH DARK MODE SUPPORT
// ============================================

// ==================== ADD SCHEDULE DIALOG ====================
class _AddScheduleDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final String salonTimezone;
  final List<Map<String, dynamic>> existingSchedules;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _AddScheduleDialog({
    required this.barberId,
    required this.salonId,
    required this.salonTimezone,
    required this.existingSchedules,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends State<_AddScheduleDialog> {
  final supabase = Supabase.instance.client;

  int? _selectedDay;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isWorking = true;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _days = const [
    {'id': 1, 'name': 'Monday'},
    {'id': 2, 'name': 'Tuesday'},
    {'id': 3, 'name': 'Wednesday'},
    {'id': 4, 'name': 'Thursday'},
    {'id': 5, 'name': 'Friday'},
    {'id': 6, 'name': 'Saturday'},
    {'id': 7, 'name': 'Sunday'},
  ];

  List<int> get _availableDays {
    final existingDays = widget.existingSchedules
        .where((s) => s['day_of_week'] != null)
        .map((s) => s['day_of_week'] as int)
        .toSet();
    return _days
        .where((d) => !existingDays.contains(d['id']))
        .map((d) => d['id'] as int)
        .toList();
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  void initState() {
    super.initState();
    _startTime = widget.defaultOpenTime;
    _endTime = widget.defaultCloseTime;
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Schedule',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Day',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _days.map((day) {
                  final isSelected = _selectedDay == day['id'];
                  final isAvailable = _availableDays.contains(day['id']);
                  return FilterChip(
                    label: Text(
                      day['name'],
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: isAvailable
                        ? (selected) => setState(() => _selectedDay = day['id'])
                        : null,
                    backgroundColor: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[100],
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primary,
                    avatar: isAvailable
                        ? null
                        : Icon(
                            Icons.lock,
                            size: 16,
                            color: widget.isDark ? Colors.white30 : Colors.grey,
                          ),
                  );
                }).toList(),
              ),
              if (_availableDays.isEmpty && _selectedDay == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'All days already have schedules!',
                    style: TextStyle(
                      color: widget.isDark
                          ? Colors.orange[300]
                          : Colors.orange[700],
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      onTimeSelected: (time) =>
                          setState(() => _startTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      onTimeSelected: (time) => setState(() => _endTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isWorking
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isWorking
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isWorking ? Icons.check_circle : Icons.cancel,
                      color: _isWorking ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Working Day',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isWorking ? Colors.green : Colors.red,
                            ),
                          ),
                          Text(
                            _isWorking
                                ? 'This day will be available for bookings'
                                : 'This day will be marked as day off',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isWorking,
                      onChanged: (value) => setState(() => _isWorking = value),
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        (_selectedDay != null &&
                            _startTime != null &&
                            _endTime != null &&
                            !_isLoading)
                        ? _saveSchedule
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add Schedule'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSchedule() async {
    setState(() => _isLoading = true);
    try {
      final salonIdInt = int.parse(widget.salonId);
      final startTimeString = _localTimeToUtc(_startTime!);
      final endTimeString = _localTimeToUtc(_endTime!);

      await supabase.from('barber_schedules').insert({
        'barber_id': widget.barberId,
        'salon_id': salonIdInt,
        'day_of_week': _selectedDay,
        'start_time': startTimeString,
        'end_time': endTimeString,
        'is_working': _isWorking,
      });
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error saving schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== EDIT SCHEDULE DIALOG ====================
class _EditScheduleDialog extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final String salonTimezone;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _EditScheduleDialog({
    required this.schedule,
    required this.salonTimezone,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_EditScheduleDialog> createState() => _EditScheduleDialogState();
}

class _EditScheduleDialogState extends State<_EditScheduleDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _isWorking;
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _startTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.schedule['start_time'],
      widget.salonTimezone,
    );
    _endTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.schedule['end_time'],
      widget.salonTimezone,
    );
    _isWorking = widget.schedule['is_working'] ?? true;
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;
    final dayNames = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    final dayName = dayNames[widget.schedule['day_of_week']] ?? 'Unknown';

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Schedule - $dayName',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      onTimeSelected: (time) =>
                          setState(() => _startTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      onTimeSelected: (time) => setState(() => _endTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isWorking
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isWorking
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isWorking ? Icons.check_circle : Icons.cancel,
                      color: _isWorking ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Working Day',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isWorking ? Colors.green : Colors.red,
                            ),
                          ),
                          Text(
                            _isWorking
                                ? 'This day will be available for bookings'
                                : 'This day will be marked as day off',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isWorking,
                      onChanged: (value) => setState(() => _isWorking = value),
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update Schedule'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateSchedule() async {
    setState(() => _isLoading = true);
    try {
      final startTimeString = _localTimeToUtc(_startTime);
      final endTimeString = _localTimeToUtc(_endTime);

      await supabase
          .from('barber_schedules')
          .update({
            'start_time': startTimeString,
            'end_time': endTimeString,
            'is_working': _isWorking,
          })
          .eq('id', widget.schedule['id']);
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error updating schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== ADD BREAK DIALOG ====================
class _AddBreakDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final String salonTimezone;
  final List<Map<String, dynamic>> existingBreaks;
  final List<Map<String, dynamic>> breakTypes;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _AddBreakDialog({
    required this.barberId,
    required this.salonId,
    required this.salonTimezone,
    required this.existingBreaks,
    required this.breakTypes,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_AddBreakDialog> createState() => _AddBreakDialogState();
}

class _AddBreakDialogState extends State<_AddBreakDialog> {
  final supabase = Supabase.instance.client;

  int? _selectedDay;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _selectedBreakType = 'lunch';
  bool _isLoading = false;

  final List<Map<String, dynamic>> _days = const [
    {'id': 1, 'name': 'Monday'},
    {'id': 2, 'name': 'Tuesday'},
    {'id': 3, 'name': 'Wednesday'},
    {'id': 4, 'name': 'Thursday'},
    {'id': 5, 'name': 'Friday'},
    {'id': 6, 'name': 'Saturday'},
    {'id': 7, 'name': 'Sunday'},
  ];

  List<int> get _availableDays {
    final existingDays = widget.existingBreaks
        .where((b) => b['day_of_week'] != null)
        .map((b) => b['day_of_week'] as int)
        .toSet();
    return _days
        .where((d) => !existingDays.contains(d['id']))
        .map((d) => d['id'] as int)
        .toList();
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  void initState() {
    super.initState();
    _startTime = widget.defaultOpenTime;
    _endTime = widget.defaultCloseTime;
    if (_startTime != null && _endTime != null) {
      final lunchHour = _startTime!.hour + 4;
      if (lunchHour < _endTime!.hour) {
        _startTime = TimeOfDay(hour: lunchHour, minute: 0);
        _endTime = TimeOfDay(hour: lunchHour + 1, minute: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Break',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Break Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.breakTypes.map((type) {
                  final isSelected = _selectedBreakType == type['id'];
                  return FilterChip(
                    label: Text(
                      type['name'],
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBreakType = type['id']);
                      }
                    },
                    avatar: Icon(
                      type['icon'],
                      size: 18,
                      color: isSelected ? AppTheme.primary : Colors.grey,
                    ),
                    backgroundColor: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[100],
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Day',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _days.map((day) {
                  final isSelected = _selectedDay == day['id'];
                  final isAvailable = _availableDays.contains(day['id']);
                  return FilterChip(
                    label: Text(
                      day['name'],
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: isAvailable
                        ? (selected) => setState(() => _selectedDay = day['id'])
                        : null,
                    backgroundColor: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[100],
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primary,
                    avatar: isAvailable
                        ? null
                        : Icon(
                            Icons.lock,
                            size: 16,
                            color: widget.isDark ? Colors.white30 : Colors.grey,
                          ),
                  );
                }).toList(),
              ),
              if (_availableDays.isEmpty && _selectedDay == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'All days already have breaks!',
                    style: TextStyle(
                      color: widget.isDark
                          ? Colors.orange[300]
                          : Colors.orange[700],
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      onTimeSelected: (time) =>
                          setState(() => _startTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      onTimeSelected: (time) => setState(() => _endTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        (_selectedDay != null &&
                            _startTime != null &&
                            _endTime != null &&
                            !_isLoading)
                        ? _saveBreak
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add Break'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveBreak() async {
    setState(() => _isLoading = true);
    try {
      final salonIdInt = int.parse(widget.salonId);
      final startTimeString = _localTimeToUtc(_startTime!);
      final endTimeString = _localTimeToUtc(_endTime!);

      await supabase.from('barber_breaks').insert({
        'barber_id': widget.barberId,
        'salon_id': salonIdInt,
        'day_of_week': _selectedDay,
        'start_time': startTimeString,
        'end_time': endTimeString,
        'break_type': _selectedBreakType,
      });
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error saving break: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== EDIT BREAK DIALOG ====================
class _EditBreakDialog extends StatefulWidget {
  final Map<String, dynamic> breakItem;
  final String salonTimezone;
  final List<Map<String, dynamic>> breakTypes;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _EditBreakDialog({
    required this.breakItem,
    required this.salonTimezone,
    required this.breakTypes,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_EditBreakDialog> createState() => _EditBreakDialogState();
}

class _EditBreakDialogState extends State<_EditBreakDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _selectedBreakType;
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

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
    _startTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.breakItem['start_time'],
      widget.salonTimezone,
    );
    _endTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.breakItem['end_time'],
      widget.salonTimezone,
    );
    _selectedBreakType = widget.breakItem['break_type'] ?? 'lunch';
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;
    final dayName = _dayNames[widget.breakItem['day_of_week']] ?? 'Unknown';

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Break - $dayName',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Break Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.breakTypes.map((type) {
                  final isSelected = _selectedBreakType == type['id'];
                  return FilterChip(
                    label: Text(
                      type['name'],
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBreakType = type['id']);
                      }
                    },
                    avatar: Icon(
                      type['icon'],
                      size: 18,
                      color: isSelected ? AppTheme.primary : Colors.grey,
                    ),
                    backgroundColor: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[100],
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      onTimeSelected: (time) =>
                          setState(() => _startTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      onTimeSelected: (time) => setState(() => _endTime = time),
                      isDark: widget.isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateBreak,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update Break'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateBreak() async {
    setState(() => _isLoading = true);
    try {
      final startTimeString = _localTimeToUtc(_startTime);
      final endTimeString = _localTimeToUtc(_endTime);

      await supabase
          .from('barber_breaks')
          .update({
            'start_time': startTimeString,
            'end_time': endTimeString,
            'break_type': _selectedBreakType,
          })
          .eq('id', widget.breakItem['id']);
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error updating break: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== ADD SPECIAL SCHEDULE DIALOG (FIXED) ====================
class _AddSpecialScheduleDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final String salonTimezone;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _AddSpecialScheduleDialog({
    required this.barberId,
    required this.salonId,
    required this.salonTimezone,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_AddSpecialScheduleDialog> createState() =>
      _AddSpecialScheduleDialogState();
}

class _AddSpecialScheduleDialogState extends State<_AddSpecialScheduleDialog> {
  final supabase = Supabase.instance.client;

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isWorking = true;
  final TextEditingController _reasonController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startTime = widget.defaultOpenTime;
    _endTime = widget.defaultCloseTime;
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;
    final bool isMobile = !isWeb;

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.92,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Special Schedule',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Date',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => _selectedDate = date);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: _selectedDate != null
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.grey),
                        size: isMobile ? 20 : 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDate != null
                              ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
                              : 'Select date',
                          style: TextStyle(
                            color: widget.isDark
                                ? Colors.white
                                : Colors.black87,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: widget.isDark ? Colors.white70 : Colors.grey,
                        size: isMobile ? 20 : 24,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ✅ FIXED: Column layout for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        _TimePickerField(
                          label: 'Start Time',
                          initialTime: _startTime,
                          onTimeSelected: (time) =>
                              setState(() => _startTime = time),
                          isDark: widget.isDark,
                        ),
                        const SizedBox(height: 12),
                        _TimePickerField(
                          label: 'End Time',
                          initialTime: _endTime,
                          onTimeSelected: (time) =>
                              setState(() => _endTime = time),
                          isDark: widget.isDark,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _TimePickerField(
                            label: 'Start Time',
                            initialTime: _startTime,
                            onTimeSelected: (time) =>
                                setState(() => _startTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimePickerField(
                            label: 'End Time',
                            initialTime: _endTime,
                            onTimeSelected: (time) =>
                                setState(() => _endTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                style: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: 'Reason (e.g., Training, Holiday)',
                  labelStyle: TextStyle(
                    color: widget.isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primary, width: 2),
                  ),
                  fillColor: widget.isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
                  filled: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 10 : 14,
                  ),
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isWorking
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isWorking
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isWorking ? Icons.check_circle : Icons.cancel,
                      color: _isWorking ? Colors.green : Colors.red,
                      size: isMobile ? 20 : 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isWorking
                            ? 'Working on this day'
                            : 'Not working on this day',
                        style: TextStyle(
                          color: widget.isDark ? Colors.white : Colors.black87,
                          fontSize: isMobile ? 13 : 14,
                        ),
                      ),
                    ),
                    Switch(
                      value: _isWorking,
                      onChanged: (value) => setState(() => _isWorking = value),
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (_selectedDate != null &&
                                    _startTime != null &&
                                    _endTime != null &&
                                    !_isLoading)
                                ? _saveSpecialSchedule
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Add Special Schedule'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed:
                              (_selectedDate != null &&
                                  _startTime != null &&
                                  _endTime != null &&
                                  !_isLoading)
                              ? _saveSpecialSchedule
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Add Special Schedule'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSpecialSchedule() async {
    setState(() => _isLoading = true);
    try {
      final salonIdInt = int.parse(widget.salonId);
      final startTimeString = _localTimeToUtc(_startTime!);
      final endTimeString = _localTimeToUtc(_endTime!);

      await supabase.from('barber_special_schedules').insert({
        'barber_id': widget.barberId,
        'salon_id': salonIdInt,
        'schedule_date': _selectedDate!.toIso8601String().split('T').first,
        'start_time': startTimeString,
        'end_time': endTimeString,
        'is_working': _isWorking,
        'reason': _reasonController.text.isNotEmpty
            ? _reasonController.text
            : null,
      });
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error saving special schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== EDIT SPECIAL SCHEDULE DIALOG (FIXED) ====================
class _EditSpecialScheduleDialog extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final String salonTimezone;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _EditSpecialScheduleDialog({
    required this.schedule,
    required this.salonTimezone,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_EditSpecialScheduleDialog> createState() =>
      _EditSpecialScheduleDialogState();
}

class _EditSpecialScheduleDialogState
    extends State<_EditSpecialScheduleDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _isWorking;
  final TextEditingController _reasonController = TextEditingController();
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _startTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.schedule['start_time'],
      widget.salonTimezone,
    );
    _endTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.schedule['end_time'],
      widget.salonTimezone,
    );
    _isWorking = widget.schedule['is_working'] ?? true;
    _reasonController.text = widget.schedule['reason'] ?? '';
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;
    final bool isMobile = !isWeb;
    final date = DateTime.parse(widget.schedule['schedule_date']);

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.92,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Special Schedule - ${DateFormat('yyyy-MM-dd').format(date)}',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        _TimePickerField(
                          label: 'Start Time',
                          initialTime: _startTime,
                          onTimeSelected: (time) =>
                              setState(() => _startTime = time),
                          isDark: widget.isDark,
                        ),
                        const SizedBox(height: 12),
                        _TimePickerField(
                          label: 'End Time',
                          initialTime: _endTime,
                          onTimeSelected: (time) =>
                              setState(() => _endTime = time),
                          isDark: widget.isDark,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _TimePickerField(
                            label: 'Start Time',
                            initialTime: _startTime,
                            onTimeSelected: (time) =>
                                setState(() => _startTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimePickerField(
                            label: 'End Time',
                            initialTime: _endTime,
                            onTimeSelected: (time) =>
                                setState(() => _endTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                style: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: 'Reason',
                  labelStyle: TextStyle(
                    color: widget.isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primary, width: 2),
                  ),
                  fillColor: widget.isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
                  filled: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 10 : 14,
                  ),
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isWorking
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isWorking
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isWorking ? Icons.check_circle : Icons.cancel,
                      color: _isWorking ? Colors.green : Colors.red,
                      size: isMobile ? 20 : 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isWorking
                            ? 'Working on this day'
                            : 'Not working on this day',
                        style: TextStyle(
                          color: widget.isDark ? Colors.white : Colors.black87,
                          fontSize: isMobile ? 13 : 14,
                        ),
                      ),
                    ),
                    Switch(
                      value: _isWorking,
                      onChanged: (value) => setState(() => _isWorking = value),
                      activeThumbColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : _updateSpecialSchedule,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Update'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _updateSpecialSchedule,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Update'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateSpecialSchedule() async {
    setState(() => _isLoading = true);
    try {
      final startTimeString = _localTimeToUtc(_startTime);
      final endTimeString = _localTimeToUtc(_endTime);

      await supabase
          .from('barber_special_schedules')
          .update({
            'start_time': startTimeString,
            'end_time': endTimeString,
            'is_working': _isWorking,
            'reason': _reasonController.text.isNotEmpty
                ? _reasonController.text
                : null,
          })
          .eq('id', widget.schedule['id']);
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error updating special schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== ADD SPECIAL BREAK DIALOG (FIXED) ====================
class _AddSpecialBreakDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final String salonTimezone;
  final List<Map<String, dynamic>> breakTypes;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _AddSpecialBreakDialog({
    required this.barberId,
    required this.salonId,
    required this.salonTimezone,
    required this.breakTypes,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_AddSpecialBreakDialog> createState() => _AddSpecialBreakDialogState();
}

class _AddSpecialBreakDialogState extends State<_AddSpecialBreakDialog> {
  final supabase = Supabase.instance.client;

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _selectedBreakType = 'lunch';
  bool _isLoading = false;

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;
    final bool isMobile = !isWeb;

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.92,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Special Break',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select Date',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => _selectedDate = date);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: _selectedDate != null
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.grey),
                        size: isMobile ? 20 : 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDate != null
                              ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
                              : 'Select date',
                          style: TextStyle(
                            color: widget.isDark
                                ? Colors.white
                                : Colors.black87,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: widget.isDark ? Colors.white70 : Colors.grey,
                        size: isMobile ? 20 : 24,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Break Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              // ✅ FIXED: Wrap with proper spacing for mobile
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: widget.breakTypes.map((type) {
                  final isSelected = _selectedBreakType == type['id'];
                  return FilterChip(
                    label: Text(
                      type['name'],
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 13,
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBreakType = type['id']);
                      }
                    },
                    avatar: Icon(
                      type['icon'],
                      size: isMobile ? 16 : 18,
                      color: isSelected ? AppTheme.primary : Colors.grey,
                    ),
                    backgroundColor: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[100],
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primary,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 8 : 12,
                      vertical: isMobile ? 6 : 8,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        _TimePickerField(
                          label: 'Start Time',
                          initialTime: _startTime,
                          onTimeSelected: (time) =>
                              setState(() => _startTime = time),
                          isDark: widget.isDark,
                        ),
                        const SizedBox(height: 12),
                        _TimePickerField(
                          label: 'End Time',
                          initialTime: _endTime,
                          onTimeSelected: (time) =>
                              setState(() => _endTime = time),
                          isDark: widget.isDark,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _TimePickerField(
                            label: 'Start Time',
                            initialTime: _startTime,
                            onTimeSelected: (time) =>
                                setState(() => _startTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimePickerField(
                            label: 'End Time',
                            initialTime: _endTime,
                            onTimeSelected: (time) =>
                                setState(() => _endTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (_selectedDate != null &&
                                    _startTime != null &&
                                    _endTime != null &&
                                    !_isLoading)
                                ? _saveSpecialBreak
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Add Special Break'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed:
                              (_selectedDate != null &&
                                  _startTime != null &&
                                  _endTime != null &&
                                  !_isLoading)
                              ? _saveSpecialBreak
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Add Special Break'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSpecialBreak() async {
    setState(() => _isLoading = true);
    try {
      final salonIdInt = int.parse(widget.salonId);
      final startTimeString = _localTimeToUtc(_startTime!);
      final endTimeString = _localTimeToUtc(_endTime!);

      await supabase.from('barber_special_breaks').insert({
        'barber_id': widget.barberId,
        'salon_id': salonIdInt,
        'break_date': _selectedDate!.toIso8601String().split('T').first,
        'start_time': startTimeString,
        'end_time': endTimeString,
        'break_type': _selectedBreakType,
      });
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error saving special break: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== EDIT SPECIAL BREAK DIALOG (FIXED) ====================
class _EditSpecialBreakDialog extends StatefulWidget {
  final Map<String, dynamic> breakItem;
  final String salonTimezone;
  final List<Map<String, dynamic>> breakTypes;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;
  final bool isDark;

  const _EditSpecialBreakDialog({
    required this.breakItem,
    required this.salonTimezone,
    required this.breakTypes,
    this.defaultOpenTime,
    this.defaultCloseTime,
    required this.isDark,
  });

  @override
  State<_EditSpecialBreakDialog> createState() =>
      _EditSpecialBreakDialogState();
}

class _EditSpecialBreakDialogState extends State<_EditSpecialBreakDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _selectedBreakType;
  bool _isLoading = false;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _startTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.breakItem['start_time'],
      widget.salonTimezone,
    );
    _endTime = TimezoneService.utcToTimeOfDayWithTimezone(
      widget.breakItem['end_time'],
      widget.salonTimezone,
    );
    _selectedBreakType = widget.breakItem['break_type'] ?? 'lunch';
  }

  String _localTimeToUtc(TimeOfDay localTime) {
    return TimezoneService.timeOfDayToUtcWithTimezone(
      localTime,
      widget.salonTimezone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = context.isWeb;
    final bool isMobile = !isWeb;
    final date = DateTime.parse(widget.breakItem['break_date']);

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : MediaQuery.of(context).size.width * 0.92,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Special Break - ${DateFormat('yyyy-MM-dd').format(date)}',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Break Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              // ✅ FIXED: Wrap with proper spacing for mobile
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: widget.breakTypes.map((type) {
                  final isSelected = _selectedBreakType == type['id'];
                  return FilterChip(
                    label: Text(
                      type['name'],
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 13,
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBreakType = type['id']);
                      }
                    },
                    avatar: Icon(
                      type['icon'],
                      size: isMobile ? 16 : 18,
                      color: isSelected ? AppTheme.primary : Colors.grey,
                    ),
                    backgroundColor: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[100],
                    selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primary,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 8 : 12,
                      vertical: isMobile ? 6 : 8,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        _TimePickerField(
                          label: 'Start Time',
                          initialTime: _startTime,
                          onTimeSelected: (time) =>
                              setState(() => _startTime = time),
                          isDark: widget.isDark,
                        ),
                        const SizedBox(height: 12),
                        _TimePickerField(
                          label: 'End Time',
                          initialTime: _endTime,
                          onTimeSelected: (time) =>
                              setState(() => _endTime = time),
                          isDark: widget.isDark,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _TimePickerField(
                            label: 'Start Time',
                            initialTime: _startTime,
                            onTimeSelected: (time) =>
                                setState(() => _startTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimePickerField(
                            label: 'End Time',
                            initialTime: _endTime,
                            onTimeSelected: (time) =>
                                setState(() => _endTime = time),
                            isDark: widget.isDark,
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),
              // ✅ FIXED: Column for mobile, Row for web
              isMobile
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _updateSpecialBreak,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Update'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _updateSpecialBreak,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Update'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateSpecialBreak() async {
    setState(() => _isLoading = true);
    try {
      final startTimeString = _localTimeToUtc(_startTime);
      final endTimeString = _localTimeToUtc(_endTime);

      await supabase
          .from('barber_special_breaks')
          .update({
            'start_time': startTimeString,
            'end_time': endTimeString,
            'break_type': _selectedBreakType,
          })
          .eq('id', widget.breakItem['id']);
      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      debugPrint('Error updating special break: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: widget.isDark ? Colors.red[700] : Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== TIME PICKER FIELD ====================
class _TimePickerField extends StatefulWidget {
  final String label;
  final TimeOfDay? initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;
  final bool isDark;

  const _TimePickerField({
    required this.label,
    this.initialTime,
    required this.onTimeSelected,
    required this.isDark,
  });

  @override
  State<_TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<_TimePickerField> {
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  String _formatTimeForDisplay(TimeOfDay time) {
    final hour = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: widget.isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final result = await showDialog<TimeOfDay>(
              context: context,
              builder: (context) => _EnhancedTimePicker(
                initialTime: _selectedTime,
                isDark: widget.isDark,
              ),
            );

            if (result != null) {
              setState(() => _selectedTime = result);
              widget.onTimeSelected(result);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.isDark ? Colors.grey[700]! : Colors.grey[300]!,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: widget.isDark ? const Color(0xFF2A2A2A) : Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: _selectedTime != null
                      ? AppTheme.primary
                      : (widget.isDark ? Colors.white70 : Colors.grey[400]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedTime != null
                        ? _formatTimeForDisplay(_selectedTime!)
                        : 'Select time',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _selectedTime != null
                          ? (widget.isDark ? Colors.white : Colors.black)
                          : (widget.isDark ? Colors.white70 : Colors.grey[500]),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: widget.isDark ? Colors.white70 : Colors.grey,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== ENHANCED TIME PICKER ====================
class _EnhancedTimePicker extends StatefulWidget {
  final TimeOfDay? initialTime;
  final bool isDark;

  const _EnhancedTimePicker({required this.initialTime, required this.isDark});

  @override
  State<_EnhancedTimePicker> createState() => _EnhancedTimePickerState();
}

class _EnhancedTimePickerState extends State<_EnhancedTimePicker> {
  late int _selectedHour;
  late int _selectedMinute;
  late String _selectedPeriod;

  final List<int> hours12 = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  final List<int> minutes = List.generate(60, (i) => i);
  final List<String> periods = ['AM', 'PM'];

  @override
  void initState() {
    super.initState();
    _initializeTime();
  }

  void _initializeTime() {
    if (widget.initialTime != null) {
      final hour24 = widget.initialTime!.hour;
      final minute = widget.initialTime!.minute;
      if (hour24 == 0) {
        _selectedHour = 12;
        _selectedPeriod = 'AM';
      } else if (hour24 == 12) {
        _selectedHour = 12;
        _selectedPeriod = 'PM';
      } else if (hour24 > 12) {
        _selectedHour = hour24 - 12;
        _selectedPeriod = 'PM';
      } else {
        _selectedHour = hour24;
        _selectedPeriod = 'AM';
      }
      _selectedMinute = minute;
    } else {
      final now = TimeOfDay.now();
      final hour24 = now.hour;
      if (hour24 == 0) {
        _selectedHour = 12;
        _selectedPeriod = 'AM';
      } else if (hour24 == 12) {
        _selectedHour = 12;
        _selectedPeriod = 'PM';
      } else if (hour24 > 12) {
        _selectedHour = hour24 - 12;
        _selectedPeriod = 'PM';
      } else {
        _selectedHour = hour24;
        _selectedPeriod = 'AM';
      }
      _selectedMinute = now.minute;
    }
  }

  void _confirmTime() {
    int hour24;
    if (_selectedPeriod == 'AM') {
      hour24 = _selectedHour == 12 ? 0 : _selectedHour;
    } else {
      hour24 = _selectedHour == 12 ? 12 : _selectedHour + 12;
    }
    final selectedTime = TimeOfDay(hour: hour24, minute: _selectedMinute);
    Navigator.of(context).pop(selectedTime);
  }

  void _cancelTime() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      backgroundColor: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isMobile ? double.infinity : 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Time',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedHour.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  Text(
                    ':',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  Text(
                    _selectedMinute.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.grey[800]
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedPeriod,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildScrollPicker(
                  title: 'HOUR',
                  items: hours12,
                  selectedValue: _selectedHour,
                  onChanged: (v) => setState(() => _selectedHour = v),
                ),
                const SizedBox(width: 12),
                _buildScrollPicker(
                  title: 'MINUTE',
                  items: minutes,
                  selectedValue: _selectedMinute,
                  onChanged: (v) => setState(() => _selectedMinute = v),
                ),
                const SizedBox(width: 12),
                _buildScrollPicker(
                  title: 'PERIOD',
                  items: periods,
                  selectedValue: _selectedPeriod,
                  onChanged: (v) => setState(() => _selectedPeriod = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _cancelTime,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: widget.isDark
                          ? Colors.white60
                          : Colors.black87,
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmTime,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollPicker<T>({
    required String title,
    required List<T> items,
    required T selectedValue,
    required ValueChanged<T> onChanged,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: widget.isDark ? Colors.white60 : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListWheelScrollView.useDelegate(
              itemExtent: 40,
              onSelectedItemChanged: (newIndex) {
                if (newIndex >= 0 && newIndex < items.length) {
                  onChanged(items[newIndex]);
                }
              },
              childDelegate: ListWheelChildBuilderDelegate(
                builder: (context, i) {
                  final item = items[i];
                  final isSelected = item == selectedValue;
                  return Container(
                    alignment: Alignment.center,
                    child: Text(
                      item.toString(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.primary
                            : (widget.isDark
                                  ? Colors.white70
                                  : Colors.grey[800]),
                      ),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
