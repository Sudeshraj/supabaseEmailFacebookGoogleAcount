// lib/screens/barber/barber_appointments_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/timezone_service.dart';

class BarberAppointmentsScreen extends StatefulWidget {
  const BarberAppointmentsScreen({super.key});

  @override
  State<BarberAppointmentsScreen> createState() =>
      _BarberAppointmentsScreenState();
}

class _BarberAppointmentsScreenState extends State<BarberAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // Colors
  final Color _primaryColor = const Color(0xFFFF6B8B);
  final Color _vipColor = const Color(0xFF9C27B0);
  final Color _secondaryColor = const Color(0xFF4CAF50);
  final Color _warningColor = const Color(0xFFFF9800);
  final Color _dangerColor = const Color(0xFFF44336);

  // Data
  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];

  bool _isLoading = true;
  String? _error;

  // Tab controller
  late TabController _tabController;

  // Date selection
  DateTime _selectedDate = DateTime.now();

  // Action states
  bool _isProcessing = false;
  final TextEditingController _cancelReasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBarberData();
    _loadAppointments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cancelReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadBarberData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading barber data: $e');
    }
  }

  String _getDisplayQueueNumber(Map<String, dynamic> appointment) {
    final isVip = appointment['is_vip'] ?? false;
    final regularQueueNumber = appointment['regular_queue_number'];
    final vipQueueNumber = appointment['vip_queue_number'];

    if (isVip && vipQueueNumber != null) {
      return 'VIP-$vipQueueNumber';
    } else if (!isVip && regularQueueNumber != null) {
      return 'Q$regularQueueNumber';
    }
    return '';
  }

  // =====================================================
  // LOAD APPOINTMENTS
  // =====================================================
  Future<void> _loadAppointments() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }

      final appointments = await supabase
          .from('appointments')
          .select('''
            *,
            regular_queue_number,
            vip_queue_number,
            queue_position,
            is_vip
          ''')
          .eq('barber_id', user.id)
          .order('appointment_date', ascending: true);

      if (appointments.isEmpty) {
        setState(() {
          _todayAppointments = [];
          _upcomingAppointments = [];
          _pastAppointments = [];
          _isLoading = false;
        });
        return;
      }

      // Get customer details
      final customerIds = appointments
          .map((a) => a['customer_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> customersMap = {};
      if (customerIds.isNotEmpty) {
        final customers = await supabase
            .from('profiles')
            .select('id, full_name, avatar_url, phone')
            .inFilter('id', customerIds);

        for (var customer in customers) {
          customersMap[customer['id']] = customer;
        }
      }

      // Get service details
      final serviceIds = appointments
          .map((a) => a['service_id'] as int?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<int, String> servicesMap = {};
      if (serviceIds.isNotEmpty) {
        final services = await supabase
            .from('services')
            .select('id, name')
            .inFilter('id', serviceIds);

        for (var service in services) {
          servicesMap[service['id']] = service['name'];
        }
      }

      // Get salon details
      final salonIds = appointments
          .map((a) => a['salon_id'] as int?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<int, String> salonsMap = {};
      if (salonIds.isNotEmpty) {
        final salons = await supabase
            .from('salons')
            .select('id, name')
            .inFilter('id', salonIds);

        for (var salon in salons) {
          salonsMap[salon['id']] = salon['name'];
        }
      }

      // Process appointments
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final List<Map<String, dynamic>> todayList = [];
      final List<Map<String, dynamic>> upcomingList = [];
      final List<Map<String, dynamic>> pastList = [];

      for (var apt in appointments) {
        final customer = customersMap[apt['customer_id']];
        final serviceName = servicesMap[apt['service_id']] ?? 'Service';
        final salonName = salonsMap[apt['salon_id']] ?? 'Salon';

        final appointmentDate = DateTime.parse(apt['appointment_date']);
        final appointmentDateOnly = DateTime(
          appointmentDate.year,
          appointmentDate.month,
          appointmentDate.day,
        );

        final utcStart = apt['start_time'] as String;
        final utcEnd = apt['end_time'] as String;
        final localStart = TimezoneService.utcToLocalTime(
          utcStart,
          appointmentDate,
        );
        final localEnd = TimezoneService.utcToLocalTime(
          utcEnd,
          appointmentDate,
        );

        final displayQueue = _getDisplayQueueNumber(apt);
        final isVip = apt['is_vip'] ?? false;
        final queuePosition = apt['queue_position'];

        final appointmentData = {
          'id': apt['id'],
          'booking_number': apt['booking_number'],
          'appointment_date': apt['appointment_date'],
          'start_time': apt['start_time'],
          'end_time': apt['end_time'],
          'status': apt['status'],
          'is_vip': isVip,
          'price': apt['price'] ?? 0.0,
          'queue_number': apt['queue_number'],
          'regular_queue_number': apt['regular_queue_number'],
          'vip_queue_number': apt['vip_queue_number'],
          'queue_position': queuePosition,
          'display_queue': displayQueue,
          'child_name': apt['child_name'],
          'customer_name': customer?['full_name'] ?? 'Customer',
          'customer_id': apt['customer_id'],
          'customer_avatar': customer?['avatar_url'],
          'customer_phone': customer?['phone'],
          'service_name': serviceName,
          'salon_name': salonName,
          'local_start_time': localStart,
          'local_end_time': localEnd,
          'date_display': DateFormat('MMM dd, yyyy').format(appointmentDate),
          'day_display': DateFormat('EEEE').format(appointmentDate),
          'time_display': '$localStart - $localEnd',
        };

        if (apt['status'] == 'cancelled' || apt['status'] == 'no_show') {
          pastList.add(appointmentData);
        } else if (appointmentDateOnly.isAtSameMomentAs(today)) {
          todayList.add(appointmentData);
        } else if (appointmentDateOnly.isAfter(today)) {
          upcomingList.add(appointmentData);
        } else {
          pastList.add(appointmentData);
        }
      }

      // Sort by queue_position (time order)
      todayList.sort((a, b) {
        final aPos = a['queue_position'] ?? 999;
        final bPos = b['queue_position'] ?? 999;
        return aPos.compareTo(bPos);
      });
      upcomingList.sort((a, b) {
        final aPos = a['queue_position'] ?? 999;
        final bPos = b['queue_position'] ?? 999;
        return aPos.compareTo(bPos);
      });
      pastList.sort((a, b) {
        return b['appointment_date'].compareTo(a['appointment_date']);
      });

      if (mounted) {
        setState(() {
          _todayAppointments = todayList;
          _upcomingAppointments = upcomingList;
          _pastAppointments = pastList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading appointments: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load appointments: $e';
          _isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // START APPOINTMENT
  // =====================================================
  Future<void> _startAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Start Appointment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you ready to start ${appointment['customer_name']}\'s appointment?',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text('Scheduled: ${appointment['local_start_time']}'),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        appointment['is_vip'] == true
                            ? Icons.star
                            : Icons.person,
                        size: 16,
                        color: appointment['is_vip'] == true
                            ? _vipColor
                            : _primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text('Customer: ${appointment['customer_name']}'),
                    ],
                  ),
                  if (appointment['display_queue'] != null &&
                      appointment['display_queue'].toString().isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.queue, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text('Queue: ${appointment['display_queue']}'),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ If you start late, next appointments will be adjusted automatically.',
              style: TextStyle(fontSize: 11, color: _warningColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _secondaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('START NOW'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final nowUtc = DateTime.now().toUtc();

      final result = await supabase.rpc(
        'adjust_on_appointment_start',
        params: {
          'p_appointment_id': appointment['id'],
          'p_actual_start_time': nowUtc.toIso8601String(),
        },
      );

      if (result['success'] == true) {
        if (mounted) {
          String message = '✅ Appointment started!';
          if (result['start_delay_minutes'] != null &&
              result['start_delay_minutes'] > 0) {
            message =
                '⚠️ Started ${result['start_delay_minutes']} min late. Next appointments adjusted.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: result['start_delay_minutes'] > 0
                  ? _warningColor
                  : _secondaryColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadAppointments();
        }
      } else {
        throw Exception(result['message'] ?? 'Failed to start appointment');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // =====================================================
  // END / COMPLETE APPOINTMENT
  // =====================================================
  Future<void> _endAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    final hasOverflow = await _checkForOverflowWarning(appointment['id']);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End Appointment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark ${appointment['customer_name']}\'s appointment as completed?',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text('Started: ${appointment['local_start_time']}'),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        appointment['is_vip'] == true
                            ? Icons.star
                            : Icons.person,
                        size: 16,
                        color: appointment['is_vip'] == true
                            ? _vipColor
                            : _primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text('Customer: ${appointment['customer_name']}'),
                    ],
                  ),
                  if (appointment['display_queue'] != null &&
                      appointment['display_queue'].toString().isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.queue, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text('Queue: ${appointment['display_queue']}'),
                      ],
                    ),
                ],
              ),
            ),
            if (hasOverflow)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _warningColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: _warningColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⚠️ This appointment has an overflow warning. Completing will notify the customer.',
                          style: TextStyle(fontSize: 12, color: _warningColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '⚠️ If you end late, next appointments will be adjusted automatically.',
              style: TextStyle(fontSize: 11, color: _warningColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _secondaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('END APPOINTMENT'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final nowUtc = DateTime.now().toUtc();

      final result = await supabase.rpc(
        'adjust_queue_on_appointment_end',
        params: {
          'p_appointment_id': appointment['id'],
          'p_actual_end_time': nowUtc.toIso8601String(),
          'p_customer_decision': null,
        },
      );

      if (result['success'] == true) {
        if (mounted) {
          String message = '✅ Appointment completed!';
          if (result['delay_minutes'] != null && result['delay_minutes'] > 0) {
            message =
                '⚠️ Completed ${result['delay_minutes']} min late. Next appointments adjusted.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: result['delay_minutes'] > 0
                  ? _warningColor
                  : _secondaryColor,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );

          if (result['needs_confirmation'] == true) {
            _showOverflowNotificationDialog(result);
          }

          await _loadAppointments();
        }
      } else {
        throw Exception(result['message'] ?? 'Failed to complete appointment');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _checkForOverflowWarning(int appointmentId) async {
    try {
      final result = await supabase
          .from('overflow_notifications')
          .select('id')
          .eq('appointment_id', appointmentId)
          .eq('status', 'PENDING')
          .maybeSingle();

      return result != null;
    } catch (e) {
      return false;
    }
  }

  void _showOverflowNotificationDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: _warningColor),
            const SizedBox(width: 8),
            const Text('Customer Notification Sent'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result['message'] ?? 'Appointment exceeds salon hours.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Customer has been notified and can choose to MOVE or CANCEL.\n\nIf no response within 30 minutes, the appointment will be auto-cancelled.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CANCEL APPOINTMENT
  // =====================================================
  Future<void> _cancelAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    String? selectedReason;
    final TextEditingController otherReasonController = TextEditingController();
    bool showOtherField = false;
    String? validationError;

    final List<Map<String, String>> cancelReasons = [
      {'value': 'Customer no show', 'label': '❌ Customer No Show'},
      {
        'value': 'Customer requested cancellation',
        'label': '🙋 Customer Requested Cancellation',
      },
      {'value': 'Barber unavailable', 'label': '👤 Barber Unavailable'},
      {'value': 'Equipment issue', 'label': '🔧 Equipment Issue'},
      {'value': 'Schedule conflict', 'label': '📅 Schedule Conflict'},
      {'value': 'Other', 'label': '📝 Other'},
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Icon(Icons.cancel_outlined, color: _dangerColor, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Cancel Appointment',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            appointment['is_vip'] == true
                                ? Icons.star
                                : Icons.person,
                            size: 16,
                            color: appointment['is_vip'] == true
                                ? _vipColor
                                : _primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            appointment['customer_name'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${appointment['date_display']} at ${appointment['local_start_time']}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      if (appointment['service_name'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.content_cut,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                appointment['service_name'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (appointment['display_queue'] != null &&
                          appointment['display_queue'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.queue,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Queue: ${appointment['display_queue']}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Reason for cancellation',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: 'Select a reason',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: cancelReasons.map((reason) {
                    return DropdownMenuItem(
                      value: reason['value'],
                      child: Text(reason['label']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      selectedReason = value;
                      showOtherField = (value == 'Other');
                      validationError = null;
                      if (!showOtherField) {
                        otherReasonController.clear();
                      }
                    });
                  },
                ),

                if (showOtherField) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: otherReasonController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Please specify the reason...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (_) {
                      setStateDialog(() {
                        validationError = null;
                      });
                    },
                  ),
                ],

                if (validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            validationError!,
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This action cannot be undone. Customer will be notified.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: const Text('KEEP BOOKING'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedReason == null) {
                    setStateDialog(() {
                      validationError = 'Please select a reason';
                    });
                    return;
                  }
                  if (selectedReason == 'Other' &&
                      otherReasonController.text.trim().isEmpty) {
                    setStateDialog(() {
                      validationError = 'Please specify the reason';
                    });
                    return;
                  }
                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dangerColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text('YES, CANCEL'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      String finalReason;
      if (selectedReason == 'Other') {
        finalReason = otherReasonController.text.trim();
      } else {
        finalReason = selectedReason!;
      }

      final result = await supabase.rpc(
        'cancel_booking_and_reorder',
        params: {
          'p_appointment_id': appointment['id'],
          'p_cancelled_by': user.id,
          'p_cancel_reason': finalReason,
          'p_role': 'barber',
        },
      );

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(result['message'] ?? 'Appointment cancelled'),
                ],
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadAppointments();
        }
      } else {
        throw Exception(result['message'] ?? 'Cancellation failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        otherReasonController.clear();
      }
    }
  }

  void _showCustomerInfo(Map<String, dynamic> appointment) {
    final isVip = appointment['is_vip'] ?? false;
    final displayQueue = appointment['display_queue'] ?? '';
    final queuePosition = appointment['queue_position'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: isVip
                        ? _vipColor.withValues(alpha: 0.1)
                        : _primaryColor.withValues(alpha: 0.1),
                    backgroundImage: appointment['customer_avatar'] != null
                        ? NetworkImage(appointment['customer_avatar'])
                        : null,
                    child: appointment['customer_avatar'] == null
                        ? Text(
                            (appointment['customer_name'][0]).toUpperCase(),
                            style: TextStyle(
                              fontSize: 24,
                              color: isVip ? _vipColor : _primaryColor,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              appointment['customer_name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isVip)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _vipColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'VIP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (appointment['customer_phone'] != null)
                          Text(
                            appointment['customer_phone'],
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildInfoTile('Service', appointment['service_name']),
              _buildInfoTile('Date', appointment['date_display']),
              _buildInfoTile('Time', appointment['time_display']),
              _buildInfoTile('Salon', appointment['salon_name']),
              _buildInfoTile(
                'Price',
                'Rs. ${(appointment['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              ),
              if (appointment['child_name'] != null &&
                  appointment['child_name'].toString().isNotEmpty)
                _buildInfoTile('Booked For', appointment['child_name']),
              if (displayQueue.isNotEmpty)
                _buildInfoTile('Queue Number', displayQueue),
              if (queuePosition != null)
                _buildInfoTile('Position', '#$queuePosition'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isVip ? _vipColor : _primaryColor,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('CLOSE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showDatePickerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Select Date'),
        content: SizedBox(
          width: 300,
          height: 350,
          child: CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime.now().subtract(const Duration(days: 30)),
            lastDate: DateTime.now().add(const Duration(days: 60)),
            onDateChanged: (date) {
              Navigator.pop(context);
              setState(() {
                _selectedDate = date;
              });
              _loadAppointments();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Appointments'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _showDatePickerDialog,
            tooltip: 'Select Date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAppointments,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.today, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat(
                            'EEEE, MMM dd, yyyy',
                          ).format(_selectedDate),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadAppointments,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Stats summary
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildStatCard(
                        'Today',
                        _todayAppointments.length,
                        Icons.today,
                        _primaryColor,
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Upcoming',
                        _upcomingAppointments.length,
                        Icons.calendar_month,
                        _warningColor,
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Completed',
                        _pastAppointments
                            .where((a) => a['status'] == 'completed')
                            .length,
                        Icons.check_circle,
                        _secondaryColor,
                      ),
                    ],
                  ),
                ),
                // Tab bar
                TabBar(
                  controller: _tabController,
                  labelColor: _primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: _primaryColor,
                  tabs: const [
                    Tab(text: 'TODAY'),
                    Tab(text: 'UPCOMING'),
                    Tab(text: 'PAST'),
                  ],
                ),
                // Tab views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAppointmentList(_todayAppointments, isToday: true),
                      _buildAppointmentList(
                        _upcomingAppointments,
                        isToday: false,
                      ),
                      _buildAppointmentList(_pastAppointments, isToday: false),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentList(
    List<Map<String, dynamic>> appointments, {
    required bool isToday,
  }) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              isToday ? 'No appointments today' : 'No appointments found',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAppointments,
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: appointments.length,
        itemBuilder: (context, index) =>
            _buildAppointmentCard(appointments[index], isToday),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment, bool isToday) {
    final status = appointment['status'];
    final isInProgress = status == 'in_progress';
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    final isVip = appointment['is_vip'] ?? false;
    final displayQueue = appointment['display_queue'] ?? '';
    final queuePosition = appointment['queue_position'];

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusText = 'Confirmed';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Pending';
        statusIcon = Icons.pending_outlined;
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        statusText = 'In Progress';
        statusIcon = Icons.play_circle_outline;
        break;
      case 'completed':
        statusColor = Colors.purple;
        statusText = 'Completed';
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelled';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.grey;
        statusText = status;
        statusIcon = Icons.circle_outlined;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isInProgress
            ? BorderSide(color: Colors.blue, width: 2)
            : (isVip
                  ? BorderSide(color: _vipColor, width: 1)
                  : BorderSide.none),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isVip
                        ? _vipColor.withValues(alpha: 0.1)
                        : _primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    appointment['local_start_time'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isVip ? _vipColor : _primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (isVip)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _vipColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'VIP',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (displayQueue.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isVip
                          ? _vipColor.withValues(alpha: 0.1)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      displayQueue,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isVip ? _vipColor : Colors.grey[700],
                      ),
                    ),
                  ),
                if (queuePosition != null && queuePosition > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$queuePosition',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Customer info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isVip
                      ? _vipColor.withValues(alpha: 0.1)
                      : _primaryColor.withValues(alpha: 0.1),
                  backgroundImage: appointment['customer_avatar'] != null
                      ? NetworkImage(appointment['customer_avatar'])
                      : null,
                  child: appointment['customer_avatar'] == null
                      ? Text(
                          (appointment['customer_name'][0]).toUpperCase(),
                          style: TextStyle(
                            fontSize: 16,
                            color: isVip ? _vipColor : _primaryColor,
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
                        appointment['customer_name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (appointment['child_name'] != null &&
                          appointment['child_name'].toString().isNotEmpty)
                        Text(
                          'Booked for: ${appointment['child_name']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      Row(
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  onPressed: () => _showCustomerInfo(appointment),
                  tooltip: 'Customer Info',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Service info
            Row(
              children: [
                Icon(Icons.content_cut, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    appointment['service_name'],
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
                Text(
                  'Rs. ${(appointment['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isVip ? _vipColor : _primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // =====================================================
            // ACTION BUTTONS - UPDATED
            // =====================================================
            if (isToday && !isCancelled && !isCompleted)
              Row(
                children: [
                  // START button - only if not started
                  if (!isInProgress)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _startAppointment(appointment),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('START'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  
                  // END button - only if in progress
                  if (isInProgress)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _endAppointment(appointment),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('END'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  
                  const SizedBox(width: 12),
                  
                  // CANCEL button - only if not completed
                  if (!isInProgress)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _cancelAppointment(appointment),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('CANCEL'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _dangerColor,
                          side: BorderSide(color: _dangerColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                ],
              ),
            if (!isToday && isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _secondaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: _secondaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Completed on ${appointment['date_display']}',
                        style: TextStyle(fontSize: 12, color: _secondaryColor),
                      ),
                    ],
                  ),
                ),
              ),
            if (!isToday && isCancelled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _dangerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cancel, size: 16, color: _dangerColor),
                      const SizedBox(width: 8),
                      Text(
                        'Cancelled',
                        style: TextStyle(fontSize: 12, color: _dangerColor),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}