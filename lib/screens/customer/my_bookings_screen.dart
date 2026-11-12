// Customer - My Bookings Screen (mobile + web)
//  - "All" view (last 90 days + upcoming) or "By date" view
//  - status chip + PAID / PARTIAL / UNPAID / REFUND chip on every booking
//  - balance due / refund info, dual currency (salon + approx. user currency)
//  - BILL download for paid bookings
//  - cancel (pending/confirmed only) with refund warning
//  - review only once per booking
// Uses widgets/appointment_ui.dart (list, stats row, chips) and bill_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/screens/customer/booking_flow_screen.dart';
import 'package:flutter_application_1/services/currency_service.dart';
import 'package:flutter_application_1/services/currency_settings_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/appointment_ui.dart';
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
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';
  static const String _kDefaultCurrency = 'LKR';

  final supabase = Supabase.instance.client;
  final CurrencyService _currencyService = CurrencyService.instance;
  final CurrencySettingsService _currencySettings =
      CurrencySettingsService.instance;

  late TabController _tabController;

  List<Appt> _all = [];
  List<Appt> _overflow = [];
  ApptCounts _counts = ApptCounts.from(const []);

  bool _isLoading = true;
  String? _error;
  bool _isProcessingOverflow = false;
  final Set<int> _cancellingIds = {};

  // view mode: all bookings (last 90 days + upcoming) or one selected date
  bool _byDate = false;
  DateTime _selectedDate = DateTime.now();

  String _customerName = '';
  String _userTimezone = '';
  String _userCurrencyCode = _kDefaultCurrency;

  Color get _vipColor => Colors.amber.shade700;
  Color get _regularColor => Colors.blue.shade600;

  // ============================================================
  // HELPERS
  // ============================================================
  DateTime get _salonNow {
    try {
      return TimezoneService.getNowInTimezone(_kDefaultSalonTimezone);
    } catch (_) {
      return DateTime.now();
    }
  }

  DateTime get _salonToday {
    final n = _salonNow;
    return DateTime(n.year, n.month, n.day);
  }

  String get _selectedDateDisplay {
    final today = _salonToday;
    final sel =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final f = DateFormat('MMM dd, yyyy').format(sel);
    if (sel == today) return 'Today, $f';
    if (sel == today.add(const Duration(days: 1))) return 'Tomorrow, $f';
    if (sel == today.subtract(const Duration(days: 1))) return 'Yesterday, $f';
    return DateFormat('EEEE, MMM dd, yyyy').format(sel);
  }

  String _currencySymbol(String? code) =>
      _currencyService.getSymbol(code ?? _kDefaultCurrency);

  String _formatSalonPrice(dynamic price, String? salonCurrency) =>
      _currencyService.format(
        price: price,
        currencyCode: salonCurrency ?? _kDefaultCurrency,
      );

  String _formatUserPrice(dynamic price) =>
      _currencyService.format(price: price, currencyCode: _userCurrencyCode);

  /// salon price -> user currency using the rate locked at booking time
  double? _convertToUser({
    required dynamic salonPrice,
    required String? salonCurrency,
    required dynamic exchangeRate,
  }) {
    if (salonCurrency == null || salonCurrency == _userCurrencyCode) return null;
    final rate = (exchangeRate as num?)?.toDouble();
    if (rate == null || rate <= 0) return null;
    return ((salonPrice as num?)?.toDouble() ?? 0.0) * rate;
  }

  String _fmtTime(String? t, DateTime d, String tz) {
    if (t == null || t.isEmpty) return '';
    try {
      return TimezoneService.utcToLocalTimeForDateWithTimezone(t, d, tz);
    } catch (_) {
      return t.length >= 5 ? t.substring(0, 5) : t;
    }
  }

  DateTime _parseDate(dynamic v) {
    try {
      return DateTime.parse(v as String);
    } catch (_) {
      return _selectedDate;
    }
  }

  bool _isLiveStatus(String s) =>
      s == 'pending' || s == 'confirmed' || s == 'in_progress' || s == 'completed';

  // ============================================================
  // LIFECYCLE
  // ============================================================
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await TimezoneService.initialize();
    _userTimezone = TimezoneService.getCurrentTimezone();
    if (_userTimezone.isEmpty) _userTimezone = _kDefaultSalonTimezone;

    try {
      _userCurrencyCode = await _currencySettings.getUserCurrency();
    } catch (_) {
      _userCurrencyCode = _kDefaultCurrency;
    }

    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final p = await supabase
            .from('profiles')
            .select('full_name')
            .eq('id', uid)
            .maybeSingle();
        _customerName = (p?['full_name'] as String?) ?? '';
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _selectedDate = _salonToday);
    await _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _userCurrencyCode = await _currencySettings.getUserCurrency();
    } catch (_) {}

    await Future.wait([_loadBookings(), _loadOverflowNotifications()]);
    if (mounted) setState(() => _isLoading = false);
  }

  // ============================================================
  // LOAD BOOKINGS
  // ============================================================
  Future<void> _loadBookings() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _error = 'Please login to view your bookings');
        return;
      }

      final roleRow = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'customer')
          .single();
      final roleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', roleRow['id'])
          .maybeSingle();
      if (!mounted) return;

      if (roleCheck == null || roleCheck['status'] != 'active') {
        setState(() => _error = 'Your account is not active. Please contact support.');
        return;
      }

      var q = supabase.from('appointments').select('''
        id, booking_number, customer_id, barber_id, salon_id,
        appointment_date, start_time, end_time, status,
        payment_status, paid_amount, payment_paid_at, payment_note,
        price, original_price, discount_amount, extra_charge, extra_charge_note,
        currency_code, exchange_rate_at_booking,
        queue_number, regular_queue_number, vip_queue_number, queue_token,
        queue_position, is_vip, child_name, travel_time_minutes, notes,
        salons!inner ( id, name, address, currency_code, currency_symbol, timezone ),
        barber_profile:profiles!appointments_barber_id_fkey ( id, full_name ),
        appointment_services (
          id, service_id, variant_id, service_name, variant_label, duration,
          original_price, discount_amount, final_price, offer_id, added_by
        )
      ''').eq('customer_id', user.id);

      if (_byDate) {
        q = q.eq('appointment_date', DateFormat('yyyy-MM-dd').format(_selectedDate));
      } else {
        final from = _salonToday.subtract(const Duration(days: 90));
        q = q.gte('appointment_date', DateFormat('yyyy-MM-dd').format(from));
      }

      final rows = await q
          .order('appointment_date', ascending: true)
          .order('start_time', ascending: true)
          .limit(300);
      if (!mounted) return;

      // which of these bookings already have a review
      Set<int> reviewed = {};
      final ids = [for (final r in rows) r['id'] as int];
      if (ids.isNotEmpty) {
        try {
          final rv = await supabase
              .from('reviews')
              .select('appointment_id')
              .inFilter('appointment_id', ids);
          reviewed = {for (final x in rv) x['appointment_id'] as int};
        } catch (_) {}
      }

      final list = <Appt>[];
      for (final b in rows) {
        final salon = b['salons'] as Map?;
        final barber = b['barber_profile'] as Map?;
        final date = _parseDate(b['appointment_date']);
        final salonTz = (salon?['timezone'] as String?) ?? _kDefaultSalonTimezone;

        double servicesTotal = 0, totalDiscount = 0;
        int totalDuration = 0;
        final services = <Map<String, dynamic>>[];
        for (final s in (b['appointment_services'] as List?) ?? const []) {
          final orig = (s['original_price'] as num?)?.toDouble() ?? 0.0;
          final disc = (s['discount_amount'] as num?)?.toDouble() ?? 0.0;
          final dur = (s['duration'] as num?)?.toInt() ?? 30;
          servicesTotal += orig;
          totalDiscount += disc;
          totalDuration += dur;
          services.add({
            'id': s['id'],
            'service_id': s['service_id'],
            'service_name': s['service_name'] ?? 'Service',
            'variant_id': s['variant_id'],
            'variant_label': s['variant_label'],
            'duration': dur,
            'original_price': orig,
            'discount_amount': disc,
            'final_price': (s['final_price'] as num?)?.toDouble() ?? 0.0,
          });
        }

        final extra = (b['extra_charge'] as num?)?.toDouble() ?? 0.0;
        final price = (b['price'] as num?)?.toDouble() ??
            (servicesTotal - totalDiscount + extra);

        final utcStart = b['start_time'] as String? ?? '';
        final utcEnd = b['end_time'] as String? ?? '';
        final ls = _fmtTime(utcStart, date, salonTz);
        final le = _fmtTime(utcEnd, date, salonTz);

        String userTime = '';
        if (_userTimezone.isNotEmpty && _userTimezone != salonTz) {
          final us = _fmtTime(utcStart, date, _userTimezone);
          final ue = _fmtTime(utcEnd, date, _userTimezone);
          if (us.isNotEmpty && ue.isNotEmpty) userTime = '$us - $ue';
        }

        final isVip = b['is_vip'] == true;
        String queue = '';
        if (isVip) {
          final n = b['vip_queue_number'] ?? b['queue_number'];
          if (n != null) queue = 'VIP-$n';
        } else {
          final n = b['regular_queue_number'] ?? b['queue_number'];
          if (n != null) queue = 'Q$n';
        }

        final code = (salon?['currency_code'] as String?) ??
            (b['currency_code'] as String?) ??
            _kDefaultCurrency;

        list.add({
          ...b,
          'salon_name': salon?['name'] ?? 'Salon',
          'salon_address': salon?['address'],
          'timezone': salonTz,
          'currency_code': code,
          'symbol': _currencySymbol(code),
          'exchange_rate_at_booking':
              (b['exchange_rate_at_booking'] as num?)?.toDouble(),
          'barber_name': barber?['full_name'] ?? 'Barber',
          'customer_name': _customerName,
          'services': services,
          'service_name': services.isEmpty
              ? 'No services'
              : services.length == 1
                  ? '${services.first['service_name']}'
                  : '${services.first['service_name']} +${services.length - 1} more',
          'services_total': servicesTotal,
          'total_discount': totalDiscount,
          'extra_charge': extra,
          'extra_charge_note': b['extra_charge_note'],
          'price': price,
          'paid_amount': (b['paid_amount'] as num?)?.toDouble() ?? 0.0,
          'payment_status': b['payment_status'] ?? 'unpaid',
          'duration': totalDuration > 0 ? totalDuration : 30,
          'display_queue_number': queue,
          'is_vip': isVip,
          'local_start_time': ls,
          'local_end_time': le,
          'user_time': userTime,
          'display_date': DateFormat('MMM dd, yyyy').format(date),
          'has_review': reviewed.contains(b['id']),
        });
      }

      if (!mounted) return;
      setState(() {
        _all = list;
        _counts = ApptCounts.from(list);
        _error = null;
      });
    } catch (e) {
      debugPrint('❌ Error loading bookings: $e');
      if (mounted) setState(() => _error = 'Failed to load bookings: $e');
    }
  }

  /// bookings for one tab (pending: soonest first, others: newest first)
  List<Appt> _bookingsFor(int tab) {
    final l = filterAppts(_all, tab);
    int cmp(Appt a, Appt b) {
      final c = '${a['appointment_date']} ${a['start_time']}'
          .compareTo('${b['appointment_date']} ${b['start_time']}');
      return tab == 0 ? c : -c;
    }

    l.sort(cmp);
    return l;
  }

  // ============================================================
  // OVERFLOW NOTIFICATIONS
  // ============================================================
  Future<void> _loadOverflowNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final result = await supabase
          .from('overflow_notifications')
          .select('''
            id, excess_minutes, estimated_end, salon_close, notified_at, status,
            appointments!inner (
              id, booking_number, appointment_date, start_time, end_time, status,
              barber_id, salon_id, is_vip, vip_queue_number, regular_queue_number,
              queue_number, queue_position, child_name, travel_time_minutes,
              currency_code,
              salons!inner ( id, name, address, currency_code, currency_symbol, timezone ),
              barber_profile:profiles!appointments_barber_id_fkey ( id, full_name ),
              appointment_services ( id, service_name )
            )
          ''')
          .eq('customer_id', user.id)
          .eq('status', 'PENDING')
          .order('notified_at', ascending: false);
      if (!mounted) return;

      final out = <Appt>[];
      for (final n in result) {
        final apt = n['appointments'] as Map?;
        if (apt == null) continue;
        final salon = apt['salons'] as Map?;
        final barber = apt['barber_profile'] as Map?;
        final date = _parseDate(apt['appointment_date']);
        final tz = (salon?['timezone'] as String?) ?? _kDefaultSalonTimezone;

        final names = [
          for (final s in (apt['appointment_services'] as List?) ?? const [])
            '${s['service_name']}'
        ];
        final isVip = apt['is_vip'] == true;
        final qn = isVip
            ? (apt['vip_queue_number'] ?? apt['queue_number'])
            : (apt['regular_queue_number'] ?? apt['queue_number']);

        out.add({
          '_overflow': true,
          'id': n['id'],
          'excess_minutes': n['excess_minutes'],
          'estimated_end_local':
              _fmtTime(n['estimated_end'] as String?, date, tz),
          'salon_close_local': _fmtTime(n['salon_close'] as String?, date, tz),
          'appointment': {
            'id': apt['id'],
            'appointment_date': apt['appointment_date'],
            'start_time': _fmtTime(apt['start_time'] as String?, date, tz),
            'end_time': _fmtTime(apt['end_time'] as String?, date, tz),
            'display_queue_number': qn == null ? '' : (isVip ? 'VIP-$qn' : 'Q$qn'),
            'is_vip': isVip,
            'salon_name': salon?['name'] ?? 'Salon',
            'service_name': names.isEmpty
                ? 'Service'
                : names.length == 1
                    ? names.first
                    : '${names.first} +${names.length - 1} more',
            'barber_name': barber?['full_name'] ?? 'Barber',
          },
        });
      }
      if (mounted) setState(() => _overflow = out);
    } catch (e) {
      debugPrint('❌ Error loading overflow notifications: $e');
      if (mounted) setState(() => _overflow = []);
    }
  }

  Future<void> _respondToOverflow(int id, String response) async {
    if (!mounted) return;
    setState(() => _isProcessingOverflow = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final result = await supabase.rpc('handle_overflow_response', params: {
        'p_notification_id': id,
        'p_customer_id': user.id,
        'p_response': response,
      });
      if (!mounted) return;
      if (result['success'] == true) {
        _snack(result['message'] ?? 'Success',
            response == 'MOVE' ? Colors.green : Colors.orange);
        await _loadData();
      } else {
        _snack(result['message'] ?? 'Failed', Colors.red);
      }
    } catch (e) {
      _snack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessingOverflow = false);
    }
  }

  void _snack(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showOverflowDecisionDialog(Appt n) {
    final dark = context.isDarkMode;
    final apt = n['appointment'] as Map;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Appointment Overflow',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: dark ? Colors.white : Colors.black87)),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: dark ? 0.1 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '⚠️ Delay of ${n['excess_minutes']} minutes detected.\n'
                    'Your appointment on ${apt['appointment_date']} at ${apt['start_time']} may finish after closing time.\n'
                    'Estimated end: ${n['estimated_end_local']} | Salon closes: ${n['salon_close_local']}',
                    style: TextStyle(
                        color: dark ? Colors.orange.shade300 : Colors.orange.shade800),
                  ),
                ),
                const SizedBox(height: 14),
                _choiceTile(Icons.calendar_today, 'Move to next day',
                    'Reschedule your appointment to tomorrow', Colors.green, dark),
                const SizedBox(height: 8),
                _choiceTile(Icons.cancel, 'Cancel appointment',
                    'Cancel this appointment (no charges)', Colors.red, dark),
                const SizedBox(height: 12),
                Text(
                  '⚠️ If there is no response within 30 minutes, the appointment is auto-cancelled.',
                  style: TextStyle(
                      fontSize: 12,
                      color: dark ? Colors.orange.shade300 : Colors.orange.shade700),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('DECIDE LATER')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _showMoveCancelOptions(n['id'] as int);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('PROCEED'),
          ),
        ],
      ),
    );
  }

  Widget _choiceTile(
      IconData icon, String title, String sub, Color color, bool dark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.1 : 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(sub, style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveCancelOptions(int id) async {
    final dark = context.isDarkMode;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Choose action',
            style: TextStyle(color: dark ? Colors.white : Colors.black87)),
        content: Text('What would you like to do?',
            style: TextStyle(color: dark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'CANCEL'),
            child: const Text('CANCEL BOOKING', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'MOVE'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('MOVE TO NEXT DAY'),
          ),
        ],
      ),
    );
    if (r != null) await _respondToOverflow(id, r);
  }

  // ============================================================
  // CANCEL BOOKING
  // ============================================================
  Future<void> _cancelBooking(Appt b) async {
    final dark = context.isDarkMode;
    final id = b['id'] as int;
    final hasOverflow = _overflow.any((n) => (n['appointment'] as Map)['id'] == id);

    final cur = b['currency_code'] as String?;
    final total = (b['price'] as num?)?.toDouble() ?? 0.0;
    final userAmt = _convertToUser(
        salonPrice: total,
        salonCurrency: cur,
        exchangeRate: b['exchange_rate_at_booking']);
    final pay = b['payment_status'] as String? ?? 'unpaid';
    final wasPaid = pay == 'paid' || pay == 'partial';
    final paidAmt = (b['paid_amount'] as num?)?.toDouble() ?? 0.0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Cancel booking?',
                  style: TextStyle(color: dark ? Colors.white : Colors.black87)),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Are you sure you want to cancel this booking?',
                    style: TextStyle(
                        fontSize: 15, color: dark ? Colors.white70 : Colors.grey[800])),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dlgRow(Icons.store, '${b['salon_name']}', dark),
                      _dlgRow(Icons.calendar_today, '${b['display_date']}', dark),
                      _dlgRow(Icons.access_time,
                          '${b['local_start_time']} - ${b['local_end_time']}', dark),
                      if (total > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.payments_outlined,
                                  size: 16, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_formatSalonPrice(total, cur),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: dark ? Colors.white : Colors.black87)),
                                  if (userAmt != null)
                                    Text('≈ ${_formatUserPrice(userAmt)}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: dark
                                                ? Colors.blue[300]
                                                : Colors.blue[700])),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if ('${b['display_queue_number']}'.isNotEmpty)
                        _dlgRow(Icons.format_list_numbered,
                            'Queue: ${b['display_queue_number']}', dark),
                    ],
                  ),
                ),
                if (wasPaid)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'You already paid ${_formatSalonPrice(paidAmt, cur)}. The booking will be marked REFUNDED and the salon will give your money back.',
                        style: TextStyle(
                            fontSize: 12,
                            color: dark ? Colors.orange.shade300 : Colors.orange.shade800),
                      ),
                    ),
                  ),
                if (hasOverflow)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('⚠️ Cancelling now will resolve the overflow notice.',
                        style: TextStyle(
                            fontSize: 12,
                            color: dark ? Colors.orange.shade300 : Colors.orange.shade700)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('KEEP BOOKING')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    setState(() => _cancellingIds.add(id));

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final r = await supabase.rpc('cancel_booking_and_reorder', params: {
        'p_appointment_id': id,
        'p_cancelled_by': user.id,
        'p_cancel_reason': 'Cancelled by customer',
        'p_role': 'customer',
      });
      if (!mounted) return;
      if (r['success'] == true) {
        _snack(
            wasPaid
                ? 'Booking cancelled. The salon will refund your payment.'
                : 'Booking cancelled successfully',
            const Color(0xFF4CAF50));
        await _loadData();
      } else {
        throw Exception(r['message'] ?? 'Cancellation failed');
      }
    } catch (e) {
      _snack('Failed to cancel: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(id));
    }
  }

  Widget _dlgRow(IconData i, String t, bool dark) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(i, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t,
                  style: TextStyle(color: dark ? Colors.white : Colors.black87)),
            ),
          ],
        ),
      );

  // ============================================================
  // REVIEW / REBOOK
  // ============================================================
  Future<void> _showLeaveReviewDialog(Appt b) async {
    final r = await showDialog<(int, String)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReviewDialog(booking: b, isDark: context.isDarkMode),
    );
    if (r == null || !mounted) return;
    await _submitReview(bookingId: b['id'] as int, rating: r.$1, review: r.$2);
  }

  void _rebookBooking(Appt b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(
          initialSalon: {'id': b['salon_id'], 'name': b['salon_name']},
        ),
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

      final apt = await supabase
          .from('appointments')
          .select('barber_id, salon_id')
          .eq('id', bookingId)
          .single();
      if (!mounted) return;

      final barberId = apt['barber_id'] as String?;
      if (barberId == null) {
        _snack('Cannot review: barber no longer available', Colors.orange);
        return;
      }

      final existing = await supabase
          .from('reviews')
          .select('id')
          .eq('appointment_id', bookingId)
          .maybeSingle();
      if (!mounted) return;
      if (existing != null) {
        _snack('You already reviewed this appointment', Colors.orange);
        return;
      }

      await supabase.from('reviews').insert({
        'appointment_id': bookingId,
        'customer_id': user.id,
        'barber_id': barberId,
        'salon_id': apt['salon_id'],
        'overall_rating': rating,
        'comment': review,
      });

      _snack('Thank you for your review!', Colors.green);
      await _loadData();
    } catch (e) {
      _snack('Failed to submit review: $e', Colors.red);
    }
  }

  // ============================================================
  // STATUS / CHIPS / PAYMENT INFO
  // ============================================================
  ({String text, Color color, IconData icon}) _statusInfo(String s, String pay) {
    switch (s) {
      case 'confirmed':
        return (text: 'Confirmed', color: Colors.green, icon: Icons.check_circle_outline);
      case 'pending':
        return (text: 'Pending', color: Colors.orange, icon: Icons.pending_outlined);
      case 'in_progress':
        return (text: 'In Progress', color: Colors.blue, icon: Icons.play_circle_outline);
      case 'completed':
        return pay == 'paid'
            ? (text: 'Completed', color: Colors.purple, icon: Icons.check_circle)
            : (text: 'Pending Payment', color: Colors.orange, icon: Icons.payments_outlined);
      case 'cancelled':
        return (text: 'Cancelled', color: Colors.red, icon: Icons.cancel_outlined);
      case 'no_show':
        return (text: 'No Show', color: Colors.red, icon: Icons.person_off);
      default:
        return (text: s, color: Colors.grey, icon: Icons.circle_outlined);
    }
  }

  Widget? _paymentChip(Appt b) {
    final s = b['status'] as String? ?? '';
    final p = b['payment_status'] as String? ?? 'unpaid';
    if (p == 'paid') return ApptChip('PAID', Colors.green.shade700, icon: Icons.check_circle);
    if (p == 'partial') return ApptChip('PARTIAL', Colors.orange.shade800, icon: Icons.timelapse);
    if (p == 'refunded') return ApptChip('REFUND', Colors.red.shade600, icon: Icons.undo);
    if (_isLiveStatus(s)) return ApptChip('UNPAID', Colors.grey.shade600, icon: Icons.schedule);
    return null;
  }

  Widget _paymentInfo(Appt b, String symbol) {
    final status = b['status'] as String? ?? '';
    final pay = b['payment_status'] as String? ?? 'unpaid';
    final total = (b['price'] as num?)?.toDouble() ?? 0.0;
    final paid = (b['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final note = (b['payment_note'] as String?) ?? '';
    String money(double v) => '$symbol${v.toStringAsFixed(2)}';

    Widget row(String l, String v, Color c, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontSize: 12,
                        color: c,
                        fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
              ),
              Text(v,
                  style: TextStyle(
                      fontSize: 12,
                      color: c,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
            ],
          ),
        );

    Widget hint(String t) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(t,
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.orange.shade700)),
        );

    if (pay == 'partial') {
      return Column(children: [
        row('Paid', money(paid), Colors.green.shade700),
        row('Balance due', money(total - paid), Colors.orange.shade800, bold: true),
      ]);
    }
    if (pay == 'refunded') {
      return row('Refund from salon', money(paid), Colors.red.shade600, bold: true);
    }
    if (pay == 'paid' && note.contains('Overpaid')) return hint(note);
    if (status == 'completed' && pay == 'unpaid') {
      return hint('Pay at the salon to earn your loyalty points.');
    }
    return const SizedBox.shrink();
  }

  // ============================================================
  // BOOKING CARD
  // ============================================================
  Widget _buildBookingCard(Appt b, bool isPendingTab) {
    final dark = context.isDarkMode;
    final status = b['status'] as String? ?? 'pending';
    final pay = b['payment_status'] as String? ?? 'unpaid';
    final isVip = b['is_vip'] == true;
    final cur = b['currency_code'] as String?;
    final rate = b['exchange_rate_at_booking'];
    final symbol = (b['symbol'] as String?) ?? _currencySymbol(cur);

    final services = List<Appt>.from(b['services'] ?? const []);
    final duration = b['duration'] ?? 0;
    final total = (b['price'] as num?)?.toDouble() ?? 0.0;
    final extra = (b['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final discount = (b['total_discount'] as num?)?.toDouble() ?? 0.0;
    final userTotal =
        _convertToUser(salonPrice: total, salonCurrency: cur, exchangeRate: rate);

    final queue = '${b['display_queue_number'] ?? ''}';
    final token = '${b['queue_token'] ?? ''}';
    final labelColor = isVip ? _vipColor : _regularColor;
    final userTime = '${b['user_time'] ?? ''}';

    final accent = (status == 'cancelled' || status == 'no_show')
        ? Colors.red
        : isVip
            ? Colors.amber.shade600
            : (status == 'completed' && pay != 'paid')
                ? Colors.orange
                : (status == 'completed')
                    ? Colors.purple
                    : Colors.blue.shade400;

    final si = _statusInfo(status, pay);
    final payChip = _paymentChip(b);

    final showCancel = isPendingTab && (status == 'pending' || status == 'confirmed');
    final showReview = status == 'completed' && b['has_review'] != true;
    final showRebook = status == 'completed';
    final canBill = pay == 'paid' && _isLiveStatus(status);

    final fg = dark ? Colors.white : Colors.black87;
    final mu = dark ? Colors.white60 : Colors.grey.shade600;
    final id = b['id'] as int;
    final cancelling = _cancellingIds.contains(id);

    return Card(
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 5, color: accent),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CHIPS
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (queue.isNotEmpty)
                      ApptChip(queue, labelColor,
                          icon: isVip ? Icons.star : Icons.confirmation_number),
                    ApptChip(isVip ? 'VIP' : 'REGULAR', labelColor),
                    ApptChip(si.text, si.color, icon: si.icon),
                    ?payChip,
                    if (token.isNotEmpty)
                      ApptChip(token, labelColor, icon: Icons.confirmation_number_outlined),
                  ],
                ),
                const SizedBox(height: 12),

                // SALON
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: labelColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(isVip ? Icons.star : Icons.store,
                          color: labelColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${b['salon_name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold, color: fg)),
                          if ('${b['salon_address'] ?? ''}'.isNotEmpty)
                            Text('${b['salon_address']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: mu)),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 12, color: mu),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text('Barber: ${b['barber_name']}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: mu)),
                                ),
                              ],
                            ),
                          ),
                          if ('${b['child_name'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.child_care, size: 12, color: labelColor),
                                  const SizedBox(width: 4),
                                  Text('For: ${b['child_name']}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: labelColor)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // DATE + TIME
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: mu),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              DateFormat('EEE, MMM dd')
                                  .format(_parseDate(b['appointment_date'])),
                              style: TextStyle(fontSize: 12, color: fg),
                            ),
                          ),
                          Icon(Icons.access_time, size: 14, color: mu),
                          const SizedBox(width: 4),
                          Text('${b['local_start_time']} - ${b['local_end_time']}',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                        ],
                      ),
                      if (userTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.public,
                                  size: 12,
                                  color: dark ? Colors.blue[300] : Colors.blue[700]),
                              const SizedBox(width: 4),
                              Text('Your time: $userTime',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: dark ? Colors.blue[300] : Colors.blue[700])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // SERVICES
                Row(
                  children: [
                    Icon(Icons.content_cut, size: 13, color: labelColor),
                    const SizedBox(width: 5),
                    Text('Services (${services.length})',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: dark ? Colors.white70 : Colors.grey[700])),
                    const Spacer(),
                    if (duration > 0)
                      Text('$duration min', style: TextStyle(fontSize: 12, color: mu)),
                  ],
                ),
                const SizedBox(height: 6),
                if (services.isEmpty)
                  Text('No services', style: TextStyle(fontSize: 12, color: mu))
                else
                  for (final s in services)
                    _serviceLine(s, symbol, cur, rate, dark),

                const Divider(height: 18),
                if (discount > 0)
                  _smallMoney('Discount', '−$symbol${discount.toStringAsFixed(2)}',
                      Colors.green.shade700, Icons.local_offer),
                if (extra > 0)
                  _smallMoney(
                      '${b['extra_charge_note'] ?? ''}'.isNotEmpty
                          ? 'Extra (${b['extra_charge_note']})'
                          : 'Extra',
                      '+$symbol${extra.toStringAsFixed(2)}',
                      Colors.orange,
                      Icons.add_circle),
                Row(
                  children: [
                    Text('Total',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold, color: fg)),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$symbol${total.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isVip ? _vipColor : AppTheme.primary)),
                        if (userTotal != null)
                          Text('≈ ${_formatUserPrice(userTotal)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w500,
                                  color: dark ? Colors.blue[300] : Colors.blue[700])),
                      ],
                    ),
                  ],
                ),
                _paymentInfo(b, symbol),

                if ((b['travel_time_minutes'] as num? ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.directions_car, size: 12, color: mu),
                        const SizedBox(width: 4),
                        Text('Travel time: ${b['travel_time_minutes']} min',
                            style: TextStyle(fontSize: 11, color: mu)),
                      ],
                    ),
                  ),

                // ACTIONS
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (showCancel) ...[
                      Expanded(
                        child: _outBtn(
                          cancelling ? 'CANCELLING...' : 'CANCEL',
                          Icons.close_rounded,
                          Colors.red,
                          cancelling ? null : () => _cancelBooking(b),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (showReview) ...[
                      Expanded(
                        child: _outBtn('REVIEW', Icons.star_outline, Colors.amber.shade700,
                            () => _showLeaveReviewDialog(b)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (showRebook) ...[
                      Expanded(
                        child: _outBtn('BOOK AGAIN', Icons.refresh,
                            isVip ? _vipColor : AppTheme.primary, () => _rebookBooking(b)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!showCancel && !showReview && !showRebook) const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: dark ? Colors.grey[700]! : Colors.grey[300]!),
                      ),
                      child: IconButton(
                        tooltip: 'View details',
                        onPressed: () => _showBookingDetails(b),
                        icon: Icon(Icons.info_outline,
                            color: isVip ? _vipColor : AppTheme.primary, size: 22),
                      ),
                    ),
                  ],
                ),
                if (canBill) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () => ApptActions.bill(context, b),
                      icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      label: const Text('DOWNLOAD BILL',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _outBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _smallMoney(String l, String v, Color c, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
            Expanded(
              child: Text(l,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c)),
            ),
            Text(v,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c)),
          ],
        ),
      );

  Widget _serviceLine(Appt s, String symbol, String? cur, dynamic rate, bool dark) {
    final orig = (s['original_price'] as num?)?.toDouble() ?? 0;
    final disc = (s['discount_amount'] as num?)?.toDouble() ?? 0;
    final fin = (s['final_price'] as num?)?.toDouble() ?? 0;
    final has = disc > 0;
    final shown = has ? fin : orig;
    final variant = '${s['variant_label'] ?? ''}';
    final userAmt =
        _convertToUser(salonPrice: shown, salonCurrency: cur, exchangeRate: rate);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ${s['service_name'] ?? 'Service'}',
                    style: TextStyle(
                        fontSize: 12, color: dark ? Colors.white : Colors.black87)),
                if (variant.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(variant,
                        style: TextStyle(
                            fontSize: 10,
                            color: dark ? Colors.white70 : Colors.grey[500])),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  if (has)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text('$symbol${orig.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 10,
                              decoration: TextDecoration.lineThrough,
                              color: dark ? Colors.white60 : Colors.grey)),
                    ),
                  Text('$symbol${shown.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: has
                              ? Colors.green.shade700
                              : (dark ? Colors.white : Colors.black87))),
                ],
              ),
              if (userAmt != null)
                Text('≈ ${_formatUserPrice(userAmt)}',
                    style: TextStyle(
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                        color: dark ? Colors.blue[300] : Colors.blue[700])),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // OVERFLOW CARD
  // ============================================================
  Widget _buildOverflowCard(Appt n) {
    final dark = context.isDarkMode;
    final apt = n['appointment'] as Map;
    final isVip = apt['is_vip'] == true;
    final qc = isVip ? _vipColor : _regularColor;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      color: dark ? const Color(0xFF2A2A2A) : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            color: Colors.orange.withValues(alpha: dark ? 0.15 : 0.12),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠️ ACTION REQUIRED',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange)),
                      Text('${apt['salon_name']}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: dark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
                ApptChip('${n['excess_minutes']} min overflow', Colors.red),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${apt['appointment_date']}  •  ${apt['start_time']} - ${apt['end_time']}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: dark ? Colors.white : Colors.black87)),
                if ('${apt['display_queue_number']}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Queue: ${apt['display_queue_number']}',
                        style: TextStyle(fontWeight: FontWeight.w500, color: qc)),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Your appointment may be delayed by about ${n['excess_minutes']} minutes.\n'
                  'Estimated end: ${n['estimated_end_local']} | Salon closes: ${n['salon_close_local']}',
                  style: TextStyle(
                      fontSize: 12, color: dark ? Colors.white70 : Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessingOverflow
                        ? null
                        : () => _showOverflowDecisionDialog(n),
                    icon: _isProcessingOverflow
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle, size: 18),
                    label: const Text('RESPOND NOW'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange, width: 1.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '⚠️ If there is no response within 30 minutes, this appointment is auto-cancelled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: dark ? Colors.orange.shade300 : Colors.orange.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DETAILS SHEET
  // ============================================================
  void _showBookingDetails(Appt b) {
    final dark = context.isDarkMode;
    final isVip = b['is_vip'] == true;
    final color = isVip ? _vipColor : AppTheme.primary;
    final cur = b['currency_code'] as String?;
    final rate = b['exchange_rate_at_booking'];
    final symbol = (b['symbol'] as String?) ?? _currencySymbol(cur);

    final services = List<Appt>.from(b['services'] ?? const []);
    final subtotal = (b['services_total'] as num?)?.toDouble() ?? 0.0;
    final discount = (b['total_discount'] as num?)?.toDouble() ?? 0.0;
    final extra = (b['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final total = (b['price'] as num?)?.toDouble() ?? 0.0;
    final userTotal =
        _convertToUser(salonPrice: total, salonCurrency: cur, exchangeRate: rate);

    final status = b['status'] as String? ?? 'pending';
    final pay = b['payment_status'] as String? ?? 'unpaid';
    final si = _statusInfo(status, pay);
    final payChip = _paymentChip(b);
    final canBill = pay == 'paid' && _isLiveStatus(status);
    final userTime = '${b['user_time'] ?? ''}';

    showModalBottomSheet(
      context: context,
      backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.receipt_long, color: color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Booking ${b['booking_number'] ?? 'N/A'}',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: dark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ApptChip(si.text, si.color, icon: si.icon),
                            ?payChip,
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${b['display_date']} • ${b['local_start_time']} - ${b['local_end_time']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: dark ? Colors.white60 : Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _detailRow('Salon', '${b['salon_name']}'),
              _detailRow('Address', '${b['salon_address'] ?? 'N/A'}'),
              _detailRow('Barber', '${b['barber_name']}'),
              if (userTime.isNotEmpty) _detailRow('Your time', userTime),

              if (services.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Services (${services.length})',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: dark ? Colors.white : Colors.black87)),
                const SizedBox(height: 8),
                for (final s in services)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${s['service_name'] ?? 'Service'}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: dark ? Colors.white : Colors.black87)),
                              if ('${s['variant_label'] ?? ''}'.isNotEmpty)
                                Text('${s['variant_label']}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w500)),
                              Text('${s['duration'] ?? 30} min',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: dark ? Colors.white60 : Colors.grey[600])),
                            ],
                          ),
                        ),
                        _serviceLine({...s, 'service_name': '', 'variant_label': ''},
                            symbol, cur, rate, dark),
                      ],
                    ),
                  ),
              ],

              const Divider(height: 24),
              if (subtotal > 0)
                _priceRow('Services subtotal', '$symbol${subtotal.toStringAsFixed(2)}', dark),
              if (discount > 0)
                _priceRow('Discount', '−$symbol${discount.toStringAsFixed(2)}', dark,
                    color: Colors.green.shade700),
              if (extra > 0)
                _priceRow('Extra charge', '+$symbol${extra.toStringAsFixed(2)}', dark,
                    color: Colors.orange),
              _priceRow('Total', '$symbol${total.toStringAsFixed(2)}', dark,
                  bold: true, color: color),
              if (userTotal != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('≈ ${_formatUserPrice(userTotal)} in $_userCurrencyCode',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: dark ? Colors.blue[300] : Colors.blue[700])),
                  ),
                ),
              _paymentInfo(b, symbol),
              const Divider(height: 24),

              _detailRow('Duration', '${b['duration'] ?? 30} minutes'),
              if ('${b['child_name'] ?? ''}'.isNotEmpty)
                _detailRow('Booked for', '${b['child_name']}'),
              if ('${b['display_queue_number'] ?? ''}'.isNotEmpty)
                _detailRow('Queue number', '${b['display_queue_number']}'),
              if (b['queue_position'] != null)
                _detailRow('Queue position', '#${b['queue_position']}'),
              if ('${b['queue_token'] ?? ''}'.isNotEmpty)
                _detailRow('Queue token', '${b['queue_token']}'),
              if (isVip) _detailRow('Booking type', 'VIP'),
              if ((b['travel_time_minutes'] as num? ?? 0) > 0)
                _detailRow('Travel time', '${b['travel_time_minutes']} minutes'),

              const SizedBox(height: 16),
              if (canBill) ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      ApptActions.bill(context, b);
                    },
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('DOWNLOAD BILL'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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

  Widget _detailRow(String label, String value) {
    final dark = context.isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 14, color: dark ? Colors.white60 : Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: dark ? Colors.white : Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String l, String v, bool dark, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color ?? (dark ? Colors.white70 : Colors.grey[700]))),
          Text(v,
              style: TextStyle(
                  fontSize: bold ? 16 : 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: color ?? (dark ? Colors.white : Colors.black87))),
        ],
      ),
    );
  }

  // ============================================================
  // DATE / VIEW MODE
  // ============================================================
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _byDate = true;
      });
      await _loadData();
    }
  }

  void _shiftDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadData();
  }

  void _setMode(bool byDate) {
    if (_byDate == byDate) return;
    setState(() => _byDate = byDate);
    _loadData();
  }

  Widget _viewBar() {
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.list_alt, size: 16),
                        label: Text('All bookings')),
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.calendar_today, size: 16),
                        label: Text('By date')),
                  ],
                  selected: {_byDate},
                  onSelectionChanged: (s) => _setMode(s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_byDate)
            Row(
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
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_calendar, size: 18, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(_selectedDateDisplay,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: dark ? Colors.white : Colors.black87)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftDate(1),
                ),
              ],
            )
          else
            Text(
              'Your bookings from the last 90 days and all upcoming ones',
              style: TextStyle(
                  fontSize: 12, color: dark ? Colors.white60 : Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    final dark = context.isDarkMode;
    Tab t(IconData i, String s) => Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(i, size: 16), const SizedBox(width: 6), Text(s)],
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppTheme.primary,
        unselectedLabelColor: dark ? Colors.white60 : Colors.grey[600],
        indicatorColor: AppTheme.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
        tabs: [
          t(Icons.pending_actions, 'Pending (${_counts.pending})'),
          t(Icons.payments_outlined, 'Pending Payment (${_counts.pendingPay})'),
          t(Icons.check_circle_outline, 'Complete (${_counts.completed})'),
          t(Icons.cancel_outlined, 'Cancel (${_counts.cancelled})'),
        ],
      ),
    );
  }

  Widget _tabPage(int tab) {
    final dark = context.isDarkMode;
    final items = <Appt>[
      if (tab == 0) ..._overflow,
      ..._bookingsFor(tab),
    ];
    const empty = [
      'No pending bookings',
      'No pending payments',
      'No completed bookings',
      'No cancelled bookings',
    ];
    return ApptList(
      items: items,
      isDark: dark,
      onRefresh: _loadData,
      emptyText: empty[tab],
      emptySub: _byDate ? 'for $_selectedDateDisplay' : 'in the last 90 days & upcoming',
      cardBuilder: (a) => a['_overflow'] == true
          ? _buildOverflowCard(a)
          : _buildBookingCard(a, tab == 0),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final isWeb = MediaQuery.sizeOf(context).width > 800;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('My Bookings',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primary,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? ApptMessageView(
                  icon: Icons.error_outline,
                  message: _error!,
                  isDark: dark,
                  buttonText: 'TRY AGAIN',
                  onPressed: _loadData,
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              isWeb ? 20 : 12, 12, isWeb ? 20 : 12, 0),
                          child: Column(
                            children: [
                              _viewBar(),
                              const SizedBox(height: 10),
                              ApptStatsRow(
                                counts: _counts,
                                isDark: dark,
                                onTap: (i) => _tabController.animateTo(i),
                              ),
                              const SizedBox(height: 10),
                              _tabBar(),
                              const SizedBox(height: 6),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [for (var i = 0; i < 4; i++) _tabPage(i)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

// =====================================================================
// REVIEW DIALOG (own State: the text controller is disposed safely)
// =====================================================================
class _ReviewDialog extends StatefulWidget {
  final Map<String, dynamic> booking;
  final bool isDark;
  const _ReviewDialog({required this.booking, required this.isDark});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 0;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.isDark;
    final b = widget.booking;
    final fg = d ? Colors.white : Colors.black87;
    final mu = d ? Colors.white60 : Colors.grey.shade600;

    return AlertDialog(
      backgroundColor: d ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.star_rate_rounded, color: Colors.amber, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Leave a review',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fg)),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: d ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${b['salon_name']}',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: fg)),
                    const SizedBox(height: 4),
                    Text('Barber: ${b['barber_name']}',
                        style: TextStyle(fontSize: 13, color: mu)),
                    Text('Services: ${b['service_name']}',
                        style: TextStyle(fontSize: 13, color: mu)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Your rating',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 5; i++)
                    IconButton(
                      onPressed: () => setState(() => _rating = i + 1),
                      icon: Icon(
                        i < _rating ? Icons.star : Icons.star_border,
                        color: i < _rating
                            ? Colors.amber
                            : (d ? Colors.grey[600] : Colors.grey[400]),
                        size: 34,
                      ),
                    ),
                ],
              ),
              Center(
                child: Text(
                  _rating == 0 ? 'Tap to rate' : 'You rated: $_rating/5',
                  style: TextStyle(
                      fontSize: 13,
                      color: _rating == 0 ? mu : Colors.amber.shade700),
                ),
              ),
              const SizedBox(height: 16),
              Text('Your review (optional)',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                maxLines: 4,
                maxLength: 500,
                style: TextStyle(color: fg),
                decoration: InputDecoration(
                  hintText: 'Share your experience...',
                  hintStyle: TextStyle(color: mu),
                  filled: true,
                  fillColor: d ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _rating == 0
              ? null
              : () => Navigator.pop(context, (_rating, _ctrl.text.trim())),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
          child: const Text('SUBMIT REVIEW'),
        ),
      ],
    );
  }
}