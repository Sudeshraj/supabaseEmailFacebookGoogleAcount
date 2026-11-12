// Barber Appointments Screen (mobile + web)
// Barber can: START / END / PAY / BILL / SERVICES / CANCEL
//  - PAY on pending/confirmed  -> only marks paid (stays pending)
//  - PAY on in_progress        -> paid + ended (goes to Complete)
//  - once paid, PAY becomes BILL (download bill PDF)
// All cards / buttons / dialogs come from widgets/appointment_ui.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/appointment_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../extensions/context_extensions.dart';
import '../../services/currency_service.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_theme.dart';

class BarberAppointmentsScreen extends StatefulWidget {
  const BarberAppointmentsScreen({super.key});

  @override
  State<BarberAppointmentsScreen> createState() =>
      _BarberAppointmentsScreenState();
}

class _BarberAppointmentsScreenState extends State<BarberAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  static const String _kDefaultTz = 'Asia/Colombo';

  final supabase = Supabase.instance.client;
  final CurrencyService _currencyService = CurrencyService.instance;

  late TabController _tabController;

  List<Appt> _all = [];
  List<Appt> _filtered = [];
  ApptCounts _counts = ApptCounts.from(const []);

  bool _loading = true;
  bool _busy = false;
  bool _barberActive = true;
  String? _error;
  String _barberName = '';

  String _salonTimezone = _kDefaultTz;
  String _userTimezone = '';
  String _currencyCode = '';
  DateTime _selectedDate = DateTime.now();

  bool get _isDark => context.isDarkMode;
  bool get _isWeb => MediaQuery.sizeOf(context).width > 800;

  DateTime get _salonNow {
    try {
      return TimezoneService.getNowInTimezone(_salonTimezone);
    } catch (_) {
      return DateTime.now();
    }
  }

  DateTime get _salonToday {
    final n = _salonNow;
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) {
        setState(() => _filtered = filterAppts(_all, _tabController.index));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ============================================================
  // INIT
  // ============================================================
  Future<void> _init() async {
    await _loadSalonTimezone();
    try {
      _userTimezone = TimezoneService.getCurrentTimezone();
    } catch (_) {}
    if (_userTimezone.isEmpty) _userTimezone = _kDefaultTz;
    if (!mounted) return;
    setState(() => _selectedDate = _salonToday);
    await _checkStatusAndLoad();
  }

  Future<void> _loadSalonTimezone() async {
    _salonTimezone = _kDefaultTz;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final sb = await supabase
          .from('salon_barbers')
          .select('salon_id')
          .eq('barber_id', user.id)
          .eq('status', 'active')
          .limit(1);
      if (!mounted || sb.isEmpty) return;
      final salonId = sb.first['salon_id'] as int?;
      if (salonId == null) return;
      final r = await supabase
          .from('salons')
          .select('timezone, currency_code')
          .eq('id', salonId)
          .maybeSingle();
      if (r == null) return;
      final tz = r['timezone'] as String?;
      if (tz != null && tz.isNotEmpty) _salonTimezone = tz;
      final c = r['currency_code'] as String?;
      if (c != null && c.isNotEmpty) _currencyCode = c;
    } catch (e) {
      debugPrint('❌ salon timezone: $e');
    }
  }

  // ============================================================
  // BARBER STATUS CHECK
  // ============================================================
  Future<bool> _checkBarberActive() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;
      final r = await supabase
          .from('user_roles')
          .select('status, roles!inner (name)')
          .eq('user_id', user.id)
          .eq('roles.name', 'barber')
          .maybeSingle();
      return r != null && r['status'] == 'active';
    } catch (_) {
      return false;
    }
  }

  void _fail(String msg) {
    setState(() {
      _error = msg;
      _loading = false;
      _barberActive = false;
    });
  }

  Future<void> _checkStatusAndLoad() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Please login to continue';
          _loading = false;
        });
        return;
      }

      final role = await supabase
          .from('user_roles')
          .select('status, roles!inner (name)')
          .eq('user_id', user.id)
          .eq('roles.name', 'barber')
          .maybeSingle();
      if (!mounted) return;

      if (role == null) {
        _fail('Barber profile not found. Please contact support.');
        return;
      }
      final st = role['status'] as String? ?? 'active';
      if (st != 'active') {
        _fail(
          'Your barber account is ${st == 'inactive' ? 'deactivated' : st == 'scheduled_for_deletion' ? 'scheduled for deletion' : st == 'deleted' ? 'deleted' : 'not active'}. Please contact support.',
        );
        return;
      }

      final p = await supabase
          .from('profiles')
          .select('is_active, is_blocked, full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;

      if (p != null) {
        _barberName = (p['full_name'] as String?) ?? '';
        if (p['is_blocked'] == true) {
          _fail('Your account has been blocked. Please contact support.');
          return;
        }
        if (p['is_active'] == false) {
          _fail('Your profile is inactive. Please contact support.');
          return;
        }
      }

      _barberActive = true;
      await _loadAppointments(showSpinner: true);
    } catch (e) {
      if (mounted) _fail('Failed to load data: $e');
    }
  }

  // ============================================================
  // LOAD + NORMALIZE
  // ============================================================
  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);

  String get _dateDisplay {
    final today = _salonToday;
    final sel = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final f = DateFormat('MMM dd, yyyy').format(sel);
    if (sel == today) return 'Today, $f';
    if (sel == today.add(const Duration(days: 1))) return 'Tomorrow, $f';
    if (sel == today.subtract(const Duration(days: 1))) return 'Yesterday, $f';
    return DateFormat('EEEE, MMM dd, yyyy').format(sel);
  }

  Future<void> _loadAppointments({bool showSpinner = false}) async {
    if (!mounted) return;
    if (showSpinner) setState(() => _loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _error = 'Please login to continue');
        return;
      }

      final res = await supabase
          .from('appointments')
          .select('''
            id, booking_number, customer_id, barber_id, salon_id,
            appointment_date, start_time, end_time, status,
            price, paid_amount, original_price, discount_amount,
            extra_charge, extra_charge_note, offer_id, currency_code,
            is_vip, is_started, is_completed,
            queue_number, queue_token, regular_queue_number,
            vip_queue_number, queue_position,
            estimated_start_time, estimated_end_time,
            child_name, notes, travel_time_minutes,
            payment_status, payment_paid_at, payment_note, created_at,
            profiles!appointments_customer_id_fkey (
              id, full_name, avatar_url, phone, email, is_active, is_blocked
            ),
            salons ( id, name, currency_code, currency_symbol, timezone ),
            appointment_services (
              id, service_id, variant_id, service_name, variant_label,
              duration, original_price, discount_amount, final_price,
              offer_id, added_by, added_at,
              offers ( id, title )
            )
          ''')
          .eq('barber_id', user.id)
          .eq('appointment_date', _dateString)
          .order('start_time', ascending: true);
      if (!mounted) return;

      final list = [for (final a in res) _normalize(a)];
      list.sort((a, b) {
        final ap = (a['queue_position'] as num?) ?? 999;
        final bp = (b['queue_position'] as num?) ?? 999;
        return ap.compareTo(bp);
      });

      setState(() {
        _all = list;
        _counts = ApptCounts.from(list);
        _filtered = filterAppts(list, _tabController.index);
        _error = null;
      });
    } catch (e) {
      debugPrint('Error loading appointments: $e');
      if (mounted) setState(() => _error = 'Failed to load appointments: $e');
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  String _fmt(String? t, DateTime d, String tz) {
    if (t == null || t.isEmpty) return '';
    try {
      return TimezoneService.utcToLocalTimeForDateWithTimezone(t, d, tz);
    } catch (_) {
      return t.length >= 5 ? t.substring(0, 5) : t;
    }
  }

  String _fmtEstimated(String? raw, DateTime date, String tz) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final u = DateTime.parse(raw).toUtc();
      final s =
          '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}:00';
      final local =
          TimezoneService.utcToLocalDateTimeForDateWithTimezone(s, date, tz);
      return DateFormat('HH:mm').format(local);
    } catch (_) {
      return '';
    }
  }

  Appt _normalize(Map<String, dynamic> apt) {
    final customer = apt['profiles'] as Map?;
    final salon = apt['salons'] as Map?;
    final tzRaw = salon?['timezone'] as String?;
    final tz = (tzRaw != null && tzRaw.isNotEmpty) ? tzRaw : _kDefaultTz;

    DateTime date;
    try {
      date = DateTime.parse(apt['appointment_date'] as String);
    } catch (_) {
      date = _selectedDate;
    }

    final code = (salon?['currency_code'] as String?) ??
        (apt['currency_code'] as String?) ??
        (_currencyCode.isNotEmpty ? _currencyCode : 'LKR');

    double servicesTotal = 0, totalDiscount = 0;
    final services = <Map<String, dynamic>>[];
    for (final s in (apt['appointment_services'] as List?) ?? const []) {
      final offer = s['offers'] as Map?;
      final orig = (s['original_price'] as num?)?.toDouble() ?? 0.0;
      final disc = (s['discount_amount'] as num?)?.toDouble() ?? 0.0;
      servicesTotal += orig;
      totalDiscount += disc;
      services.add({
        'id': s['id'],
        'appointment_service_id': s['id'],
        'service_id': s['service_id'],
        'service_name': s['service_name'] ?? 'Service',
        'variant_id': s['variant_id'],
        'variant_label': s['variant_label'],
        'duration': (s['duration'] as num?)?.toInt() ?? 30,
        'original_price': orig,
        'discount_amount': disc,
        'final_price': (s['final_price'] as num?)?.toDouble() ?? 0.0,
        'offer_id': s['offer_id'],
        'offer_title': offer?['title'],
        'added_by': s['added_by'],
        'added_at': s['added_at'],
      });
    }

    final extra = (apt['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final price = (apt['price'] as num?)?.toDouble() ??
        (servicesTotal - totalDiscount + extra);

    final ls = _fmt(apt['start_time'] as String?, date, tz);
    final le = _fmt(apt['end_time'] as String?, date, tz);
    final est = _fmtEstimated(apt['estimated_start_time'] as String?, date, tz);

    String userTime = '';
    if (_userTimezone.isNotEmpty && _userTimezone != tz) {
      final us = _fmt(apt['start_time'] as String?, date, _userTimezone);
      final ue = _fmt(apt['end_time'] as String?, date, _userTimezone);
      if (us.isNotEmpty && ue.isNotEmpty) userTime = '$us - $ue';
    }

    final custActive = customer != null &&
        customer['is_active'] != false &&
        customer['is_blocked'] != true;

    return {
      'id': apt['id'],
      'booking_number': apt['booking_number'] ?? 'N/A',
      'customer_id': apt['customer_id'],
      'customer_name': customer?['full_name'] ??
          (apt['customer_id'] != null ? 'Deleted Customer' : 'Walk-in Customer'),
      'customer_phone': customer?['phone'] ?? '',
      'customer_email': customer?['email'] ?? '',
      'customer_avatar': customer?['avatar_url'],
      'customer_active': apt['customer_id'] == null ? true : custActive,
      'barber_id': apt['barber_id'],
      'barber_name': _barberName,
      'salon_id': apt['salon_id'],
      'salon_name': salon?['name'] ?? 'Salon',
      'timezone': tz,
      'currency_code': code,
      'symbol': _currencyService.getSymbol(code),
      'services': services,
      'services_total': servicesTotal,
      'total_discount': totalDiscount,
      'discount_amount': totalDiscount,
      'extra_charge': extra,
      'extra_charge_note': apt['extra_charge_note'],
      'offer_id': apt['offer_id'],
      'price': price,
      'paid_amount': (apt['paid_amount'] as num?)?.toDouble() ?? 0.0,
      'payment_status': apt['payment_status'] ?? 'unpaid',
      'payment_paid_at': apt['payment_paid_at'],
      'payment_note': apt['payment_note'],
      'status': apt['status'] ?? 'pending',
      'is_vip': apt['is_vip'] == true,
      'is_started': apt['is_started'] ?? false,
      'is_completed': apt['is_completed'] ?? false,
      'regular_queue_number': apt['regular_queue_number'],
      'vip_queue_number': apt['vip_queue_number'],
      'queue_position': apt['queue_position'],
      'queue_token': apt['queue_token'],
      'child_name': apt['child_name'],
      'notes': apt['notes'],
      'travel_time_minutes': apt['travel_time_minutes'],
      'appointment_date': apt['appointment_date'],
      'display_date': DateFormat('MMM dd, yyyy').format(date),
      'start_time': apt['start_time'],
      'end_time': apt['end_time'],
      'local_start_time': ls,
      'local_end_time': le,
      'user_time': userTime,
      'est_display': est,
      'duration': services.fold<int>(0, (a, s) => a + (s['duration'] as int)),
    };
  }

  // ============================================================
  // ACTIONS (all guarded: an inactive barber can not act)
  // ============================================================
  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final changed = await action();
      if (changed && mounted) await _loadAppointments();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ApptHandlers _handlers(Appt a) => ApptHandlers(
        onStart: () => _run(() => ApptActions.start(context, a,
            isDark: _isDark, guard: _checkBarberActive)),
        onEnd: () => _run(() => ApptActions.end(context, a,
            isDark: _isDark, guard: _checkBarberActive)),
        onPay: () => _run(() => ApptActions.pay(context, a,
            isDark: _isDark, guard: _checkBarberActive)),
        onBill: () => ApptActions.bill(context, a),
        onServices: () => _run(() =>
            ApptActions.editServices(context, a, guard: _checkBarberActive)),
        onCancel: () => _run(() => ApptActions.cancel(context, a,
            isDark: _isDark, role: 'barber', guard: _checkBarberActive)),
      );

  // ============================================================
  // DATE
  // ============================================================
  Future<void> _pickDate() async {
    final today = _salonToday;
    final p = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today.subtract(const Duration(days: 90)),
      lastDate: today.add(const Duration(days: 90)),
    );
    if (p != null && mounted) {
      setState(() => _selectedDate = p);
      _loadAppointments(showSpinner: true);
    }
  }

  void _shiftDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadAppointments(showSpinner: true);
  }

  void _goToday() {
    setState(() => _selectedDate = _salonToday);
    _loadAppointments(showSpinner: true);
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Appointments',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _loadAppointments(),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : (_error != null && _all.isEmpty)
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ApptMessageView(
                        icon: Icons.error_outline,
                        message: _error!,
                        isDark: dark,
                        buttonText: 'Retry',
                        onPressed: _init,
                      ),
                      if (!_barberActive)
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Go to Login'),
                        ),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1300),
                      child: _content(dark),
                    ),
                  ),
      ),
    );
  }

  Widget _content(bool dark) {
    final side = _isWeb ? 20.0 : 12.0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, 12, side, 0),
          child: Column(
            children: [
              _dateBar(dark),
              const SizedBox(height: 10),
              ApptStatsRow(
                counts: _counts,
                isDark: dark,
                onTap: (i) => _tabController.animateTo(i),
              ),
              const SizedBox(height: 10),
              buildApptTabBar(_tabController, _counts, dark),
              const SizedBox(height: 6),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side - 8 < 0 ? 0 : side - 8),
            child: ApptList(
              items: _filtered,
              isDark: dark,
              onRefresh: _loadAppointments,
              emptyText: _emptyText(),
              emptySub: 'for $_dateDisplay',
              cardBuilder: (a) => ApptCard(
                apt: a,
                isDark: dark,
                busy: _busy,
                showBarber: false,
                h: _handlers(a),
                onTap: () => showApptDetails(
                  context,
                  apt: a,
                  isDark: dark,
                  busy: _busy,
                  showBarber: false,
                  h: _handlers(a),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _emptyText() {
    switch (_tabController.index) {
      case 0:
        return 'No pending appointments';
      case 1:
        return 'No pending payments';
      case 2:
        return 'No completed appointments';
      case 3:
        return 'No cancelled appointments';
      default:
        return 'No appointments found';
    }
  }

  Widget _dateBar(bool dark) {
    final isToday = DateTime(_selectedDate.year, _selectedDate.month,
            _selectedDate.day) ==
        _salonToday;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
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
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftDate(-1),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_calendar, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _dateDisplay,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: dark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isToday)
            TextButton(onPressed: _goToday, child: const Text('Today')),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftDate(1),
          ),
        ],
      ),
    );
  }
}