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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 🔥 FIXED: Load barbers for this salon without foreign key issues
      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('''
            id,
            barber_id,
            is_active
          ''')
          .eq('salon_id', int.parse(widget.salonId!))
          .eq('is_active', true);

      if (salonBarbersResponse.isEmpty) {
        setState(() {
          _barbers = [];
          _schedules = [];
          _isLoading = false;
        });
        return;
      }

      // Get all barber IDs
      final barberIds = salonBarbersResponse
          .map((sb) => sb['barber_id'] as String)
          .toList();

      // Load profiles for these barbers
      List<Map<String, dynamic>> barbersList = [];
      for (String barberId in barberIds) {
        final profile = await supabase
            .from('profiles')
            .select('id, full_name, email, avatar_url')
            .eq('id', barberId)
            .maybeSingle();

        if (profile != null) {
          final salonBarber = salonBarbersResponse.firstWhere(
            (sb) => sb['barber_id'] == barberId,
          );

          barbersList.add({
            'id': barberId,
            'salon_barber_id': salonBarber['id'],
            'name': profile['full_name'] ?? 'Unknown',
            'email': profile['email'],
            'avatar': profile['avatar_url'],
          });
        }
      }

      _barbers = barbersList;

      // Load schedules for all barbers
      if (_barbers.isNotEmpty) {
        List<Map<String, dynamic>> allSchedules = [];

        for (String barberId in barberIds) {
          final schedulesResponse = await supabase
              .from('barber_schedules')
              .select()
              .eq('barber_id', barberId)
              .eq('salon_id', int.parse(widget.salonId!))
              .order('day_of_week');

          allSchedules.addAll(schedulesResponse);
        }

        _schedules = allSchedules;

        // Group schedules by barber
        _groupedSchedules = {};
        for (var schedule in _schedules) {
          final barberId = schedule['barber_id'] as String;
          if (!_groupedSchedules.containsKey(barberId)) {
            _groupedSchedules[barberId] = [];
          }
          _groupedSchedules[barberId]!.add(schedule);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading schedules: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addSchedule(String barberId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddScheduleDialog(
        barberId: barberId,
        salonId: widget.salonId!,
        existingSchedules:
            _schedules.where((s) => s['barber_id'] == barberId).toList(),
      ),
    );

    if (result != null) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _editSchedule(Map<String, dynamic> schedule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditScheduleDialog(schedule: schedule),
    );

    if (result != null) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _deleteSchedule(int scheduleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      try {
        await supabase.from('barber_schedules').delete().eq('id', scheduleId);

        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule deleted'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error deleting schedule: $e');
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
              ? Center(
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
                )
              : isWeb
                  ? _buildWebView(padding, screenWidth)
                  : _buildMobileView(padding),
    );
  }

  Widget _buildWebView(double padding, double screenWidth) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Barber Cards Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: screenWidth > 1200 ? 3 : 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _barbers.length,
            itemBuilder: (context, index) {
              final barber = _barbers[index];
              final barberSchedules = _groupedSchedules[barber['id']] ?? [];

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Barber info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFFFF6B8B)
                                .withValues(alpha: 0.1),
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${barberSchedules.length} schedules',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: Colors.green,
                            ),
                            onPressed: () => _addSchedule(barber['id']),
                            tooltip: 'Add Schedule',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const Divider(height: 16),

                      // Schedules list
                      Expanded(
                        child: barberSchedules.isEmpty
                            ? Center(
                                child: Text(
                                  'No schedules',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                              )
                            : ListView.separated(
                                itemCount: barberSchedules.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, idx) {
                                  final schedule = barberSchedules[idx];
                                  final dayName =
                                      _dayNames[schedule['day_of_week']] ??
                                      'Unknown';
                                  final startTime = _formatTime(
                                    schedule['start_time'],
                                  );
                                  final endTime = _formatTime(
                                    schedule['end_time'],
                                  );
                                  final isWorking =
                                      schedule['is_working'] ?? true;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isWorking
                                          ? Colors.green.withValues(alpha: 0.05)
                                          : Colors.red.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            dayName.substring(0, 3),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            '$startTime - $endTime',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 14,
                                          ),
                                          onPressed: () =>
                                              _editSchedule(schedule),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            size: 14,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _deleteSchedule(schedule['id']),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
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

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor:
                    const Color(0xFFFF6B8B).withValues(alpha: 0.1),
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
              subtitle: Text('${barberSchedules.length} schedules'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.green),
                    onPressed: () => _addSchedule(barber['id']),
                    tooltip: 'Add Schedule',
                  ),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
              children: [
                if (barberSchedules.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No schedules set',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...barberSchedules.map((schedule) {
                    final dayName =
                        _dayNames[schedule['day_of_week']] ?? 'Unknown';
                    final startTime = _formatTime(schedule['start_time']);
                    final endTime = _formatTime(schedule['end_time']);
                    final isWorking = schedule['is_working'] ?? true;

                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isWorking
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isWorking ? Icons.work : Icons.block,
                          color: isWorking ? Colors.green : Colors.red,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        dayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isWorking ? Colors.black : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        '$startTime - $endTime',
                        style: TextStyle(
                          color:
                              isWorking ? Colors.grey[700] : Colors.grey[500],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editSchedule(schedule),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: () => _deleteSchedule(schedule['id']),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==================== ADD SCHEDULE DIALOG ====================
class _AddScheduleDialog extends StatefulWidget {
  final String barberId;
  final String salonId;
  final List<Map<String, dynamic>> existingSchedules;

  const _AddScheduleDialog({
    required this.barberId,
    required this.salonId,
    required this.existingSchedules,
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
        .where((s) => s['is_working'] == true)
        .map((s) => s['day_of_week'] as int)
        .toSet();

    return _days
        .where((d) => !existingDays.contains(d['id']))
        .map((d) => d['id'] as int)
        .toList();
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

              // Day selection
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
                        ? (selected) {
                            setState(() => _selectedDay = day['id']);
                          }
                        : null,
                    backgroundColor: Colors.grey[100],
                    selectedColor:
                        const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                    checkmarkColor: const Color(0xFFFF6B8B),
                    avatar:
                        isAvailable ? null : const Icon(Icons.lock, size: 16),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Time selection
              Row(
                children: [
                  Expanded(
                    child: _buildTimePicker(
                      label: 'Start Time',
                      time: _startTime,
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) setState(() => _startTime = time);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimePicker(
                      label: 'End Time',
                      time: _endTime,
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) setState(() => _endTime = time);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Working status
              Row(
                children: [
                  Checkbox(
                    value: _isWorking,
                    onChanged: (value) =>
                        setState(() => _isWorking = value ?? true),
                    activeColor: const Color(0xFFFF6B8B),
                  ),
                  const SizedBox(width: 8),
                  const Text('Working day'),
                ],
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedDay != null &&
                            _startTime != null &&
                            _endTime != null &&
                            !_isLoading
                        ? _saveSchedule
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
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
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              time != null ? time.format(context) : 'Select',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: time != null ? Colors.black : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSchedule() async {
    setState(() => _isLoading = true);

    try {
      final startTimeString =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
      final endTimeString =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';

      await supabase.from('barber_schedules').insert({
        'barber_id': widget.barberId,
        'salon_id': int.parse(widget.salonId),
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

  const _EditScheduleDialog({required this.schedule});

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

    // Parse start time
    final startParts = (widget.schedule['start_time'] as String).split(':');
    _startTime = TimeOfDay(
      hour: int.parse(startParts[0]),
      minute: int.parse(startParts[1]),
    );

    // Parse end time
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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _buildTimePicker(
                      label: 'Start Time',
                      time: _startTime,
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (time != null) setState(() => _startTime = time);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimePicker(
                      label: 'End Time',
                      time: _endTime,
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (time != null) setState(() => _endTime = time);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Checkbox(
                    value: _isWorking,
                    onChanged: (value) =>
                        setState(() => _isWorking = value ?? true),
                    activeColor: const Color(0xFFFF6B8B),
                  ),
                  const SizedBox(width: 8),
                  const Text('Working day'),
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
                    onPressed: _isLoading ? null : _updateSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
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

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              time.format(context),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
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