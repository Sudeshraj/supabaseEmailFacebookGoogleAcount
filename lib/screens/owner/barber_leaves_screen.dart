// screens/owner/barber_leaves_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';
import '../../widgets/customer_choice_dialog.dart';

class BarberLeavesScreen extends StatefulWidget {
  final String? salonId;

  const BarberLeavesScreen({super.key, this.salonId});

  @override
  State<BarberLeavesScreen> createState() => _BarberLeavesScreenState();
}

class _BarberLeavesScreenState extends State<BarberLeavesScreen> {
  final supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _barbers = [];
  List<Map<String, dynamic>> _leaves = [];
  Map<String, Map<String, dynamic>> _barberProfiles = {};

  // Salon working hours
  String? _salonOpenTime;
  String? _salonCloseTime;
  List<Map<String, dynamic>> _holidays = [];

  // Filters
  DateTime? _selectedDate;
  String? _selectedBarberId;
  String _selectedStatus = 'all';
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load salon details
      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time')
          .eq('id', int.parse(widget.salonId!))
          .maybeSingle();

      if (salonResponse != null) {
        _salonOpenTime = salonResponse['open_time'];
        _salonCloseTime = salonResponse['close_time'];
      }

      // Load holidays for this salon
      final holidaysResponse = await supabase
          .from('salon_holidays')
          .select('holiday_date, name, description')
          .eq('salon_id', int.parse(widget.salonId!))
          .order('holiday_date', ascending: false);

      _holidays = List<Map<String, dynamic>>.from(holidaysResponse);

      // Get barber IDs with status = 'active'
      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', int.parse(widget.salonId!))
          .eq('status', 'active');

      final barberIds = salonBarbersResponse
          .map((sb) => sb['barber_id'] as String)
          .toList();

      if (barberIds.isNotEmpty) {
        // Get profiles
        List<Map<String, dynamic>> allProfiles = [];
        for (String barberId in barberIds) {
          final profile = await supabase
              .from('profiles')
              .select('id, full_name, email, avatar_url')
              .eq('id', barberId)
              .maybeSingle();

          if (profile != null) {
            allProfiles.add(profile);
          }
        }

        _barbers = allProfiles.map<Map<String, dynamic>>((p) {
          return {
            'id': p['id'],
            'name': p['full_name'] ?? 'Unknown',
            'email': p['email'],
            'avatar': p['avatar_url'],
          };
        }).toList();

        _barberProfiles = {};
        for (var profile in allProfiles) {
          _barberProfiles[profile['id']] = profile;
        }

        // Get leaves
        await _loadLeavesWithFilters(barberIds);
      } else {
        _barbers = [];
        _leaves = [];
      }
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLeavesWithFilters(List<String> barberIds) async {
    List<Map<String, dynamic>> allLeaves = [];

    for (String barberId in barberIds) {
      var query = supabase
          .from('barber_leaves')
          .select()
          .eq('barber_id', barberId)
          .eq('salon_id', int.parse(widget.salonId!));

      if (_selectedBarberId != null) {
        query = query.eq('barber_id', _selectedBarberId!);
      }

      if (_selectedDate != null) {
        final dateStr =
            '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
        query = query.eq('leave_date', dateStr);
      }

      if (_selectedStatus != 'all') {
        query = query.eq('status', _selectedStatus);
      }

      if (_selectedType != 'all') {
        query = query.eq('leave_type', _selectedType);
      }

      final leavesForBarber = await query;
      allLeaves.addAll(leavesForBarber);
    }

    allLeaves.sort((a, b) {
      final dateA = a['leave_date'] ?? '';
      final dateB = b['leave_date'] ?? '';
      return dateB.compareTo(dateA);
    });

    if (mounted) {
      setState(() {
        _leaves = allLeaves;
      });
    }
  }

  Future<void> _applyFilters() async {
    setState(() => _isLoading = true);

    final salonBarbersResponse = await supabase
        .from('salon_barbers')
        .select('barber_id')
        .eq('salon_id', int.parse(widget.salonId!))
        .eq('status', 'active');

    final barberIds = salonBarbersResponse
        .map((sb) => sb['barber_id'] as String)
        .toList();

    await _loadLeavesWithFilters(barberIds);

    setState(() => _isLoading = false);
  }

  // Check if a date is a holiday
  bool _isHoliday(String dateStr) {
    return _holidays.any((h) => h['holiday_date'] == dateStr);
  }

  String? _getHolidayName(String dateStr) {
    final holiday = _holidays.firstWhere(
      (h) => h['holiday_date'] == dateStr,
      orElse: () => {},
    );
    return holiday['name'];
  }

  // ==================== CUSTOMER CHOICE HANDLING ====================

  Future<void> _handleAffectedAppointment(
    Map<String, dynamic> appointment,
    String dateStr,
    String barberId,
  ) async {
    try {
      final customerId = appointment['customer_id'];
      final startTime = appointment['start_time'];

      final timeFormatted = _formatTimeForDisplay(startTime);
      final dateFormatted = _formatDate(dateStr);

      final customer = await supabase
          .from('profiles')
          .select('full_name, email, fcm_token')
          .eq('id', customerId)
          .maybeSingle();

      if (customer == null) return;

      // Get appointment priority
      final priority = await _getAppointmentPriority(appointment);

      // Try to find available barber
      final availableBarber = await _findAvailableBarber(
        salonId: widget.salonId!,
        appointmentDate: dateStr,
        startTime: appointment['start_time'],
        endTime: appointment['end_time'],
        excludeBarberId: barberId,
        appointmentPriority: priority,
      );

      final service = await supabase
          .from('services')
          .select('name')
          .eq('id', appointment['service_id'])
          .single();

      // Show choice dialog to customer
      if (context.mounted) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => CustomerChoiceDialog(
            customerName: customer['full_name'] ?? 'Customer',
            appointmentDate: dateFormatted,
            appointmentTime: timeFormatted,
            serviceName: service['name'],
            availableBarber: availableBarber,
            onAcceptNewBarber: () => Navigator.pop(dialogContext, 'accept'),
            onMoveToNextDay: () => Navigator.pop(dialogContext, 'next_day'),
            onCancel: () => Navigator.pop(dialogContext, 'cancel'),
          ),
        );

        switch (choice) {
          case 'accept':
            if (availableBarber != null) {
              await _reassignToBarber(appointment, availableBarber, barberId);
              await _notificationService.sendAppointmentNotification(
                customerId: customerId,
                title: 'Appointment Reassigned',
                body:
                    'Your appointment has been reassigned to ${availableBarber['name']}.',
                data: {
                  'type': 'reassigned',
                  'barber_name': availableBarber['name'],
                },
              );
            }
            break;

          case 'next_day':
            final newDate = await _moveToNextDay(appointment);
            await _notificationService.sendAppointmentNotification(
              customerId: customerId,
              title: 'Appointment Moved to Tomorrow',
              body:
                  'Your appointment has been moved to ${_formatDate(newDate)} at 9:00 AM (Queue #1).',
              data: {'type': 'moved', 'new_date': newDate},
            );
            break;

          case 'cancel':
            await _cancelAppointment(
              appointment['id'],
              'Customer cancelled due to barber leave',
            );
            await _notificationService.sendAppointmentNotification(
              customerId: customerId,
              title: 'Appointment Cancelled',
              body: 'Your appointment has been cancelled as requested.',
              data: {'type': 'cancelled'},
            );
            break;
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling affected appointment: $e');
    }
  }

  Future<int> _getAppointmentPriority(Map<String, dynamic> appointment) async {
    try {
      if (appointment['is_vip'] == true &&
          appointment['vip_booking_id'] != null) {
        final vipBooking = await supabase
            .from('vip_bookings')
            .select('vip_type_id')
            .eq('id', appointment['vip_booking_id'])
            .single();

        final vipType = await supabase
            .from('vip_booking_types')
            .select('priority_level')
            .eq('id', vipBooking['vip_type_id'])
            .single();

        return vipType['priority_level'] ?? 4;
      }
      return 4;
    } catch (e) {
      return 4;
    }
  }

  Future<Map<String, dynamic>?> _findAvailableBarber({
    required String salonId,
    required String appointmentDate,
    required String startTime,
    required String endTime,
    required String excludeBarberId,
    required int appointmentPriority,
  }) async {
    try {
      final salonBarbers = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', int.parse(salonId))
          .eq('status', 'active');

      final barberIds = salonBarbers
          .map((sb) => sb['barber_id'] as String)
          .toList();
      final availableBarberIds = barberIds
          .where((id) => id != excludeBarberId)
          .toList();

      if (availableBarberIds.isEmpty) return null;

      for (String barberId in availableBarberIds) {
        if (await _isBarberAvailable(
          barberId,
          appointmentDate,
          startTime,
          endTime,
        )) {
          final profile = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', barberId)
              .maybeSingle();

          return {
            'barber_id': barberId,
            'name': profile?['full_name'] ?? 'Another barber',
          };
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error finding available barber: $e');
      return null;
    }
  }

  Future<bool> _isBarberAvailable(
    String barberId,
    String appointmentDate,
    String startTime,
    String endTime,
  ) async {
    try {
      final dayOfWeek = DateTime.parse(appointmentDate).weekday;

      final schedule = await supabase
          .from('barber_schedules')
          .select()
          .eq('barber_id', barberId)
          .eq('day_of_week', dayOfWeek)
          .maybeSingle();

      if (schedule == null) return false;

      final leave = await supabase
          .from('barber_leaves')
          .select()
          .eq('barber_id', barberId)
          .eq('leave_date', appointmentDate)
          .eq('status', 'approved')
          .maybeSingle();

      if (leave != null) return false;

      final conflict = await supabase
          .from('appointments')
          .select()
          .eq('barber_id', barberId)
          .eq('appointment_date', appointmentDate)
          .eq('status', 'confirmed')
          .or('start_time.lte.$endTime,end_time.gte.$startTime')
          .maybeSingle();

      return conflict == null;
    } catch (e) {
      return false;
    }
  }

  Future<void> _reassignToBarber(
    Map<String, dynamic> appointment,
    Map<String, dynamic> newBarber,
    String oldBarberId,
  ) async {
    try {
      await _adjustQueueNumbers(
        barberId: newBarber['barber_id'],
        date: appointment['appointment_date'],
        newAppointment: appointment,
      );

      await supabase
          .from('appointments')
          .update({
            'barber_id': newBarber['barber_id'],
            'reassigned_from': oldBarberId,
            'status': 'confirmed',
            'notes': 'Reassigned due to barber leave',
          })
          .eq('id', appointment['id']);
    } catch (e) {
      debugPrint('❌ Error reassigning to barber: $e');
      rethrow;
    }
  }

  Future<int> _getVariantDuration(int? variantId) async {
    if (variantId == null) return 30;

    try {
      final response = await supabase
          .from('service_variants')
          .select('duration')
          .eq('id', variantId)
          .maybeSingle();

      return response?['duration'] ?? 30;
    } catch (e) {
      debugPrint('❌ Error getting variant duration: $e');
      return 30;
    }
  }

  Future<String> _moveToNextDay(Map<String, dynamic> appointment) async {
    try {
      final duration = await _getVariantDuration(appointment['variant_id']);

      DateTime nextDate = DateTime.parse(
        appointment['appointment_date'],
      ).add(const Duration(days: 1));

      // Skip holidays and Sundays
      while (await _isHolidayDate(nextDate) || nextDate.weekday == DateTime.sunday) {
        nextDate = nextDate.add(const Duration(days: 1));
      }

      final nextDateStr =
          '${nextDate.year.toString().padLeft(4, '0')}-${nextDate.month.toString().padLeft(2, '0')}-${nextDate.day.toString().padLeft(2, '0')}';
      final queueNumber = 1;

      final appointmentsToShift = await supabase
          .from('appointments')
          .select('id, queue_number')
          .eq('barber_id', appointment['barber_id'])
          .eq('appointment_date', nextDateStr)
          .eq('status', 'confirmed')
          .gte('queue_number', queueNumber)
          .order('queue_number', ascending: false);

      for (var appt in appointmentsToShift) {
        await supabase
            .from('appointments')
            .update({'queue_number': appt['queue_number'] + 1})
            .eq('id', appt['id']);
      }

      final endTime = _calculateEndTimeWithDuration('09:00:00', duration);

      await supabase
          .from('appointments')
          .update({
            'appointment_date': nextDateStr,
            'start_time': '09:00:00',
            'end_time': endTime,
            'queue_number': queueNumber,
            'status': 'confirmed',
            'notes':
                'Moved from ${appointment['appointment_date']} due to barber leave',
          })
          .eq('id', appointment['id']);

      debugPrint(
        '✅ Appointment moved to $nextDateStr at 09:00 AM (Queue #$queueNumber)',
      );
      return nextDateStr;
    } catch (e) {
      debugPrint('❌ Error moving to next day: $e');
      rethrow;
    }
  }

  Future<bool> _isHolidayDate(DateTime date) async {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    
    final holiday = await supabase
        .from('salon_holidays')
        .select()
        .eq('salon_id', int.parse(widget.salonId!))
        .eq('holiday_date', dateStr)
        .maybeSingle();
    
    return holiday != null;
  }

  String _calculateEndTimeWithDuration(String startTime, int durationMinutes) {
    try {
      final parts = startTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final totalMinutes = hour * 60 + minute + durationMinutes;
      final newHour = (totalMinutes ~/ 60) % 24;
      final newMinute = totalMinutes % 60;

      return '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      debugPrint('❌ Error calculating end time: $e');
      return '09:30:00';
    }
  }

  Future<void> _adjustQueueNumbers({
    required String barberId,
    required String date,
    required Map<String, dynamic> newAppointment,
  }) async {
    try {
      final currentQueue = await supabase
          .from('appointments')
          .select('id, queue_number, start_time, is_vip')
          .eq('barber_id', barberId)
          .eq('appointment_date', date)
          .eq('status', 'confirmed')
          .order('queue_number');

      if (currentQueue.isEmpty) {
        await supabase
            .from('appointments')
            .update({'queue_number': 1})
            .eq('id', newAppointment['id']);
        return;
      }

      int newQueueNumber = currentQueue.length + 1;

      for (int i = 0; i < currentQueue.length; i++) {
        final existing = currentQueue[i];

        if (newAppointment['is_vip'] == true && existing['is_vip'] != true) {
          newQueueNumber = existing['queue_number'];
          break;
        }

        if (existing['is_vip'] == newAppointment['is_vip']) {
          if (newAppointment['start_time'].compareTo(existing['start_time']) <
              0) {
            newQueueNumber = existing['queue_number'];
            break;
          }
        }
      }

      final appointmentsToShift = await supabase
          .from('appointments')
          .select('id, queue_number')
          .eq('barber_id', barberId)
          .eq('appointment_date', date)
          .eq('status', 'confirmed')
          .gte('queue_number', newQueueNumber)
          .order('queue_number', ascending: false);

      for (var appt in appointmentsToShift) {
        await supabase
            .from('appointments')
            .update({'queue_number': appt['queue_number'] + 1})
            .eq('id', appt['id']);
      }

      await supabase
          .from('appointments')
          .update({'queue_number': newQueueNumber})
          .eq('id', newAppointment['id']);

      debugPrint('✅ Queue adjusted: new appointment #$newQueueNumber');
    } catch (e) {
      debugPrint('❌ Error adjusting queue: $e');
    }
  }

  Future<void> _cancelAppointment(int appointmentId, String reason) async {
    try {
      await supabase
          .from('appointments')
          .update({
            'status': 'cancelled',
            'cancel_reason': reason,
            'cancelled_by': supabase.auth.currentUser?.id,
          })
          .eq('id', appointmentId);
    } catch (e) {
      debugPrint('❌ Error cancelling appointment: $e');
      rethrow;
    }
  }

  // ==================== APPROVE LEAVE WITH REASSIGN ====================

  Future<void> _approveLeaveWithReassign(
    int leaveId,
    String barberId,
    DateTime leaveDate,
    String leaveType,
  ) async {
    try {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
          ),
        );
      }

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      await supabase
          .from('barber_leaves')
          .update({
            'status': 'approved',
            'approved_by': currentUser.id,
          })
          .eq('id', leaveId);

      final dateStr =
          '${leaveDate.year.toString().padLeft(4, '0')}-${leaveDate.month.toString().padLeft(2, '0')}-${leaveDate.day.toString().padLeft(2, '0')}';

      String startTime = '00:00:00';
      String endTime = '23:59:59';

      if (leaveType == 'half_day') {
        final leaveRecord = await supabase
            .from('barber_leaves')
            .select('start_time, end_time')
            .eq('id', leaveId)
            .single();

        startTime = leaveRecord['start_time'] ?? '00:00:00';
        endTime = leaveRecord['end_time'] ?? '23:59:59';
      }

      var appointmentsQuery = supabase
          .from('appointments')
          .select('''
            id,
            customer_id,
            service_id,
            variant_id,
            start_time,
            end_time,
            is_vip,
            vip_booking_id
          ''')
          .eq('barber_id', barberId)
          .eq('appointment_date', dateStr)
          .eq('status', 'confirmed');

      if (leaveType == 'half_day') {
        appointmentsQuery = appointmentsQuery
            .gte('start_time', startTime)
            .lte('end_time', endTime);
      }

      final affectedAppointments = await appointmentsQuery;

      debugPrint(
        '📋 Found ${affectedAppointments.length} appointments to handle',
      );

      if (context.mounted) {
        Navigator.pop(context);
      }

      if (affectedAppointments.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Leave approved. No appointments affected.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadData();
        return;
      }

      int processedCount = 0;
      int failedCount = 0;

      for (var appointment in affectedAppointments) {
        try {
          await _handleAffectedAppointment(appointment, dateStr, barberId);
          processedCount++;
        } catch (e) {
          debugPrint('❌ Error processing appointment ${appointment['id']}: $e');
          failedCount++;
        }
      }

      if (context.mounted) {
        String message = 'Leave approved. ';
        if (processedCount > 0) {
          message += '$processedCount appointments processed. ';
        }
        if (failedCount > 0) {
          message += '$failedCount appointments failed.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: failedCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }

      await _loadData();
    } catch (e) {
      debugPrint('❌ Error approving leave with reassign: $e');
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== REJECT WITH REASON ====================

  Future<void> _showRejectReasonDialog(
    int leaveId,
    Map<String, dynamic> leaveData,
  ) async {
    final TextEditingController reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide a reason for rejecting this leave request:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFFFF6B8B),
                    width: 2,
                  ),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a reason'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _rejectLeaveWithReason(
        leaveId,
        reasonController.text.trim(),
        leaveData,
      );
    }
  }

  Future<void> _rejectLeaveWithReason(
    int leaveId,
    String reason,
    Map<String, dynamic> leaveData,
  ) async {
    setState(() => _isLoading = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      await supabase
          .from('barber_leaves')
          .update({
            'status': 'rejected',
            'rejection_reason': reason,
            'rejected_at': DateTime.now().toIso8601String(),
            'rejected_by': currentUser.id,
          })
          .eq('id', leaveId);

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Leave rejected: $reason'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error rejecting leave: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== HELPER METHODS ====================

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '';
    }
  }

  String _formatTimeForDisplay(String time) {
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

  String _getLeaveTypeIcon(String type) {
    switch (type) {
      case 'full_day':
        return '📅';
      case 'half_day':
        return '⌛';
      case 'emergency':
        return '🚨';
      case 'short_leave':
        return '⏱️';
      default:
        return '📝';
    }
  }

  String _getLeaveTypeName(String type) {
    switch (type) {
      case 'full_day':
        return 'Full Day';
      case 'half_day':
        return 'Half Day';
      case 'emergency':
        return 'Emergency';
      case 'short_leave':
        return 'Short Leave';
      default:
        return type;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // ==================== FILTER WIDGETS ====================

  Widget _buildBarberFilter() {
    return Container(
      height: 50,
      child: DropdownButtonFormField<String>(
        value: _selectedBarberId,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        hint: const Text('All Barbers'),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('All Barbers'),
          ),
          ..._barbers.map<DropdownMenuItem<String>>((b) {
            return DropdownMenuItem<String>(
              value: b['id'] as String,
              child: Text(b['name'] as String),
            );
          }).toList(),
        ],
        onChanged: (String? value) {
          setState(() {
            _selectedBarberId = value;
          });
        },
      ),
    );
  }

  Widget _buildDateFilter() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (date != null) setState(() => _selectedDate = date);
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedDate != null
                    ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                    : 'Select Date',
                style: TextStyle(
                  color: _selectedDate != null
                      ? Colors.black
                      : Colors.grey[500],
                ),
              ),
            ),
            if (_selectedDate != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _selectedDate = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      height: 50,
      child: DropdownButtonFormField<String>(
        value: _selectedType,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: const [
          DropdownMenuItem<String>(value: 'all', child: Text('All Types')),
          DropdownMenuItem<String>(value: 'full_day', child: Text('Full Day')),
          DropdownMenuItem<String>(value: 'half_day', child: Text('Half Day')),
          DropdownMenuItem<String>(
            value: 'emergency',
            child: Text('Emergency'),
          ),
          DropdownMenuItem<String>(
            value: 'short_leave',
            child: Text('Short Leave'),
          ),
        ],
        onChanged: (String? value) {
          setState(() {
            _selectedType = value ?? 'all';
          });
        },
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      height: 50,
      child: DropdownButtonFormField<String>(
        value: _selectedStatus,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: const [
          DropdownMenuItem<String>(value: 'all', child: Text('All Status')),
          DropdownMenuItem<String>(value: 'pending', child: Text('Pending')),
          DropdownMenuItem<String>(value: 'approved', child: Text('Approved')),
          DropdownMenuItem<String>(value: 'rejected', child: Text('Rejected')),
        ],
        onChanged: (String? value) {
          setState(() {
            _selectedStatus = value ?? 'all';
          });
        },
      ),
    );
  }

  Widget _buildStatusCell(Map<String, dynamic> leave, String status) {
    final Color statusColor = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<String>(
        value: status,
        icon: Icon(Icons.arrow_drop_down, color: statusColor, size: 16),
        iconSize: 16,
        elevation: 8,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: statusColor,
        ),
        underline: Container(),
        dropdownColor: Colors.white,
        onChanged: (String? newValue) {
          if (newValue != null && newValue != leave['status']) {
            if (newValue == 'rejected') {
              _showRejectReasonDialog(leave['id'], leave);
            } else if (newValue == 'approved') {
              _approveLeaveWithReassign(
                leave['id'],
                leave['barber_id'],
                DateTime.parse(leave['leave_date']),
                leave['leave_type'] ?? 'full_day',
              );
            } else {
              _updateLeaveStatus(leave['id'], newValue, leaveData: leave);
            }
          }
        },
        items: [
          DropdownMenuItem(
            value: 'pending',
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Pending', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          DropdownMenuItem(
            value: 'approved',
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Approved', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          DropdownMenuItem(
            value: 'rejected',
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('Rejected', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLeaveStatus(
    int leaveId,
    String status, {
    Map<String, dynamic>? leaveData,
  }) async {
    if (status == 'rejected' || status == 'approved') return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Status'),
          content: Text(
            'Are you sure you want to change status to ${status.toUpperCase()}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await supabase
            .from('barber_leaves')
            .update({'status': status})
            .eq('id', leaveId);

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated to ${status.toUpperCase()}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating leave: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _addLeave() async {
    if (_barbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No barbers to add leave'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEditLeaveDialog(
        barbers: _barbers,
        salonId: widget.salonId!,
        salonOpenTime: _salonOpenTime,
        salonCloseTime: _salonCloseTime,
        holidays: _holidays,
      ),
    );

    if (result != null && result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request added'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    }
  }

  Future<void> _editLeave(Map<String, dynamic> leave) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEditLeaveDialog(
        barbers: _barbers,
        salonId: widget.salonId!,
        salonOpenTime: _salonOpenTime,
        salonCloseTime: _salonCloseTime,
        leaveToEdit: leave,
        holidays: _holidays,
      ),
    );

    if (result != null && result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    }
  }

  Future<void> _deleteLeave(Map<String, dynamic> leave) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Leave'),
          content: const Text(
            'Are you sure you want to delete this leave request? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await supabase.from('barber_leaves').delete().eq('id', leave['id']);

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting leave: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barber Leaves'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () {
              context.push('/owner/salon/holidays?salonId=${widget.salonId}');
            },
            tooltip: 'Manage Holidays',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: isWeb
                ? Row(
                    children: [
                      Expanded(child: _buildBarberFilter()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateFilter()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTypeFilter()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatusFilter()),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.filter_alt),
                        label: const Text('Apply Filters'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildBarberFilter(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildDateFilter()),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTypeFilter()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildStatusFilter()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _applyFilters,
                              icon: const Icon(Icons.filter_alt),
                              label: const Text('Apply'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B8B),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          Expanded(
            child: _isLoading
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
                            'Add barbers first to manage leaves',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => context.pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B8B),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Go Back'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _leaves.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.beach_access,
                            size: isWeb ? 80 : 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No leave records',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use + button to add leave for barbers',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : isWeb
                ? _buildWebView(padding)
                : _buildMobileView(padding),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLeave,
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ==================== WEB VIEW ====================

  Widget _buildWebView(double padding) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildStatItem(
                    'Total',
                    _leaves.length.toString(),
                    Icons.event_note,
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    'Pending',
                    _leaves
                        .where((l) => l['status'] == 'pending')
                        .length
                        .toString(),
                    Icons.pending,
                    Colors.orange,
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    'Approved',
                    _leaves
                        .where((l) => l['status'] == 'approved')
                        .length
                        .toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    'Rejected',
                    _leaves
                        .where((l) => l['status'] == 'rejected')
                        .length
                        .toString(),
                    Icons.cancel,
                    Colors.red,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Barber',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Date',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Type',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Time',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Reason',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Actions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          ..._leaves.map((leave) {
            final barberId = leave['barber_id'] as String;
            final profile = _barberProfiles[barberId] ?? {};
            final barberName = profile['full_name'] ?? 'Unknown';
            final leaveDate = _formatDate(leave['leave_date']);
            final leaveType = leave['leave_type'] ?? 'full_day';
            final status = leave['status'] ?? 'pending';
            final reason = leave['reason'] ?? 'No reason provided';
            final rejectionReason = leave['rejection_reason'];
            final isHoliday = _isHoliday(leave['leave_date']);
            final holidayName = _getHolidayName(leave['leave_date']);

            String timeDisplay = '';
            if (leaveType == 'full_day' || leaveType == 'emergency') {
              timeDisplay = 'All Day';
            } else if (leaveType == 'half_day') {
              timeDisplay =
                  '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
            } else if (leaveType == 'short_leave') {
              timeDisplay =
                  '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isHoliday ? Colors.orange.withValues(alpha: 0.05) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isHoliday ? Colors.orange : Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(
                            0xFFFF6B8B,
                          ).withValues(alpha: 0.1),
                          backgroundImage: profile['avatar_url'] != null
                              ? NetworkImage(profile['avatar_url'])
                              : null,
                          child: profile['avatar_url'] == null
                              ? Text(
                                  barberName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFFFF6B8B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            barberName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(leaveDate),
                        if (isHoliday && holidayName != null)
                          Text(
                            '⚠️ $holidayName',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Text(
                          _getLeaveTypeIcon(leaveType),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getLeaveTypeName(leaveType),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      timeDisplay,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reason,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (status == 'rejected' &&
                            rejectionReason != null) ...[
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Rejected: $rejectionReason',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red[700],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(child: _buildStatusCell(leave, status)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _editLeave(leave),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteLeave(leave),
                          tooltip: 'Delete',
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
    );
  }

  // ==================== MOBILE VIEW ====================

  Widget _buildMobileView(double padding) {
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _leaves.length,
      itemBuilder: (context, index) {
        final leave = _leaves[index];
        final barberId = leave['barber_id'] as String;
        final profile = _barberProfiles[barberId] ?? {};
        final barberName = profile['full_name'] ?? 'Unknown';
        final leaveDate = _formatDate(leave['leave_date']);
        final leaveType = leave['leave_type'] ?? 'full_day';
        final status = leave['status'] ?? 'pending';
        final reason = leave['reason'] ?? 'No reason provided';
        final rejectionReason = leave['rejection_reason'];
        final isHoliday = _isHoliday(leave['leave_date']);
        final holidayName = _getHolidayName(leave['leave_date']);

        String timeDisplay = '';
        if (leaveType == 'full_day' || leaveType == 'emergency') {
          timeDisplay = 'All Day';
        } else if (leaveType == 'half_day') {
          timeDisplay =
              '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
        } else if (leaveType == 'short_leave') {
          timeDisplay =
              '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(
                    0xFFFF6B8B,
                  ).withValues(alpha: 0.1),
                  backgroundImage: profile['avatar_url'] != null
                      ? NetworkImage(profile['avatar_url'])
                      : null,
                  child: profile['avatar_url'] == null
                      ? Text(
                          barberName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFFF6B8B),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        barberName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _buildStatusCell(leave, status),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          leaveDate,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    if (isHoliday && holidayName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ $holidayName',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _getLeaveTypeIcon(leaveType),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getLeaveTypeName(leaveType),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (timeDisplay.isNotEmpty)
                          Expanded(
                            child: Text(
                              '• $timeDisplay',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      reason,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (status == 'rejected' && rejectionReason != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Rejected: $rejectionReason',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editLeave(leave),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteLeave(leave),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color ?? const Color(0xFFFF6B8B)),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== ADD/EDIT LEAVE DIALOG (UPDATED) ====================

class _AddEditLeaveDialog extends StatefulWidget {
  final List<Map<String, dynamic>> barbers;
  final String salonId;
  final String? salonOpenTime;
  final String? salonCloseTime;
  final Map<String, dynamic>? leaveToEdit;
  final List<Map<String, dynamic>> holidays;

  const _AddEditLeaveDialog({
    required this.barbers,
    required this.salonId,
    this.salonOpenTime,
    this.salonCloseTime,
    this.leaveToEdit,
    required this.holidays,
  });

  @override
  State<_AddEditLeaveDialog> createState() => _AddEditLeaveDialogState();
}

class _AddEditLeaveDialogState extends State<_AddEditLeaveDialog> {
  final supabase = Supabase.instance.client;

  String? _selectedBarberId;
  DateTime? _selectedDate;
  String _leaveType = 'full_day';
  final TextEditingController _reasonController = TextEditingController();

  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  bool _isLoading = false;
  String? _errorMessage;
  bool _isEditMode = false;
  int _editLeaveId = 0;

  TimeOfDay? _minTime;
  TimeOfDay? _maxTime;
  
  bool _isHoliday = false;
  String? _holidayName;

  @override
  void initState() {
    super.initState();
    _parseSalonHours();

    if (widget.leaveToEdit != null) {
      _isEditMode = true;
      _loadLeaveData();
    }
  }

  void _parseSalonHours() {
    if (widget.salonOpenTime != null) {
      final openParts = widget.salonOpenTime!.split(':');
      _minTime = TimeOfDay(
        hour: int.parse(openParts[0]),
        minute: int.parse(openParts[1]),
      );
      _startTime = _minTime!;
    }

    if (widget.salonCloseTime != null) {
      final closeParts = widget.salonCloseTime!.split(':');
      _maxTime = TimeOfDay(
        hour: int.parse(closeParts[0]),
        minute: int.parse(closeParts[1]),
      );
      _endTime = _maxTime!;
    }
  }

  void _loadLeaveData() {
    final leave = widget.leaveToEdit!;

    _selectedBarberId = leave['barber_id'];
    _leaveType = leave['leave_type'] ?? 'full_day';
    _reasonController.text = leave['reason'] ?? '';
    _editLeaveId = leave['id'] as int;

    if (leave['leave_date'] != null) {
      try {
        _selectedDate = DateTime.parse(leave['leave_date']);
        _checkHoliday(_selectedDate!);
      } catch (e) {}
    }

    if (leave['start_time'] != null && leave['end_time'] != null) {
      try {
        final startParts = leave['start_time'].split(':');
        final endParts = leave['end_time'].split(':');

        _startTime = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );

        _endTime = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );
      } catch (e) {}
    }
  }

  void _checkHoliday(DateTime date) {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    
    final holiday = widget.holidays.firstWhere(
      (h) => h['holiday_date'] == dateStr,
      orElse: () => {},
    );
    
    setState(() {
      _isHoliday = holiday.isNotEmpty;
      _holidayName = holiday['name'];
    });
    
    if (_isHoliday && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ $_holidayName - Salon is closed on this day!'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 600 : screenWidth * 0.95,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEditMode ? Icons.edit : Icons.beach_access,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isEditMode ? 'Edit Leave' : 'Add Leave',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isWeb ? 24 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Barber Selection
                    const Text(
                      'Select Barber',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedBarberId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      hint: const Text('Choose barber'),
                      items: widget.barbers.map<DropdownMenuItem<String>>((b) {
                        return DropdownMenuItem<String>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String),
                        );
                      }).toList(),
                      onChanged: _isEditMode
                          ? null
                          : (String? value) {
                              setState(() {
                                _selectedBarberId = value;
                                _errorMessage = null;
                              });
                            },
                    ),

                    const SizedBox(height: 16),

                    // Date Selection with Holiday Check
                    const Text(
                      'Date',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                            _errorMessage = null;
                          });
                          _checkHoliday(date);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isHoliday && !_isEditMode
                                ? Colors.orange
                                : Colors.grey[300]!,
                            width: _isHoliday && !_isEditMode ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: _isHoliday && !_isEditMode
                              ? Colors.orange.withValues(alpha: 0.05)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: _isHoliday && !_isEditMode
                                  ? Colors.orange
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedDate != null
                                        ? DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!)
                                        : 'Select date',
                                    style: TextStyle(
                                      color: _selectedDate != null
                                          ? Colors.black
                                          : Colors.grey[500],
                                      fontWeight: _isHoliday && !_isEditMode
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (_isHoliday && !_isEditMode && _holidayName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '⚠️ $_holidayName - Salon closed',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Holiday Warning
                    if (_isHoliday && !_isEditMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'The salon is closed on this day due to holiday. '
                                  'Leave requests on holidays are not allowed.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Leave Type
                    const Text(
                      'Leave Type',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTypeChip(
                          'Full Day',
                          'full_day',
                          Icons.calendar_month,
                          Colors.purple,
                        ),
                        _buildTypeChip(
                          'Half Day',
                          'half_day',
                          Icons.access_time,
                          Colors.blue,
                        ),
                        _buildTypeChip(
                          'Emergency',
                          'emergency',
                          Icons.warning,
                          Colors.red,
                        ),
                        _buildTypeChip(
                          'Short Leave',
                          'short_leave',
                          Icons.timer,
                          Colors.green,
                        ),
                      ],
                    ),

                    if (_leaveType == 'half_day' ||
                        _leaveType == 'short_leave') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Select Time',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      if (_minTime != null && _maxTime != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info,
                                size: 16,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Salon hours: ${_formatTimeOfDay(_minTime!)} - ${_formatTimeOfDay(_maxTime!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTimePicker(
                                label: 'Start Time',
                                time: _startTime,
                                onTimeSelected: (TimeOfDay newTime) {
                                  setState(() => _startTime = newTime);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTimePicker(
                                label: 'End Time',
                                time: _endTime,
                                onTimeSelected: (TimeOfDay newTime) {
                                  setState(() => _endTime = newTime);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_leaveType == 'short_leave')
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.timer,
                                size: 16,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Maximum 2 hours for short leave',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_leaveType == 'half_day')
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Half day should be approximately 4 hours',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 16),

                    // Reason
                    const Text(
                      'Reason',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter reason for leave',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        _selectedBarberId != null &&
                            _selectedDate != null &&
                            !_isLoading &&
                            (!_isHoliday || _isEditMode)
                        ? _saveLeave
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
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
                        : Text(_isEditMode ? 'Update' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isSelected = _leaveType == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _leaveType = value;
          _errorMessage = null;
        });
      },
      backgroundColor: Colors.grey[100],
      selectedColor: color,
      checkmarkColor: Colors.white,
      showCheckmark: false,
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onTimeSelected,
  }) {
    return GestureDetector(
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onTimeSelected(picked);
        }
      },
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
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimeOfDay(time),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _saveLeave() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if date is holiday
      if (_isHoliday && !_isEditMode) {
        setState(() {
          _errorMessage = 'Cannot add leave on a holiday. The salon is closed.';
          _isLoading = false;
        });
        return;
      }

      if (_leaveType == 'half_day' || _leaveType == 'short_leave') {
        final startMinutes = _startTime.hour * 60 + _startTime.minute;
        final endMinutes = _endTime.hour * 60 + _endTime.minute;

        if (_minTime != null) {
          final minMinutes = _minTime!.hour * 60 + _minTime!.minute;
          if (startMinutes < minMinutes) {
            setState(() {
              _errorMessage = 'Start time cannot be before salon opening time';
              _isLoading = false;
            });
            return;
          }
        }

        if (_maxTime != null) {
          final maxMinutes = _maxTime!.hour * 60 + _maxTime!.minute;
          if (endMinutes > maxMinutes) {
            setState(() {
              _errorMessage = 'End time cannot be after salon closing time';
              _isLoading = false;
            });
            return;
          }
        }

        if (startMinutes >= endMinutes) {
          setState(() {
            _errorMessage = 'Start time must be before end time';
            _isLoading = false;
          });
          return;
        }

        final durationMinutes = endMinutes - startMinutes;

        if (_leaveType == 'half_day') {
          if (durationMinutes < 180 || durationMinutes > 300) {
            setState(() {
              _errorMessage = 'Half day should be approximately 4 hours (3-5 hours range)';
              _isLoading = false;
            });
            return;
          }
        } else if (_leaveType == 'short_leave') {
          if (durationMinutes > 120) {
            setState(() {
              _errorMessage = 'Short leave cannot exceed 2 hours';
              _isLoading = false;
            });
            return;
          }
          if (durationMinutes < 15) {
            setState(() {
              _errorMessage = 'Short leave must be at least 15 minutes';
              _isLoading = false;
            });
            return;
          }
        }
      }

      final dateStr =
          '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';

      if (!_isEditMode) {
        final existingLeave = await supabase
            .from('barber_leaves')
            .select()
            .eq('barber_id', _selectedBarberId!)
            .eq('leave_date', dateStr)
            .maybeSingle();

        if (existingLeave != null) {
          setState(() {
            _errorMessage = 'This barber already has a leave on this date.';
            _isLoading = false;
          });
          return;
        }
      }

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      Map<String, dynamic> leaveData = {
        'barber_id': _selectedBarberId!,
        'salon_id': int.parse(widget.salonId),
        'leave_date': dateStr,
        'leave_type': _leaveType,
        'reason': _reasonController.text.trim(),
        'status': _isEditMode ? widget.leaveToEdit!['status'] : 'pending',
      };

      if (_leaveType == 'half_day' || _leaveType == 'short_leave') {
        leaveData['start_time'] =
            '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';
        leaveData['end_time'] =
            '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00';
      } else {
        leaveData['start_time'] = null;
        leaveData['end_time'] = null;
      }

      if (_isEditMode) {
        await supabase
            .from('barber_leaves')
            .update(leaveData)
            .eq('id', _editLeaveId);
      } else {
        await supabase.from('barber_leaves').insert(leaveData);
      }

      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'leave_id': _editLeaveId ?? leaveData['id'],
          'barber_id': _selectedBarberId,
          'barber_name': widget.barbers.firstWhere(
            (b) => b['id'] == _selectedBarberId,
            orElse: () => {'name': 'Unknown'},
          )['name'],
          'leave_date': dateStr,
          'leave_type': _leaveType,
          'reason': _reasonController.text.trim(),
          'start_time': leaveData['start_time'],
          'end_time': leaveData['end_time'],
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving leave: $e');

      if (e.toString().contains('duplicate key') ||
          e.toString().contains('23505')) {
        setState(() {
          _errorMessage = 'This barber already has a leave on this date.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Error saving leave: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }
}