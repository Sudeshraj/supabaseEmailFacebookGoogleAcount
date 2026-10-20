import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/customer/booking_flow_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/services/currency_service.dart';
import 'package:flutter_application_1/services/currency_settings_service.dart'; // ✅ NEW
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/timezone_service.dart';

class MyBookingsScreen extends StatefulWidget {
  final int? highlightId;

  const MyBookingsScreen({super.key, this.highlightId});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final CurrencyService _currencyService = CurrencyService.instance;
  final CurrencySettingsService _currencySettings =
      CurrencySettingsService.instance; // ✅ NEW

  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _filteredBookings = [];
  List<Map<String, dynamic>> _overflowNotifications = [];
  bool _isLoading = true;
  String? _error;

  late TabController _tabController;

  // ✅ VIP = Amber, Regular = Blue
  Color get _vipColor => Colors.amber.shade700;
  Color get _vipBorderColor => Colors.amber.shade400;

  Color get _regularQueueColor => Colors.blue.shade600;
  Color get _regularQueueBorderColor => Colors.blue.shade400;

  // ✅ Track cancelling by ID (not shared flag)
  final Set<int> _cancellingIds = {};

  bool _isProcessingOverflow = false;

  final ScrollController _scrollController = ScrollController();

  // ✅ Default salon timezone (salon DB default)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';
  static const String _kDefaultCurrency = 'LKR'; // ✅ NEW
  String salonTimezone = _kDefaultSalonTimezone;
  String _userTimezone = '';
  String _userCurrencyCode = _kDefaultCurrency; // ✅ NEW

  DateTime _selectedDate = DateTime.now();

  int _pendingCount = 0;
  int _pendingPaymentCount = 0;
  int _completedCount = 0;
  int _cancelledCount = 0;

  // ============================================================
  // ✅ SALON "NOW" — consistent timezone reference
  // ============================================================
  DateTime get _salonNow {
    final tz = salonTimezone.isNotEmpty
        ? salonTimezone
        : _kDefaultSalonTimezone;
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

  String get _selectedDateString =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  String get _selectedDateDisplay =>
      DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate);

  /// ✅ Use CurrencyService instead of hardcoded map
  String _currencySymbol(String? code) {
    return _currencyService.getSymbol(code ?? 'LKR');
  }

  /// ✅ NEW: Format salon price in salon currency
  String _formatSalonPrice(dynamic price, String? salonCurrency) {
    return _currencyService.format(
      price: price,
      currencyCode: salonCurrency ?? _kDefaultCurrency,
    );
  }

  /// ✅ NEW: Format user price (approximation)
  String _formatUserPrice(dynamic price) {
    return _currencyService.format(
      price: price,
      currencyCode: _userCurrencyCode,
    );
  }

  /// ✅ NEW: Convert salon price to user currency using locked rate
  double? _convertToUser({
    required dynamic salonPrice,
    required String? salonCurrency,
    required dynamic exchangeRate,
  }) {
    if (salonCurrency == null) return null;
    if (salonCurrency == _userCurrencyCode) return null; // same currency — no approx needed

    final rate = (exchangeRate as num?)?.toDouble();
    if (rate == null || rate <= 0) return null;

    final price = (salonPrice as num?)?.toDouble() ?? 0.0;
    return price * rate;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    _userTimezone = TimezoneService.getCurrentTimezone();
    if (_userTimezone.isEmpty) {
      _userTimezone = _kDefaultSalonTimezone;
    }

    // ✅ NEW: Load user preferred currency (non-blocking fallback)
    try {
      _userCurrencyCode = await _currencySettings.getUserCurrency();
      debugPrint('✅ User currency loaded: $_userCurrencyCode');
    } catch (e) {
      debugPrint('⚠️ Failed to load user currency: $e');
      _userCurrencyCode = _kDefaultCurrency;
    }

    // ✅ Set selectedDate based on salon timezone
    if (!mounted) return;
    setState(() {
      _selectedDate = _salonToday;
    });

    await _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() => _applyStatusFilter());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // ✅ NEW: Refresh user currency from DB on each load
    try {
      _userCurrencyCode = await _currencySettings.getUserCurrency();
    } catch (e) {
      debugPrint('⚠️ Failed to refresh currency: $e');
    }

    await Future.wait([_loadBookings(), _loadOverflowNotifications()]);

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  // =====================================================
  // LOAD BOOKINGS
  // ✅ Single query with all joins
  // ✅ Null-safe date parsing
  // ✅ Salon timezone for times
  // ✅ Mounted checks between awaits
  // ✅ NEW: Load exchange_rate_at_booking for locked rate
  // =====================================================
  Future<void> _loadBookings() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Please login to view your bookings';
          _isLoading = false;
        });
        return;
      }

      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'customer')
          .single();

      if (!mounted) return;

      final customerRoleId = roleResponse['id'];

      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', customerRoleId)
          .maybeSingle();

      if (!mounted) return;

      if (roleCheck == null || roleCheck['status'] != 'active') {
        setState(() {
          _error = 'Your account is not active. Please contact support.';
          _isLoading = false;
        });
        return;
      }

      final appointments = await supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            customer_id,
            barber_id,
            salon_id,
            appointment_date,
            start_time,
            end_time,
            status,
            payment_status,
            payment_paid_at,
            price,
            original_price,
            discount_amount,
            extra_charge,
            extra_charge_note,
            currency_code,
            exchange_rate_at_booking,
            queue_number,
            regular_queue_number,
            vip_queue_number,
            queue_token,
            queue_position,
            is_vip,
            child_name,
            travel_time_minutes,
            notes,
            salons!inner (
              id,
              name,
              address,
              currency_code,
              currency_symbol,
              timezone
            ),
            barber_profile:profiles!appointments_barber_id_fkey (
              id,
              full_name
            ),
            appointment_services (
              id,
              service_id,
              variant_id,
              service_name,
              variant_label,
              duration,
              original_price,
              discount_amount,
              final_price,
              offer_id,
              added_by
            )
          ''')
          .eq('customer_id', user.id)
          .eq('appointment_date', _selectedDateString)
          .order('start_time', ascending: true);

      if (!mounted) return;

      final List<Map<String, dynamic>> processedBookings = [];

      for (var booking in appointments) {
        final salon = booking['salons'] as Map?;
        final barber = booking['barber_profile'] as Map?;

        final servicesList = (booking['appointment_services'] as List?) ?? [];
        final List<Map<String, dynamic>> services = [];
        double servicesTotal = 0.0;
        double totalDiscount = 0.0;
        int totalDuration = 0;

        for (var svc in servicesList) {
          final sOriginal = (svc['original_price'] as num?)?.toDouble() ?? 0.0;
          final sDiscount = (svc['discount_amount'] as num?)?.toDouble() ?? 0.0;
          final sFinal = (svc['final_price'] as num?)?.toDouble() ?? 0.0;
          final sDuration = (svc['duration'] as num?)?.toInt() ?? 30;

          servicesTotal += sOriginal;
          totalDiscount += sDiscount;
          totalDuration += sDuration;

          services.add({
            'id': svc['id'],
            'service_id': svc['service_id'],
            'service_name': svc['service_name'] ?? 'Service',
            'variant_id': svc['variant_id'],
            'variant_label': svc['variant_label'],
            'duration': sDuration,
            'original_price': sOriginal,
            'discount_amount': sDiscount,
            'final_price': sFinal,
          });
        }

        final extraCharge =
            (booking['extra_charge'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = servicesTotal - totalDiscount + extraCharge;

        String serviceName = 'No services';
        if (services.isNotEmpty) {
          final names = services.map((s) => s['service_name']).toList();
          serviceName = names.length == 1
              ? names.first.toString()
              : '${names.first} +${names.length - 1} more';
        }

        // ✅ Null-safe date parsing
        DateTime utcDate;
        try {
          utcDate = DateTime.parse(
            booking['appointment_date'] as String? ?? '',
          );
        } catch (_) {
          utcDate = _selectedDate;
        }

        final utcStartTime = booking['start_time'] as String? ?? '';
        final utcEndTime = booking['end_time'] as String? ?? '';

        // ✅ Use SALON timezone for times (not user timezone)
        final salonTz = salon?['timezone'] as String? ?? _kDefaultSalonTimezone;

        final localStartTime =
            TimezoneService.utcToLocalTimeForDateWithTimezone(
              utcStartTime,
              utcDate,
              salonTz,
            );
        final localEndTime = TimezoneService.utcToLocalTimeForDateWithTimezone(
          utcEndTime,
          utcDate,
          salonTz,
        );

        // ✅ User time reference (only if different from salon)
        String? userStartTime;
        String? userEndTime;
        if (_userTimezone.isNotEmpty && _userTimezone != salonTz) {
          userStartTime = TimezoneService.utcToLocalTimeForDateWithTimezone(
            utcStartTime,
            utcDate,
            _userTimezone,
          );
          userEndTime = TimezoneService.utcToLocalTimeForDateWithTimezone(
            utcEndTime,
            utcDate,
            _userTimezone,
          );
        }

        final isVip = booking['is_vip'] ?? false;
        String displayQueueNumber = '';

        if (isVip) {
          final vipNum = booking['vip_queue_number'];
          if (vipNum != null) {
            displayQueueNumber = 'VIP-$vipNum';
          } else if (booking['queue_number'] != null) {
            displayQueueNumber = 'VIP-${booking['queue_number']}';
          }
        } else {
          final regNum = booking['regular_queue_number'];
          if (regNum != null) {
            displayQueueNumber = 'Q$regNum';
          } else if (booking['queue_number'] != null) {
            displayQueueNumber = 'Q${booking['queue_number']}';
          }
        }

        // ✅ NEW: Extract exchange rate (locked at booking time)
        final exchangeRate =
            (booking['exchange_rate_at_booking'] as num?)?.toDouble();

        processedBookings.add({
          ...booking,
          'local_start_time': localStartTime,
          'local_end_time': localEndTime,
          'user_start_time': userStartTime,
          'user_end_time': userEndTime,
          'salon_name': salon?['name'] ?? 'Salon',
          'salon_address': salon?['address'],
          'salon_timezone': salonTz,
          'currency_code':
              salon?['currency_code'] ?? booking['currency_code'] ?? 'LKR',
          'currency_symbol': salon?['currency_symbol'],
          'exchange_rate_at_booking': exchangeRate, // ✅ NEW
          'barber_name': barber?['full_name'] ?? 'Barber',
          'services': services,
          'service_name': serviceName,
          'services_total': servicesTotal,
          'total_discount': totalDiscount,
          'extra_charge': extraCharge,
          'extra_charge_note': booking['extra_charge_note'],
          'price': totalPrice > 0
              ? totalPrice
              : (booking['price'] as num?)?.toDouble() ?? 0.0,
          'duration': totalDuration > 0 ? totalDuration : 30,
          'display_queue_number': displayQueueNumber,
          'queue_position': booking['queue_position'],
          'queue_token': booking['queue_token'],
          'is_vip': isVip,
        });
      }

      int pending = 0;
      int pendingPayment = 0;
      int completed = 0;
      int cancelled = 0;

      for (var b in processedBookings) {
        final s = b['status'] as String? ?? '';
        final ps = b['payment_status'] as String? ?? 'unpaid';
        if (s == 'pending' || s == 'confirmed' || s == 'in_progress') {
          pending++;
        } else if (s == 'completed') {
          if (ps == 'paid') {
            completed++;
          } else {
            pendingPayment++;
          }
        } else if (s == 'cancelled' || s == 'no_show') {
          cancelled++;
        }
      }

      if (!mounted) return;
      setState(() {
        _allBookings = processedBookings;
        _pendingCount = pending;
        _pendingPaymentCount = pendingPayment;
        _completedCount = completed;
        _cancelledCount = cancelled;
        _applyStatusFilter();
      });
    } catch (e) {
      debugPrint('❌ Error loading bookings: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load bookings: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyStatusFilter() {
    switch (_tabController.index) {
      case 0:
        _filteredBookings = _allBookings.where((b) {
          final s = b['status'] as String? ?? '';
          return s == 'pending' || s == 'confirmed' || s == 'in_progress';
        }).toList();
        break;
      case 1:
        _filteredBookings = _allBookings.where((b) {
          return b['status'] == 'completed' &&
              (b['payment_status'] as String? ?? 'unpaid') != 'paid';
        }).toList();
        break;
      case 2:
        _filteredBookings = _allBookings.where((b) {
          return b['status'] == 'completed' &&
              (b['payment_status'] as String? ?? 'unpaid') == 'paid';
        }).toList();
        break;
      case 3:
      default:
        _filteredBookings = _allBookings.where((b) {
          final s = b['status'] as String? ?? '';
          return s == 'cancelled' || s == 'no_show';
        }).toList();
        break;
    }
  }

  // =====================================================
  // ✅ LOAD OVERFLOW NOTIFICATIONS — SINGLE QUERY (no N+1)
  // =====================================================
  Future<void> _loadOverflowNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final result = await supabase
          .from('overflow_notifications')
          .select('''
            id,
            excess_minutes,
            estimated_end,
            salon_close,
            notified_at,
            status,
            appointments!inner (
              id,
              booking_number,
              appointment_date,
              start_time,
              end_time,
              status,
              barber_id,
              salon_id,
              is_vip,
              vip_queue_number,
              regular_queue_number,
              queue_number,
              queue_position,
              child_name,
              travel_time_minutes,
              currency_code,
              exchange_rate_at_booking,
              salons!inner (
                id,
                name,
                address,
                currency_code,
                currency_symbol,
                timezone
              ),
              barber_profile:profiles!appointments_barber_id_fkey (
                id,
                full_name
              ),
              appointment_services (
                id,
                service_name,
                variant_label,
                duration,
                final_price
              )
            )
          ''')
          .eq('customer_id', user.id)
          .eq('status', 'PENDING')
          .order('notified_at', ascending: false);

      if (!mounted) return;

      final List<Map<String, dynamic>> notifications = [];

      for (var notice in result) {
        final apt = notice['appointments'] as Map?;
        if (apt == null) continue;

        final salon = apt['salons'] as Map?;
        final barber = apt['barber_profile'] as Map?;

        final servicesList = (apt['appointment_services'] as List?) ?? [];
        String serviceName = 'Service';
        if (servicesList.isNotEmpty) {
          final names = servicesList.map((s) => s['service_name']).toList();
          serviceName = names.length == 1
              ? names.first.toString()
              : '${names.first} +${names.length - 1} more';
        }

        // ✅ Null-safe date parsing
        DateTime appointmentDate;
        try {
          appointmentDate = DateTime.parse(
            apt['appointment_date'] as String? ?? '',
          );
        } catch (_) {
          appointmentDate = _selectedDate;
        }

        final utcStartTime = apt['start_time'] as String? ?? '';
        final utcEndTime = apt['end_time'] as String? ?? '';

        // ✅ Use SALON timezone
        final salonTz = salon?['timezone'] as String? ?? _kDefaultSalonTimezone;

        final localStartTime =
            TimezoneService.utcToLocalTimeForDateWithTimezone(
              utcStartTime,
              appointmentDate,
              salonTz,
            );
        final localEndTime = TimezoneService.utcToLocalTimeForDateWithTimezone(
          utcEndTime,
          appointmentDate,
          salonTz,
        );

        final isVip = apt['is_vip'] ?? false;
        String displayQueue = '';
        if (isVip) {
          displayQueue =
              'VIP-${apt['vip_queue_number'] ?? apt['queue_number']}';
        } else {
          displayQueue =
              'Q${apt['regular_queue_number'] ?? apt['queue_number']}';
        }

        notifications.add({
          'id': notice['id'],
          'excess_minutes': notice['excess_minutes'],
          'estimated_end': notice['estimated_end'],
          'salon_close': notice['salon_close'],
          'notified_at': notice['notified_at'],
          'appointment': {
            'id': apt['id'],
            'booking_number': apt['booking_number'],
            'appointment_date': apt['appointment_date'],
            'start_time': localStartTime,
            'end_time': localEndTime,
            'utc_start_time': utcStartTime,
            'utc_end_time': utcEndTime,
            'status': apt['status'],
            'display_queue_number': displayQueue,
            'queue_position': apt['queue_position'],
            'is_vip': isVip,
            'child_name': apt['child_name'],
            'travel_time_minutes': apt['travel_time_minutes'],
            'salon_name': salon?['name'] ?? 'Salon',
            'salon_address': salon?['address'],
            'salon_id': apt['salon_id'],
            'currency_code':
                salon?['currency_code'] ?? apt['currency_code'] ?? 'LKR',
            'currency_symbol': salon?['currency_symbol'],
            'exchange_rate_at_booking':
                (apt['exchange_rate_at_booking'] as num?)?.toDouble(), // ✅ NEW
            'service_name': serviceName,
            'barber_name': barber?['full_name'] ?? 'Barber',
          },
        });
      }

      if (!mounted) return;
      setState(() => _overflowNotifications = notifications);
    } catch (e) {
      debugPrint('❌ Error loading overflow notifications: $e');
      if (mounted) setState(() => _overflowNotifications = []);
    }
  }

  Future<void> _respondToOverflow(int notificationId, String response) async {
    if (!mounted) return;
    setState(() => _isProcessingOverflow = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final result = await supabase.rpc(
        'handle_overflow_response',
        params: {
          'p_notification_id': notificationId,
          'p_customer_id': user.id,
          'p_response': response,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  response == 'MOVE'
                      ? Icons.calendar_today
                      : Icons.check_circle,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(result['message'] ?? 'Success')),
              ],
            ),
            backgroundColor: response == 'MOVE' ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingOverflow = false);
    }
  }

  void _showOverflowDecisionDialog(Map<String, dynamic> notification) {
    final isDark = context.isDarkMode;
    final apt = notification['appointment'];
    final excessMinutes = notification['excess_minutes'];
    final estimatedEnd = notification['estimated_end'];
    final salonClose = notification['salon_close'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Appointment Overflow',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠️ Delay of $excessMinutes minutes detected',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.orange.shade300
                            : Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your appointment on ${apt['appointment_date']} at ${apt['start_time']} may be significantly delayed.',
                      style: TextStyle(
                        color: isDark
                            ? Colors.orange.shade300
                            : Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Estimated end: $estimatedEnd | Salon closes: $salonClose',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.orange.shade300
                            : Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'What would you like to do?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.green.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Move to Next Day',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade800,
                            ),
                          ),
                          Text(
                            'Reschedule your appointment to tomorrow',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cancel Appointment',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade800,
                            ),
                          ),
                          Text(
                            'Cancel this appointment (no charges)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '⚠️ If no response within 30 minutes, your appointment will be auto-cancelled.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.orange.shade300
                      : Colors.orange.shade600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'DECIDE LATER',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black87),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _showMoveCancelOptions(notification['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('PROCEED'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveCancelOptions(int notificationId) async {
    final isDark = context.isDarkMode;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Choose Action',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'What would you like to do?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'CANCEL'),
            child: Text(
              'CANCEL',
              style: TextStyle(
                color: isDark ? Colors.red.shade300 : Colors.red,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'MOVE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('MOVE TO NEXT DAY'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _respondToOverflow(notificationId, result);
    }
  }

  // =====================================================
  // CANCEL BOOKING
  // ✅ Track by ID (not shared flag)
  // ✅ NEW: dual currency in cancel dialog
  // =====================================================
  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final isDark = context.isDarkMode;
    final bookingId = booking['id'] as int;
    final hasOverflow = _overflowNotifications.any(
      (n) => n['appointment']['id'] == bookingId,
    );

    final salonCurrency = booking['currency_code'] as String?;
    final exchangeRate = booking['exchange_rate_at_booking'] as num?;
    final totalPrice = (booking['price'] as num?)?.toDouble() ?? 0.0;
    final userAmount = _convertToUser(
      salonPrice: totalPrice,
      salonCurrency: salonCurrency,
      exchangeRate: exchangeRate,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cancel Booking?',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to cancel this booking?',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            booking['salon_name'] ?? 'Salon',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          booking['appointment_date'] != null
                              ? DateFormat('EEEE, MMM dd, yyyy').format(
                                  DateTime.parse(
                                    booking['appointment_date'] as String,
                                  ),
                                )
                              : 'Unknown date',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${booking['local_start_time']} - ${booking['local_end_time']}',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    // ✅ NEW: Show total price (dual currency)
                    if (totalPrice > 0) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.attach_money,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatSalonPrice(totalPrice, salonCurrency),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                if (userAmount != null)
                                  Text(
                                    '≈ ${_formatUserPrice(userAmount)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: isDark
                                          ? Colors.blue[300]
                                          : Colors.blue[700],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (booking['display_queue_number'] != null &&
                        booking['display_queue_number'].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.format_list_numbered,
                              size: 16,
                              color: booking['is_vip'] == true
                                  ? _vipColor
                                  : _regularQueueColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Queue: ${booking['display_queue_number']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: booking['is_vip'] == true
                                    ? _vipColor
                                    : _regularQueueColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (hasOverflow)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '⚠️ Cancelling now will resolve overflow.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'KEEP BOOKING',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black87),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _cancellingIds.add(bookingId));

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final result = await supabase.rpc(
        'cancel_booking_and_reorder',
        params: {
          'p_appointment_id': bookingId,
          'p_cancelled_by': user.id,
          'p_cancel_reason': 'Cancelled by customer',
          'p_role': 'customer',
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Booking cancelled successfully'),
              ],
            ),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        await _loadData();
      } else {
        throw Exception(result['message'] ?? 'Cancellation failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(bookingId));
    }
  }

  // =====================================================
  // ✅ LEAVE REVIEW DIALOG — controller properly disposed
  // =====================================================
  Future<void> _showLeaveReviewDialog(Map<String, dynamic> booking) async {
    final isDark = context.isDarkMode;
    int selectedRating = 0;
    final reviewController = TextEditingController();

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.star_rate_rounded,
                    color: Colors.amber,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Leave a Review',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width * 0.85,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booking['salon_name'] ?? 'Salon',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Barber: ${booking['barber_name'] ?? 'Barber'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                            ),
                            Text(
                              'Services: ${booking['service_name'] ?? 'Service'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Your Rating',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final isSelected = index < selectedRating;
                          return IconButton(
                            onPressed: () => setDialogState(
                              () => selectedRating = index + 1,
                            ),
                            icon: Icon(
                              isSelected ? Icons.star : Icons.star_border,
                              color: isSelected
                                  ? Colors.amber
                                  : (isDark
                                        ? Colors.grey[600]
                                        : Colors.grey[400]),
                              size: 36,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          selectedRating == 0
                              ? 'Tap to rate'
                              : 'You rated: $selectedRating/5',
                          style: TextStyle(
                            fontSize: 13,
                            color: selectedRating == 0
                                ? (isDark ? Colors.white70 : Colors.grey[500])
                                : Colors.amber[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Your Review (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reviewController,
                        maxLines: 4,
                        maxLength: 500,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Share your experience...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey[400],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppTheme.primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedRating == 0
                      ? null
                      : () async {
                          final reviewText = reviewController.text.trim();
                          Navigator.pop(dialogContext);
                          await _submitReview(
                            bookingId: booking['id'] as int,
                            rating: selectedRating,
                            review: reviewText,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('SUBMIT REVIEW'),
                ),
              ],
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            );
          },
        ),
      );
    } finally {
      reviewController.dispose();
    }
  }

  void _rebookBooking(Map<String, dynamic> booking) {
    final salonData = {
      'id': booking['salon_id'],
      'name': booking['salon_name'],
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(initialSalon: salonData),
      ),
    );
  }

  Future<void> _submitReview({
    required int bookingId,
    required int rating,
    required String review,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final appointment = await supabase
          .from('appointments')
          .select('barber_id, salon_id')
          .eq('id', bookingId)
          .single();

      if (!mounted) return;

      final barberId = appointment['barber_id'] as String?;
      if (barberId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot review: barber no longer available'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final existingReview = await supabase
          .from('reviews')
          .select('id')
          .eq('appointment_id', bookingId)
          .maybeSingle();

      if (!mounted) return;

      if (existingReview != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already reviewed this appointment'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await supabase.from('reviews').insert({
        'appointment_id': bookingId,
        'customer_id': user.id,
        'barber_id': barberId,
        'salon_id': appointment['salon_id'],
        'overall_rating': rating,
        'comment': review,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Thank you for your review!'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit review: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =====================================================
  // BOOKING DETAILS BOTTOM SHEET
  // ✅ NEW: Dual currency display (salon + approx user)
  // =====================================================
  void _showBookingDetails(Map<String, dynamic> booking) {
    final isDark = context.isDarkMode;
    final isVip = booking['is_vip'] ?? false;
    final detailColor = isVip ? _vipColor : AppTheme.primary;
    final symbol = _currencySymbol(booking['currency_code'] as String?);

    final salonCurrency = booking['currency_code'] as String?;
    final exchangeRate = booking['exchange_rate_at_booking'] as num?;

    final services = (booking['services'] as List?) ?? [];
    final servicesTotal =
        (booking['services_total'] as num?)?.toDouble() ?? 0.0;
    final totalDiscount =
        (booking['total_discount'] as num?)?.toDouble() ?? 0.0;
    final extraCharge = (booking['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final totalPrice = (booking['price'] as num?)?.toDouble() ?? 0.0;

    // ✅ NEW: Convert totals to user currency (if different)
    final userTotal = _convertToUser(
      salonPrice: totalPrice,
      salonCurrency: salonCurrency,
      exchangeRate: exchangeRate,
    );

    final status = booking['status'] as String? ?? 'pending';
    final paymentStatus = booking['payment_status'] as String? ?? 'unpaid';

    // ✅ Status display
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
        if (paymentStatus == 'paid') {
          statusColor = Colors.purple;
          statusText = 'Completed';
          statusIcon = Icons.check_circle;
        } else {
          statusColor = Colors.orange;
          statusText = 'Pending Payment';
          statusIcon = Icons.payments_outlined;
        }
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelled';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'no_show':
        statusColor = Colors.red;
        statusText = 'No Show';
        statusIcon = Icons.person_off;
        break;
      default:
        statusColor = Colors.grey;
        statusText = status;
        statusIcon = Icons.circle_outlined;
    }

    // ✅ Null-safe appointment date
    DateTime appointmentDate;
    try {
      appointmentDate = DateTime.parse(
        booking['appointment_date'] as String? ?? '',
      );
    } catch (_) {
      appointmentDate = _selectedDate;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: detailColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.receipt_long,
                        color: detailColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Booking ${booking['booking_number'] ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 12, color: statusColor),
                                const SizedBox(width: 3),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy • hh:mm a',
                            ).format(appointmentDate),
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
                const SizedBox(height: 20),
                _buildDetailRow('Salon', booking['salon_name'] ?? 'Salon'),
                _buildDetailRow('Address', booking['salon_address'] ?? 'N/A'),
                _buildDetailRow('Barber', booking['barber_name'] ?? 'Barber'),

                // ✅ User time reference (only if different)
                if (booking['user_start_time'] != null &&
                    booking['user_end_time'] != null)
                  _buildDetailRow(
                    'Your Time',
                    '${booking['user_start_time']} - ${booking['user_end_time']}',
                  ),

                if (services.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Services (${services.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...services.map((s) {
                    final sOriginal =
                        (s['original_price'] as num?)?.toDouble() ?? 0;
                    final sDiscount =
                        (s['discount_amount'] as num?)?.toDouble() ?? 0;
                    final sFinal = (s['final_price'] as num?)?.toDouble() ?? 0;
                    final variantLabel = s['variant_label'] as String?;
                    final displayPrice = sDiscount > 0 ? sFinal : sOriginal;
                    final userServicePrice = _convertToUser(
                      salonPrice: displayPrice,
                      salonCurrency: salonCurrency,
                      exchangeRate: exchangeRate,
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['service_name'] ?? 'Service',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                if (variantLabel != null &&
                                    variantLabel.isNotEmpty)
                                  Text(
                                    variantLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                Text(
                                  '${s['duration'] ?? 30} min',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (sDiscount > 0)
                                Text(
                                  '$symbol${sOriginal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    decoration: TextDecoration.lineThrough,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey,
                                  ),
                                ),
                              Text(
                                '$symbol${displayPrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sDiscount > 0
                                      ? Colors.green.shade700
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                ),
                              ),
                              // ✅ NEW: approx user currency
                              if (userServicePrice != null)
                                Text(
                                  '≈ ${_formatUserPrice(userServicePrice)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: isDark
                                        ? Colors.blue[300]
                                        : Colors.blue[700],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                const Divider(height: 24),
                if (servicesTotal > 0)
                  _buildPriceRow(
                    'Services Subtotal',
                    '$symbol${servicesTotal.toStringAsFixed(2)}',
                    isDark: isDark,
                  ),
                if (totalDiscount > 0)
                  _buildPriceRow(
                    'Discount',
                    '−$symbol${totalDiscount.toStringAsFixed(2)}',
                    isDark: isDark,
                    color: Colors.green.shade700,
                  ),
                if (extraCharge > 0)
                  _buildPriceRow(
                    'Extra Charge',
                    '+$symbol${extraCharge.toStringAsFixed(2)}',
                    isDark: isDark,
                    color: Colors.orange,
                  ),
                _buildPriceRow(
                  'Total',
                  '$symbol${totalPrice.toStringAsFixed(2)}',
                  isDark: isDark,
                  bold: true,
                  color: detailColor,
                ),
                // ✅ NEW: User currency approx below total
                if (userTotal != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '≈ ${_formatUserPrice(userTotal)} in $_userCurrencyCode',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.blue[300]
                                : Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),

                _buildDetailRow(
                  'Duration',
                  '${booking['duration'] ?? 30} minutes',
                ),
                if (booking['child_name'] != null &&
                    booking['child_name'].toString().isNotEmpty)
                  _buildDetailRow('Booked For', booking['child_name']),
                if (booking['display_queue_number'] != null &&
                    booking['display_queue_number'].toString().isNotEmpty)
                  _buildDetailRow(
                    'Queue Number',
                    booking['display_queue_number'],
                  ),
                if (booking['queue_position'] != null)
                  _buildDetailRow(
                    'Queue Position',
                    '#${booking['queue_position']}',
                  ),
                if (booking['queue_token'] != null &&
                    booking['queue_token'].toString().isNotEmpty)
                  _buildDetailRow('Queue Token', booking['queue_token']),
                if (booking['is_vip'] == true)
                  _buildDetailRow('Booking Type', 'VIP'),
                if (booking['travel_time_minutes'] != null &&
                    (booking['travel_time_minutes'] as num) > 0)
                  _buildDetailRow(
                    'Travel Time',
                    '${booking['travel_time_minutes']} minutes',
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: detailColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    String value, {
    required bool isDark,
    Color? color,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color ?? (isDark ? Colors.white70 : Colors.grey[700]),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // ✅ BUTTONS — track by ID
  // =====================================================
  Widget _buildCancelButton(Map<String, dynamic> booking) {
    final bookingId = booking['id'] as int;
    final isCancelling = _cancellingIds.contains(bookingId);

    return OutlinedButton(
      onPressed: isCancelling ? null : () => _cancelBooking(booking),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: isCancelling
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            )
          : const Text(
              'CANCEL',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
    );
  }

  Widget _buildReviewButton(Map<String, dynamic> booking) {
    return OutlinedButton(
      onPressed: () => _showLeaveReviewDialog(booking),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.amber, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_outline, color: Colors.amber, size: 18),
          SizedBox(width: 8),
          Text(
            'REVIEW',
            style: TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRebookButton(Map<String, dynamic> booking) {
    final isVip = booking['is_vip'] ?? false;
    final buttonColor = isVip ? _vipColor : AppTheme.primary;

    return OutlinedButton(
      onPressed: () => _rebookBooking(booking),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: buttonColor, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.refresh, color: buttonColor, size: 18),
          const SizedBox(width: 8),
          Text(
            'BOOK AGAIN',
            style: TextStyle(
              color: buttonColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsIconButton(Map<String, dynamic> booking) {
    final isDark = context.isDarkMode;
    final isVip = booking['is_vip'] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: IconButton(
        onPressed: () => _showBookingDetails(booking),
        icon: Icon(
          Icons.info_outline,
          color: isVip ? _vipColor : AppTheme.primary,
          size: 22,
        ),
        tooltip: 'View Details',
      ),
    );
  }

  // =====================================================
  // OVERFLOW CARD
  // =====================================================
  Widget _buildOverflowCard(Map<String, dynamic> notification) {
    final isDark = context.isDarkMode;
    final apt = notification['appointment'];
    final excessMinutes = notification['excess_minutes'];
    final estimatedEnd = notification['estimated_end'];
    final salonClose = notification['salon_close'];
    final isVip = apt['is_vip'] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? Colors.orange.withValues(alpha: 0.1)
              : Colors.orange.shade50,
          border: Border.all(
            color: isDark
                ? Colors.orange.withValues(alpha: 0.3)
                : Colors.orange.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withValues(alpha: 0.15)
                    : Colors.orange.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.withValues(alpha: 0.2)
                          : Colors.orange.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚠️ ACTION REQUIRED',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.orange.shade300
                                : Colors.orange,
                          ),
                        ),
                        Text(
                          apt['salon_name'] ?? 'Salon',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
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
                      color: isDark
                          ? Colors.red.withValues(alpha: 0.2)
                          : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$excessMinutes min overflow',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.red.shade300
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        apt['appointment_date'] ?? 'N/A',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${apt['start_time']} - ${apt['end_time']}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  if (apt['display_queue_number'] != null &&
                      apt['display_queue_number'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_list_numbered,
                            size: 16,
                            color: isVip ? _vipColor : _regularQueueColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Queue: ${apt['display_queue_number']}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isVip ? _vipColor : _regularQueueColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚠️ Schedule Overflow Detected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.orange.shade300
                                : Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your appointment may be delayed by approximately $excessMinutes minutes.',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Estimated end: $estimatedEnd | Salon closes: $salonClose',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isProcessingOverflow
                        ? null
                        : () => _showOverflowDecisionDialog(notification),
                    icon: _isProcessingOverflow
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle, size: 18),
                    label: const Text('RESPOND NOW'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '⚠️ If no response within 30 minutes, this appointment will be auto-cancelled.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // BOOKING CARD
  // ✅ NEW: Dual currency display everywhere (salon + approx user)
  // ✅ Uses LOCKED exchange rate from appointment
  // =====================================================
  Widget _buildBookingCard(Map<String, dynamic> booking, bool isPendingTab) {
    final isDark = context.isDarkMode;

    // ✅ Null-safe date parsing
    DateTime appointmentDateRaw;
    try {
      appointmentDateRaw = DateTime.parse(
        booking['appointment_date'] as String? ?? '',
      );
    } catch (_) {
      appointmentDateRaw = _selectedDate;
    }

    final status = booking['status'];
    final isVip = booking['is_vip'] ?? false;
    final salonCurrency = booking['currency_code'] as String?;
    final exchangeRate = booking['exchange_rate_at_booking'] as num?;
    final symbol = _currencySymbol(salonCurrency);

    final services = (booking['services'] as List?) ?? [];
    final duration = booking['duration'] ?? 0;
    final totalPrice = (booking['price'] as num?)?.toDouble() ?? 0.0;
    final extraCharge = (booking['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final totalDiscount =
        (booking['total_discount'] as num?)?.toDouble() ?? 0.0;

    // ✅ NEW: Convert total to user currency
    final userTotalAmount = _convertToUser(
      salonPrice: totalPrice,
      salonCurrency: salonCurrency,
      exchangeRate: exchangeRate,
    );

    final queueToken = booking['queue_token'] as String?;

    // VIP / Regular label
    final labelColor = isVip ? _vipColor : _regularQueueColor;
    final labelIcon = isVip ? Icons.star : Icons.confirmation_number;

    // Border
    BorderSide borderSide;
    if (isVip) {
      borderSide = BorderSide(color: _vipBorderColor, width: 2);
    } else {
      borderSide = BorderSide(
        color: _regularQueueBorderColor.withValues(alpha: 0.6),
        width: 1.5,
      );
    }

    // ✅ Determine actions by tab
    final showCancel =
        isPendingTab &&
        (status == 'pending' ||
            status == 'confirmed' ||
            status == 'in_progress');
    final showReviewRebook = !isPendingTab && status == 'completed';

    // ✅ User time reference (only if different from salon)
    final userStartTime = booking['user_start_time'] as String?;
    final userEndTime = booking['user_end_time'] as String?;
    final hasUserTime = userStartTime != null && userEndTime != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: borderSide,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ============ ROW 1: Queue badge + Label + Queue Token ============
            Row(
              children: [
                if (booking['display_queue_number'] != null &&
                    booking['display_queue_number'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: labelColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: labelColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(labelIcon, size: 11, color: labelColor),
                        const SizedBox(width: 4),
                        Text(
                          booking['display_queue_number'],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: labelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: labelColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: labelColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(labelIcon, size: 10, color: labelColor),
                      const SizedBox(width: 3),
                      Text(
                        isVip ? 'VIP' : 'REGULAR',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: labelColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // ✅ Queue Token
                if (queueToken != null && queueToken.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: labelColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: labelColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 11,
                          color: labelColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          queueToken,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ============ ROW 2: Salon ============
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: labelColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isVip ? Icons.star : Icons.store,
                    color: labelColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking['salon_name'] ?? 'Salon',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (booking['salon_address'] != null &&
                          booking['salon_address'].toString().isNotEmpty)
                        Text(
                          booking['salon_address'],
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: isDark ? Colors.white60 : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Barber: ${booking['barber_name'] ?? 'Barber'}',
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
                      if (booking['child_name'] != null &&
                          booking['child_name'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.child_care,
                                size: 12,
                                color: labelColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'For: ${booking['child_name']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: labelColor,
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

            const SizedBox(height: 12),

            // ============ ROW 3: Date/Time + User time reference ============
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: isDark ? Colors.white60 : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'EEE, MMM dd',
                            ).format(appointmentDateRaw),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: isDark ? Colors.white60 : Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${booking['local_start_time']} - ${booking['local_end_time']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                // ✅ User time reference (only if different)
                if (hasUserTime)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.public,
                          size: 12,
                          color: isDark ? Colors.blue[300] : Colors.blue[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Your time: $userStartTime - $userEndTime',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ============ ROW 4: Services ============
            Row(
              children: [
                Icon(Icons.content_cut, size: 13, color: labelColor),
                const SizedBox(width: 5),
                Text(
                  'Services (${services.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                const Spacer(),
                if (duration > 0)
                  Text(
                    '$duration min',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            if (services.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No services',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              )
            else
              ...services.map((s) {
                final sFinal = (s['final_price'] as num?)?.toDouble() ?? 0;
                final sDiscount =
                    (s['discount_amount'] as num?)?.toDouble() ?? 0;
                final sOriginal =
                    (s['original_price'] as num?)?.toDouble() ?? 0;
                final hasDiscount = sDiscount > 0;
                final variantLabel = s['variant_label'] as String?;
                final displayPrice = hasDiscount ? sFinal : sOriginal;

                // ✅ NEW: user currency conversion for this service
                final userServiceAmount = _convertToUser(
                  salonPrice: displayPrice,
                  salonCurrency: salonCurrency,
                  exchangeRate: exchangeRate,
                );

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '• ${s['service_name'] ?? 'Service'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasDiscount)
                            Icon(
                              Icons.local_offer,
                              size: 10,
                              color: Colors.green.shade700,
                            ),
                          const SizedBox(width: 3),
                          if (hasDiscount)
                            Text(
                              '$symbol${sOriginal.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 10,
                                decoration: TextDecoration.lineThrough,
                                color: isDark ? Colors.white60 : Colors.grey,
                              ),
                            ),
                          if (hasDiscount) const SizedBox(width: 3),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$symbol${displayPrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: hasDiscount
                                      ? Colors.green.shade700
                                      : (isDark
                                            ? Colors.white
                                            : Colors.black87),
                                ),
                              ),
                              // ✅ NEW: approx user amount
                              if (userServiceAmount != null)
                                Text(
                                  '≈ ${_formatUserPrice(userServiceAmount)}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic,
                                    color: isDark
                                        ? Colors.blue[300]
                                        : Colors.blue[700],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (variantLabel != null && variantLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 1),
                          child: Text(
                            variantLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white70 : Colors.grey[500],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),

            if (extraCharge > 0) ...[
              const Divider(height: 12),
              Row(
                children: [
                  const Icon(Icons.add_circle, size: 12, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      booking['extra_charge_note'] != null &&
                              booking['extra_charge_note'].toString().isNotEmpty
                          ? 'Extra (${booking['extra_charge_note']})'
                          : 'Extra',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '+$symbol${extraCharge.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ],

            if (totalDiscount > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.local_offer,
                    size: 12,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Discount',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '−$symbol${totalDiscount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: 14),
            // ✅ UPDATED: Total row with dual currency
            Row(
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$symbol${totalPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isVip ? _vipColor : AppTheme.primary,
                      ),
                    ),
                    // ✅ NEW: approx user total
                    if (userTotalAmount != null)
                      Text(
                        '≈ ${_formatUserPrice(userTotalAmount)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.blue[300]
                              : Colors.blue[700],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            if (booking['travel_time_minutes'] != null &&
                (booking['travel_time_minutes'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.directions_car,
                      size: 12,
                      color: isDark ? Colors.white60 : Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Travel time: ${booking['travel_time_minutes']} min',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // ============ ROW 5: Actions ============
            Row(
              children: [
                if (showCancel) ...[
                  Expanded(child: _buildCancelButton(booking)),
                  const SizedBox(width: 8),
                ] else if (showReviewRebook) ...[
                  Expanded(child: _buildReviewButton(booking)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildRebookButton(booking)),
                  const SizedBox(width: 8),
                ] else ...[
                  const Spacer(),
                ],
                _buildDetailsIconButton(booking),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // LIST BUILDER
  // =====================================================
  Widget _buildBookingList() {
    final isDark = context.isDarkMode;

    final showOverflow = _tabController.index == 0;
    final overflowList = showOverflow
        ? _overflowNotifications
        : <Map<String, dynamic>>[];
    final totalItems = _filteredBookings.length + overflowList.length;

    if (totalItems == 0) {
      return RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height - 350,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getEmptyIcon(),
                    size: 64,
                    color: isDark ? Colors.white30 : Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _getEmptyMessage(),
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[500],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (showOverflow && index < overflowList.length) {
            return _buildOverflowCard(overflowList[index]);
          }
          final bookingIndex = showOverflow
              ? index - overflowList.length
              : index;
          if (bookingIndex < 0 || bookingIndex >= _filteredBookings.length) {
            return const SizedBox.shrink();
          }
          return _buildBookingCard(
            _filteredBookings[bookingIndex],
            showOverflow,
          );
        },
      ),
    );
  }

  IconData _getEmptyIcon() {
    switch (_tabController.index) {
      case 0:
        return Icons.pending_actions;
      case 1:
        return Icons.payments_outlined;
      case 2:
        return Icons.check_circle_outline;
      default:
        return Icons.cancel_outlined;
    }
  }

  String _getEmptyMessage() {
    switch (_tabController.index) {
      case 0:
        return 'No pending bookings';
      case 1:
        return 'No pending payments';
      case 2:
        return 'No completed bookings';
      default:
        return 'No cancelled bookings';
    }
  }

  // =====================================================
  // DATE PICKER
  // =====================================================
  Future<void> _pickDate() async {
    // ✅ Dynamic date range (not hardcoded)
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        final isDark = context.isDarkMode;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF1E1E1E),
                    onSurface: Colors.white,
                  ),
                  dialogTheme: DialogThemeData(
                    backgroundColor: const Color(0xFF1E1E1E),
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
                  dialogTheme: DialogThemeData(backgroundColor: Colors.white),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      await _loadData();
    }
  }

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'My Bookings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.primary,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('TRY AGAIN'),
                  ),
                ],
              ),
            )
          : isWeb
          ? _buildWebLayout()
          : _buildMobileLayout(),
    );
  }

  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDateChanger(),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildTabBar(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingList(),
                  _buildBookingList(),
                  _buildBookingList(),
                  _buildBookingList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    final isDark = context.isDarkMode;

    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildDateChanger(),
        ),
        const SizedBox(height: 8),
        Container(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: _buildTabBar(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBookingList(),
              _buildBookingList(),
              _buildBookingList(),
              _buildBookingList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateChanger() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.today, size: 20, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedDateDisplay,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _pickDate,
            icon: Icon(Icons.edit_calendar, size: 16, color: AppTheme.primary),
            label: Text('Change', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final isDark = context.isDarkMode;

    return TabBar(
      controller: _tabController,
      isScrollable: true,
      labelColor: AppTheme.primary,
      unselectedLabelColor: isDark ? Colors.white60 : Colors.grey[600],
      indicatorColor: AppTheme.primary,
      indicatorWeight: 3,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.normal,
      ),
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pending_actions, size: 16),
              const SizedBox(width: 6),
              Text('Pending ($_pendingCount)'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.payments_outlined, size: 16),
              const SizedBox(width: 6),
              Text('Pending Payment ($_pendingPaymentCount)'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 16),
              const SizedBox(width: 6),
              Text('Complete ($_completedCount)'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cancel_outlined, size: 16),
              const SizedBox(width: 6),
              Text('Cancel ($_cancelledCount)'),
            ],
          ),
        ),
      ],
    );
  }
}