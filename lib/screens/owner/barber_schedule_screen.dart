// screens/owner/barber_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Map<String, List<Map<String, dynamic>>> _groupedSchedules = {};
  Map<String, List<Map<String, dynamic>>> _groupedBreaks = {};

  // Salon default times
  TimeOfDay? _salonOpenTime;
  TimeOfDay? _salonCloseTime;

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadSalonTimes() async {
    if (widget.salonId == null) return;

    try {
      final salonIdInt = int.parse(widget.salonId!);
      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time')
          .eq('id', salonIdInt)
          .maybeSingle();

      if (salonResponse != null) {
        final openTimeStr = salonResponse['open_time'] as String?;
        if (openTimeStr != null) {
          final parts = openTimeStr.split(':');
          _salonOpenTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }

        final closeTimeStr = salonResponse['close_time'] as String?;
        if (closeTimeStr != null) {
          final parts = closeTimeStr.split(':');
          _salonCloseTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
      }

      debugPrint(
        '✅ Salon times loaded - Open: $_salonOpenTime, Close: $_salonCloseTime',
      );
    } catch (e) {
      debugPrint('❌ Error loading salon times: $e');
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
          .select('id, barber_id, status')
          .eq('salon_id', salonIdInt)
          .eq('status', 'active');

      if (salonBarbersResponse.isEmpty) {
        setState(() {
          _barbers = [];
          _schedules = [];
          _isLoading = false;
        });
        return;
      }

      final barberIds = salonBarbersResponse
          .map((sb) => sb['barber_id'] as String)
          .toList();

      final profilesResponse = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .inFilter('id', barberIds);

      final Map<String, Map<String, dynamic>> profileMap = {};
      for (var profile in profilesResponse) {
        profileMap[profile['id']] = profile;
      }

      List<Map<String, dynamic>> barbersList = [];
      for (var sb in salonBarbersResponse) {
        final barberId = sb['barber_id'] as String;
        final profile = profileMap[barberId] ?? {};

        barbersList.add({
          'id': barberId,
          'salon_barber_id': sb['id'],
          'name': profile['full_name'] ?? 'Unknown',
          'email': profile['email'],
          'avatar': profile['avatar_url'],
          'status': sb['status'],
        });
      }

      _barbers = barbersList;

      if (_barbers.isNotEmpty) {
        // Load schedules
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

        // Load breaks
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
      }

      debugPrint(
        '✅ Loaded ${_barbers.length} barbers, ${_schedules.length} schedules, ${_groupedBreaks.values.expand((i) => i).length} breaks',
      );
    } catch (e) {
      debugPrint('❌ Error loading schedules: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addSchedule(String barberId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddScheduleDialog(
        barberId: barberId,
        salonId: widget.salonId!,
        existingSchedules: _schedules
            .where((s) => s['barber_id'] == barberId)
            .toList(),
        defaultOpenTime: _salonOpenTime,
        defaultCloseTime: _salonCloseTime,
      ),
    );

    if (result != null && result['success'] == true) {
      await _loadData();
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
        existingBreaks: _groupedBreaks[barberId] ?? [],
        breakTypes: _breakTypes,
        defaultOpenTime: _salonOpenTime,
        defaultCloseTime: _salonCloseTime,
      ),
    );

    if (result != null && result['success'] == true) {
      await _loadData();
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
        defaultOpenTime: _salonOpenTime,
        defaultCloseTime: _salonCloseTime,
      ),
    );

    if (result != null && result['success'] == true) {
      await _loadData();
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
        breakTypes: _breakTypes,
        defaultOpenTime: _salonOpenTime,
        defaultCloseTime: _salonCloseTime,
      ),
    );

    if (result != null && result['success'] == true) {
      await _loadData();
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

    // Optimistic update
    setState(() {
      final index = _schedules.indexWhere((s) => s['id'] == schedule['id']);
      if (index != -1) {
        _schedules[index]['is_working'] = newStatus;
      }
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
      // Revert on error
      debugPrint('❌ Error updating working status: $e');
      setState(() {
        final index = _schedules.indexWhere((s) => s['id'] == schedule['id']);
        if (index != -1) {
          _schedules[index]['is_working'] = !newStatus;
        }
        final barberId = schedule['barber_id'] as String;
        if (_groupedSchedules.containsKey(barberId)) {
          final scheduleIndex = _groupedSchedules[barberId]!.indexWhere(
            (s) => s['id'] == schedule['id'],
          );
          if (scheduleIndex != -1) {
            _groupedSchedules[barberId]![scheduleIndex]['is_working'] =
                !newStatus;
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSchedule(int scheduleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Schedule'),
        content: const Text('Are you sure you want to delete this schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await supabase.from('barber_schedules').delete().eq('id', scheduleId);
        await _loadData();
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
        debugPrint('❌ Error deleting schedule: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteBreak(int breakId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Break'),
        content: const Text('Are you sure you want to delete this break?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await supabase.from('barber_breaks').delete().eq('id', breakId);
        await _loadData();
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
        debugPrint('❌ Error deleting break: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  String _formatTime(String? time) {
    if (time == null) return '--:--';
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return time;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barber Schedules'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : _barbers.isEmpty
          ? _buildEmptyState(isWeb, padding)
          : isWeb
          ? _buildWebView(padding, screenWidth)
          : _buildMobileView(padding),
    );
  }

  Widget _buildEmptyState(bool isWeb, double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: isWeb ? 80 : 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No barbers found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Add barbers first to manage schedules',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(double padding, double screenWidth) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Row(
                children: [
                  Icon(Icons.people, color: const Color(0xFFFF6B8B)),
                  const SizedBox(width: 12),
                  Text(
                    'Total Barbers: ${_barbers.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  const SizedBox(width: 24),
                  Icon(Icons.schedule, color: Colors.green),
                  const SizedBox(width: 12),
                  Text(
                    'Total Schedules: ${_schedules.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  const SizedBox(width: 24),
                  Icon(Icons.free_breakfast, color: Colors.orange),
                  const SizedBox(width: 12),
                  Text(
                    'Total Breaks: ${_groupedBreaks.values.expand((i) => i).length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
              childAspectRatio: 1.4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _barbers.length,
            itemBuilder: (context, index) {
              final barber = _barbers[index];
              final barberSchedules = _groupedSchedules[barber['id']] ?? [];
              final barberBreaks = _groupedBreaks[barber['id']] ?? [];
              return _buildBarberCard(barber, barberSchedules, barberBreaks, true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileView(double padding) {
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        final barber = _barbers[index];
        final barberSchedules = _groupedSchedules[barber['id']] ?? [];
        final barberBreaks = _groupedBreaks[barber['id']] ?? [];
        return _buildBarberCard(barber, barberSchedules, barberBreaks, false);
      },
    );
  }

  Widget _buildBarberCard(
    Map<String, dynamic> barber,
    List<Map<String, dynamic>> schedules,
    List<Map<String, dynamic>> breaks,
    bool isWeb,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: isWeb
          ? _buildWebBarberCard(barber, schedules, breaks)
          : _buildMobileBarberCard(barber, schedules, breaks),
    );
  }

  Widget _buildWebBarberCard(
    Map<String, dynamic> barber,
    List<Map<String, dynamic>> schedules,
    List<Map<String, dynamic>> breaks,
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
                backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                backgroundImage: barber['avatar'] != null
                    ? NetworkImage(barber['avatar'])
                    : null,
                child: barber['avatar'] == null
                    ? Text(
                        barber['name'][0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFFF6B8B),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${schedules.where((s) => s['is_working'] == true).length} Working / ${schedules.length} Total',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Tooltip(
                    message: 'Add Break',
                    child: IconButton(
                      icon: const Icon(Icons.free_breakfast, color: Colors.orange),
                      onPressed: () => _addBreak(barber['id']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Add Schedule',
                    child: IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
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
                  // Schedules Section
                  if (schedules.isNotEmpty) ...[
                    const Text(
                      'Working Hours',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...schedules.map((schedule) {
                      final dayName = _dayNames[schedule['day_of_week']] ?? 'Unknown';
                      final startTime = _formatTime(schedule['start_time']);
                      final endTime = _formatTime(schedule['end_time']);
                      final isWorking = schedule['is_working'] ?? true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                              flex: 2,
                              child: Row(
                                children: [
                                  Icon(
                                    isWorking
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    size: 14,
                                    color: isWorking
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dayName.substring(0, 3),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: isWorking
                                          ? Colors.black87
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '$startTime - $endTime',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isWorking
                                      ? Colors.grey[700]
                                      : Colors.grey[500],
                                  decoration: isWorking
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 30,
                              child: Transform.scale(
                                scale: 0.7,
                                child: Switch(
                                  value: isWorking,
                                  onChanged: (_) =>
                                      _toggleWorkingStatus(schedule),
                                  activeThumbColor: Colors.green,
                                  inactiveThumbColor: Colors.red,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 14),
                              onPressed: () => _editSchedule(schedule),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 14,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteSchedule(schedule['id']),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 8),

                  // Breaks Section
                  if (breaks.isNotEmpty) ...[
                    const Text(
                      'Breaks',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...breaks.map((breakItem) {
                      final dayName = _dayNames[breakItem['day_of_week']] ?? 'Unknown';
                      final startTime = _formatTime(breakItem['start_time']);
                      final endTime = _formatTime(breakItem['end_time']);
                      final breakType = breakItem['break_type'] ?? 'custom';
                      final breakTypeData = _breakTypes.firstWhere(
                        (b) => b['id'] == breakType,
                        orElse: () => _breakTypes.last,
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                              flex: 2,
                              child: Row(
                                children: [
                                  Icon(
                                    breakTypeData['icon'],
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dayName.substring(0, 3),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$startTime - $endTime',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    breakTypeData['name'],
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 14),
                              onPressed: () => _editBreak(breakItem),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 14,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteBreak(breakItem['id']),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBarberCard(
    Map<String, dynamic> barber,
    List<Map<String, dynamic>> schedules,
    List<Map<String, dynamic>> breaks,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            backgroundImage: barber['avatar'] != null
                ? NetworkImage(barber['avatar'])
                : null,
            child: barber['avatar'] == null
                ? Text(
                    barber['name'][0].toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFFF6B8B),
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          title: Text(
            barber['name'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${schedules.where((s) => s['is_working'] == true).length} Working / ${schedules.length} Total',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.free_breakfast, color: Colors.orange),
                onPressed: () => _addBreak(barber['id']),
                tooltip: 'Add Break',
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.green),
                onPressed: () => _addSchedule(barber['id']),
                tooltip: 'Add Schedule',
              ),
              const Icon(Icons.keyboard_arrow_down),
            ],
          ),
          children: [
            if (schedules.isEmpty && breaks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No schedules or breaks set',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            if (schedules.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  'Working Hours',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ...schedules.map((schedule) {
                final dayName = _dayNames[schedule['day_of_week']] ?? 'Unknown';
                final startTime = _formatTime(schedule['start_time']);
                final endTime = _formatTime(schedule['end_time']);
                final isWorking = schedule['is_working'] ?? true;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isWorking
                        ? Colors.green.withValues(alpha: 0.05)
                        : Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isWorking
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isWorking
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isWorking ? Icons.work : Icons.work_off,
                                color: isWorking ? Colors.green : Colors.red,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        dayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isWorking ? Colors.green : Colors.red,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isWorking ? 'Working' : 'Off',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$startTime - $endTime',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isWorking ? Colors.grey[700] : Colors.grey[500],
                                      decoration: isWorking ? null : TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 50,
                              height: 40,
                              child: Transform.scale(
                                scale: 0.7,
                                child: Switch(
                                  value: isWorking,
                                  onChanged: (_) => _toggleWorkingStatus(schedule),
                                  activeThumbColor: Colors.green,
                                  inactiveThumbColor: Colors.red,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _editSchedule(schedule),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _deleteSchedule(schedule['id']),
                              icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                              label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            if (breaks.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  'Breaks',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ...breaks.map((breakItem) {
                final dayName = _dayNames[breakItem['day_of_week']] ?? 'Unknown';
                final startTime = _formatTime(breakItem['start_time']);
                final endTime = _formatTime(breakItem['end_time']);
                final breakType = breakItem['break_type'] ?? 'custom';
                final breakTypeData = _breakTypes.firstWhere(
                  (b) => b['id'] == breakType,
                  orElse: () => _breakTypes.last,
                );

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(breakTypeData['icon'], color: Colors.orange, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dayName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$startTime - $endTime',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  Text(
                                    breakTypeData['name'],
                                    style: const TextStyle(fontSize: 10, color: Colors.orange),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _editBreak(breakItem),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _deleteBreak(breakItem['id']),
                              icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                              label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== ADD BREAK DIALOG ====================
class _AddBreakDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final List<Map<String, dynamic>> existingBreaks;
  final List<Map<String, dynamic>> breakTypes;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;

  const _AddBreakDialog({
    required this.barberId,
    required this.salonId,
    required this.existingBreaks,
    required this.breakTypes,
    this.defaultOpenTime,
    this.defaultCloseTime,
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

  @override
  void initState() {
    super.initState();
    _startTime = widget.defaultOpenTime;
    _endTime = widget.defaultCloseTime;
    
    // Default break times
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
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : screenWidth * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Break',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // Break Type Selection
              const Text(
                'Break Type',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.breakTypes.map((type) {
                  final isSelected = _selectedBreakType == type['id'];
                  return FilterChip(
                    label: Text(type['name']),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBreakType = type['id']);
                      }
                    },
                    avatar: Icon(type['icon'], size: 18),
                    backgroundColor: Colors.grey[100],
                    selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                    checkmarkColor: const Color(0xFFFF6B8B),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Day Selection
              const Text(
                'Select Day',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _days.map((day) {
                  final isSelected = _selectedDay == day['id'];
                  final isAvailable = _availableDays.contains(day['id']);
                  return FilterChip(
                    label: Text(day['name']),
                    selected: isSelected,
                    onSelected: isAvailable
                        ? (selected) => setState(() => _selectedDay = day['id'])
                        : null,
                    backgroundColor: Colors.grey[100],
                    selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                    checkmarkColor: const Color(0xFFFF6B8B),
                    avatar: isAvailable ? null : const Icon(Icons.lock, size: 16),
                  );
                }).toList(),
              ),

              if (_availableDays.isEmpty && _selectedDay == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'All days already have breaks!',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  ),
                ),

              const SizedBox(height: 16),

              // Time Selection
              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _startTime = time),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _endTime = time),
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
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        _selectedDay != null &&
                            _startTime != null &&
                            _endTime != null &&
                            !_isLoading
                        ? _saveBreak
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Add Break',
                            style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> _saveBreak() async {
    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId);
      final startTimeString =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
      final endTimeString =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';

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
      debugPrint('❌ Error saving break: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== EDIT BREAK DIALOG ====================
class _EditBreakDialog extends StatefulWidget {
  final Map<String, dynamic> breakItem;
  final List<Map<String, dynamic>> breakTypes;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;

  const _EditBreakDialog({
    required this.breakItem,
    required this.breakTypes,
    this.defaultOpenTime,
    this.defaultCloseTime,
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
    final startParts = (widget.breakItem['start_time'] as String).split(':');
    _startTime = TimeOfDay(
      hour: int.parse(startParts[0]),
      minute: int.parse(startParts[1]),
    );
    final endParts = (widget.breakItem['end_time'] as String).split(':');
    _endTime = TimeOfDay(
      hour: int.parse(endParts[0]),
      minute: int.parse(endParts[1]),
    );
    _selectedBreakType = widget.breakItem['break_type'] ?? 'lunch';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final dayName = _dayNames[widget.breakItem['day_of_week']] ?? 'Unknown';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : screenWidth * 0.9,
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Break Type Selection
              const Text(
                'Break Type',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.breakTypes.map((type) {
                  final isSelected = _selectedBreakType == type['id'];
                  return FilterChip(
                    label: Text(type['name']),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedBreakType = type['id']);
                      }
                    },
                    avatar: Icon(type['icon'], size: 18),
                    backgroundColor: Colors.grey[100],
                    selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                    checkmarkColor: const Color(0xFFFF6B8B),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Time Selection
              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _startTime = time),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _endTime = time),
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
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateBreak,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Update Break',
                            style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> _updateBreak() async {
    setState(() => _isLoading = true);

    try {
      final startTimeString =
          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';
      final endTimeString =
          '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00';

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
      debugPrint('❌ Error updating break: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== ENHANCED TIME PICKER ====================
class _EnhancedTimePicker extends StatefulWidget {
  final TimeOfDay? initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;

  const _EnhancedTimePicker({
    required this.initialTime,
    required this.onTimeSelected,
  });

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
    widget.onTimeSelected(selectedTime);
    Navigator.of(context).pop(selectedTime);
  }

  void _cancelTime() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isMobile ? double.infinity : 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Time',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedHour.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B8B),
                    ),
                  ),
                  const Text(
                    ':',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B8B),
                    ),
                  ),
                  Text(
                    _selectedMinute.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B8B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedPeriod,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                  onChanged: (value) => setState(() => _selectedHour = value),
                ),
                const SizedBox(width: 12),
                _buildScrollPicker(
                  title: 'MINUTE',
                  items: minutes,
                  selectedValue: _selectedMinute,
                  onChanged: (value) => setState(() => _selectedMinute = value),
                ),
                const SizedBox(width: 12),
                _buildScrollPicker(
                  title: 'PERIOD',
                  items: periods,
                  selectedValue: _selectedPeriod,
                  onChanged: (value) => setState(() => _selectedPeriod = value),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmTime,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
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
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[800],
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

// ==================== TIME PICKER FIELD ====================
class _TimePickerField extends StatefulWidget {
  final String label;
  final TimeOfDay? initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;
  final bool isRequired;

  const _TimePickerField({
    required this.label,
    this.initialTime,
    required this.onTimeSelected,
    this.isRequired = true,
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

  Future<void> _showTimePicker() async {
    final result = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) => _EnhancedTimePicker(
        initialTime: _selectedTime,
        onTimeSelected: (time) {
          setState(() {
            _selectedTime = time;
          });
          widget.onTimeSelected(time);
        },
      ),
    );

    if (result != null) {
      setState(() {
        _selectedTime = result;
      });
      widget.onTimeSelected(result);
    }
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
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showTimePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!, width: 1),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: _selectedTime != null
                      ? const Color(0xFFFF6B8B)
                      : Colors.grey[400],
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
                          ? Colors.black
                          : Colors.grey[500],
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== ADD SCHEDULE DIALOG ====================
class _AddScheduleDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final List<Map<String, dynamic>> existingSchedules;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;

  const _AddScheduleDialog({
    required this.barberId,
    required this.salonId,
    required this.existingSchedules,
    this.defaultOpenTime,
    this.defaultCloseTime,
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

  @override
  void initState() {
    super.initState();
    _startTime = widget.defaultOpenTime;
    _endTime = widget.defaultCloseTime;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : screenWidth * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.all(isWeb ? 24 : 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Schedule',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              const Text(
                'Select Day',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _days.map((day) {
                  final isSelected = _selectedDay == day['id'];
                  final isAvailable = _availableDays.contains(day['id']);
                  return FilterChip(
                    label: Text(day['name']),
                    selected: isSelected,
                    onSelected: isAvailable
                        ? (selected) => setState(() => _selectedDay = day['id'])
                        : null,
                    backgroundColor: Colors.grey[100],
                    selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                    checkmarkColor: const Color(0xFFFF6B8B),
                    avatar: isAvailable ? null : const Icon(Icons.lock, size: 16),
                  );
                }).toList(),
              ),

              if (_availableDays.isEmpty && _selectedDay == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'All days already have schedules!',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  ),
                ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _startTime = time),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _endTime = time),
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
                              color: Colors.grey[600],
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
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        _selectedDay != null &&
                            _startTime != null &&
                            _endTime != null &&
                            !_isLoading
                        ? _saveSchedule
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Add Schedule',
                            style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> _saveSchedule() async {
    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId);
      final startTimeString =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
      final endTimeString =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';

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
      debugPrint('❌ Error saving schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

// ==================== EDIT SCHEDULE DIALOG ====================
class _EditScheduleDialog extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final TimeOfDay? defaultOpenTime;
  final TimeOfDay? defaultCloseTime;

  const _EditScheduleDialog({
    required this.schedule,
    this.defaultOpenTime,
    this.defaultCloseTime,
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
    final startParts = (widget.schedule['start_time'] as String).split(':');
    _startTime = TimeOfDay(
      hour: int.parse(startParts[0]),
      minute: int.parse(startParts[1]),
    );
    final endParts = (widget.schedule['end_time'] as String).split(':');
    _endTime = TimeOfDay(
      hour: int.parse(endParts[0]),
      minute: int.parse(endParts[1]),
    );
    _isWorking = widget.schedule['is_working'] ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 500 : screenWidth * 0.9,
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _TimePickerField(
                      label: 'Start Time',
                      initialTime: _startTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _startTime = time),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimePickerField(
                      label: 'End Time',
                      initialTime: _endTime,
                      isRequired: true,
                      onTimeSelected: (time) => setState(() => _endTime = time),
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
                              color: Colors.grey[600],
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
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Update Schedule',
                            style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> _updateSchedule() async {
    setState(() => _isLoading = true);

    try {
      final startTimeString =
          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';
      final endTimeString =
          '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00';

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
      debugPrint('❌ Error updating schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}