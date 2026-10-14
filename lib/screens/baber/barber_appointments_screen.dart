import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/edit_appointment_services_sheet.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/timezone_service.dart';
import '../../services/currency_service.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class BarberAppointmentsScreen extends StatefulWidget {
  const BarberAppointmentsScreen({super.key});

  @override
  State<BarberAppointmentsScreen> createState() =>
      _BarberAppointmentsScreenState();
}

class _BarberAppointmentsScreenState extends State<BarberAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  // ✅ Default salon timezone
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';

  final supabase = Supabase.instance.client;
  final CurrencyService _currencyService = CurrencyService.instance;

  Color get _primaryColor => AppTheme.primary;
  Color get _vipColor => Colors.amber.shade700;
  Color get _vipBorderColor => Colors.amber.shade400;
  Color get _regularQueueColor => Colors.blue.shade600;
  Color get _regularQueueBorderColor => Colors.blue.shade400;
  Color get _secondaryColor => Colors.green;
  Color get _warningColor => Colors.orange;
  Color get _dangerColor => Colors.red;

  // Appointments
  List<Map<String, dynamic>> _allAppointments = [];
  List<Map<String, dynamic>> _filteredAppointments = [];

  bool _isLoading = true;
  String? _error;
  bool _isBarberActive = true;

  late TabController _tabController;

  int _totalCount = 0;
  int _completedCount = 0;
  int _pendingCount = 0;
  int _cancelledCount = 0;
  int _pendingPaymentCount = 0;

  DateTime _selectedDate = DateTime.now();
  bool _isProcessing = false;

  // Timezone + currency
  String _salonTimezone = _kDefaultSalonTimezone;
  String _userTimezone = '';
  String _currencyCode = '';

  // Cached salon today
  DateTime? _salonToday;

  final ScrollController _scrollController = ScrollController();

  bool _isWeb = false;
  bool _isDark = false;

  static const _editableStatuses = {'pending', 'confirmed', 'in_progress'};

  // ============================================================
  // GETTERS
  // ============================================================

  String get _effectiveCurrencyCode {
    if (_currencyCode.isNotEmpty) return _currencyCode;
    if (_salonTimezone.isNotEmpty) {
      return TimezoneService.getCurrencyForTimezone(_salonTimezone);
    }
    return 'LKR';
  }

  bool get _isDifferentTimezone {
    if (_salonTimezone.isEmpty || _userTimezone.isEmpty) return false;
    return _salonTimezone != _userTimezone;
  }

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

  DateTime get _cachedSalonToday {
    if (_salonToday != null) return _salonToday!;
    final now = _salonNow;
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initializeAndLoad();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = context.isDarkMode;
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.sizeOf(context);
    final isWeb = size.width > 800;

    if (_isWeb != isWeb) {
      setState(() {
        _isWeb = isWeb;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted && !_tabController.indexIsChanging) {
      setState(() => _applyStatusFilter());
    }
  }

  String get _selectedDateString =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  String get _selectedDateDisplay {
    final salonToday = _cachedSalonToday;
    final tomorrow = salonToday.add(const Duration(days: 1));

    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    if (selected.isAtSameMomentAs(salonToday)) {
      return 'Today, ${DateFormat('MMM dd, yyyy').format(_selectedDate)}';
    } else if (selected.isAtSameMomentAs(tomorrow)) {
      return 'Tomorrow, ${DateFormat('MMM dd, yyyy').format(_selectedDate)}';
    }
    return DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate);
  }

  void _applyStatusFilter() {
    switch (_tabController.index) {
      case 0:
        _filteredAppointments = _allAppointments.where((a) {
          final s = a['status'] as String? ?? '';
          return s == 'pending' || s == 'confirmed' || s == 'in_progress';
        }).toList();
        break;
      case 1:
        _filteredAppointments = _allAppointments.where((a) {
          return a['status'] == 'completed' &&
              (a['payment_status'] as String? ?? 'unpaid') != 'paid';
        }).toList();
        break;
      case 2:
        _filteredAppointments = _allAppointments.where((a) {
          return a['status'] == 'completed' &&
              (a['payment_status'] as String? ?? 'unpaid') == 'paid';
        }).toList();
        break;
      case 3:
        _filteredAppointments = _allAppointments.where((a) {
          final s = a['status'] as String? ?? '';
          return s == 'cancelled' || s == 'no_show';
        }).toList();
        break;
      case 4:
      default:
        _filteredAppointments = List.from(_allAppointments);
        break;
    }
  }

  String _currencySymbol(String? code) {
    return _currencyService.getSymbol(code ?? _effectiveCurrencyCode);
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> _initializeAndLoad() async {
    await _loadSalonTimezone();
    await _loadUserTimezone();

    if (!mounted) return;

    final now = _salonNow;
    setState(() {
      _salonToday = DateTime(now.year, now.month, now.day);
      _selectedDate = _salonToday!;
    });

    await _checkBarberStatusAndLoad();
  }

  /// ✅ FIXED: Get as list, then take first (avoids limit+maybeSingle conflict)
  /// ✅ FIXED: mounted checks after awaits
  Future<void> _loadSalonTimezone() async {
    _salonTimezone = _kDefaultSalonTimezone;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final salonBarbers = await supabase
          .from('salon_barbers')
          .select('salon_id')
          .eq('barber_id', user.id)
          .eq('status', 'active')
          .limit(1);

      if (!mounted) return;

      if (salonBarbers.isEmpty) return;

      final salonId = salonBarbers.first['salon_id'] as int?;
      if (salonId == null) return;

      final response = await supabase
          .from('salons')
          .select('timezone, currency_code')
          .eq('id', salonId)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        final tz = response['timezone'] as String?;
        if (tz != null && tz.isNotEmpty) {
          _salonTimezone = tz;
        } else {
          debugPrint('⚠️ Salon TZ empty → default: $_kDefaultSalonTimezone');
        }

        final curr = response['currency_code'] as String?;
        if (curr != null && curr.isNotEmpty) {
          _currencyCode = curr;
        }
      }
      debugPrint('✅ Salon timezone loaded: $_salonTimezone');
    } catch (e) {
      debugPrint('❌ Error loading salon timezone: $e');
      _salonTimezone = _kDefaultSalonTimezone;
    }
  }

  Future<void> _loadUserTimezone() async {
    try {
      _userTimezone = TimezoneService.getCurrentTimezone();
      if (_userTimezone.isEmpty) {
        _userTimezone = _kDefaultSalonTimezone;
        debugPrint('⚠️ User TZ empty → default: $_kDefaultSalonTimezone');
      }
      debugPrint('✅ User timezone loaded: $_userTimezone');
    } catch (e) {
      debugPrint('❌ Error loading user timezone: $e');
      _userTimezone = _kDefaultSalonTimezone;
    }
  }

  // ============================================================
  // CHECK BARBER STATUS
  // ✅ FIXED: mounted checks between all awaits
  // ============================================================

  Future<void> _checkBarberStatusAndLoad() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }

      final roleCheck = await supabase
          .from('user_roles')
          .select('status, roles!inner (name)')
          .eq('user_id', user.id)
          .eq('roles.name', 'barber')
          .maybeSingle();

      if (!mounted) return;

      if (roleCheck == null) {
        setState(() {
          _error = 'Barber profile not found. Please contact support.';
          _isLoading = false;
          _isBarberActive = false;
        });
        return;
      }

      final status = roleCheck['status'] as String? ?? 'active';
      if (status != 'active') {
        String message = 'Your barber account is ';
        switch (status) {
          case 'inactive':
            message += 'deactivated. Please contact support.';
            break;
          case 'scheduled_for_deletion':
            message += 'scheduled for deletion. Please contact support.';
            break;
          case 'deleted':
            message += 'deleted. Please contact support.';
            break;
          default:
            message += 'not active. Please contact support.';
        }
        setState(() {
          _error = message;
          _isLoading = false;
          _isBarberActive = false;
        });
        return;
      }

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked, full_name, extra_data')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          setState(() {
            _error = 'Your account has been blocked. Please contact support.';
            _isLoading = false;
            _isBarberActive = false;
          });
          return;
        }

        if (profileCheck['is_active'] == false) {
          final extraData =
              profileCheck['extra_data'] as Map<String, dynamic>? ?? {};
          final profileStatus =
              extraData['profile_status'] as Map<String, dynamic>?;

          if (profileStatus != null &&
              profileStatus['status'] == 'scheduled_for_deletion') {
            setState(() {
              _error =
                  'Your profile is scheduled for deletion. Please contact support.';
              _isLoading = false;
              _isBarberActive = false;
            });
            return;
          }

          setState(() {
            _error = 'Your profile is inactive. Please contact support.';
            _isLoading = false;
            _isBarberActive = false;
          });
          return;
        }
      }

      _isBarberActive = true;
      await _loadAppointments();
    } catch (e) {
      debugPrint('Error checking barber status: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load data: $e';
        _isLoading = false;
        _isBarberActive = false;
      });
    }
  }

  // ============================================================
  // LOAD APPOINTMENTS
  // ✅ FIXED: mounted everywhere
  // ✅ FIXED: null-safe date parsing
  // ✅ FIXED: single-pass estimated times conversion
  // ============================================================

  Future<void> _loadAppointments() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }

      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 2)
          .maybeSingle();

      if (!mounted) return;

      if (roleCheck == null || roleCheck['status'] != 'active') {
        setState(() {
          _error = 'Your barber account is not active.';
          _isBarberActive = false;
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
            price,
            original_price,
            discount_amount,
            extra_charge,
            extra_charge_note,
            offer_id,
            currency_code,
            is_vip,
            is_started,
            is_completed,
            queue_number,
            queue_token,
            regular_queue_number,
            vip_queue_number,
            queue_position,
            estimated_start_time,
            estimated_end_time,
            child_name,
            notes,
            payment_status,
            payment_paid_at,
            payment_note,
            created_at,
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
              offers (
                id,
                title
              ),
              added_by,
              added_at
            )
          ''')
          .eq('barber_id', user.id)
          .eq('appointment_date', _selectedDateString)
          .order('start_time', ascending: true);

      if (!mounted) return;

      if (appointments.isEmpty) {
        setState(() {
          _allAppointments = [];
          _filteredAppointments = [];
          _totalCount = 0;
          _completedCount = 0;
          _pendingCount = 0;
          _cancelledCount = 0;
          _pendingPaymentCount = 0;
        });
        return;
      }

      // Type-safe IDs
      final customerIds = appointments
          .map((a) => a['customer_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final salonIds = appointments
          .map((a) => a['salon_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      // Parallel queries
      final futures = <Future<List<Map<String, dynamic>>>>[];

      if (customerIds.isNotEmpty) {
        futures.add(
          supabase
              .from('user_roles')
              .select('user_id')
              .eq('role_id', 3)
              .eq('status', 'active')
              .inFilter('user_id', customerIds),
        );
      }

      if (salonIds.isNotEmpty) {
        futures.add(
          supabase
              .from('salons')
              .select('id, name, currency_code, currency_symbol')
              .inFilter('id', salonIds),
        );
      }

      final results = await Future.wait(futures);

      if (!mounted) return;

      List<Map<String, dynamic>> activeCustomers = [];
      List<Map<String, dynamic>> salons = [];

      if (customerIds.isNotEmpty) activeCustomers = results[0];
      if (salonIds.isNotEmpty) {
        salons = customerIds.isNotEmpty ? results[1] : results[0];
      }

      final activeCustomerIds = activeCustomers
          .map((c) => c['user_id'] as String)
          .toList();

      Map<String, Map<String, dynamic>> customersMap = {};
      if (activeCustomerIds.isNotEmpty) {
        final customers = await supabase
            .from('profiles')
            .select('id, full_name, avatar_url, phone, is_active, is_blocked')
            .inFilter('id', activeCustomerIds);

        if (!mounted) return;

        for (var customer in customers) {
          customersMap[customer['id']] = customer;
        }
      }

      Map<int, String> salonsMap = {};
      for (var salon in salons) {
        salonsMap[salon['id']] = salon['name'];
      }

      final List<Map<String, dynamic>> allList = [];
      int total = 0;
      int completed = 0;
      int pending = 0;
      int cancelled = 0;
      int pendingPayment = 0;

      for (var apt in appointments) {
        final customerId = apt['customer_id'] as String?;
        final customer = customerId != null ? customersMap[customerId] : null;

        final isCustomerActive = customer != null &&
            customer['is_active'] != false &&
            customer['is_blocked'] != true;

        final customerName = customer?['full_name'] as String? ??
            (customerId != null ? 'Deleted Customer' : 'Walk-in Customer');
        final customerAvatar = customer?['avatar_url'] as String?;
        final customerPhone = customer?['phone'] as String? ?? '';

        final List<Map<String, dynamic>> aptServices =
            List<Map<String, dynamic>>.from(apt['appointment_services'] ?? []);

        final serviceName = aptServices.isNotEmpty
            ? aptServices
                .map((s) => s['service_name']?.toString() ?? 'Service')
                .join(', ')
            : 'Service';

        final salonName = salonsMap[apt['salon_id']] ?? 'Salon';

        // ✅ Null-safe date parsing
        DateTime utcDate;
        try {
          utcDate = DateTime.parse(apt['appointment_date'] as String? ?? '');
        } catch (_) {
          utcDate = _selectedDate;
        }

        final utcStart = apt['start_time'] as String? ?? '';
        final utcEnd = apt['end_time'] as String? ?? '';

        final localStart = TimezoneService.utcToLocalTimeForDateWithTimezone(
          utcStart,
          utcDate,
          _salonTimezone,
        );
        final localEnd = TimezoneService.utcToLocalTimeForDateWithTimezone(
          utcEnd,
          utcDate,
          _salonTimezone,
        );

        // ✅ Single-pass estimated times conversion
        String estimatedStartDisplay = '';
        String estimatedEndDisplay = '';

        final estStartRaw = apt['estimated_start_time'] as String?;
        if (estStartRaw != null && estStartRaw.isNotEmpty) {
          try {
            final estStartUtc = DateTime.parse(estStartRaw).toUtc();
            final estStartTimeStr =
                '${estStartUtc.hour.toString().padLeft(2, '0')}:${estStartUtc.minute.toString().padLeft(2, '0')}:00';
            final localEstStart =
                TimezoneService.utcToLocalDateTimeForDateWithTimezone(
              estStartTimeStr,
              utcDate,
              _salonTimezone,
            );
            estimatedStartDisplay = DateFormat('HH:mm').format(localEstStart);
          } catch (e) {
            debugPrint('⚠️ Error parsing estimated_start_time: $e');
          }
        }

        final estEndRaw = apt['estimated_end_time'] as String?;
        if (estEndRaw != null && estEndRaw.isNotEmpty) {
          try {
            final estEndUtc = DateTime.parse(estEndRaw).toUtc();
            final estEndTimeStr =
                '${estEndUtc.hour.toString().padLeft(2, '0')}:${estEndUtc.minute.toString().padLeft(2, '0')}:00';
            final localEstEnd =
                TimezoneService.utcToLocalDateTimeForDateWithTimezone(
              estEndTimeStr,
              utcDate,
              _salonTimezone,
            );
            estimatedEndDisplay = DateFormat('HH:mm').format(localEstEnd);
          } catch (e) {
            debugPrint('⚠️ Error parsing estimated_end_time: $e');
          }
        }

        final displayQueue = _getDisplayQueueNumber(apt);
        final isVip = apt['is_vip'] ?? false;
        final queuePosition = apt['queue_position'];
        final isStarted = apt['is_started'] ?? false;
        final isCompleted = apt['is_completed'] ?? false;
        final status = apt['status'] as String? ?? 'pending';
        final paymentStatus = apt['payment_status']?.toString() ?? 'unpaid';

        total++;
        if (status == 'completed') {
          if (paymentStatus == 'paid') {
            completed++;
          } else {
            pendingPayment++;
          }
        } else if (status == 'pending' ||
            status == 'confirmed' ||
            status == 'in_progress') {
          pending++;
        } else if (status == 'cancelled' || status == 'no_show') {
          cancelled++;
        }

        final displayTime = estimatedStartDisplay.isNotEmpty
            ? estimatedStartDisplay
            : localStart;

        // Extract offer_title
        final List<Map<String, dynamic>> enrichedServices = aptServices.map((s) {
          final offer = s['offers'] as Map?;
          return {
            ...s,
            'offer_title': offer?['title'],
          };
        }).toList();

        allList.add({
          'id': apt['id'],
          'booking_number': apt['booking_number'],
          'appointment_date': apt['appointment_date'],
          'start_time': apt['start_time'],
          'end_time': apt['end_time'],
          'status': status,
          'is_vip': isVip,
          'price': (apt['price'] as num?)?.toDouble() ?? 0.0,
          'original_price': (apt['original_price'] as num?)?.toDouble() ??
              (apt['price'] as num?)?.toDouble() ??
              0.0,
          'discount_amount':
              (apt['discount_amount'] as num?)?.toDouble() ?? 0.0,
          'extra_charge': (apt['extra_charge'] as num?)?.toDouble() ?? 0.0,
          'extra_charge_note': apt['extra_charge_note'],
          'offer_id': apt['offer_id'],
          'salon_id': apt['salon_id'],
          'services': enrichedServices,
          'queue_number': apt['queue_number'],
          'regular_queue_number': apt['regular_queue_number'],
          'vip_queue_number': apt['vip_queue_number'],
          'queue_position': queuePosition,
          'display_queue': displayQueue,
          'child_name': apt['child_name'],
          'notes': apt['notes'],
          'customer_name': customerName,
          'customer_id': customerId,
          'customer_avatar': customerAvatar,
          'customer_phone': customerPhone,
          'customer_active': isCustomerActive,
          'service_name': serviceName,
          'salon_name': salonName,
          'currency_code': apt['currency_code'] ?? _effectiveCurrencyCode,
          'local_start_time': localStart,
          'local_end_time': localEnd,
          'estimated_start_time': estimatedStartDisplay,
          'estimated_end_time': estimatedEndDisplay,
          'is_started': isStarted,
          'is_completed': isCompleted,
          'payment_status': paymentStatus,
          'payment_paid_at': apt['payment_paid_at'],
          'payment_note': apt['payment_note'],
          'date_display': DateFormat('MMM dd, yyyy').format(utcDate),
          'day_display': DateFormat('EEEE').format(utcDate),
          'time_display': '$localStart - $localEnd',
          'display_time': displayTime,
        });
      }

      allList.sort((a, b) {
        final aPos = a['queue_position'] ?? 999;
        final bPos = b['queue_position'] ?? 999;
        return aPos.compareTo(bPos);
      });

      if (!mounted) return;
      setState(() {
        _allAppointments = allList;
        _totalCount = total;
        _completedCount = completed;
        _pendingCount = pending;
        _cancelledCount = cancelled;
        _pendingPaymentCount = pendingPayment;
        _applyStatusFilter();
      });
    } catch (e) {
      debugPrint('Error loading appointments: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load appointments: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

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

  String _formatUtcToUserTime(String? utcTimeStr, DateTime date) {
    if (utcTimeStr == null || utcTimeStr.isEmpty) return '';
    if (!_isDifferentTimezone) return '';
    if (_userTimezone.isEmpty) return '';

    try {
      return TimezoneService.utcToLocalTimeForDateWithTimezone(
        utcTimeStr,
        date,
        _userTimezone,
      );
    } catch (e) {
      debugPrint('❌ Error in _formatUtcToUserTime: $e');
      return '';
    }
  }

  Future<bool> _checkBarberActive() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 2)
          .maybeSingle();

      if (roleCheck == null) return false;
      return roleCheck['status'] == 'active';
    } catch (e) {
      debugPrint('Error checking barber active status: $e');
      return false;
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

  // ============================================================
  // EDIT SERVICES
  // ============================================================

  Future<void> _openEditServices(Map<String, dynamic> appointment) async {
    final isActive = await _checkBarberActive();
    if (!isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your barber account is not active.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditAppointmentServicesSheet(appointment: appointment),
    );

    if (changed == true && mounted) {
      await _loadAppointments();
    }
  }

  // ============================================================
  // START APPOINTMENT
  // ============================================================

  Future<void> _startAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    final isActive = await _checkBarberActive();
    if (!isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your barber account is not active.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Start Appointment?',
          style: dialogContext.titleLarge.copyWith(
            color: dialogContext.textColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you ready to start ${appointment['customer_name']}\'s appointment?',
              style: dialogContext.bodyMedium.copyWith(
                color: dialogContext.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dialogContext.isDarkMode
                    ? Colors.grey[800]
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Display Time: ${appointment['display_time']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: dialogContext.textColor,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
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
                        'Customer: ${appointment['customer_name']}',
                        style: TextStyle(color: dialogContext.textColor),
                      ),
                    ],
                  ),
                  if (appointment['display_queue'] != null &&
                      appointment['display_queue'].toString().isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.queue,
                          size: 16,
                          color: dialogContext.secondaryTextColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Queue: ${appointment['display_queue']}',
                          style: TextStyle(color: dialogContext.textColor),
                        ),
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
    if (!mounted) return;

    setState(() => _isProcessing = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final nowUtc = DateTime.now().toUtc();
      final tz = _salonTimezone.isNotEmpty
          ? _salonTimezone
          : _kDefaultSalonTimezone;

      final result = await supabase.rpc(
        'adjust_on_appointment_start',
        params: {
          'p_appointment_id': appointment['id'],
          'p_actual_start_time': nowUtc.toIso8601String(),
          'p_country_timezone': tz,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        String message = '✅ Appointment started!';
        if (result['start_delay_minutes'] != null &&
            result['start_delay_minutes'] > 0) {
          message =
              '⚠️ Started ${result['start_delay_minutes']} min late. Next appointments adjusted.';
        } else if (result['start_delay_minutes'] != null &&
            result['start_delay_minutes'] < 0) {
          message =
              '✅ Started ${result['start_delay_minutes'].abs()} min early.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: (result['start_delay_minutes'] ?? 0) > 0
                ? _warningColor
                : _secondaryColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        await _loadAppointments();
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

  // ============================================================
  // END APPOINTMENT
  // ============================================================

  Future<void> _endAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    final isActive = await _checkBarberActive();
    if (!isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your barber account is not active.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final hasOverflow = await _checkForOverflowWarning(appointment['id']);
    if (!mounted) return;

    final symbol = _currencySymbol(appointment['currency_code'] as String?);
    final total = (appointment['price'] as num?)?.toDouble() ?? 0.0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'End Appointment?',
          style: dialogContext.titleLarge.copyWith(
            color: dialogContext.textColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark ${appointment['customer_name']}\'s appointment as completed?',
              style: dialogContext.bodyMedium.copyWith(
                color: dialogContext.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dialogContext.isDarkMode
                    ? Colors.grey[800]
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Started: ${appointment['display_time']}',
                        style: TextStyle(color: dialogContext.textColor),
                      ),
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
                      Text(
                        'Customer: ${appointment['customer_name']}',
                        style: TextStyle(color: dialogContext.textColor),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 16,
                        color: _primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total: $symbol${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: dialogContext.textColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _warningColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: _warningColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Appointment will move to PENDING PAYMENT. Collect payment and mark as PAID later.',
                      style: TextStyle(fontSize: 11, color: _warningColor),
                    ),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
    if (!mounted) return;

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

      if (!mounted) return;

      if (result['success'] == true) {
        final newPrice = (result['new_price'] as num?)?.toDouble();
        String message = newPrice != null
            ? '✅ Completed. Total: $symbol${newPrice.toStringAsFixed(2)} — Pending payment'
            : '✅ Completed — Pending payment';
        if (result['delay_minutes'] != null && result['delay_minutes'] > 0) {
          message =
              '⚠️ Completed ${result['delay_minutes']} min late. Next appointments adjusted.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor:
                result['delay_minutes'] != null && result['delay_minutes'] > 0
                    ? _warningColor
                    : _secondaryColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );

        if (result['needs_confirmation'] == true && mounted) {
          _showOverflowNotificationDialog(result);
        }

        await _loadAppointments();
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

  // ============================================================
  // PAY APPOINTMENT
  // ============================================================

  Future<void> _payAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    final isActive = await _checkBarberActive();
    if (!isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your barber account is not active.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final symbol = _currencySymbol(appointment['currency_code'] as String?);
    final total = (appointment['price'] as num?)?.toDouble() ?? 0.0;
    final status = appointment['status'] as String? ?? '';

    final willAutoComplete =
        status == 'pending' || status == 'confirmed' || status == 'in_progress';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.payments, color: _secondaryColor, size: 26),
            const SizedBox(width: 10),
            Text(
              'Confirm Payment',
              style: dialogContext.titleLarge.copyWith(
                color: dialogContext.textColor,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark payment as received?',
              style: dialogContext.bodyMedium.copyWith(
                color: dialogContext.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dialogContext.isDarkMode
                    ? Colors.grey[800]
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
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
                      Expanded(
                        child: Text(
                          appointment['customer_name'],
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: dialogContext.textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: dialogContext.textColor,
                        ),
                      ),
                      Text(
                        '$symbol${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (willAutoComplete) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _warningColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: _warningColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This will END the appointment',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _warningColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'The appointment is still $status. Marking as paid will also complete it and adjust the queue.',
                            style: TextStyle(
                              fontSize: 11,
                              color: _warningColor,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('MARK AS PAID'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _secondaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);

    try {
      final result = await supabase.rpc(
        'mark_appointment_payment',
        params: {
          'p_appointment_id': appointment['id'],
          'p_payment_status': 'paid',
          'p_note': null,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final autoCompleted = result['auto_completed'] == true;
        final message = autoCompleted
            ? '✅ Appointment completed & paid — $symbol${total.toStringAsFixed(2)}'
            : '✅ Payment of $symbol${total.toStringAsFixed(2)} recorded';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: _secondaryColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        await _loadAppointments();
      } else {
        throw Exception(result['message'] ?? 'Failed to mark as paid');
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

  // ============================================================
  // CANCEL APPOINTMENT
  // ✅ FIXED: controller text read BEFORE dispose
  // ============================================================

  Future<void> _cancelAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;

    final isActive = await _checkBarberActive();
    if (!isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your barber account is not active.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    String? selectedReason;
    final otherReasonController = TextEditingController();
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

    bool? confirmed;
    // ✅ FIX: Read reason text BEFORE controller dispose
    String finalReason = '';

    try {
      confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (innerContext, setStateDialog) {
            return AlertDialog(
              backgroundColor: dialogContext.backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  Icon(Icons.cancel_outlined, color: _dangerColor, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Cancel Appointment',
                    style: dialogContext.titleLarge.copyWith(
                      color: dialogContext.textColor,
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
                        color: dialogContext.isDarkMode
                            ? Colors.grey[800]
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: dialogContext.isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[200]!,
                        ),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: dialogContext.textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: dialogContext.secondaryTextColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${appointment['date_display']} at ${appointment['display_time']}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dialogContext.secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Reason for cancellation',
                      style: dialogContext.titleSmall.copyWith(
                        color: dialogContext.textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      isExpanded: true,
                      dropdownColor: dialogContext.backgroundColor,
                      decoration: InputDecoration(
                        hintText: 'Select a reason',
                        hintStyle: TextStyle(
                          color: dialogContext.secondaryTextColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: dialogContext.isDarkMode
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                      ),
                      style: TextStyle(color: dialogContext.textColor),
                      items: cancelReasons.map((reason) {
                        return DropdownMenuItem<String>(
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
                        style: TextStyle(color: dialogContext.textColor),
                        decoration: InputDecoration(
                          hintText: 'Please specify the reason...',
                          hintStyle: TextStyle(
                            color: dialogContext.secondaryTextColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: dialogContext.isDarkMode
                              ? const Color(0xFF2A2A2A)
                              : Colors.white,
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
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                validationError!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
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
                    Navigator.pop(dialogContext, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dangerColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('YES, CANCEL'),
                ),
              ],
            );
          },
        ),
      );

      // ✅ FIX: Read reason BEFORE controller dispose
      if (confirmed == true) {
        if (selectedReason == 'Other') {
          finalReason = otherReasonController.text.trim();
        } else {
          finalReason = selectedReason ?? '';
        }
      }
    } finally {
      // ✅ Dispose AFTER reading text
      otherReasonController.dispose();
    }

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final result = await supabase.rpc(
        'cancel_booking_and_reorder',
        params: {
          'p_appointment_id': appointment['id'],
          'p_cancelled_by': user.id,
          'p_cancel_reason': finalReason,
          'p_role': 'barber',
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Appointment cancelled'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadAppointments();
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showOverflowNotificationDialog(Map<String, dynamic> result) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: _warningColor),
            const SizedBox(width: 8),
            Text(
              'Customer Notification Sent',
              style: dialogContext.titleLarge.copyWith(
                color: dialogContext.textColor,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result['message'] ?? 'Appointment exceeds salon hours.',
              style: dialogContext.bodyMedium.copyWith(
                color: dialogContext.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Customer has been notified and can choose to MOVE or CANCEL.\n\nIf no response within 30 minutes, the appointment will be auto-cancelled.',
                style: dialogContext.bodySmall.copyWith(color: _warningColor),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CUSTOMER INFO BOTTOM SHEET
  // ✅ FIXED: null-safe date parsing
  // ============================================================

  void _showCustomerInfo(Map<String, dynamic> appointment) {
    final isVip = appointment['is_vip'] ?? false;
    final displayQueue = appointment['display_queue'] ?? '';
    final queuePosition = appointment['queue_position'];
    final displayTime = appointment['display_time'];
    final isDark = context.isDarkMode;
    final paymentStatus = appointment['payment_status']?.toString() ?? 'unpaid';
    final symbol = _currencySymbol(appointment['currency_code'] as String?);

    final List<Map<String, dynamic>> services = List<Map<String, dynamic>>.from(
      appointment['services'] ?? [],
    );
    final double discountAmount =
        (appointment['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final double extraCharge =
        (appointment['extra_charge'] as num?)?.toDouble() ?? 0.0;

    // ✅ Null-safe date parsing
    DateTime utcDate;
    try {
      utcDate =
          DateTime.parse(appointment['appointment_date'] as String? ?? '');
    } catch (_) {
      utcDate = _selectedDate;
    }

    final userStartTime = _formatUtcToUserTime(
      appointment['start_time'] as String?,
      utcDate,
    );
    final userEndTime = _formatUtcToUserTime(
      appointment['end_time'] as String?,
      utcDate,
    );
    final hasUserTime = userStartTime.isNotEmpty && userEndTime.isNotEmpty;

    final avatarUrl = appointment['customer_avatar'] as String?;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final customerName =
        (appointment['customer_name'] as String?) ?? 'Customer';
    final initial =
        customerName.isNotEmpty ? customerName[0].toUpperCase() : '?';
    final isCustomerActive = appointment['customer_active'] != false;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
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
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
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
                    backgroundImage: hasAvatar
                        ? CachedNetworkImageProvider(avatarUrl)
                        : null,
                    child: !hasAvatar
                        ? Text(
                            initial,
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
                            Flexible(
                              child: Text(
                                customerName,
                                style: sheetContext.titleMedium.copyWith(
                                  color: sheetContext.textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
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
                            if (!isCustomerActive)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _dangerColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'INACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (appointment['customer_phone'] != null &&
                            appointment['customer_phone']
                                .toString()
                                .isNotEmpty)
                          Text(
                            appointment['customer_phone'],
                            style: sheetContext.bodyMedium.copyWith(
                              color: sheetContext.secondaryTextColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildInfoTile(
                'Services',
                services.isEmpty
                    ? (appointment['service_name']?.toString() ?? 'Service')
                    : services
                        .map(
                          (s) =>
                              '• ${s['service_name']}  $symbol${((s['final_price'] as num?) ?? 0).toStringAsFixed(2)}',
                        )
                        .join('\n'),
              ),
              _buildInfoTile('Date', appointment['date_display']),
              _buildInfoTile('Time', displayTime),
              if (hasUserTime)
                _buildInfoTile(
                  'Your Time',
                  '$userStartTime - $userEndTime',
                  valueColor: isDark ? Colors.blue[300] : Colors.blue[700],
                  italic: true,
                ),
              _buildInfoTile('Salon', appointment['salon_name']),
              if (discountAmount > 0)
                _buildInfoTile(
                  'Discount',
                  '- $symbol${discountAmount.toStringAsFixed(2)}',
                ),
              if (extraCharge > 0)
                _buildInfoTile(
                  'Extra Charge',
                  '+ $symbol${extraCharge.toStringAsFixed(2)}',
                ),
              _buildInfoTile(
                'Total',
                '$symbol${(appointment['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              ),
              _buildInfoTile(
                'Payment',
                paymentStatus == 'paid' ? 'PAID' : 'PENDING',
              ),
              if (appointment['child_name'] != null &&
                  appointment['child_name'].toString().isNotEmpty)
                _buildInfoTile('Booked For', appointment['child_name']),
              if (displayQueue.isNotEmpty)
                _buildInfoTile('Queue Number', displayQueue),
              if (queuePosition != null)
                _buildInfoTile('Position', '#$queuePosition'),
              const SizedBox(height: 12),
              if (_editableStatuses.contains(appointment['status']) ||
                  (appointment['status'] == 'completed' &&
                      paymentStatus != 'paid'))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openEditServices(appointment);
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Edit Services / Extra Charge'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isVip ? _vipColor : _primaryColor,
                      side: BorderSide(
                        color: isVip ? _vipColor : _primaryColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isVip ? _vipColor : _primaryColor,
                    foregroundColor: Colors.white,
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

  Widget _buildInfoTile(
    String label,
    String value, {
    Color? valueColor,
    bool italic = false,
  }) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: context.bodyMedium.copyWith(
                color: isDark ? Colors.white60 : context.secondaryTextColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: context.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                color:
                    valueColor ?? (isDark ? Colors.white : context.textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDatePickerDialog() {
    final isDark = context.isDarkMode;

    final salonNow = _salonNow;
    final salonToday = DateTime(salonNow.year, salonNow.month, salonNow.day);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Select Date',
          style: dialogContext.titleLarge.copyWith(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: SizedBox(
          width: 300,
          height: 350,
          child: CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: salonToday.subtract(const Duration(days: 30)),
            lastDate: salonToday.add(const Duration(days: 60)),
            onDateChanged: (date) {
              Navigator.pop(dialogContext);
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

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    final isDark = _isDark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // APPOINTMENT CARD
  // ✅ FIXED: null-safe date parsing
  // ============================================================

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final isDark = _isDark;
    final status = appointment['status'];
    final paymentStatus = appointment['payment_status']?.toString() ?? 'unpaid';
    final isInProgress = status == 'in_progress';
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    final isNoShow = status == 'no_show';
    final isPendingPayment = isCompleted && paymentStatus != 'paid';
    final isFullyCompleted = isCompleted && paymentStatus == 'paid';
    final isVip = appointment['is_vip'] ?? false;
    final isPaid = paymentStatus == 'paid';
    final isCustomerActive = appointment['customer_active'] != false;

    final symbol = _currencySymbol(appointment['currency_code'] as String?);

    final customerName = appointment['customer_name'] ?? 'Customer';
    final customerAvatar = appointment['customer_avatar'] as String?;
    final displayDate = appointment['date_display'] ?? '';
    final startTime = appointment['local_start_time'] ?? '';
    final endTime = appointment['local_end_time'] ?? '';
    final regQueue = appointment['regular_queue_number'];
    final vipQueue = appointment['vip_queue_number'];
    final childName = appointment['child_name'] as String?;
    final notes = appointment['notes'] as String?;

    final estimatedStart =
        appointment['estimated_start_time']?.toString() ?? '';
    final hasEstimatedTime = estimatedStart.isNotEmpty &&
        estimatedStart != appointment['local_start_time'];

    // ✅ Null-safe date parsing
    DateTime utcDate;
    try {
      utcDate =
          DateTime.parse(appointment['appointment_date'] as String? ?? '');
    } catch (_) {
      utcDate = _selectedDate;
    }

    final userStartTime = _formatUtcToUserTime(
      appointment['start_time'] as String?,
      utcDate,
    );
    final userEndTime = _formatUtcToUserTime(
      appointment['end_time'] as String?,
      utcDate,
    );
    final hasUserTime = userStartTime.isNotEmpty && userEndTime.isNotEmpty;

    final List<Map<String, dynamic>> services = List<Map<String, dynamic>>.from(
      appointment['services'] ?? [],
    );
    final double totalPrice = (appointment['price'] as num?)?.toDouble() ?? 0.0;
    final double totalDiscount =
        (appointment['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final double extraCharge =
        (appointment['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final String? extraNote = appointment['extra_charge_note'] as String?;

    final int duration = services.fold<int>(
      0,
      (a, s) => a + ((s['duration'] as num?)?.toInt() ?? 0),
    );

    final bool canStart = !isCancelled &&
        !isNoShow &&
        (status == 'pending' || status == 'confirmed');
    final bool canEnd = isInProgress;
    final bool canPay = isInProgress || isPendingPayment;
    final bool canCancel = !isCancelled &&
        !isNoShow &&
        (status == 'pending' || status == 'confirmed');
    final bool canEditServices =
        _editableStatuses.contains(status) || isPendingPayment;

    final labelColor = isVip ? _vipColor : _regularQueueColor;
    final labelIcon = isVip ? Icons.star : Icons.confirmation_number;

    BorderSide borderSide;
    if (isVip) {
      borderSide = BorderSide(color: _vipBorderColor, width: 2);
    } else if (isPendingPayment) {
      borderSide = BorderSide(color: Colors.orange.shade400, width: 2);
    } else {
      borderSide = BorderSide(
        color: _regularQueueBorderColor.withValues(alpha: 0.6),
        width: 1.5,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: borderSide,
      ),
      child: InkWell(
        onTap: () => _showCustomerInfo(appointment),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ROW 1: Queue badge + VIP/Regular label + customer inactive
              Row(
                children: [
                  if (regQueue != null || vipQueue != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isVip
                            ? _vipColor.withValues(alpha: 0.12)
                            : _regularQueueColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isVip
                              ? _vipColor.withValues(alpha: 0.5)
                              : _regularQueueColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVip ? Icons.star : Icons.confirmation_number,
                            size: 11,
                            color: isVip ? _vipColor : _regularQueueColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isVip ? 'VIP-$vipQueue' : 'Q$regQueue',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isVip ? _vipColor : _regularQueueColor,
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
                  if (!isCustomerActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _dangerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _dangerColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_off,
                            size: 10,
                            color: _dangerColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'INACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: _dangerColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // ROW 2: Customer
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                    ),
                    child: customerAvatar != null && customerAvatar.isNotEmpty
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: customerAvatar,
                              fit: BoxFit.cover,
                              width: 42,
                              height: 42,
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  customerName.isNotEmpty
                                      ? customerName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              customerName.isNotEmpty
                                  ? customerName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white60 : Colors.grey,
                              ),
                            ),
                          ),
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCompleted)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isPaid
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPaid
                                          ? Icons.check_circle
                                          : Icons.schedule,
                                      size: 10,
                                      color: isPaid
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isPaid ? 'PAID' : 'UNPAID',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: isPaid
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (childName != null && childName.isNotEmpty)
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
                                  'For: $childName',
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

              // ROW 3: Services
              Row(
                children: [
                  Icon(Icons.content_cut, size: 13, color: _primaryColor),
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
                  final offerTitle = s['offer_title'] as String?;
                  final variantLabel = s['variant_label'] as String?;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '• ${s['service_name']}',
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
                            Text(
                              '$symbol${(hasDiscount ? sFinal : sOriginal).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: hasDiscount
                                    ? Colors.green.shade700
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
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
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[500],
                              ),
                            ),
                          ),
                        if (hasDiscount && offerTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 1),
                            child: Text(
                              'Offer: $offerTitle',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
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
                    const Icon(
                      Icons.add_circle,
                      size: 12,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        extraNote != null && extraNote.isNotEmpty
                            ? 'Extra ($extraNote)'
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
                  Text(
                    '$symbol${totalPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isVip ? _vipColor : _primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ROW 4: Date/Time + user reference
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          displayDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: isDark ? Colors.white60 : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasEstimatedTime
                                  ? '${appointment['display_time']} (Est)'
                                  : '$startTime - $endTime',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        if (hasUserTime)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.public,
                                  size: 10,
                                  color: isDark
                                      ? Colors.blue[300]
                                      : Colors.blue[700],
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    'Your: $userStartTime - $userEndTime',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                      color: isDark
                                          ? Colors.blue[300]
                                          : Colors.blue[700],
                                    ),
                                    overflow: TextOverflow.ellipsis,
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

              // ROW 5: Notes
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note, size: 12, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        notes,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // ACTION BUTTONS
              if (canStart ||
                  canEnd ||
                  canPay ||
                  canCancel ||
                  canEditServices) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (canStart)
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _startAppointment(appointment),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text(
                            'START',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _secondaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if (canEnd)
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _endAppointment(appointment),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text(
                            'END',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _secondaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if (canPay)
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _payAppointment(appointment),
                          icon: const Icon(Icons.payments, size: 16),
                          label: const Text(
                            'PAY',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if ((canStart || canEnd || canPay) && canEditServices)
                      const SizedBox(width: 8),
                    if (canEditServices)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _openEditServices(appointment),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text(
                            'SERVICES',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primaryColor,
                            side: BorderSide(color: _primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (canCancel) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _cancelAppointment(appointment),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text(
                        'CANCEL',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _dangerColor,
                        side: BorderSide(color: _dangerColor),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ] else if (isFullyCompleted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
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
                          'Paid & Completed',
                          style: TextStyle(
                            fontSize: 12,
                            color: _secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (isCancelled || isNoShow)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _dangerColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCancelled ? Icons.cancel : Icons.person_off,
                          size: 16,
                          color: _dangerColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isCancelled ? 'Cancelled' : 'No Show',
                          style: TextStyle(fontSize: 12, color: _dangerColor),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // APPOINTMENT LIST
  // ============================================================

  Widget _buildAppointmentList() {
    if (_filteredAppointments.isEmpty) {
      if (_isWeb) {
        return _buildEmptyState();
      }
      return RefreshIndicator(
        onRefresh: _loadAppointments,
        color: _primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height - 250,
            child: _buildEmptyState(),
          ),
        ),
      );
    }

    if (_isWeb) {
      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 8,
        radius: const Radius.circular(10),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.55,
                ),
                itemCount: _filteredAppointments.length,
                itemBuilder: (context, index) {
                  return _buildAppointmentCard(_filteredAppointments[index]);
                },
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAppointments,
      color: _primaryColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _filteredAppointments.length,
        itemBuilder: (context, index) {
          return _buildAppointmentCard(_filteredAppointments[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (_tabController.index) {
      case 0:
        message = 'No pending appointments';
        icon = Icons.pending_actions;
        break;
      case 1:
        message = 'No pending payments';
        icon = Icons.payments_outlined;
        break;
      case 2:
        message = 'No completed appointments';
        icon = Icons.check_circle_outline;
        break;
      case 3:
        message = 'No cancelled appointments';
        icon = Icons.cancel_outlined;
        break;
      default:
        message = 'No appointments found';
        icon = Icons.event_busy;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: _isDark ? Colors.white30 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: _isDark ? Colors.white70 : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'for $_selectedDateDisplay',
            style: TextStyle(
              fontSize: 13,
              color: _isDark ? Colors.white70 : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Pull down to refresh',
            style: TextStyle(
              fontSize: 11,
              color: _isDark ? Colors.white30 : Colors.grey[400],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'My Appointments',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: _isDark ? Colors.white30 : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color:
                                _isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _initializeAndLoad,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                        ),
                        child: const Text('Retry'),
                      ),
                      if (!_isBarberActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(
                              'Go to Login',
                              style: TextStyle(
                                color: _isDark ? Colors.white60 : Colors.blue,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : _isWeb
                  ? _buildWebLayout()
                  : _buildMobileLayout(),
    );
  }

  Widget _buildWebLayout() {
    final isDark = _isDark;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1100),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
                  Icon(Icons.today, size: 20, color: _primaryColor),
                  const SizedBox(width: 12),
                  Text(
                    _selectedDateDisplay,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showDatePickerDialog,
                    icon: Icon(
                      Icons.edit_calendar,
                      size: 16,
                      color: _primaryColor,
                    ),
                    label: Text(
                      'Change',
                      style: TextStyle(color: _primaryColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Pending',
                    _pendingCount,
                    Icons.pending_actions,
                    _warningColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Pending Payment',
                    _pendingPaymentCount,
                    Icons.payments_outlined,
                    Colors.teal.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Complete',
                    _completedCount,
                    Icons.check_circle_outline,
                    _secondaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Cancel',
                    _cancelledCount,
                    Icons.cancel_outlined,
                    _dangerColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
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
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: _primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _primaryColor,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.list_alt, size: 16),
                        const SizedBox(width: 6),
                        Text('All ($_totalCount)'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAppointments,
                color: _primaryColor,
                child: _buildAppointmentList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    final isDark = _isDark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
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
                Icon(Icons.today, size: 20, color: _primaryColor),
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
                  onPressed: _showDatePickerDialog,
                  icon: Icon(
                    Icons.edit_calendar,
                    size: 16,
                    color: _primaryColor,
                  ),
                  label: Text('Change', style: TextStyle(color: _primaryColor)),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Pending',
                  _pendingCount,
                  Icons.pending_actions,
                  _warningColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Pending Pay',
                  _pendingPaymentCount,
                  Icons.payments_outlined,
                  Colors.teal.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Complete',
                  _completedCount,
                  Icons.check_circle_outline,
                  _secondaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Cancel',
                  _cancelledCount,
                  Icons.cancel_outlined,
                  _dangerColor,
                ),
              ),
            ],
          ),
        ),
        Container(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: _primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _primaryColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
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
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.list_alt, size: 16),
                    const SizedBox(width: 6),
                    Text('All ($_totalCount)'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildAppointmentList()),
      ],
    );
  }
}