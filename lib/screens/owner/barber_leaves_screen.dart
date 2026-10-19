import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';
import '../../services/timezone_service.dart';
import '../../widgets/customer_choice_dialog.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

// ✅ Safe initial letter for an avatar placeholder
String _safeInitial(String? name) {
  final s = (name ?? '').trim();
  return s.isEmpty ? '?' : s[0].toUpperCase();
}

// ✅ Lets a built-in dialog (e.g. the date picker) scroll instead of
// overflowing when the browser viewport is very short (for example when
// DevTools is docked at the bottom). On normal viewports it does nothing.
class _ShortViewportGuard extends StatelessWidget {
  final Widget child;

  const _ShortViewportGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height;
    if (height >= 420) return child;

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Center(child: child),
      ),
    );
  }
}

class BarberLeavesScreen extends StatefulWidget {
  final String? salonId;

  const BarberLeavesScreen({super.key, this.salonId});

  @override
  State<BarberLeavesScreen> createState() => _BarberLeavesScreenState();
}

class _BarberLeavesScreenState extends State<BarberLeavesScreen> {
  // ✅ Default salon timezone (DB default — NOT user timezone!)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';

  final supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  bool _isLoading = true;
  List<Map<String, dynamic>> _barbers = [];
  List<Map<String, dynamic>> _leaves = [];
  Map<String, Map<String, dynamic>> _barberProfiles = {};

  // ============================================
  // ✅ TIMEZONE VARIABLES
  // ============================================
  String _salonTimezone = _kDefaultSalonTimezone;
  String _userTimezone = '';

  // Salon working hours (stored in UTC)
  String? _salonOpenTimeUtc;
  String? _salonCloseTimeUtc;
  List<Map<String, dynamic>> _holidays = [];

  // Filters
  DateTime? _selectedLocalDate;
  String? _selectedBarberId;
  String _selectedStatus = 'all';
  String _selectedType = 'all';

  // ✅ Responsive variables (default values — safer than late)
  bool _isWeb = false;
  bool _isDark = false;

  // ✅ Scroll Controller for web
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initializeAndLoad();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenWidth = MediaQuery.of(context).size.width;
    _isWeb = screenWidth > 800;
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================
  // ✅ INITIALIZE
  // ============================================
  Future<void> _initializeAndLoad() async {
    await TimezoneService.initialize();

    _userTimezone = TimezoneService.getCurrentTimezone();

    if (_userTimezone.isEmpty) {
      _userTimezone = _kDefaultSalonTimezone;
    }

    debugPrint('✅ User timezone: $_userTimezone');

    await _loadData();
  }

  // ============================================
  // ✅ TIMEZONE HELPERS
  // ============================================

  bool get _isSameTimezone {
    return _salonTimezone.isEmpty || _userTimezone.isEmpty
        ? true
        : _salonTimezone == _userTimezone;
  }

  /// Format UTC time to SALON local time
  String _formatUtcToSalonTime(String? utcTimeStr) {
    if (utcTimeStr == null || utcTimeStr.isEmpty) return '';

    final tz = _salonTimezone.isNotEmpty
        ? _salonTimezone
        : _kDefaultSalonTimezone;

    try {
      return TimezoneService.utcToLocalTimeRecurringWithTimezone(
        utcTimeStr,
        tz,
      );
    } catch (e) {
      debugPrint('❌ Error formatting UTC to salon time: $e');
      return '--:--';
    }
  }

  /// Format UTC time → User timezone (reference only)
  String _formatUtcToUserTime(String? utcTimeStr) {
    if (utcTimeStr == null || utcTimeStr.isEmpty) return '';
    if (_isSameTimezone) return '';
    if (_userTimezone.isEmpty) return '';

    try {
      return TimezoneService.utcToLocalTimeRecurringWithTimezone(
        utcTimeStr,
        _userTimezone,
      );
    } catch (e) {
      debugPrint('❌ Error in _formatUtcToUserTime: $e');
      return '';
    }
  }

  // ============================================
  // DATE CONVERSION HELPERS
  // ============================================

  String _localDateToUtcDateString(DateTime localDate) {
    try {
      final utcDateTime = DateTime.utc(
        localDate.year,
        localDate.month,
        localDate.day,
      );
      return _formatDateForDb(utcDateTime);
    } catch (e) {
      debugPrint('❌ Error converting local date to UTC: $e');
      return '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
    }
  }

  DateTime _utcDateStringToLocalDate(String utcDateStr) {
    try {
      final utcDateTime = DateTime.parse(utcDateStr);
      final tz = _salonTimezone.isNotEmpty
          ? _salonTimezone
          : _kDefaultSalonTimezone;

      final localDateTime =
          TimezoneService.utcToLocalDateTimeForDateWithTimezone(
        '12:00:00',
        utcDateTime,
        tz,
      );
      return DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );
    } catch (e) {
      debugPrint('❌ Error converting UTC date to local: $e');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
  }

  String _formatDateForDb(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateForDisplay(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateForPicker(DateTime date) {
    return DateFormat('EEEE, MMM d, yyyy').format(date);
  }

  String _formatDateForDisplayFromUtc(String? utcDateStr) {
    if (utcDateStr == null) return 'Unknown';
    try {
      final localDate = _utcDateStringToLocalDate(utcDateStr);
      return _formatDateForDisplay(localDate);
    } catch (e) {
      debugPrint('Error formatting date from UTC: $e');
      return utcDateStr;
    }
  }

  bool _isHoliday(String utcDateStr) {
    final localDate = _utcDateStringToLocalDate(utcDateStr);
    final localDateStr = _formatDateForDb(localDate);

    return _holidays.any((h) {
      final holidayLocalDate = _utcDateStringToLocalDate(h['holiday_date']);
      final holidayLocalStr = _formatDateForDb(holidayLocalDate);
      return holidayLocalStr == localDateStr;
    });
  }

  String? _getHolidayName(String utcDateStr) {
    final localDate = _utcDateStringToLocalDate(utcDateStr);
    final localDateStr = _formatDateForDb(localDate);

    final holiday = _holidays.firstWhere((h) {
      final holidayLocalDate = _utcDateStringToLocalDate(h['holiday_date']);
      final holidayLocalStr = _formatDateForDb(holidayLocalDate);
      return holidayLocalStr == localDateStr;
    }, orElse: () => {});
    return holiday['name'];
  }

  // ============================================
  // DATA LOADING
  // ============================================

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      if (widget.salonId == null) {
        if (!mounted) return;
        setState(() {
          _barbers = [];
          _leaves = [];
          _isLoading = false;
        });
        return;
      }

      final salonIdInt = int.tryParse(widget.salonId!);
      if (salonIdInt == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      // ✅ Salon default BEFORE query (NOT user timezone)
      _salonTimezone = _kDefaultSalonTimezone;

      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time, timezone')
          .eq('id', salonIdInt)
          .maybeSingle();

      if (salonResponse != null) {
        _salonOpenTimeUtc = salonResponse['open_time'] as String?;
        _salonCloseTimeUtc = salonResponse['close_time'] as String?;

        final timezone = salonResponse['timezone'] as String?;
        if (timezone != null && timezone.isNotEmpty) {
          _salonTimezone = timezone;
        } else {
          debugPrint(
            '⚠️ Salon TZ empty → default: $_kDefaultSalonTimezone',
          );
        }

        debugPrint('✅ Salon timezone loaded: $_salonTimezone');
      }

      final holidaysResponse = await supabase
          .from('salon_holidays')
          .select('holiday_date, name, description')
          .eq('salon_id', salonIdInt)
          .order('holiday_date', ascending: false);

      _holidays = List<Map<String, dynamic>>.from(holidaysResponse);

      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('''
            barber_id,
            profiles:barber_id (
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

      final List<Map<String, dynamic>> allProfiles = [];
      for (var entry in salonBarbersResponse) {
        final dynamic profileData = entry['profiles'];
        if (profileData != null) {
          final Map<String, dynamic> profile =
              Map<String, dynamic>.from(profileData);
          allProfiles.add(profile);
        }
      }

      _barbers = allProfiles.map<Map<String, dynamic>>((p) {
        return {
          'id': p['id']?.toString() ?? '',
          'name': p['full_name']?.toString() ?? 'Unknown',
          'email': p['email']?.toString() ?? '',
          'avatar': p['avatar_url']?.toString(),
        };
      }).toList();

      _barberProfiles = <String, Map<String, dynamic>>{};
      for (var profile in allProfiles) {
        final id = profile['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          _barberProfiles[id] = profile;
        }
      }

      final barberIds = _barbers.map((b) => b['id'] as String).toList();

      if (barberIds.isNotEmpty) {
        await _loadLeavesWithFilters(barberIds);
      } else {
        _leaves = [];
      }
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _isDark ? Colors.red[800] : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLeavesWithFilters(List<String> barberIds) async {
    try {
      if (widget.salonId == null) return;
      final salonIdInt = int.tryParse(widget.salonId!);
      if (salonIdInt == null) return;

      var query = supabase
          .from('barber_leaves')
          .select()
          .inFilter('barber_id', barberIds)
          .eq('salon_id', salonIdInt);

      if (_selectedBarberId != null) {
        query = query.eq('barber_id', _selectedBarberId!);
      }

      if (_selectedLocalDate != null) {
        final utcDateStr = _localDateToUtcDateString(_selectedLocalDate!);
        query = query.eq('leave_date', utcDateStr);
      }

      if (_selectedStatus != 'all') {
        query = query.eq('status', _selectedStatus);
      }

      if (_selectedType != 'all') {
        query = query.eq('leave_type', _selectedType);
      }

      final leavesResponse = await query;
      var allLeaves = List<Map<String, dynamic>>.from(leavesResponse);

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
    } catch (e) {
      debugPrint('❌ Error loading leaves: $e');
      if (mounted) {
        setState(() {
          _leaves = [];
        });
      }
    }
  }

  Future<void> _applyFilters() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final barberIds = _barbers.map((b) => b['id'] as String).toList();
      await _loadLeavesWithFilters(barberIds);
    } catch (e) {
      debugPrint('❌ Error applying filters: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearFilters() async {
    setState(() {
      _selectedBarberId = null;
      _selectedLocalDate = null;
      _selectedStatus = 'all';
      _selectedType = 'all';
    });
    await _applyFilters();
  }

  // ============================================
  // ✅ SERVICE NAMES (BATCH QUERY - no N+1)
  // ============================================

  Future<Map<int, String>> _getServiceNamesForAppointments(
    List<int> appointmentIds,
  ) async {
    if (appointmentIds.isEmpty) return {};

    try {
      final response = await supabase
          .from('appointment_services')
          .select('appointment_id, service_name, services(name)')
          .inFilter('appointment_id', appointmentIds);

      final Map<int, List<String>> namesByAppointment = {};
      for (var item in response) {
        final apptId = item['appointment_id'] as int;
        final snapshotName = item['service_name'] as String?;
        final svc = item['services'] as Map?;
        final svcName = svc?['name'] as String?;

        final name = (snapshotName != null && snapshotName.isNotEmpty)
            ? snapshotName
            : (svcName ?? '');

        if (name.isNotEmpty) {
          namesByAppointment.putIfAbsent(apptId, () => []).add(name);
        }
      }

      return namesByAppointment.map(
        (k, v) => MapEntry(k, v.join(', ')),
      );
    } catch (e) {
      debugPrint('❌ Error getting service names: $e');
      return {};
    }
  }

  Future<String> _getServiceNameForAppointment(int appointmentId) async {
    final names = await _getServiceNamesForAppointments([appointmentId]);
    return names[appointmentId] ?? 'Unknown Service';
  }

  // ============================================
  // CUSTOMER CHOICE HANDLING
  // ============================================

  Future<void> _handleAffectedAppointment(
    Map<String, dynamic> appointment,
    String utcDateStr,
    String barberId,
  ) async {
    if (!mounted) return;

    try {
      final customerId = appointment['customer_id'];
      final startTimeUtc = appointment['start_time'];

      final localDate = _utcDateStringToLocalDate(utcDateStr);
      final timeFormatted = _formatUtcToSalonTime(startTimeUtc);
      final dateFormatted = _formatDateForDisplay(localDate);

      final customer = await supabase
          .from('profiles')
          .select('full_name, email, fcm_token')
          .eq('id', customerId)
          .maybeSingle();

      if (customer == null) return;

      final priority = _getAppointmentPriority(appointment);

      final availableBarber = await _findAvailableBarber(
        salonId: widget.salonId!,
        appointmentDate: utcDateStr,
        startTime: appointment['start_time'],
        endTime: appointment['end_time'],
        excludeBarberId: barberId,
        appointmentPriority: priority,
      );

      final serviceName = await _getServiceNameForAppointment(
        appointment['id'] as int,
      );

      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => CustomerChoiceDialog(
          customerName: customer['full_name'] ?? 'Customer',
          appointmentDate: dateFormatted,
          appointmentTime: timeFormatted,
          serviceName: serviceName,
          availableBarber: availableBarber,
          onAcceptNewBarber: () => Navigator.pop(dialogContext, 'accept'),
          onMoveToNextDay: () => Navigator.pop(dialogContext, 'next_day'),
          onCancel: () => Navigator.pop(dialogContext, 'cancel'),
        ),
      );

      if (!mounted) return;

      switch (choice) {
        case 'accept':
          if (availableBarber != null) {
            await _reassignToBarber(appointment, availableBarber, barberId);
            await _notificationService.sendAppointmentReassigned(
              customerId: customerId,
              newBarberName: availableBarber['name'],
              appointmentDate: dateFormatted,
              appointmentTime: timeFormatted,
              appointmentId: appointment['id'],
              bookingNumber: appointment['booking_number'] ?? '',
            );
          }
          break;

        case 'next_day':
          final newDate = await _moveToNextDay(appointment);
          final newLocalDate = _utcDateStringToLocalDate(newDate);
          await _notificationService.sendAppointmentMoved(
            customerId: customerId,
            newDate: _formatDateForDisplay(newLocalDate),
            queueNumber: 1,
            appointmentId: appointment['id'],
            bookingNumber: appointment['booking_number'] ?? '',
            oldDate: dateFormatted,
          );
          break;

        case 'cancel':
          await _cancelAppointment(
            appointment['id'],
            'Customer cancelled due to barber leave',
          );
          await _notificationService.sendAppointmentCancelled(
            customerId: customerId,
            reason: 'Customer cancelled due to barber leave',
            appointmentId: appointment['id'],
            bookingNumber: appointment['booking_number'] ?? '',
            cancelledBy: 'System',
          );
          break;
      }
    } catch (e) {
      debugPrint('❌ Error handling affected appointment: $e');
    }
  }

  /// ✅ Batch choice handler for ALL affected appointments
  Future<void> _handleAffectedAppointmentsBatch(
    List<Map<String, dynamic>> appointments,
    String utcDateStr,
    String barberId,
  ) async {
    if (!mounted || appointments.isEmpty) return;

    try {
      Map<String, dynamic>? commonAvailableBarber;
      if (appointments.length == 1) {
        await _handleAffectedAppointment(
          appointments.first,
          utcDateStr,
          barberId,
        );
        return;
      }

      final firstAppt = appointments.first;
      commonAvailableBarber = await _findAvailableBarber(
        salonId: widget.salonId!,
        appointmentDate: utcDateStr,
        startTime: firstAppt['start_time'],
        endTime: firstAppt['end_time'],
        excludeBarberId: barberId,
        appointmentPriority: _getAppointmentPriority(firstAppt),
      );

      if (!mounted) return;

      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '${appointments.length} Appointments Affected',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How would you like to handle all affected appointments?',
                style: TextStyle(
                  color: _isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This decision will be applied to all ${appointments.length} appointments.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (commonAvailableBarber != null)
              TextButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'accept_all'),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text(
                  'Reassign to ${commonAvailableBarber['name']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'next_day_all'),
              icon: const Icon(Icons.event_available, size: 16),
              label: const Text(
                'Move all to next day',
                style: TextStyle(fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'cancel_all'),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text(
                'Cancel all',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );

      if (!mounted || choice == null) return;

      int processedCount = 0;
      int failedCount = 0;

      for (var appointment in appointments) {
        try {
          switch (choice) {
            case 'accept_all':
              if (commonAvailableBarber != null) {
                await _reassignToBarber(
                  appointment,
                  commonAvailableBarber,
                  barberId,
                );
                if (appointment['customer_id'] != null) {
                  final localDate = _utcDateStringToLocalDate(utcDateStr);
                  await _notificationService.sendAppointmentReassigned(
                    customerId: appointment['customer_id'],
                    newBarberName: commonAvailableBarber['name'],
                    appointmentDate: _formatDateForDisplay(localDate),
                    appointmentTime:
                        _formatUtcToSalonTime(appointment['start_time']),
                    appointmentId: appointment['id'],
                    bookingNumber: appointment['booking_number'] ?? '',
                  );
                }
              }
              break;

            case 'next_day_all':
              final newDate = await _moveToNextDay(appointment);
              final newLocalDate = _utcDateStringToLocalDate(newDate);
              if (appointment['customer_id'] != null) {
                await _notificationService.sendAppointmentMoved(
                  customerId: appointment['customer_id'],
                  newDate: _formatDateForDisplay(newLocalDate),
                  queueNumber: 1,
                  appointmentId: appointment['id'],
                  bookingNumber: appointment['booking_number'] ?? '',
                  oldDate: _formatDateForDisplay(
                    _utcDateStringToLocalDate(utcDateStr),
                  ),
                );
              }
              break;

            case 'cancel_all':
              await _cancelAppointment(
                appointment['id'],
                'Cancelled due to barber leave (batch)',
              );
              if (appointment['customer_id'] != null) {
                await _notificationService.sendAppointmentCancelled(
                  customerId: appointment['customer_id'],
                  reason: 'Cancelled due to barber leave',
                  appointmentId: appointment['id'],
                  bookingNumber: appointment['booking_number'] ?? '',
                  cancelledBy: 'System',
                );
              }
              break;
          }
          processedCount++;
        } catch (e) {
          debugPrint(
              '❌ Error processing appointment ${appointment['id']}: $e');
          failedCount++;
        }
      }

      if (!mounted) return;
      final message = failedCount > 0
          ? '$processedCount processed, $failedCount failed'
          : '$processedCount appointments processed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failedCount > 0
              ? (_isDark ? Colors.orange[800] : Colors.orange)
              : (_isDark ? Colors.green[800] : Colors.green),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error in batch handling: $e');
    }
  }

  int _getAppointmentPriority(Map<String, dynamic> appointment) {
    try {
      final vipPriority = appointment['vip_priority'];
      if (vipPriority is int) return vipPriority;
      return 4;
    } catch (e) {
      debugPrint('❌ Error getting appointment priority: $e');
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
      final salonIdInt = int.tryParse(salonId);
      if (salonIdInt == null) return null;

      final salonBarbers = await supabase
          .from('salon_barbers')
          .select('''
            barber_id,
            profiles:barber_id (
                user_roles!inner (
                    status
                )
            )
        ''')
          .eq('salon_id', salonIdInt)
          .eq('status', 'active')
          .eq('profiles.user_roles.role_id', 2)
          .eq('profiles.user_roles.status', 'active');

      final List<String> barberIds = [];
      for (var entry in salonBarbers) {
        final dynamic profileData = entry['profiles'];
        if (profileData != null) {
          final Map<String, dynamic> profile =
              Map<String, dynamic>.from(profileData);
          final userRoles = profile['user_roles'] as List? ?? [];
          bool isActive = false;
          for (var role in userRoles) {
            if (role['status'] == 'active') {
              isActive = true;
              break;
            }
          }
          if (isActive) {
            final barberId = entry['barber_id']?.toString();
            if (barberId != null && barberId.isNotEmpty) {
              barberIds.add(barberId);
            }
          }
        }
      }

      final availableBarberIds =
          barberIds.where((id) => id != excludeBarberId).toList();

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
            'name': profile?['full_name']?.toString() ?? 'Another barber',
          };
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error finding available barber: $e');
      return null;
    }
  }

  /// ✅ FIXED: check all active appointment statuses
  Future<bool> _isBarberAvailable(
    String barberId,
    String appointmentDate,
    String startTime,
    String endTime,
  ) async {
    try {
      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', barberId)
          .eq('role_id', 2)
          .maybeSingle();

      if (roleCheck == null || roleCheck['status'] != 'active') {
        return false;
      }

      final localDate = _utcDateStringToLocalDate(appointmentDate);
      final dayOfWeek = localDate.weekday;

      final schedule = await supabase
          .from('barber_schedules')
          .select()
          .eq('barber_id', barberId)
          .eq('day_of_week', dayOfWeek)
          .maybeSingle();

      if (schedule == null) return false;
      if (schedule['is_working'] != true) return false;

      final leave = await supabase
          .from('barber_leaves')
          .select()
          .eq('barber_id', barberId)
          .eq('leave_date', appointmentDate)
          .eq('status', 'approved')
          .maybeSingle();

      if (leave != null) return false;

      // ✅ FIX: include pending / in_progress / waiting_list (was only 'confirmed')
      final appointments = await supabase
          .from('appointments')
          .select('start_time, end_time')
          .eq('barber_id', barberId)
          .eq('appointment_date', appointmentDate)
          .inFilter('status', ['pending', 'confirmed', 'in_progress']);

      for (final appt in appointments) {
        final existingStart = appt['start_time'] as String?;
        final existingEnd = appt['end_time'] as String?;
        if (existingStart == null || existingEnd == null) continue;

        final noOverlap = endTime.compareTo(existingStart) <= 0 ||
            startTime.compareTo(existingEnd) >= 0;

        if (!noOverlap) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error checking barber availability: $e');
      return false;
    }
  }

  Future<void> _reassignToBarber(
    Map<String, dynamic> appointment,
    Map<String, dynamic> newBarber,
    String oldBarberId,
  ) async {
    try {
      await supabase
          .from('appointments')
          .update({
            'barber_id': newBarber['barber_id'],
            'reassigned_from': oldBarberId,
            'status': 'confirmed',
            'notes': 'Reassigned due to barber leave',
          })
          .eq('id', appointment['id']);

      // ✅ NEW: server RPC for queue + time shift (after reassignment)
      await _adjustQueueNumbers(
        barberId: newBarber['barber_id'],
        date: appointment['appointment_date'],
        newAppointment: appointment,
      );
    } catch (e) {
      debugPrint('❌ Error reassigning to barber: $e');
      rethrow;
    }
  }

  Future<int> _getAppointmentDuration(int appointmentId) async {
    try {
      final response = await supabase
          .from('appointment_services')
          .select('duration')
          .eq('appointment_id', appointmentId);

      if (response.isEmpty) return 30;

      int totalDuration = 0;
      for (var item in response) {
        final dur = item['duration'] as int?;
        if (dur != null) totalDuration += dur;
      }

      return totalDuration > 0 ? totalDuration : 30;
    } catch (e) {
      debugPrint('❌ Error getting appointment duration: $e');
      return 30;
    }
  }

  /// ✅ FIXED: now checks salon holiday + barber leave + schedule
  Future<bool> _isNonWorkingDay(String barberId, DateTime localDate) async {
    try {
      if (widget.salonId == null) return false;
      final salonIdInt = int.tryParse(widget.salonId!);
      if (salonIdInt == null) return false;

      final utcDateStr = _localDateToUtcDateString(localDate);

      // 1. Holiday check
      final holiday = await supabase
          .from('salon_holidays')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('holiday_date', utcDateStr)
          .maybeSingle();

      if (holiday != null) return true;

      // ✅ NEW: 2. Approved full-day leave check
      final leave = await supabase
          .from('barber_leaves')
          .select('leave_type')
          .eq('barber_id', barberId)
          .eq('leave_date', utcDateStr)
          .eq('status', 'approved')
          .maybeSingle();

      if (leave != null) {
        final leaveType = leave['leave_type'] as String?;
        // full_day / emergency → not working the whole day
        if (leaveType == 'full_day' || leaveType == 'emergency') {
          return true;
        }
      }

      // 3. Barber schedule check
      final dayOfWeek = localDate.weekday;
      final schedule = await supabase
          .from('barber_schedules')
          .select('is_working')
          .eq('barber_id', barberId)
          .eq('salon_id', salonIdInt)
          .eq('day_of_week', dayOfWeek)
          .maybeSingle();

      if (schedule == null) return true;
      return schedule['is_working'] != true;
    } catch (e) {
      debugPrint('❌ Error checking non-working day: $e');
      return false;
    }
  }

  /// ✅ FIXED: uses salon open time instead of hardcoded '09:00:00'
  Future<String> _moveToNextDay(Map<String, dynamic> appointment) async {
    try {
      final barberId = appointment['barber_id'] as String;
      final duration = await _getAppointmentDuration(appointment['id'] as int);

      DateTime nextLocalDate =
          _utcDateStringToLocalDate(appointment['appointment_date'])
              .add(const Duration(days: 1));

      int loopGuard = 0;
      while (await _isNonWorkingDay(barberId, nextLocalDate)) {
        nextLocalDate = nextLocalDate.add(const Duration(days: 1));
        loopGuard++;
        if (loopGuard > 30) {
          throw Exception(
              'No working day found within 30 days for this barber');
        }
      }

      final nextUtcDateStr = _localDateToUtcDateString(nextLocalDate);

      // ✅ FIX: use salon open time (not hardcoded 09:00:00 UTC)
      final salonOpenUtc =
          (_salonOpenTimeUtc != null && _salonOpenTimeUtc!.isNotEmpty)
              ? _salonOpenTimeUtc!
              : _fallbackSalonOpenUtc();

      final endTime = _calculateEndTimeWithDuration(salonOpenUtc, duration);

      // Shift existing appointments on the target day
      final appointmentsToShift = await supabase
          .from('appointments')
          .select('id, queue_number')
          .eq('barber_id', barberId)
          .eq('appointment_date', nextUtcDateStr)
          .eq('status', 'confirmed')
          .order('queue_number', ascending: false);

      for (var appt in appointmentsToShift) {
        final qn = appt['queue_number'] as int?;
        if (qn == null) continue;
        await supabase
            .from('appointments')
            .update({'queue_number': qn + 1})
            .eq('id', appt['id']);
      }

      await supabase
          .from('appointments')
          .update({
            'appointment_date': nextUtcDateStr,
            'start_time': salonOpenUtc, // ✅ salon open time
            'end_time': endTime,
            'queue_number': 1,
            'status': 'confirmed',
            'notes':
                'Moved from ${appointment['appointment_date']} due to barber leave',
          })
          .eq('id', appointment['id']);

      // ✅ Server RPC for full time-shift + queue reorder
      await _adjustQueueNumbers(
        barberId: barberId,
        date: nextUtcDateStr,
        newAppointment: appointment,
      );

      debugPrint(
        '✅ Appointment moved to $nextUtcDateStr at salon open ($salonOpenUtc UTC)',
      );
      return nextUtcDateStr;
    } catch (e) {
      debugPrint('❌ Error moving to next day: $e');
      rethrow;
    }
  }

  /// ✅ Fallback salon open time (salon TZ 09:00 → UTC)
  ///    Used only if the salon row had no open_time.
  String _fallbackSalonOpenUtc() {
    try {
      return TimezoneService.localToUtcTimeRecurringWithTimezone(
        '09:00',
        _salonTimezone.isNotEmpty
            ? _salonTimezone
            : _kDefaultSalonTimezone,
      );
    } catch (_) {
      return '03:30:00'; // Asia/Colombo 09:00 fallback
    }
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

  /// ✅ FIXED: delegates to server RPC `assign_queue_numbers_with_shift`
  ///          which handles time shift + queue numbers + VIP priority
  Future<void> _adjustQueueNumbers({
    required String barberId,
    required String date,
    required Map<String, dynamic> newAppointment,
  }) async {
    try {
      await supabase.rpc('assign_queue_numbers_with_shift', params: {
        'p_barber_id': barberId,
        'p_appointment_date': date,
      });
      debugPrint('✅ Queue adjusted via server RPC');
    } catch (e) {
      debugPrint('❌ Error adjusting queue via RPC: $e');
      // Non-fatal: appointment is still reassigned / moved
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

  // ============================================
  // LEAVE APPROVAL WITH REASSIGN
  // ============================================

  Future<void> _approveLeaveWithReassign(
    int leaveId,
    String barberId,
    String utcDateStr,
    String leaveType,
  ) async {
    if (!mounted) return;

    final loadingDialogFuture = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      await supabase
          .from('barber_leaves')
          .update({'status': 'approved', 'approved_by': currentUser.id})
          .eq('id', leaveId);

      String startTime = '00:00:00';
      String endTime = '23:59:59';

      if (leaveType == 'half_day' || leaveType == 'short_leave') {
        final leaveRecord = await supabase
            .from('barber_leaves')
            .select('start_time, end_time')
            .eq('id', leaveId)
            .maybeSingle();

        if (leaveRecord != null) {
          startTime = leaveRecord['start_time'] as String? ?? '00:00:00';
          endTime = leaveRecord['end_time'] as String? ?? '23:59:59';
        }
      }

      var appointmentsQuery = supabase
          .from('appointments')
          .select('''
            id,
            customer_id,
            booking_number,
            start_time,
            end_time,
            is_vip,
            vip_booking_id,
            vip_priority,
            appointment_date
          ''')
          .eq('barber_id', barberId)
          .eq('appointment_date', utcDateStr)
          .eq('status', 'confirmed');

      // ✅ FIX: correct overlap logic (partial overlaps included)
      if (leaveType == 'half_day' || leaveType == 'short_leave') {
        // Any appointment overlapping [startTime, endTime]:
        //   appt.start < leave.end AND appt.end > leave.start
        appointmentsQuery = appointmentsQuery
            .lt('start_time', endTime)
            .gt('end_time', startTime);
      }

      final affectedAppointments = await appointmentsQuery;

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await loadingDialogFuture;

      if (affectedAppointments.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Leave approved. No appointments affected.'),
            backgroundColor: _isDark ? Colors.green[800] : Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadData();
        return;
      }

      if (affectedAppointments.length > 1) {
        await _handleAffectedAppointmentsBatch(
          List<Map<String, dynamic>>.from(affectedAppointments),
          utcDateStr,
          barberId,
        );
      } else {
        await _handleAffectedAppointment(
          affectedAppointments.first,
          utcDateStr,
          barberId,
        );
      }

      await _loadData();
    } catch (e) {
      debugPrint('❌ Error approving leave with reassign: $e');
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await loadingDialogFuture;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _isDark ? Colors.red[800] : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showRejectReasonDialog(
    int leaveId,
    Map<String, dynamic> leaveData,
  ) async {
    final TextEditingController reasonController = TextEditingController();

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Reject Leave',
            style: dialogContext.titleLarge.copyWith(
              color: _isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please provide a reason for rejecting this leave request:',
                  style: dialogContext.bodyMedium.copyWith(
                    color: _isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  style: TextStyle(
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter reason...',
                    hintStyle: TextStyle(
                      color: _isDark ? Colors.white70 : Colors.grey[500],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 2,
                      ),
                    ),
                    fillColor: _isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    filled: true,
                  ),
                  autofocus: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: _isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a reason'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reject'),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        await _rejectLeaveWithReason(
          leaveId,
          reasonController.text.trim(),
          leaveData,
        );
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _rejectLeaveWithReason(
    int leaveId,
    String reason,
    Map<String, dynamic> leaveData,
  ) async {
    if (!mounted) return;
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
            backgroundColor: _isDark ? Colors.red[800] : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error rejecting leave: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _isDark ? Colors.red[800] : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================
  // HELPER METHODS
  // ============================================

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

  bool get _hasActiveFilters {
    return _selectedBarberId != null ||
        _selectedLocalDate != null ||
        _selectedStatus != 'all' ||
        _selectedType != 'all';
  }

  // ============================================
  // FILTER WIDGETS
  // ============================================

  Widget _buildBarberFilter() {
    final isDark = _isDark;

    return SizedBox(
      height: 50,
      child: DropdownButtonFormField<String>(
        initialValue: _selectedBarberId,
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          filled: true,
        ),
        hint: Text(
          'All Barbers',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
        ),
        dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
        ),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(
              'All Barbers',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          ..._barbers.map<DropdownMenuItem<String>>((b) {
            return DropdownMenuItem<String>(
              value: b['id'] as String,
              child: Text(
                b['name'] as String,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            );
          }),
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
    final isDark = _isDark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedLocalDate ?? today,
          firstDate: today,
          lastDate: now.add(const Duration(days: 365)),
          builder: (dateCtx, child) {
            return MediaQuery(
              data: MediaQuery.of(dateCtx).copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: Theme(
                data: Theme.of(dateCtx).copyWith(
                  colorScheme: ColorScheme(
                    brightness: isDark ? Brightness.dark : Brightness.light,
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    secondary: AppTheme.primary,
                    onSecondary: Colors.white,
                    error: Colors.red,
                    onError: Colors.white,
                    surface: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    onSurface: isDark ? Colors.white : Colors.black87,
                  ),
                  dialogTheme: DialogThemeData(
                    backgroundColor: isDark
                        ? const Color(0xFF1E1E1E)
                        : Colors.white,
                  ),
                ),
                child: _ShortViewportGuard(child: child!),
              ),
            );
          },
        );
        if (date != null && mounted) {
          setState(() => _selectedLocalDate = date);
        }
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedLocalDate != null
                    ? _formatDateForPicker(_selectedLocalDate!)
                    : 'Select Date',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _selectedLocalDate != null
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? Colors.white70 : Colors.grey[500]),
                ),
              ),
            ),
            if (_selectedLocalDate != null)
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: isDark ? Colors.white60 : Colors.grey[500],
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() => _selectedLocalDate = null);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    final isDark = _isDark;

    return SizedBox(
      height: 50,
      child: DropdownButtonFormField<String>(
        initialValue: _selectedType,
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          filled: true,
        ),
        dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
        ),
        items: const [
          DropdownMenuItem<String>(
              value: 'all',
              child: Text('All Types', overflow: TextOverflow.ellipsis)),
          DropdownMenuItem<String>(
              value: 'full_day',
              child: Text('Full Day', overflow: TextOverflow.ellipsis)),
          DropdownMenuItem<String>(
              value: 'half_day',
              child: Text('Half Day', overflow: TextOverflow.ellipsis)),
          DropdownMenuItem<String>(
            value: 'emergency',
            child: Text('Emergency', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: 'short_leave',
            child: Text('Short Leave', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: (String? value) {
          if (mounted) {
            setState(() {
              _selectedType = value ?? 'all';
            });
          }
        },
      ),
    );
  }

  Widget _buildStatusFilter() {
    final isDark = _isDark;

    return SizedBox(
      height: 50,
      child: DropdownButtonFormField<String>(
        initialValue: _selectedStatus,
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          filled: true,
        ),
        dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
        ),
        items: const [
          DropdownMenuItem<String>(
              value: 'all',
              child: Text('All Status', overflow: TextOverflow.ellipsis)),
          DropdownMenuItem<String>(
              value: 'pending',
              child: Text('Pending', overflow: TextOverflow.ellipsis)),
          DropdownMenuItem<String>(
              value: 'approved',
              child: Text('Approved', overflow: TextOverflow.ellipsis)),
          DropdownMenuItem<String>(
              value: 'rejected',
              child: Text('Rejected', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (String? value) {
          if (mounted) {
            setState(() {
              _selectedStatus = value ?? 'all';
            });
          }
        },
      ),
    );
  }

  Widget _buildStatusCell(Map<String, dynamic> leave, String status) {
    final Color statusColor = _getStatusColor(status);
    final isDark = _isDark;

    const validStatuses = ['pending', 'approved', 'rejected'];
    final safeStatus = validStatuses.contains(status) ? status : 'pending';

    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeStatus,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: statusColor, size: 16),
          iconSize: 16,
          elevation: 8,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: statusColor,
          ),
          underline: const SizedBox.shrink(),
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          onChanged: (String? newValue) {
            if (newValue != null && newValue != leave['status']) {
              if (newValue == 'rejected') {
                _showRejectReasonDialog(leave['id'], leave);
              } else if (newValue == 'approved') {
                _approveLeaveWithReassign(
                  leave['id'],
                  leave['barber_id'],
                  leave['leave_date'],
                  leave['leave_type'] ?? 'full_day',
                );
              } else {
                _updateLeaveStatus(leave['id'], newValue);
              }
            }
          },
          items: [
            DropdownMenuItem(
              value: 'pending',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _StatusDot(color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'approved',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _StatusDot(color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'Approved',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'rejected',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _StatusDot(color: Colors.red),
                  const SizedBox(width: 4),
                  Text(
                    'Rejected',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white : Colors.black87,
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

  Future<void> _updateLeaveStatus(int leaveId, String status) async {
    if (status == 'rejected' || status == 'approved') return;
    if (!mounted) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Update Status',
            style: dialogContext.titleLarge.copyWith(
              color: _isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            'Are you sure you want to change status to ${status.toUpperCase()}?',
            style: dialogContext.bodyMedium.copyWith(
              color: _isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: _isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
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

    if (confirm == true && mounted) {
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
              backgroundColor: _isDark ? Colors.orange[800] : Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating leave: $e'),
              backgroundColor: _isDark ? Colors.red[800] : Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _addLeave() async {
    if (_barbers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No barbers to add leave'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _AddEditLeaveDialog(
        barbers: _barbers,
        salonId: widget.salonId!,
        salonTimezone: _salonTimezone,
        userTimezone: _userTimezone,
        salonOpenTimeUtc: _salonOpenTimeUtc,
        salonCloseTimeUtc: _salonCloseTimeUtc,
        holidays: _holidays,
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request added'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadData();
    }
  }

  Future<void> _editLeave(Map<String, dynamic> leave) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _AddEditLeaveDialog(
        barbers: _barbers,
        salonId: widget.salonId!,
        salonTimezone: _salonTimezone,
        userTimezone: _userTimezone,
        salonOpenTimeUtc: _salonOpenTimeUtc,
        salonCloseTimeUtc: _salonCloseTimeUtc,
        leaveToEdit: leave,
        holidays: _holidays,
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave updated successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadData();
    }
  }

  Future<void> _deleteLeave(Map<String, dynamic> leave) async {
    if (!mounted) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Delete Leave',
            style: dialogContext.titleLarge.copyWith(
              color: _isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this leave request? This action cannot be undone.',
            style: dialogContext.bodyMedium.copyWith(
              color: _isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: _isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
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

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);

      try {
        await supabase.from('barber_leaves').delete().eq('id', leave['id']);

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave deleted successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting leave: $e'),
              backgroundColor: _isDark ? Colors.red[800] : Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // ============================================
  // MAIN BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final double padding = _isWeb ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Barber Leaves',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: () {
              context.push('/owner/salon/holidays?salonId=${widget.salonId}');
            },
            tooltip: 'Manage Holidays',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLeave,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _buildFiltersSection(_isWeb, padding),
            ),
            SliverFillRemaining(
              hasScrollBody: true,
              child: _buildMainContent(_isWeb, padding),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersSection(bool isWeb, double padding) {
    final isDark = _isDark;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
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
                if (_hasActiveFilters) ...[
                  OutlinedButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          isDark ? Colors.white70 : Colors.grey[700],
                      side: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                ElevatedButton.icon(
                  onPressed: _applyFilters,
                  icon: const Icon(Icons.filter_alt),
                  label: const Text('Apply Filters'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
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
              mainAxisSize: MainAxisSize.min,
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
                        label: const Text(
                          'Apply',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear Filters',
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          foregroundColor:
                              isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _scrollableCentered(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 0 ? constraints.maxHeight : 0,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }

  Widget _buildMainContent(bool isWeb, double padding) {
    final isDark = _isDark;

    if (_isLoading) {
      return _scrollableCentered(
        Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Loading...',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_barbers.isEmpty) {
      return _scrollableCentered(
        Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off,
                size: isWeb ? 80 : 64,
                color: isDark ? Colors.white30 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No barbers found',
                style: TextStyle(
                  fontSize: isWeb ? 18 : 16,
                  color: isDark ? Colors.white60 : Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add barbers first to manage leaves',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[600],
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

    if (_leaves.isEmpty) {
      return _scrollableCentered(
        Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.beach_access,
                size: isWeb ? 80 : 64,
                color: isDark ? Colors.white30 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No leave records',
                style: TextStyle(
                  fontSize: isWeb ? 18 : 16,
                  color: isDark ? Colors.white60 : Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _hasActiveFilters
                    ? 'Try clearing filters or add a new leave'
                    : 'Use + button to add leave for barbers',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(color: AppTheme.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return isWeb
        ? Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8.0,
            radius: const Radius.circular(10),
            scrollbarOrientation: ScrollbarOrientation.right,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(padding),
              child: _buildWebContent(),
            ),
          )
        : _buildMobileContent();
  }

  Widget _buildWebContent() {
    return Column(
      children: [
        _buildStatsCard(),
        const SizedBox(height: 16),
        _buildWebTableHeader(),
        const SizedBox(height: 8),
        ..._leaves.map((leave) => _buildWebLeaveRow(leave)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMobileContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _leaves.length,
        itemBuilder: (context, index) {
          final leave = _leaves[index];
          return _buildMobileLeaveCard(leave);
        },
      ),
    );
  }

  Widget _buildStatsCard() {
    final isDark = _isDark;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildStatItem(
                'Total',
                _leaves.length.toString(),
                Icons.event_note,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.grey[800]! : Colors.grey[300],
              ),
              _buildStatItem(
                'Pending',
                _leaves.where((l) => l['status'] == 'pending').length.toString(),
                Icons.pending,
                Colors.orange,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.grey[800]! : Colors.grey[300],
              ),
              _buildStatItem(
                'Approved',
                _leaves
                    .where((l) => l['status'] == 'approved')
                    .length
                    .toString(),
                Icons.check_circle,
                Colors.green,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.grey[800]! : Colors.grey[300],
              ),
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
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    final isDark = _isDark;
    final accentColor = color ?? AppTheme.primary;

    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: accentColor),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebTableHeader() {
    final isDark = _isDark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Barber',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Date',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Type',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Time',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Reason',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'Status',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Actions',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLeaveRow(Map<String, dynamic> leave) {
    final isDark = _isDark;
    final barberId = leave['barber_id'] as String;
    final profile = _barberProfiles[barberId] ?? {};
    final barberName = profile['full_name'] ?? 'Unknown';
    final avatarUrl = profile['avatar_url'];
    final hasAvatar = avatarUrl != null && avatarUrl.toString().isNotEmpty;
    final leaveDate = _formatDateForDisplayFromUtc(leave['leave_date']);
    final leaveType = leave['leave_type'] ?? 'full_day';
    final status = leave['status'] ?? 'pending';
    final reason = leave['reason'] ?? 'No reason provided';
    final rejectionReason = leave['rejection_reason'];
    final isHoliday = _isHoliday(leave['leave_date']);
    final holidayName = _getHolidayName(leave['leave_date']);

    String timeDisplay = '';
    String? userTimeDisplay;
    if (leaveType == 'full_day' || leaveType == 'emergency') {
      timeDisplay = 'All Day';
    } else if (leaveType == 'half_day' || leaveType == 'short_leave') {
      final startSalon = _formatUtcToSalonTime(leave['start_time']);
      final endSalon = _formatUtcToSalonTime(leave['end_time']);
      timeDisplay = '$startSalon - $endSalon';

      final userStart = _formatUtcToUserTime(leave['start_time']);
      final userEnd = _formatUtcToUserTime(leave['end_time']);
      if (userStart.isNotEmpty && userEnd.isNotEmpty) {
        userTimeDisplay = '$userStart - $userEnd';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHoliday
            ? Colors.orange.withValues(alpha: 0.05)
            : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHoliday
              ? Colors.orange
              : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  backgroundImage: hasAvatar
                      ? NetworkImage(avatarUrl.toString())
                      : null,
                  child: !hasAvatar
                      ? Text(
                          _safeInitial(barberName),
                          style: TextStyle(
                            color: AppTheme.primary,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  leaveDate,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (isHoliday && holidayName != null)
                  Text(
                    '⚠️ $holidayName',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getLeaveTypeIcon(leaveType),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _getLeaveTypeName(leaveType),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeDisplay,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                if (userTimeDisplay != null)
                  Text(
                    'Your time: $userTimeDisplay',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.blue[300] : Colors.blue[700],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (status == 'rejected' && rejectionReason != null) ...[
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.red,
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
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: isDark ? Colors.blue[300] : Colors.blue,
                  ),
                  onPressed: () => _editLeave(leave),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
                  onPressed: () => _deleteLeave(leave),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLeaveCard(Map<String, dynamic> leave) {
    final isDark = _isDark;
    final barberId = leave['barber_id'] as String;
    final profile = _barberProfiles[barberId] ?? {};
    final barberName = profile['full_name'] ?? 'Unknown';
    final avatarUrl = profile['avatar_url'];
    final hasAvatar = avatarUrl != null && avatarUrl.toString().isNotEmpty;
    final leaveDate = _formatDateForDisplayFromUtc(leave['leave_date']);
    final leaveType = leave['leave_type'] ?? 'full_day';
    final status = leave['status'] ?? 'pending';
    final reason = leave['reason'] ?? 'No reason provided';
    final rejectionReason = leave['rejection_reason'];
    final isHoliday = _isHoliday(leave['leave_date']);
    final holidayName = _getHolidayName(leave['leave_date']);

    String timeDisplay = '';
    String? userTimeDisplay;
    if (leaveType == 'full_day' || leaveType == 'emergency') {
      timeDisplay = 'All Day';
    } else if (leaveType == 'half_day' || leaveType == 'short_leave') {
      final startSalon = _formatUtcToSalonTime(leave['start_time']);
      final endSalon = _formatUtcToSalonTime(leave['end_time']);
      timeDisplay = '$startSalon - $endSalon';

      final userStart = _formatUtcToUserTime(leave['start_time']);
      final userEnd = _formatUtcToUserTime(leave['end_time']);
      if (userStart.isNotEmpty && userEnd.isNotEmpty) {
        userTimeDisplay = '$userStart - $userEnd';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  backgroundImage: hasAvatar
                      ? NetworkImage(avatarUrl.toString())
                      : null,
                  child: !hasAvatar
                      ? Text(
                          _safeInitial(barberName),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              barberName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _buildStatusCell(leave, status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              leaveDate,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    isDark ? Colors.white70 : Colors.grey[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isHoliday && holidayName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '⚠️ $holidayName',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
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
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.white70 : Colors.grey[800],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (timeDisplay.isNotEmpty)
                            Expanded(
                              child: Text(
                                '• $timeDisplay',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      if (userTimeDisplay != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Your time: $userTimeDisplay',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color:
                                  isDark ? Colors.blue[300] : Colors.blue[700],
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
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
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: isDark ? Colors.blue[300] : Colors.blue,
                  ),
                  onPressed: () => _editLeave(leave),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
                  onPressed: () => _deleteLeave(leave),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Small helper widget used inside status dropdown items above.
class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ==================== ADD/EDIT LEAVE DIALOG ====================

class _AddEditLeaveDialog extends StatefulWidget {
  static const String kDefaultSalonTimezone = 'Asia/Colombo';

  final List<Map<String, dynamic>> barbers;
  final String salonId;
  final String salonTimezone;
  final String userTimezone;
  final String? salonOpenTimeUtc;
  final String? salonCloseTimeUtc;
  final Map<String, dynamic>? leaveToEdit;
  final List<Map<String, dynamic>> holidays;

  const _AddEditLeaveDialog({
    required this.barbers,
    required this.salonId,
    required this.salonTimezone,
    required this.userTimezone,
    this.salonOpenTimeUtc,
    this.salonCloseTimeUtc,
    this.leaveToEdit,
    required this.holidays,
  });

  @override
  State<_AddEditLeaveDialog> createState() => _AddEditLeaveDialogState();
}

class _AddEditLeaveDialogState extends State<_AddEditLeaveDialog> {
  final supabase = Supabase.instance.client;

  String? _selectedBarberId;
  DateTime? _selectedLocalDate;
  String _leaveType = 'full_day';
  final TextEditingController _reasonController = TextEditingController();

  TimeOfDay _startLocalTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endLocalTime = const TimeOfDay(hour: 17, minute: 0);

  bool _isLoading = false;
  String? _errorMessage;
  bool _isEditMode = false;
  int _editLeaveId = 0;

  TimeOfDay? _minLocalTime;
  TimeOfDay? _maxLocalTime;

  bool _isHoliday = false;
  String? _holidayName;

  bool _isWeb = false;
  bool _isDark = false;

  bool get _isSameTimezone {
    return widget.salonTimezone.isEmpty || widget.userTimezone.isEmpty
        ? true
        : widget.salonTimezone == widget.userTimezone;
  }

  String get _effectiveSalonTimezone {
    return widget.salonTimezone.isNotEmpty
        ? widget.salonTimezone
        : _AddEditLeaveDialog.kDefaultSalonTimezone;
  }

  @override
  void initState() {
    super.initState();
    _parseSalonHours();

    if (widget.leaveToEdit != null) {
      _isEditMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadLeaveData();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenWidth = MediaQuery.of(context).size.width;
    _isWeb = screenWidth > 800;
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // ============================================
  // ✅ TIMEZONE HELPERS
  // ============================================

  String _formatTimeOfDay(TimeOfDay time) {
    final hour =
        time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  TimeOfDay _convertSalonTimeToUserTime(TimeOfDay salonTime) {
    if (_isSameTimezone) return salonTime;
    if (widget.userTimezone.isEmpty) return salonTime;
    try {
      return TimezoneService.convertTimeOfDayBetweenTimezones(
        salonTime,
        fromTimezone: _effectiveSalonTimezone,
        toTimezone: widget.userTimezone,
      );
    } catch (e) {
      debugPrint('❌ Error converting salon time: $e');
      return salonTime;
    }
  }

  /// ✅ FIXED: uses direct `utcToTimeOfDayWithTimezone` (no string parsing)
  void _parseSalonHours() {
    if (widget.salonOpenTimeUtc != null) {
      try {
        final openTime = TimezoneService.utcToTimeOfDayWithTimezone(
          widget.salonOpenTimeUtc!,
          _effectiveSalonTimezone,
        );
        _minLocalTime = openTime;
        _startLocalTime = openTime;
      } catch (e) {
        debugPrint('Error parsing salon open time: $e');
      }
    }

    if (widget.salonCloseTimeUtc != null) {
      try {
        final closeTime = TimezoneService.utcToTimeOfDayWithTimezone(
          widget.salonCloseTimeUtc!,
          _effectiveSalonTimezone,
        );
        _maxLocalTime = closeTime;
        _endLocalTime = closeTime;
      } catch (e) {
        debugPrint('Error parsing salon close time: $e');
      }
    }
  }

  /// ✅ FIXED: direct TimeOfDay conversion (no `_parseTimeString`)
  void _loadLeaveData() {
    final leave = widget.leaveToEdit!;

    _selectedBarberId = leave['barber_id'];
    _leaveType = leave['leave_type'] ?? 'full_day';
    _reasonController.text = leave['reason'] ?? '';
    _editLeaveId = leave['id'] as int;

    if (leave['leave_date'] != null) {
      try {
        final utcDate = DateTime.parse(leave['leave_date']);
        _selectedLocalDate =
            TimezoneService.utcToLocalDateTimeForDateWithTimezone(
          '12:00:00',
          utcDate,
          _effectiveSalonTimezone,
        );
        _checkHoliday(_selectedLocalDate!, showSnackBar: false);
      } catch (e) {
        debugPrint('Error parsing leave_date: $e');
      }
    }

    if (leave['start_time'] != null && leave['end_time'] != null) {
      try {
        // ✅ Direct TimeOfDay conversion (UTC → salon TZ)
        _startLocalTime = TimezoneService.utcToTimeOfDayWithTimezone(
          leave['start_time'],
          _effectiveSalonTimezone,
        );
        _endLocalTime = TimezoneService.utcToTimeOfDayWithTimezone(
          leave['end_time'],
          _effectiveSalonTimezone,
        );
      } catch (e) {
        debugPrint('Error parsing start_time/end_time: $e');
      }
    }
  }

  void _checkHoliday(DateTime localDate, {bool showSnackBar = true}) {
    final localDateStr = _formatDateForDb(localDate);

    final holiday = widget.holidays.firstWhere((h) {
      final holidayLocalDate = _utcDateStringToLocalDate(h['holiday_date']);
      final holidayLocalStr = _formatDateForDb(holidayLocalDate);
      return holidayLocalStr == localDateStr;
    }, orElse: () => {});

    if (mounted) {
      setState(() {
        _isHoliday = holiday.isNotEmpty;
        _holidayName = holiday['name'];
      });

      if (_isHoliday && showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ $_holidayName - Salon is closed on this day!'),
            backgroundColor: _isDark ? Colors.orange[800] : Colors.orange,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  DateTime _utcDateStringToLocalDate(String utcDateStr) {
    try {
      final utcDateTime = DateTime.parse(utcDateStr);
      final localDateTime =
          TimezoneService.utcToLocalDateTimeForDateWithTimezone(
        '12:00:00',
        utcDateTime,
        _effectiveSalonTimezone,
      );
      return DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );
    } catch (e) {
      debugPrint('Error converting UTC date to local: $e');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
  }

  String _localDateToUtcDateString(DateTime localDate) {
    try {
      final utcDateTime = DateTime.utc(
        localDate.year,
        localDate.month,
        localDate.day,
      );
      return '${utcDateTime.year.toString().padLeft(4, '0')}-${utcDateTime.month.toString().padLeft(2, '0')}-${utcDateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('Error converting local date to UTC: $e');
      return '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
    }
  }

  String _formatDateForDb(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _localTimeToUtcTimeString(TimeOfDay localTime, DateTime localDate) {
    try {
      final timeString =
          '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
      return TimezoneService.localToUtcTimeRecurringWithTimezone(
        timeString,
        _effectiveSalonTimezone,
      );
    } catch (e) {
      debugPrint('Error converting local time to UTC: $e');
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:00';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    final double maxDialogHeight = math.max(
      0.0,
      math.min(screenSize.height * 0.9, screenSize.height - 48),
    );

    final bool isCompact = maxDialogHeight < 360;

    final Widget body = Padding(
      padding: EdgeInsets.all(_isWeb ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) _buildErrorMessage(),
          _buildBarberSelector(),
          const SizedBox(height: 16),
          _buildDateSelector(),
          if (_isHoliday && !_isEditMode) _buildHolidayWarning(),
          const SizedBox(height: 16),
          _buildLeaveTypeSelector(),
          if (_leaveType == 'half_day' || _leaveType == 'short_leave')
            _buildTimeSection(),
          const SizedBox(height: 16),
          _buildReasonField(),
        ],
      ),
    );

    return Dialog(
      backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Container(
        width: _isWeb ? 600 : screenSize.width * 0.95,
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: isCompact
            ? SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogHeader(),
                    body,
                    _buildDialogActions(),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogHeader(),
                  Flexible(
                    child: SingleChildScrollView(child: body),
                  ),
                  _buildDialogActions(),
                ],
              ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.only(
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
          Flexible(
            child: Text(
              _isEditMode ? 'Edit Leave' : 'Add Leave',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarberSelector() {
    final isDark = _isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Barber',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedBarberId,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          hint: Text(
            'Choose barber',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: widget.barbers.map<DropdownMenuItem<String>>((b) {
            return DropdownMenuItem<String>(
              value: b['id'] as String,
              child: Text(
                b['name'] as String,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
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
      ],
    );
  }

  Widget _buildDateSelector() {
    final isDark = _isDark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _selectedLocalDate ?? today,
              firstDate: today,
              lastDate: now.add(const Duration(days: 365)),
              builder: (dateCtx, child) {
                return MediaQuery(
                  data: MediaQuery.of(dateCtx).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: Theme(
                    data: Theme.of(dateCtx).copyWith(
                      colorScheme: ColorScheme(
                        brightness:
                            isDark ? Brightness.dark : Brightness.light,
                        primary: AppTheme.primary,
                        onPrimary: Colors.white,
                        secondary: AppTheme.primary,
                        onSecondary: Colors.white,
                        error: Colors.red,
                        onError: Colors.white,
                        surface:
                            isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        onSurface: isDark ? Colors.white : Colors.black87,
                      ),
                      dialogTheme: DialogThemeData(
                        backgroundColor:
                            isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      ),
                    ),
                    child: _ShortViewportGuard(child: child!),
                  ),
                );
              },
            );
            if (date != null && mounted) {
              setState(() {
                _selectedLocalDate = date;
                _errorMessage = null;
              });
              _checkHoliday(date);
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isHoliday && !_isEditMode
                    ? Colors.orange
                    : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                width: _isHoliday && !_isEditMode ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: _isHoliday && !_isEditMode
                  ? Colors.orange.withValues(alpha: 0.05)
                  : (isDark ? const Color(0xFF2A2A2A) : null),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: _isHoliday && !_isEditMode
                      ? Colors.orange
                      : (isDark ? Colors.white60 : Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedLocalDate != null
                            ? DateFormat(
                                'EEEE, MMM d, yyyy',
                              ).format(_selectedLocalDate!)
                            : 'Select date',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedLocalDate != null
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark
                                  ? Colors.white70
                                  : Colors.grey[500]),
                          fontWeight: _isHoliday && !_isEditMode
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                      if (_isHoliday &&
                          !_isEditMode &&
                          _holidayName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '⚠️ $_holidayName - Salon closed',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
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
      ],
    );
  }

  Widget _buildHolidayWarning() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'The salon is closed on this day due to holiday. '
                'Leave requests on holidays are not allowed.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveTypeSelector() {
    final isDark = _isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Leave Type',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
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
                'Emergency', 'emergency', Icons.warning, Colors.red),
            _buildTypeChip(
              'Short Leave',
              'short_leave',
              Icons.timer,
              Colors.green,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isDark = _isDark;
    final isSelected = _leaveType == value;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white : Colors.black87),
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
      backgroundColor:
          isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
      selectedColor: color,
      checkmarkColor: Colors.white,
      showCheckmark: false,
    );
  }

  Widget _buildTimeSection() {
    final isDark = _isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Select Time',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        if (_minLocalTime != null && _maxLocalTime != null)
          _buildSalonHoursInfo(),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: _isWeb
              ? Row(
                  children: [
                    Expanded(
                      child: _buildTimePicker(
                        label: 'Start Time',
                        time: _startLocalTime,
                        onTimeSelected: (TimeOfDay newTime) {
                          setState(() => _startLocalTime = newTime);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTimePicker(
                        label: 'End Time',
                        time: _endLocalTime,
                        onTimeSelected: (TimeOfDay newTime) {
                          setState(() => _endLocalTime = newTime);
                        },
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildTimePicker(
                      label: 'Start Time',
                      time: _startLocalTime,
                      onTimeSelected: (TimeOfDay newTime) {
                        setState(() => _startLocalTime = newTime);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTimePicker(
                      label: 'End Time',
                      time: _endLocalTime,
                      onTimeSelected: (TimeOfDay newTime) {
                        setState(() => _endLocalTime = newTime);
                      },
                    ),
                  ],
                ),
        ),
        if (_leaveType == 'short_leave')
          _buildInfoCard(
            icon: Icons.timer,
            color: Colors.green,
            message: 'Maximum 2 hours for short leave',
          )
        else if (_leaveType == 'half_day')
          _buildInfoCard(
            icon: Icons.access_time,
            color: Colors.blue,
            message: 'Half day should be approximately 4 hours',
          ),
      ],
    );
  }

  Widget _buildSalonHoursInfo() {
    final userStart = _convertSalonTimeToUserTime(_minLocalTime!);
    final userEnd = _convertSalonTimeToUserTime(_maxLocalTime!);
    final hasUserTime = !_isSameTimezone;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Salon hours: ${_formatTimeOfDay(_minLocalTime!)} - ${_formatTimeOfDay(_maxLocalTime!)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            ],
          ),
          if (hasUserTime)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 24),
              child: Text(
                'Your time: ${_formatTimeOfDay(userStart)} - ${_formatTimeOfDay(userEnd)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: _isDark ? Colors.blue[300] : Colors.blue[700],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onTimeSelected,
  }) {
    final isDark = _isDark;

    return GestureDetector(
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (timeCtx, child) {
            return MediaQuery(
              data: MediaQuery.of(
                timeCtx,
              ).copyWith(alwaysUse24HourFormat: false),
              child: child!,
            );
          },
        );
        if (picked != null && mounted) {
          onTimeSelected(picked);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimeOfDay(time),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonField() {
    final isDark = _isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reason',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonController,
          maxLines: 3,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Enter reason for leave',
            hintStyle: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[500],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 2),
            ),
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogActions() {
    final isDark = _isDark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _selectedBarberId != null &&
                    _selectedLocalDate != null &&
                    !_isLoading &&
                    (!_isHoliday || _isEditMode)
                ? _saveLeave
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
    );
  }

  Future<void> _saveLeave() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isHoliday && !_isEditMode) {
        setState(() {
          _errorMessage = 'Cannot add leave on a holiday. The salon is closed.';
          _isLoading = false;
        });
        return;
      }

      if (_leaveType == 'half_day' || _leaveType == 'short_leave') {
        final startMinutes =
            _startLocalTime.hour * 60 + _startLocalTime.minute;
        final endMinutes = _endLocalTime.hour * 60 + _endLocalTime.minute;

        if (_minLocalTime != null) {
          final minMinutes =
              _minLocalTime!.hour * 60 + _minLocalTime!.minute;
          if (startMinutes < minMinutes) {
            setState(() {
              _errorMessage =
                  'Start time cannot be before salon opening time';
              _isLoading = false;
            });
            return;
          }
        }

        if (_maxLocalTime != null) {
          final maxMinutes =
              _maxLocalTime!.hour * 60 + _maxLocalTime!.minute;
          if (endMinutes > maxMinutes) {
            setState(() {
              _errorMessage =
                  'End time cannot be after salon closing time';
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
              _errorMessage =
                  'Half day should be approximately 4 hours (3-5 hours range)';
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
              _errorMessage =
                  'Short leave must be at least 15 minutes';
              _isLoading = false;
            });
            return;
          }
        }
      }

      final utcDateStr = _localDateToUtcDateString(_selectedLocalDate!);

      if (!_isEditMode) {
        final existingLeave = await supabase
            .from('barber_leaves')
            .select()
            .eq('barber_id', _selectedBarberId!)
            .eq('leave_date', utcDateStr)
            .maybeSingle();

        if (existingLeave != null) {
          setState(() {
            _errorMessage =
                'This barber already has a leave on this date.';
            _isLoading = false;
          });
          return;
        }
      }

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      String? startTimeUtc;
      String? endTimeUtc;

      if (_leaveType == 'half_day' || _leaveType == 'short_leave') {
        startTimeUtc = _localTimeToUtcTimeString(
          _startLocalTime,
          _selectedLocalDate!,
        );
        endTimeUtc = _localTimeToUtcTimeString(
          _endLocalTime,
          _selectedLocalDate!,
        );
      }

      Map<String, dynamic> leaveData = {
        'barber_id': _selectedBarberId!,
        'salon_id': int.parse(widget.salonId),
        'leave_date': utcDateStr,
        'leave_type': _leaveType,
        'reason': _reasonController.text.trim(),
        'status': _isEditMode ? widget.leaveToEdit!['status'] : 'pending',
        'start_time': startTimeUtc,
        'end_time': endTimeUtc,
      };

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
          'leave_id': _editLeaveId,
          'barber_id': _selectedBarberId,
          'barber_name': widget.barbers.firstWhere(
            (b) => b['id'] == _selectedBarberId,
            orElse: () => {'name': 'Unknown'},
          )['name'],
          'leave_date': utcDateStr,
          'leave_type': _leaveType,
          'reason': _reasonController.text.trim(),
          'start_time': startTimeUtc,
          'end_time': endTimeUtc,
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving leave: $e');

      if (e.toString().contains('duplicate key') ||
          e.toString().contains('23505')) {
        setState(() {
          _errorMessage =
              'This barber already has a leave on this date.';
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