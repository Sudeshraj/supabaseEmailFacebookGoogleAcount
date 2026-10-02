// Owner Dashboard - Appointments Screen

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/edit_appointment_services_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../extensions/context_extensions.dart';
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
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _filteredAppointments = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedSalonName = '';
  String _currencyCode = 'LKR';
  bool _isMarkingPaid = false;

  // ✅ Filter period state
  String _selectedPeriod = 'date'; // 'date' | 'month' | 'year'
  DateTime _selectedDate = DateTime.now();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // ✅ Tabs
  late TabController _tabController;

  int _totalCount = 0;
  int _completedCount = 0;
  int _pendingCount = 0;
  int _cancelledCount = 0;
  int _pendingPaymentCount = 0;

  // ✅ Search state (for barber search, still needed)
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _barberSuggestions = [];
  List<Map<String, dynamic>> _allBarbers = [];
  bool _isSearchingBarbers = false;
  bool _showSuggestions = false;
  Map<String, dynamic>? _selectedBarber;

  final ScrollController _scrollController = ScrollController();
  late bool _isWeb;
  late bool _isDark;

  static const _editableStatuses = {'pending', 'confirmed', 'in_progress'};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ CURRENCY SYMBOL
  // ============================================================
  String _currencySymbol(String? code) {
    switch (code) {
      case 'USD':
        return '\$';
      case 'INR':
        return '₹';
      case 'GBP':
        return '£';
      case 'EUR':
        return '€';
      case 'AUD':
        return 'A\$';
      case 'AED':
        return 'د.إ';
      case 'CAD':
        return 'C\$';
      case 'JPY':
        return '¥';
      case 'SGD':
        return 'S\$';
      case 'MYR':
        return 'RM';
      case 'LKR':
      default:
        return 'Rs.';
    }
  }

  // ============================================================
  // ✅ DATE RANGE HELPERS
  // ============================================================
  String get _dateRangeStart {
    if (_selectedPeriod == 'date') {
      return DateFormat('yyyy-MM-dd').format(_selectedDate);
    } else if (_selectedPeriod == 'month') {
      return '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-01';
    } else {
      return '$_selectedYear-01-01';
    }
  }

  String get _dateRangeEnd {
    if (_selectedPeriod == 'date') {
      return DateFormat('yyyy-MM-dd').format(_selectedDate);
    } else if (_selectedPeriod == 'month') {
      final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
      return '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    } else {
      return '$_selectedYear-12-31';
    }
  }

  String get _periodDisplayText {
    if (_selectedPeriod == 'date') {
      final today = DateTime.now();
      if (DateFormat('yyyy-MM-dd').format(_selectedDate) ==
          DateFormat('yyyy-MM-dd').format(today)) {
        return 'Today';
      }
      return DateFormat('MMM dd, yyyy').format(_selectedDate);
    } else if (_selectedPeriod == 'month') {
      return DateFormat(
        'MMMM yyyy',
      ).format(DateTime(_selectedYear, _selectedMonth));
    } else {
      return 'Year $_selectedYear';
    }
  }

  // ============================================================
  // ✅ LOAD DATA
  // ============================================================
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view appointments';
          _isLoading = false;
        });
        return;
      }

      if (widget.salonId != null) {
        final salonResponse = await supabase
            .from('salons')
            .select('name, currency_code')
            .eq('id', int.parse(widget.salonId!))
            .maybeSingle();

        if (salonResponse != null) {
          _selectedSalonName = salonResponse['name'] ?? 'Salon';
          _currencyCode = salonResponse['currency_code'] ?? 'LKR';
        }

        await _loadSalonBarbers();
      }

      await _loadAppointments();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading appointments: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // ✅ LOAD BARBERS
  // ============================================================
  Future<void> _loadSalonBarbers() async {
    if (widget.salonId == null) return;

    try {
      final salonIdInt = int.parse(widget.salonId!);

      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', salonIdInt)
          .eq('status', 'active');

      final barberIds = (salonBarbersResponse as List)
          .map((item) => item['barber_id'] as String)
          .where((id) => id.isNotEmpty)
          .toList();

      if (barberIds.isEmpty) {
        if (mounted) setState(() => _allBarbers = []);
        return;
      }

      final profilesResponse = await supabase
          .from('profiles')
          .select('id, full_name, email, phone, avatar_url')
          .inFilter('id', barberIds)
          .eq('is_active', true)
          .eq('is_blocked', false);

      final List<Map<String, dynamic>> barbers = [];
      for (var profile in profilesResponse) {
        barbers.add({
          'id': profile['id'],
          'full_name': profile['full_name'] ?? 'Unknown Barber',
          'email': profile['email'] ?? '',
          'phone': profile['phone'] ?? '',
          'avatar_url': profile['avatar_url'],
        });
      }

      barbers.sort(
        (a, b) => (a['full_name'] as String).toLowerCase().compareTo(
          (b['full_name'] as String).toLowerCase(),
        ),
      );

      if (mounted) setState(() => _allBarbers = barbers);
    } catch (e) {
      debugPrint('Error loading barbers: $e');
      if (mounted) setState(() => _allBarbers = []);
    }
  }

  // ============================================================
  // ✅ BARBER SEARCH
  // ============================================================
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _filterBarbers(query);
    });
  }

  void _filterBarbers(String query) {
    final trimmed = query.trim().toLowerCase();

    if (trimmed.isEmpty) {
      setState(() {
        _barberSuggestions = [];
        _showSuggestions = false;
        _isSearchingBarbers = false;
      });
      return;
    }

    setState(() => _isSearchingBarbers = true);

    final filtered = _allBarbers.where((b) {
      final name = (b['full_name'] as String? ?? '').toLowerCase();
      final email = (b['email'] as String? ?? '').toLowerCase();
      return name.contains(trimmed) || email.contains(trimmed);
    }).toList();

    setState(() {
      _barberSuggestions = filtered;
      _showSuggestions = true;
      _isSearchingBarbers = false;
    });
  }

  void _selectBarber(Map<String, dynamic> barber) {
    setState(() {
      _selectedBarber = barber;
      _searchController.text = barber['full_name'] ?? '';
      _showSuggestions = false;
      _barberSuggestions = [];
    });
    _searchFocusNode.unfocus();
    _loadAppointments();
  }

  void _clearBarberSelection() {
    setState(() {
      _selectedBarber = null;
      _searchController.clear();
      _barberSuggestions = [];
      _showSuggestions = false;
    });
    _searchFocusNode.unfocus();
    _loadAppointments();
  }

  // ============================================================
  // ✅ LOAD APPOINTMENTS
  // ============================================================
  Future<void> _loadAppointments() async {
    try {
      final salonIdInt = widget.salonId != null
          ? int.parse(widget.salonId!)
          : null;

      var query = supabase.from('appointments').select('''
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
            payment_note,
            price,
            currency_code,
            original_price,
            discount_amount,
            extra_charge,
            extra_charge_note,
            offer_id,
            queue_number,
            regular_queue_number,
            vip_queue_number,
            queue_token,
            queue_position,
            is_vip,
            child_name,
            travel_time_minutes,
            created_at,
            notes,
            profiles!appointments_customer_id_fkey (
              id,
              full_name,
              email,
              phone,
              avatar_url
            ),
            barber_profiles:profiles!appointments_barber_id_fkey (
              id,
              full_name,
              avatar_url
            ),
            salons!inner (
              id,
              name,
              currency_code,
              currency_symbol
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
              added_by,
              added_at,
              offers (
                id,
                title,
                discount_type,
                discount_value
              )
            )
          ''');

      if (salonIdInt != null) {
        query = query.eq('salon_id', salonIdInt);
      }

      if (_selectedBarber != null) {
        query = query.eq('barber_id', _selectedBarber!['id']);
      }

      query = query
          .gte('appointment_date', _dateRangeStart)
          .lte('appointment_date', _dateRangeEnd);

      final response = await query
          .order('appointment_date', ascending: false)
          .order('start_time', ascending: false);

      final List<Map<String, dynamic>> appointments = [];
      int total = 0;
      int completed = 0;
      int pending = 0;
      int cancelled = 0;
      int pendingPayment = 0;

      for (var apt in response) {
        final customer = apt['profiles'] as Map?;
        final barber = apt['barber_profiles'] as Map?;
        final salon = apt['salons'] as Map?;

        final status = apt['status'] as String? ?? 'pending';
        final paymentStatus = apt['payment_status'] as String? ?? 'unpaid';
        final isVip = apt['is_vip'] as bool? ?? false;

        final apptServices = (apt['appointment_services'] as List?) ?? [];
        final List<Map<String, dynamic>> services = [];
        double servicesTotal = 0.0;
        double totalDiscount = 0.0;
        int totalDuration = 0;

        for (var svc in apptServices) {
          final offer = svc['offers'] as Map?;

          final originalPrice =
              (svc['original_price'] as num?)?.toDouble() ?? 0.0;
          final discount = (svc['discount_amount'] as num?)?.toDouble() ?? 0.0;
          final finalPrice = (svc['final_price'] as num?)?.toDouble() ?? 0.0;
          final duration = (svc['duration'] as num?)?.toInt() ?? 30;

          servicesTotal += originalPrice;
          totalDiscount += discount;
          totalDuration += duration;

          services.add({
            'appointment_service_id': svc['id'],
            'service_id': svc['service_id'],
            'service_name': svc['service_name'] ?? 'Service',
            'variant_id': svc['variant_id'],
            'variant_label': svc['variant_label'],
            'duration': duration,
            'original_price': originalPrice,
            'discount_amount': discount,
            'final_price': finalPrice,
            'offer_id': svc['offer_id'],
            'offer_title': offer?['title'],
            'offer_discount_type': offer?['discount_type'],
            'offer_discount_value': offer?['discount_value'],
            'added_by': svc['added_by'],
            'added_at': svc['added_at'],
          });
        }

        final extraCharge = (apt['extra_charge'] as num?)?.toDouble() ?? 0.0;
        final extraNote = apt['extra_charge_note'] as String?;
        final totalPrice = servicesTotal - totalDiscount + extraCharge;
        final currencyCode =
            (salon?['currency_code'] as String?) ?? _currencyCode;

        String serviceSummary;
        if (services.isEmpty) {
          serviceSummary = 'No services';
        } else if (services.length == 1) {
          serviceSummary = services.first['service_name'] as String;
        } else {
          serviceSummary =
              '${services.first['service_name']} +${services.length - 1} more';
        }

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

        appointments.add({
          'id': apt['id'],
          'booking_number': apt['booking_number'] ?? 'N/A',
          'customer_id': apt['customer_id'],
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_phone': customer?['phone'] ?? '',
          'customer_email': customer?['email'] ?? '',
          'customer_avatar': customer?['avatar_url'],
          'barber_id': apt['barber_id'],
          'barber_name': barber?['full_name'] ?? 'Unknown Barber',
          'barber_avatar': barber?['avatar_url'],
          'salon_id': apt['salon_id'],
          'salon_name': salon?['name'] ?? 'Unknown Salon',
          'currency_code': currencyCode,
          'currency_symbol': salon?['currency_symbol'],
          'services': services,
          'service_count': services.length,
          'service_name': serviceSummary,
          'duration': totalDuration,
          'services_total': servicesTotal,
          'total_discount': totalDiscount,
          'extra_charge': extraCharge,
          'extra_charge_note': extraNote,
          'offer_id': apt['offer_id'],
          'price': totalPrice,
          'original_price': apt['original_price'],
          'discount_amount': apt['discount_amount'],
          'appointment_date': apt['appointment_date'],
          'display_date': _formatDate(apt['appointment_date']),
          'start_time': apt['start_time'],
          'end_time': apt['end_time'],
          'status': status,
          'payment_status': paymentStatus,
          'payment_paid_at': apt['payment_paid_at'],
          'payment_note': apt['payment_note'],
          'is_vip': isVip,
          'queue_number': apt['queue_number'],
          'regular_queue_number': apt['regular_queue_number'],
          'vip_queue_number': apt['vip_queue_number'],
          'queue_position': apt['queue_position'],
          'queue_token': apt['queue_token'],
          'child_name': apt['child_name'],
          'travel_time_minutes': apt['travel_time_minutes'],
          'notes': apt['notes'],
          'created_at': apt['created_at'],
        });
      }

      if (mounted) {
        setState(() {
          _appointments = appointments;
          _totalCount = total;
          _completedCount = completed;
          _pendingCount = pending;
          _cancelledCount = cancelled;
          _pendingPaymentCount = pendingPayment;
          _applyStatusFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
      setState(() {
        _errorMessage = 'Error loading appointments: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // ✅ EDIT SERVICES
  // ============================================================
  Future<void> _openEditServices(Map<String, dynamic> apt) async {
    if (!mounted) return;

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditAppointmentServicesSheet(appointment: apt),
    );

    if (changed == true) {
      await _loadAppointments();
    }
  }

  // ============================================================
  // ✅ MARK AS PAID
  // ============================================================
  Future<void> _markAsPaid(Map<String, dynamic> apt) async {
    if (_isMarkingPaid) return;

    final symbol = _currencySymbol(apt['currency_code'] as String?);
    final total = (apt['price'] as num?)?.toDouble() ?? 0.0;
    final customerName = apt['customer_name'] as String? ?? 'Customer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.payments, color: Colors.green.shade600, size: 26),
            const SizedBox(width: 10),
            Text(
              'Confirm Payment',
              style: TextStyle(
                color: _isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark this appointment as PAID?',
              style: TextStyle(
                color: _isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          customerName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 14,
                        color: _isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Booking: ${apt['booking_number']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '$symbol${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('MARK AS PAID'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMarkingPaid = true);

    try {
      final result = await supabase.rpc(
        'mark_appointment_payment',
        params: {
          'p_appointment_id': apt['id'],
          'p_payment_status': 'paid',
          'p_note': null,
        },
      );

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment of $symbol${total.toStringAsFixed(2)} recorded',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadAppointments();
        }
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
      if (mounted) setState(() => _isMarkingPaid = false);
    }
  }

  // ============================================================
  // ✅ APPLY STATUS TAB FILTER
  // ============================================================
  void _applyStatusFilter() {
    switch (_tabController.index) {
      case 0:
        _filteredAppointments = _appointments.where((a) {
          final s = a['status'] as String;
          return s == 'pending' || s == 'confirmed' || s == 'in_progress';
        }).toList();
        break;
      case 1:
        _filteredAppointments = _appointments.where((a) {
          return a['status'] == 'completed' &&
              (a['payment_status'] as String? ?? 'unpaid') != 'paid';
        }).toList();
        break;
      case 2:
        _filteredAppointments = _appointments.where((a) {
          return a['status'] == 'completed' &&
              (a['payment_status'] as String? ?? 'unpaid') == 'paid';
        }).toList();
        break;
      case 3:
        _filteredAppointments = _appointments.where((a) {
          final s = a['status'] as String;
          return s == 'cancelled' || s == 'no_show';
        }).toList();
        break;
      case 4:
      default:
        _filteredAppointments = List.from(_appointments);
        break;
    }
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() => _applyStatusFilter());
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      if (date.isAtSameMomentAs(today)) {
        return 'Today';
      } else if (date.isAtSameMomentAs(tomorrow)) {
        return 'Tomorrow';
      } else {
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'confirmed':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'no_show':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'confirmed':
        return 'Confirmed';
      case 'in_progress':
        return 'In Progress';
      case 'pending':
        return 'Pending';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No Show';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.hourglass_top;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'no_show':
        return Icons.person_off;
      default:
        return Icons.info;
    }
  }

  // ============================================================
  // ✅ DATE PICKER
  // ============================================================
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: _isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF1E1E1E),
                    onSurface: Colors.white,
                  ), dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF1E1E1E)),
                )
              : ThemeData.light().copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedPeriod = 'date';
      });
      _loadAppointments();
    }
  }

  // ============================================================
  // ✅ MONTH PICKER
  // ============================================================
  Future<void> _pickMonth() async {
    int tempYear = _selectedYear;
    int tempMonth = _selectedMonth;

    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(Icons.calendar_month, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Select Month',
                    style: TextStyle(
                      color: _isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => setDialogState(() => tempYear--),
                            icon: Icon(
                              Icons.chevron_left,
                              color: _isDark
                                  ? Colors.white70
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            '$tempYear',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setDialogState(() => tempYear++),
                            icon: Icon(
                              Icons.chevron_right,
                              color: _isDark
                                  ? Colors.white70
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (index) {
                        final month = index + 1;
                        final isSelected = month == tempMonth;
                        return SizedBox(
                          width: 90,
                          height: 44,
                          child: Material(
                            color: isSelected
                                ? AppTheme.primary
                                : (_isDark
                                      ? const Color(0xFF2A2A2A)
                                      : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () =>
                                  setDialogState(() => tempMonth = month),
                              borderRadius: BorderRadius.circular(10),
                              child: Center(
                                child: Text(
                                  DateFormat(
                                    'MMM',
                                  ).format(DateTime(2024, month, 1)),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : (_isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      color: _isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, tempYear * 100 + tempMonth),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedYear = picked ~/ 100;
        _selectedMonth = picked % 100;
        _selectedPeriod = 'month';
      });
      _loadAppointments();
    }
  }

  // ============================================================
  // ✅ YEAR PICKER
  // ============================================================
  Future<void> _pickYear() async {
    final currentYear = DateTime.now().year;
    final years = List.generate(12, (i) => currentYear - 5 + i);

    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.event_note, color: AppTheme.primary),
              const SizedBox(width: 10),
              Text(
                'Select Year',
                style: TextStyle(
                  color: _isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: years.map((year) {
                final isSelected = year == _selectedYear;
                return SizedBox(
                  width: 90,
                  height: 44,
                  child: Material(
                    color: isSelected
                        ? AppTheme.primary
                        : (_isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => Navigator.pop(dialogContext, year),
                      borderRadius: BorderRadius.circular(10),
                      child: Center(
                        child: Text(
                          '$year',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : (_isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'CANCEL',
                style: TextStyle(
                  color: _isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
          ],
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedYear = picked;
        _selectedPeriod = 'year';
      });
      _loadAppointments();
    }
  }

  // ============================================================
  // ✅ BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Appointments',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_selectedSalonName.isNotEmpty)
              Text(
                _selectedSalonName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingState()
            : _errorMessage != null
            ? _buildErrorState()
            : _isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 16),
          Text(
            'Loading appointments...',
            style: TextStyle(
              color: _isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: _isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ MOBILE LAYOUT (barber-style)
  // ============================================================
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Search bar
        _buildSearchBar(),

        // Date period selector (Date/Month/Year)
        _buildDatePeriodSelector(),

        // Period display
        _buildPeriodDisplay(),

        // Stats cards
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Pending',
                  _pendingCount,
                  Icons.pending_actions,
                  Colors.orange,
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
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Cancel',
                  _cancelledCount,
                  Icons.cancel_outlined,
                  Colors.red,
                ),
              ),
            ],
          ),
        ),

        // Tabs
        Container(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: _buildTabBar(),
        ),

        // List
        Expanded(child: _buildAppointmentList()),
      ],
    );
  }

  // ============================================================
  // ✅ WEB LAYOUT (barber-style centered)
  // ============================================================
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1100),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            _buildSearchBar(isWeb: true),

            const SizedBox(height: 12),

            // Date period selector
            _buildDatePeriodSelector(),

            // Period display
            _buildPeriodDisplay(),

            const SizedBox(height: 12),

            // Stats cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Pending',
                    _pendingCount,
                    Icons.pending_actions,
                    Colors.orange,
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
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Cancel',
                    _cancelledCount,
                    Icons.cancel_outlined,
                    Colors.red,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
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

            const SizedBox(height: 12),

            // List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAppointments,
                color: AppTheme.primary,
                child: _buildAppointmentList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ STAT CARD
  // ============================================================
  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: _isDark ? Colors.white60 : Colors.grey[600],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ TAB BAR
  // ============================================================
  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      labelColor: AppTheme.primary,
      unselectedLabelColor: _isDark ? Colors.white60 : Colors.grey[600],
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
    );
  }

  // ============================================================
  // ✅ DATE PERIOD SELECTOR (Date / Month / Year)
  // ============================================================
  Widget _buildDatePeriodSelector() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
      child: Row(
        children: [
          Expanded(
            child: _buildPeriodButton(
              icon: Icons.calendar_today,
              label: 'Date',
              isSelected: _selectedPeriod == 'date',
              onTap: _pickDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildPeriodButton(
              icon: Icons.calendar_month,
              label: 'Month',
              isSelected: _selectedPeriod == 'month',
              onTap: _pickMonth,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildPeriodButton(
              icon: Icons.event_note,
              label: 'Year',
              isSelected: _selectedPeriod == 'year',
              onTap: _pickYear,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary
                : (_isDark ? const Color(0xFF2A2A2A) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primary
                  : (_isDark ? Colors.grey[800]! : Colors.grey[300]!),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : (_isDark ? Colors.white70 : Colors.grey[700]),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (_isDark ? Colors.white70 : Colors.grey[700]),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ PERIOD DISPLAY
  // ============================================================
  Widget _buildPeriodDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: _isDark ? Colors.white60 : Colors.grey[600],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing: $_periodDisplayText',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ),
          Text(
            '$_totalCount total',
            style: TextStyle(
              fontSize: 12,
              color: _isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ SEARCH BAR (barber)
  // ============================================================
  Widget _buildSearchBar({bool isWeb = false}) {
    final searchBox = Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: _isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selectedBarber != null
                  ? AppTheme.primary
                  : (_isDark ? Colors.grey[800]! : Colors.grey[300]!),
              width: _selectedBarber != null ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                Icons.search,
                color: _isDark ? Colors.grey[400] : Colors.grey[500],
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  onTap: () {
                    if (_searchController.text.isNotEmpty &&
                        _barberSuggestions.isNotEmpty) {
                      setState(() => _showSuggestions = true);
                    }
                  },
                  style: TextStyle(
                    fontSize: 14,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search barber by name or email...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: _isDark ? Colors.grey[500] : Colors.grey[400],
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: _isDark ? Colors.grey[400] : Colors.grey[500],
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _filterBarbers('');
                  },
                ),
              if (_isSearchingBarbers)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),

        // Selected barber chip
        if (_selectedBarber != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBarberAvatar(
                    _selectedBarber!['avatar_url'],
                    _selectedBarber!['full_name'] ?? '',
                    20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedBarber!['full_name'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _clearBarberSelection,
                    child: Icon(Icons.close, size: 14, color: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Suggestions
        if (_showSuggestions) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _barberSuggestions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_search,
                          size: 18,
                          color: _isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'No barbers found',
                          style: TextStyle(
                            fontSize: 13,
                            color: _isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _barberSuggestions.length,
                    itemBuilder: (context, index) {
                      return _buildBarberSuggestionTile(
                        _barberSuggestions[index],
                      );
                    },
                  ),
          ),
        ],
      ],
    );

    return Container(
      padding: EdgeInsets.fromLTRB(0, isWeb ? 0 : 12, 0, 0),
      color: isWeb
          ? Colors.transparent
          : (_isDark ? const Color(0xFF1E1E1E) : Colors.grey[50]),
      child: isWeb
          ? searchBox
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: searchBox,
            ),
    );
  }

  Widget _buildBarberSuggestionTile(Map<String, dynamic> barber) {
    final fullName = barber['full_name'] as String? ?? 'Unknown';
    final email = barber['email'] as String? ?? '';
    final avatarUrl = barber['avatar_url'] as String?;

    return InkWell(
      onTap: () => _selectBarber(barber),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _buildBarberAvatar(avatarUrl, fullName, 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: _isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarberAvatar(String? avatarUrl, String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isDark ? Colors.grey[800] : Colors.grey[200],
      ),
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorWidget: (context, url, error) => Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.bold,
                      color: _isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold,
                  color: _isDark ? Colors.white60 : Colors.grey,
                ),
              ),
            ),
    );
  }

  // ============================================================
  // ✅ APPOINTMENT LIST
  // ============================================================
  Widget _buildAppointmentList() {
    if (_filteredAppointments.isEmpty) {
      return _buildEmptyState();
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
              constraints: const BoxConstraints(maxWidth: 1200),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.7,
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
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 400,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: _isDark ? Colors.white30 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: _isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'for $_periodDisplayText',
              style: TextStyle(
                fontSize: 13,
                color: _isDark ? Colors.white70 : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ APPOINTMENT CARD (unchanged design)
  // ============================================================
  Widget _buildAppointmentCard(Map<String, dynamic> apt) {
    final status = apt['status'] as String;
    final paymentStatus = apt['payment_status'] as String? ?? 'unpaid';
    final statusColor = _getStatusColor(status);
    final isVip = apt['is_vip'] as bool? ?? false;
    final customerName = apt['customer_name'] as String;
    final customerAvatar = apt['customer_avatar'] as String?;
    final barberName = apt['barber_name'] as String;
    final displayDate = apt['display_date'] as String;
    final startTime = _formatTime(apt['start_time']);
    final endTime = _formatTime(apt['end_time']);
    final symbol = _currencySymbol(apt['currency_code'] as String?);
    final services = (apt['services'] as List?) ?? [];
    final totalPrice = (apt['price'] as num?)?.toDouble() ?? 0.0;
    final extraCharge = (apt['extra_charge'] as num?)?.toDouble() ?? 0.0;
    final extraNote = apt['extra_charge_note'] as String?;
    final totalDiscount = (apt['total_discount'] as num?)?.toDouble() ?? 0.0;
    final duration = apt['duration'] as int? ?? 0;
    final isCompleted = status == 'completed';
    final isPaid = paymentStatus == 'paid';
    final isPendingPayment = isCompleted && !isPaid;
    final regQueue = apt['regular_queue_number'];
    final vipQueue = apt['vip_queue_number'];
    final childName = apt['child_name'] as String?;
    final travelTime = apt['travel_time_minutes'] as int? ?? 0;
    final notes = apt['notes'] as String?;

    final canEditServices =
        _editableStatuses.contains(status) || isPendingPayment;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isVip
            ? BorderSide(color: Colors.amber.shade400, width: 2)
            : (isPendingPayment
                  ? BorderSide(color: Colors.orange.shade400, width: 2)
                  : BorderSide.none),
      ),
      child: InkWell(
        onTap: () => _viewAppointmentDetails(apt),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    apt['booking_number'] ?? 'BK-XXXX',
                    style: TextStyle(
                      fontSize: _isWeb ? 15 : 14,
                      fontWeight: FontWeight.bold,
                      color: _isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  if (isVip)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'VIP',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(status),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusDisplay(status),
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Customer
              Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isDark ? Colors.grey[800] : Colors.grey[200],
                    ),
                    child: customerAvatar != null && customerAvatar.isNotEmpty
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: customerAvatar,
                              fit: BoxFit.cover,
                              width: 45,
                              height: 45,
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  customerName.isNotEmpty
                                      ? customerName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _isDark
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
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isDark ? Colors.white60 : Colors.grey,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
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
                                  fontSize: _isWeb ? 16 : 15,
                                  fontWeight: FontWeight.bold,
                                  color: _isDark
                                      ? Colors.white
                                      : Colors.black87,
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
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 12,
                              color: _isDark
                                  ? Colors.white60
                                  : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Barber: $barberName',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
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
                                  color: _isDark
                                      ? Colors.white60
                                      : Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'For: $childName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isDark
                                        ? Colors.white60
                                        : Colors.grey[600],
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

              // Services
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.content_cut,
                          size: 12,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Services (${services.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$duration min',
                          style: TextStyle(
                            fontSize: 11,
                            color: _isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    if (services.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'No services',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      )
                    else
                      ...services.take(3).map((s) {
                        final sFinal =
                            (s['final_price'] as num?)?.toDouble() ?? 0;
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
                                        color: _isDark
                                            ? Colors.white
                                            : Colors.black87,
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
                                  const SizedBox(width: 4),
                                  if (hasDiscount)
                                    Text(
                                      '$symbol${sOriginal.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        decoration: TextDecoration.lineThrough,
                                        color: _isDark
                                            ? Colors.white60
                                            : Colors.grey,
                                      ),
                                    ),
                                  if (hasDiscount) const SizedBox(width: 4),
                                  Text(
                                    '$symbol${(hasDiscount ? sFinal : sOriginal).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: hasDiscount
                                          ? Colors.green.shade700
                                          : (_isDark
                                                ? Colors.white
                                                : Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                              if (variantLabel != null &&
                                  variantLabel.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    top: 1,
                                  ),
                                  child: Text(
                                    variantLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _isDark
                                          ? Colors.white70
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ),
                              if (hasDiscount && offerTitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    top: 1,
                                  ),
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
                    if (services.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${services.length - 3} more',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: _isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ),
                    if (extraCharge > 0) ...[
                      const Divider(height: 12),
                      Row(
                        children: [
                          Icon(
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
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '+$symbol${extraCharge.toStringAsFixed(2)}',
                            style: TextStyle(
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
                    const Divider(height: 12),
                    Row(
                      children: [
                        Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$symbol${totalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isVip
                                ? Colors.amber.shade700
                                : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Date/Time
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: _isDark ? Colors.white60 : Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: _isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: _isDark ? Colors.white60 : Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$startTime - $endTime',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),

              // Queue info
              if (regQueue != null || vipQueue != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (regQueue != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Q$regQueue',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    if (vipQueue != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'VIP-$vipQueue',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ),
                    ],
                    if (travelTime > 0) ...[
                      const Spacer(),
                      Icon(
                        Icons.directions_car,
                        size: 12,
                        color: _isDark ? Colors.white60 : Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$travelTime min',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Notes
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isDark
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
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
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons
              if (canEditServices || isPendingPayment) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (canEditServices)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isMarkingPaid
                              ? null
                              : () => _openEditServices(apt),
                          icon: const Icon(
                            Icons.add_circle_outline,
                            size: 16,
                          ),
                          label: const Text(
                            'SERVICES',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(color: AppTheme.primary),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if (isPendingPayment) ...[
                      if (canEditServices) const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isMarkingPaid
                              ? null
                              : () => _markAsPaid(apt),
                          icon: const Icon(Icons.payments, size: 16),
                          label: const Text(
                            'PAY',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _viewAppointmentDetails(Map<String, dynamic> apt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AppointmentDetailsSheet(
        appointment: apt,
        isDark: _isDark,
        isWeb: _isWeb,
        currencySymbol: _currencySymbol,
        onEditServices:
            _editableStatuses.contains(apt['status']) ||
                (apt['status'] == 'completed' &&
                    (apt['payment_status'] as String? ?? 'unpaid') != 'paid')
            ? () {
                Navigator.pop(context);
                _openEditServices(apt);
              }
            : null,
        onMarkAsPaid:
            (apt['status'] == 'completed' &&
                (apt['payment_status'] as String? ?? 'unpaid') != 'paid')
            ? () {
                Navigator.pop(context);
                _markAsPaid(apt);
              }
            : null,
      ),
    );
  }
}

// ============================================================
// APPOINTMENT DETAILS SHEET (unchanged)
// ============================================================
class AppointmentDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final bool isDark;
  final bool isWeb;
  final String Function(String?) currencySymbol;
  final VoidCallback? onMarkAsPaid;
  final VoidCallback? onEditServices;

  const AppointmentDetailsSheet({
    super.key,
    required this.appointment,
    required this.isDark,
    required this.isWeb,
    required this.currencySymbol,
    this.onMarkAsPaid,
    this.onEditServices,
  });

  @override
  Widget build(BuildContext context) {
    final customerName = appointment['customer_name'] as String;
    final customerPhone = appointment['customer_phone'] as String? ?? '';
    final customerEmail = appointment['customer_email'] as String? ?? '';
    final customerAvatar = appointment['customer_avatar'] as String?;
    final barberName = appointment['barber_name'] as String;
    final status = appointment['status'] as String;
    final paymentStatus = appointment['payment_status'] as String? ?? 'unpaid';
    final statusColor = _getStatusColor(status);
    final isVip = appointment['is_vip'] as bool? ?? false;
    final displayDate = appointment['display_date'] as String;
    final startTime = appointment['start_time'] as String;
    final endTime = appointment['end_time'] as String;
    final bookingNumber = appointment['booking_number'] as String? ?? 'N/A';
    final childName = appointment['child_name'] as String?;
    final notes = appointment['notes'] as String?;

    final symbol = currencySymbol(appointment['currency_code'] as String?);
    final services = (appointment['services'] as List?) ?? [];
    final servicesTotal =
        (appointment['services_total'] as num?)?.toDouble() ?? 0;
    final totalDiscount =
        (appointment['total_discount'] as num?)?.toDouble() ?? 0;
    final extraCharge = (appointment['extra_charge'] as num?)?.toDouble() ?? 0;
    final extraNote = appointment['extra_charge_note'] as String?;
    final totalPrice = (appointment['price'] as num?)?.toDouble() ?? 0;
    final duration = appointment['duration'] as int? ?? 0;
    final queuePosition = appointment['queue_position'];
    final regQueue = appointment['regular_queue_number'];
    final vipQueue = appointment['vip_queue_number'];
    final queueToken = appointment['queue_token'] as String?;
    final travelTime = appointment['travel_time_minutes'] ?? 0;
    final isCompleted = status == 'completed';
    final isPaid = paymentStatus == 'paid';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Booking #$bookingNumber',
                                  style: TextStyle(
                                    fontSize: isWeb ? 18 : 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getStatusIcon(status),
                                            size: 14,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _getStatusDisplay(status),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: statusColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isCompleted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPaid
                                              ? Colors.green.withValues(
                                                  alpha: 0.15,
                                                )
                                              : Colors.orange.withValues(
                                                  alpha: 0.15,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isPaid
                                                  ? Icons.check_circle
                                                  : Icons.schedule,
                                              size: 12,
                                              color: isPaid
                                                  ? Colors.green.shade700
                                                  : Colors.orange.shade700,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isPaid
                                                  ? 'PAID'
                                                  : 'PENDING PAYMENT',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isPaid
                                                    ? Colors.green.shade700
                                                    : Colors.orange.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (isVip)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade400,
                                          ),
                                        ),
                                        child: const Text(
                                          '⭐ VIP',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(),

                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                          ),
                          child: customerAvatar != null &&
                                  customerAvatar.isNotEmpty
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: customerAvatar,
                                    fit: BoxFit.cover,
                                    width: 50,
                                    height: 50,
                                    errorWidget: (context, url, error) =>
                                        Center(
                                          child: Text(
                                            customerName.isNotEmpty
                                                ? customerName[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              fontSize: 20,
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
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                        ),
                        title: Text(
                          customerName,
                          style: TextStyle(
                            fontSize: isWeb ? 17 : 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (customerPhone.isNotEmpty)
                              Text(
                                customerPhone,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            if (customerEmail.isNotEmpty)
                              Text(
                                customerEmail,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                              ),
                            if (childName != null && childName.isNotEmpty)
                              Text(
                                'Booked For: $childName',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      if (services.isNotEmpty) ...[
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
                          final sFinal =
                              (s['final_price'] as num?)?.toDouble() ?? 0;
                          final sDuration =
                              (s['duration'] as num?)?.toInt() ?? 30;
                          final offerTitle = s['offer_title'] as String?;
                          final variantLabel = s['variant_label'] as String?;

                          final details = [
                            if (variantLabel != null && variantLabel.isNotEmpty)
                              variantLabel,
                            '$sDuration min',
                          ].join(' • ');

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? Colors.grey[800]!
                                    : Colors.grey[200]!,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s['service_name'] ?? 'Service',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (sDiscount > 0)
                                      Text(
                                        '$symbol${sOriginal.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          decoration:
                                              TextDecoration.lineThrough,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.grey,
                                        ),
                                      ),
                                    if (sDiscount > 0) const SizedBox(width: 4),
                                    Text(
                                      '$symbol${(sDiscount > 0 ? sFinal : sOriginal).toStringAsFixed(2)}',
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
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  details,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey[600],
                                  ),
                                ),
                                if (sDiscount > 0 && offerTitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.local_offer,
                                          size: 11,
                                          color: Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '$offerTitle — save $symbol${sDiscount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],

                      const Divider(),

                      _buildDetailRow('Barber', barberName),
                      _buildDetailRow('Date', displayDate),
                      _buildDetailRow(
                        'Time',
                        '${_formatTime(startTime)} - ${_formatTime(endTime)}',
                      ),
                      _buildDetailRow('Total Duration', '$duration min'),
                      if (regQueue != null)
                        _buildDetailRow('Queue', 'Q$regQueue'),
                      if (vipQueue != null)
                        _buildDetailRow('VIP Queue', 'VIP-$vipQueue'),
                      if (queuePosition != null)
                        _buildDetailRow('Position', '#$queuePosition'),
                      if (queueToken != null && queueToken.isNotEmpty)
                        _buildDetailRow('Queue Token', queueToken),
                      if (travelTime > 0)
                        _buildDetailRow('Travel Time', '$travelTime min'),

                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.blue.withValues(alpha: 0.1)
                                : Colors.blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.note,
                                    size: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Notes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                notes,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const Divider(height: 20),

                      _buildPriceRow(
                        'Services Subtotal',
                        '$symbol${servicesTotal.toStringAsFixed(2)}',
                      ),
                      if (totalDiscount > 0)
                        _buildPriceRow(
                          'Total Discount',
                          '−$symbol${totalDiscount.toStringAsFixed(2)}',
                          color: Colors.green.shade700,
                        ),
                      if (extraCharge > 0)
                        _buildPriceRow(
                          extraNote != null && extraNote.isNotEmpty
                              ? 'Extra Charge ($extraNote)'
                              : 'Extra Charge',
                          '+$symbol${extraCharge.toStringAsFixed(2)}',
                          color: Colors.orange,
                        ),

                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isVip ? Colors.amber : AppTheme.primary)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              '$symbol${totalPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isVip
                                    ? Colors.amber.shade700
                                    : AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (onEditServices != null) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onEditServices,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                            ),
                            label: const Text('EDIT SERVICES / EXTRA CHARGE'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: BorderSide(color: AppTheme.primary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (onMarkAsPaid != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: onMarkAsPaid,
                            icon: const Icon(Icons.payments, size: 20),
                            label: const Text('MARK AS PAID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? Colors.white
                                : Colors.black87,
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isWeb ? 14 : 13,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: isWeb ? 14 : 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color ?? (isDark ? Colors.white70 : Colors.grey[700]),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'confirmed':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'no_show':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'confirmed':
        return 'Confirmed';
      case 'in_progress':
        return 'In Progress';
      case 'pending':
        return 'Pending';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No Show';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.hourglass_top;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'no_show':
        return Icons.person_off;
      default:
        return Icons.info;
    }
  }

  String _formatTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }
}