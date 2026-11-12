// Owner Dashboard - Appointments Screen (mobile + web)
// Owner can: START / END / PAY / BILL / SERVICES / CANCEL
//  - PAY on pending/confirmed  -> only marks paid (stays pending)
//  - PAY on in_progress        -> paid + ended (goes to Complete)
//  - once paid, PAY becomes BILL (download bill PDF)
// All cards / buttons / dialogs come from widgets/appointment_ui.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/appointment_ui.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../extensions/context_extensions.dart';
import '../../services/currency_service.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_theme.dart';

class AppointmentsScreen extends StatefulWidget {
  final String? salonId;
  final String? filter;

  const AppointmentsScreen({super.key, this.salonId, this.filter});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
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
  String? _error;
  String _salonName = '';
  String _currencyCode = '';

  String _salonTimezone = _kDefaultTz;
  String _userTimezone = '';
  bool _tzLoaded = false;

  // period filter
  String _period = 'date'; // date | month | year
  DateTime _selectedDate = DateTime.now();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // barber search
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _allBarbers = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  Map<String, dynamic>? _selectedBarber;

  bool get _isDark => context.isDarkMode;
  bool get _isWeb => MediaQuery.sizeOf(context).width > 800;
  bool get _tzDiffers =>
      _salonTimezone.isNotEmpty &&
      _userTimezone.isNotEmpty &&
      _salonTimezone != _userTimezone;

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
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ============================================================
  // INIT
  // ============================================================
  Future<void> _init() async {
    await _loadSalonTimezone();
    await _loadUserTimezone();
    if (!mounted) return;
    setState(() {
      _selectedDate = _salonToday;
      _tzLoaded = true;
    });
    await _loadData();
  }

  Future<void> _loadSalonTimezone() async {
    _salonTimezone = _kDefaultTz;
    final id = int.tryParse(widget.salonId ?? '');
    if (id == null) return;
    try {
      final r = await supabase
          .from('salons')
          .select('timezone')
          .eq('id', id)
          .maybeSingle();
      final tz = r?['timezone'] as String?;
      if (tz != null && tz.isNotEmpty) _salonTimezone = tz;
    } catch (e) {
      debugPrint('❌ salon timezone: $e');
    }
  }

  Future<void> _loadUserTimezone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userTimezone = prefs.getString(TimezoneService.kUserTimezone) ??
          TimezoneService.getCurrentTimezone();
    } catch (_) {
      _userTimezone = TimezoneService.getCurrentTimezone();
    }
    if (_userTimezone.isEmpty) _userTimezone = _kDefaultTz;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (supabase.auth.currentUser == null) {
        _error = 'Please login to view appointments';
        return;
      }
      final id = int.tryParse(widget.salonId ?? '');
      if (widget.salonId != null && id == null) {
        _error = 'Invalid salon ID';
        return;
      }
      if (id != null) {
        final s = await supabase
            .from('salons')
            .select('name, currency_code')
            .eq('id', id)
            .maybeSingle();
        if (s != null) {
          _salonName = (s['name'] as String?) ?? '';
          _currencyCode = (s['currency_code'] as String?) ?? '';
        }
        await _loadBarbers(id);
      }
      await _loadAppointments();
    } catch (e) {
      _error = 'Error loading appointments: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBarbers(int salonId) async {
    try {
      final sb = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', salonId)
          .eq('status', 'active');
      final ids = (sb as List).map((e) => e['barber_id'] as String).toList();
      if (ids.isEmpty) {
        _allBarbers = [];
        return;
      }
      final p = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .inFilter('id', ids)
          .eq('is_active', true)
          .eq('is_blocked', false);
      _allBarbers = [
        for (final r in p)
          {
            'id': r['id'],
            'full_name': r['full_name'] ?? 'Unknown Barber',
            'email': r['email'] ?? '',
            'avatar_url': r['avatar_url'],
          }
      ]..sort((a, b) => (a['full_name'] as String)
          .toLowerCase()
          .compareTo((b['full_name'] as String).toLowerCase()));
    } catch (e) {
      debugPrint('Error loading barbers: $e');
      _allBarbers = [];
    }
  }

  // ============================================================
  // LOAD + NORMALIZE APPOINTMENTS
  // ============================================================
  String get _rangeStart {
    if (_period == 'date') return DateFormat('yyyy-MM-dd').format(_selectedDate);
    if (_period == 'month') {
      return '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-01';
    }
    return '$_selectedYear-01-01';
  }

  String get _rangeEnd {
    if (_period == 'date') return DateFormat('yyyy-MM-dd').format(_selectedDate);
    if (_period == 'month') {
      final last = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
      return '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
    }
    return '$_selectedYear-12-31';
  }

  String get _periodText {
    if (_period == 'date') {
      final same = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
          DateFormat('yyyy-MM-dd').format(_salonToday);
      return same ? 'Today' : DateFormat('EEE, MMM dd, yyyy').format(_selectedDate);
    }
    if (_period == 'month') {
      return DateFormat('MMMM yyyy')
          .format(DateTime(_selectedYear, _selectedMonth));
    }
    return 'Year $_selectedYear';
  }

  Future<void> _loadAppointments() async {
    if (!mounted) return;
    try {
      final id = int.tryParse(widget.salonId ?? '');
      var q = supabase.from('appointments').select('''
        id, booking_number, customer_id, barber_id, salon_id,
        appointment_date, start_time, end_time, status,
        payment_status, paid_amount, payment_paid_at, payment_note,
        price, currency_code, original_price, discount_amount,
        extra_charge, extra_charge_note, offer_id,
        queue_number, regular_queue_number, vip_queue_number, queue_token,
        queue_position, is_vip, is_started, is_completed, child_name,
        travel_time_minutes, estimated_start_time, estimated_end_time,
        created_at, notes,
        profiles!appointments_customer_id_fkey (
          id, full_name, email, phone, avatar_url, is_active, is_blocked
        ),
        barber_profiles:profiles!appointments_barber_id_fkey (
          id, full_name, avatar_url
        ),
        salons!inner ( id, name, currency_code, currency_symbol, timezone ),
        appointment_services (
          id, service_id, variant_id, service_name, variant_label, duration,
          original_price, discount_amount, final_price, offer_id,
          added_by, added_at,
          offers ( id, title, discount_type, discount_value )
        )
      ''');

      if (id != null) q = q.eq('salon_id', id);
      if (_selectedBarber != null) {
        q = q.eq('barber_id', _selectedBarber!['id']);
      }
      q = q.gte('appointment_date', _rangeStart).lte('appointment_date', _rangeEnd);

      final res = await q
          .order('appointment_date', ascending: false)
          .order('start_time', ascending: false);
      if (!mounted) return;

      final list = [for (final a in res) _normalize(a)];
      setState(() {
        _all = list;
        _counts = ApptCounts.from(list);
        _filtered = filterAppts(list, _tabController.index);
        _error = null;
      });
    } catch (e) {
      debugPrint('❌ load appointments: $e');
      if (mounted) setState(() => _error = 'Error loading appointments: $e');
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

  String _displayDate(DateTime d) {
    final today = _salonToday;
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('MMM dd, yyyy').format(day);
  }

  Appt _normalize(Map<String, dynamic> apt) {
    final customer = apt['profiles'] as Map?;
    final barber = apt['barber_profiles'] as Map?;
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
        'offer_discount_type': offer?['discount_type'],
        'offer_discount_value': offer?['discount_value'],
        'added_by': s['added_by'],
        'added_at': s['added_at'],
      });
    }

    final extra = (apt['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final price = (apt['price'] as num?)?.toDouble() ??
        (servicesTotal - totalDiscount + extra);

    final ls = _fmt(apt['start_time'] as String?, date, tz);
    final le = _fmt(apt['end_time'] as String?, date, tz);
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
          (apt['customer_id'] != null ? 'Unknown Customer' : 'Walk-in Customer'),
      'customer_phone': customer?['phone'] ?? '',
      'customer_email': customer?['email'] ?? '',
      'customer_avatar': customer?['avatar_url'],
      'customer_active': apt['customer_id'] == null ? true : custActive,
      'barber_id': apt['barber_id'],
      'barber_name': barber?['full_name'] ?? 'Unknown Barber',
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
      'display_date': _displayDate(date),
      'start_time': apt['start_time'],
      'end_time': apt['end_time'],
      'local_start_time': ls,
      'local_end_time': le,
      'user_time': userTime,
      'est_display': '',
      'duration': services.fold<int>(0, (a, s) => a + (s['duration'] as int)),
    };
  }

  // ============================================================
  // ACTIONS
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
        onStart: () =>
            _run(() => ApptActions.start(context, a, isDark: _isDark)),
        onEnd: () => _run(() => ApptActions.end(context, a, isDark: _isDark)),
        onPay: () => _run(() => ApptActions.pay(context, a, isDark: _isDark)),
        onBill: () => ApptActions.bill(context, a),
        onServices: () => _run(() => ApptActions.editServices(context, a)),
        onCancel: () => _run(() =>
            ApptActions.cancel(context, a, isDark: _isDark, role: 'owner')),
      );

  // ============================================================
  // BARBER SEARCH
  // ============================================================
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final t = q.trim().toLowerCase();
      if (!mounted) return;
      setState(() {
        if (t.isEmpty) {
          _suggestions = [];
          _showSuggestions = false;
        } else {
          _suggestions = _allBarbers.where((b) {
            return (b['full_name'] as String).toLowerCase().contains(t) ||
                (b['email'] as String).toLowerCase().contains(t);
          }).toList();
          _showSuggestions = true;
        }
      });
    });
  }

  void _selectBarber(Map<String, dynamic> b) {
    setState(() {
      _selectedBarber = b;
      _searchCtrl.text = b['full_name'] ?? '';
      _showSuggestions = false;
      _suggestions = [];
    });
    _searchFocus.unfocus();
    _loadAppointments();
  }

  void _clearBarber() {
    setState(() {
      _selectedBarber = null;
      _searchCtrl.clear();
      _suggestions = [];
      _showSuggestions = false;
    });
    _searchFocus.unfocus();
    _loadAppointments();
  }

  // ============================================================
  // PERIOD PICKERS
  // ============================================================
  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (p != null && mounted) {
      setState(() {
        _selectedDate = p;
        _period = 'date';
      });
      _loadAppointments();
    }
  }

  void _shiftDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      _period = 'date';
    });
    _loadAppointments();
  }

  Future<void> _pickMonth() async {
    var y = _selectedYear;
    var m = _selectedMonth;
    final dark = _isDark;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Select month',
              style: TextStyle(color: dark ? Colors.white : Colors.black87)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                        onPressed: () => setD(() => y--),
                        icon: const Icon(Icons.chevron_left)),
                    Text('$y',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: dark ? Colors.white : Colors.black87)),
                    IconButton(
                        onPressed: () => setD(() => y++),
                        icon: const Icon(Icons.chevron_right)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 1; i <= 12; i++)
                      SizedBox(
                        width: 90,
                        height: 42,
                        child: ChoiceChip(
                          label: Center(
                            child: Text(DateFormat('MMM')
                                .format(DateTime(2024, i, 1))),
                          ),
                          selected: m == i,
                          selectedColor: AppTheme.primary,
                          labelStyle: TextStyle(
                              color: m == i
                                  ? Colors.white
                                  : (dark ? Colors.white70 : Colors.black87)),
                          onSelected: (_) => setD(() => m = i),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, y * 100 + m),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedYear = picked ~/ 100;
        _selectedMonth = picked % 100;
        _period = 'month';
      });
      _loadAppointments();
    }
  }

  Future<void> _pickYear() async {
    final cur = _salonNow.year;
    final dark = _isDark;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Select year',
            style: TextStyle(color: dark ? Colors.white : Colors.black87)),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var y = cur - 5; y < cur + 7; y++)
                SizedBox(
                  width: 90,
                  height: 42,
                  child: ChoiceChip(
                    label: Center(child: Text('$y')),
                    selected: y == _selectedYear,
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                        color: y == _selectedYear
                            ? Colors.white
                            : (dark ? Colors.white70 : Colors.black87)),
                    onSelected: (_) => Navigator.pop(ctx, y),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedYear = picked;
        _period = 'year';
      });
      _loadAppointments();
    }
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment:
              _isWeb ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            const Text('Appointments',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (_salonName.isNotEmpty)
              Text(_salonName,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAppointments,
          ),
        ],
      ),
      body: SafeArea(
        child: (!_tzLoaded || _loading)
            ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _error != null
                ? ApptMessageView(
                    icon: Icons.error_outline,
                    message: _error!,
                    isDark: dark,
                    buttonText: 'Retry',
                    onPressed: _loadData,
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
              if (_tzDiffers) ...[_tzBanner(dark), const SizedBox(height: 10)],
              _searchBox(dark),
              const SizedBox(height: 10),
              _periodBar(dark),
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
              emptySub: 'for $_periodText',
              cardBuilder: (a) => ApptCard(
                apt: a,
                isDark: dark,
                busy: _busy,
                showBarber: true,
                h: _handlers(a),
                onTap: () => showApptDetails(
                  context,
                  apt: a,
                  isDark: dark,
                  busy: _busy,
                  showBarber: true,
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

  Widget _tzBanner(bool dark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: dark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: dark ? 0.3 : 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: dark ? Colors.blue[300] : Colors.blue[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Salon timezone: ${TimezoneService.getFullTimezoneDisplayFor(_salonTimezone)}\n'
              'Times are shown in the salon\'s timezone. Your timezone: ${TimezoneService.getFullTimezoneDisplayFor(_userTimezone)}',
              style: TextStyle(
                  fontSize: 12, color: dark ? Colors.white70 : Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(bool dark) {
    final borderColor = _selectedBarber != null
        ? AppTheme.primary
        : (dark ? Colors.grey[800]! : Colors.grey[300]!);
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: borderColor, width: _selectedBarber != null ? 1.5 : 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(Icons.search,
                  size: 20, color: dark ? Colors.grey[400] : Colors.grey[500]),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: (v) {
                    setState(() {}); // refresh the clear button
                    _onSearchChanged(v);
                  },
                  style: TextStyle(
                      fontSize: 14, color: dark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Search barber by name or email...',
                    hintStyle: TextStyle(
                        fontSize: 14,
                        color: dark ? Colors.grey[500] : Colors.grey[400]),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty || _selectedBarber != null)
                IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: dark ? Colors.grey[400] : Colors.grey[500]),
                  onPressed: _clearBarber,
                ),
            ],
          ),
        ),
        if (_showSuggestions) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: dark ? Colors.grey[800]! : Colors.grey[200]!),
            ),
            child: _suggestions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.person_search,
                            size: 18,
                            color: dark ? Colors.grey[500] : Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text('No barbers found',
                            style: TextStyle(
                                fontSize: 13,
                                color: dark ? Colors.grey[400] : Colors.grey[600])),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _suggestions.length,
                    itemBuilder: (_, i) {
                      final b = _suggestions[i];
                      return ListTile(
                        dense: true,
                        leading: ApptAvatar(
                          url: b['avatar_url'] as String?,
                          name: b['full_name'] as String,
                          size: 34,
                          isDark: dark,
                        ),
                        title: Text(b['full_name'] as String,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: dark ? Colors.white : Colors.black87)),
                        subtitle: (b['email'] as String).isEmpty
                            ? null
                            : Text(b['email'] as String,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: dark
                                        ? Colors.grey[400]
                                        : Colors.grey[600])),
                        onTap: () => _selectBarber(b),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _periodBar(bool dark) {
    Widget btn(IconData icon, String label, String key, VoidCallback onTap) {
      final sel = _period == key;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.primary
                  : (dark ? const Color(0xFF2A2A2A) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: sel
                      ? AppTheme.primary
                      : (dark ? Colors.grey[800]! : Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: sel
                        ? Colors.white
                        : (dark ? Colors.white70 : Colors.grey[700])),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color: sel
                            ? Colors.white
                            : (dark ? Colors.white70 : Colors.grey[700]))),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            btn(Icons.calendar_today, 'Date', 'date', _pickDate),
            const SizedBox(width: 8),
            btn(Icons.calendar_month, 'Month', 'month', _pickMonth),
            const SizedBox(width: 8),
            btn(Icons.event_note, 'Year', 'year', _pickYear),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_period == 'date')
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftDate(-1),
              ),
            Expanded(
              child: Text(
                'Showing: $_periodText',
                textAlign: _period == 'date' ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white70 : Colors.grey[800]),
              ),
            ),
            if (_period == 'date')
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shiftDate(1),
              ),
            Text('${_counts.total} total',
                style: TextStyle(
                    fontSize: 12, color: dark ? Colors.white60 : Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}