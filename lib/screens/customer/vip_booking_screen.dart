import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../services/timezone_service.dart';
import '../../services/currency_service.dart';
import '../../services/currency_settings_service.dart'; // ✅ NEW
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class VIPBookingScreen extends StatefulWidget {
  final Map<String, dynamic>? initialSalon;
  const VIPBookingScreen({super.key, this.initialSalon});

  @override
  State<VIPBookingScreen> createState() => _VIPBookingScreenState();
}

class _VIPBookingScreenState extends State<VIPBookingScreen> {
  final supabase = Supabase.instance.client;

  // 0 Salon, 1 Service, 2 Date, 3 Barber, 4 Person, 5 Time, 6 Confirm
  int _currentStep = 0;

  // Step 0: Salon
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allSalons = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedSalon;
  bool _isLoadingSalons = true;
  Timer? _salonSearchDebounce;

  // Step 1: Service
  List<Map<String, dynamic>> _salonServices = [];
  List<Map<String, dynamic>> _selectedServices = [];
  bool _isLoadingServices = false;
  bool _servicesLoaded = false;

  final Map<String, List<Map<String, dynamic>>> _availableOffersPerService = {};
  final Map<String, Map<String, dynamic>> _serviceOffers = {};

  // Step 2: Date
  DateTime? _selectedDate;
  Set<DateTime> _holidays = {};
  Map<DateTime, String> _holidayNames = {};
  bool _isDateUnavailable = false;
  String? _unavailableReason;
  bool _isCheckingDate = false;
  bool _scheduleLoaded = false;
  Set<int> _workingWeekdays = {};
  int _calendarVersion = 0;

  // Step 3: Barber
  List<Map<String, dynamic>> _availableBarbers = [];
  Map<String, dynamic>? _selectedBarber;
  bool _isLoadingBarbers = false;
  bool _barbersLoaded = false;
  Map<String, Map<String, dynamic>> _barberAvailability = {};

  // Step 4: Person
  final TextEditingController _childNameController = TextEditingController();
  String? _selectedChildName;
  bool _isSameAsCustomer = true;
  bool _isCheckingDuplicate = false;
  String? _duplicateError;

  // Step 5: Time Slot (VIP)
  List<Map<String, dynamic>> _allTimeSlots = [];
  Map<String, dynamic>? _selectedSlot;
  bool _isLoadingSlots = false;
  String? _slotErrorMessage;
  String? _slotErrorType;
  bool _showingVipNumber = false;
  int _generatedVipNumber = 0;
  String _selectedStartTime = '';

  // Step 6: Confirm
  bool _isBooking = false;
  bool _isInitialized = false;

  Map<String, dynamic>? _appliedOffer;
  Set<int> offerServiceIds = {};

  List<Map<String, dynamic>>? _preselectedServices;
  bool _preselectedServicesApplied = false;
  bool _skipToDate = false;

  double _discountAmount = 0;
  double _originalTotalPrice = 0;
  double _finalTotalPrice = 0;

  // ✅ Timezone (salon + user)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';
  static const String _kDefaultCurrency = 'LKR'; // ✅ NEW
  String _userTimezone = '';
  String _selectedSalonTimezone = _kDefaultSalonTimezone;
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  // ✅ Currency (salon + user + rate)
  String _salonCurrencyCode = 'LKR';
  String _userCurrencyCode = _kDefaultCurrency; // ✅ NEW
  double? _exchangeRate; // ✅ NEW
  final CurrencyService _currencyService = CurrencyService.instance;
  final CurrencySettingsService _currencySettings =
      CurrencySettingsService.instance; // ✅ NEW

  // ✅ Responsive
  bool _isWeb = false;

  final ScrollController _scrollController = ScrollController();

  final Color _secondaryColor = const Color(0xFF4CAF50);
  final Color _textDark = const Color(0xFF333333);
  final Color _bgLight = const Color(0xFFF8F9FA);
  final List<Color> _cardColors = [
    const Color(0xFFFCE4EC),
    const Color(0xFFE3F2FD),
    const Color(0xFFE8F5E9),
    const Color(0xFFFFF3E0),
    const Color(0xFFF3E5F5),
  ];

  // ═══════════════════════════════════════════════════
  // ✅ SALON "NOW" / "TODAY" (salon timezone reference)
  // ═══════════════════════════════════════════════════
  DateTime get _salonNow {
    final tz = _selectedSalonTimezone.isNotEmpty
        ? _selectedSalonTimezone
        : _kDefaultSalonTimezone;
    try {
      return TimezoneService.getNowInTimezone(tz);
    } catch (e) {
      debugPrint('❌ Error getting salon now: $e');
      return DateTime.now();
    }
  }

  DateTime get _todayDate {
    final now = _salonNow;
    return DateTime(now.year, now.month, now.day);
  }

  // ═══════════════════════════════════════════════════
  // ✅ CURRENCY + TIMEZONE HELPERS
  // ═══════════════════════════════════════════════════

  /// ✅ Salon currency format
  String _formatPrice(dynamic price) {
    return _currencyService.format(
      price: price,
      currencyCode: _salonCurrencyCode,
    );
  }

  /// ✅ NEW: User currency format (approximate)
  String _formatUserPrice(dynamic price) {
    return _currencyService.format(
      price: price,
      currencyCode: _userCurrencyCode,
    );
  }

  /// ✅ NEW: Check if dual display is applicable
  bool get _showApprox {
    return _exchangeRate != null &&
        _exchangeRate! > 0 &&
        _userCurrencyCode != _salonCurrencyCode;
  }

  /// ✅ Salon timezone display (main)
  String _getSalonTimezoneDisplay() {
    final tz = _selectedSalonTimezone.isNotEmpty
        ? _selectedSalonTimezone
        : _kDefaultSalonTimezone;
    return TimezoneService.getFullTimezoneDisplayFor(tz);
  }

  /// ✅ User timezone display
  String _getUserTimezoneDisplay() {
    if (_userTimezone.isEmpty) return '';
    return TimezoneService.getFullTimezoneDisplayFor(_userTimezone);
  }

  /// ✅ User timezone ≠ salon timezone?
  bool get _isDifferentTimezone {
    if (_selectedSalonTimezone.isEmpty || _userTimezone.isEmpty) return false;
    return _selectedSalonTimezone != _userTimezone;
  }

  /// ✅ DST check via TimezoneService (salon timezone)
  bool _isDST() {
    try {
      final status = TimezoneService.getDSTStatus();
      return status['isDST'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _extractPreselectedFromInitialSalon();
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
    _checkTimezoneChange();
    _checkForOffer();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _childNameController.dispose();
    _scrollController.dispose();
    _salonSearchDebounce?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // SALON NORMALIZE + PRESELECTED EXTRACTION
  // ═══════════════════════════════════════════════════════

  void _extractPreselectedFromInitialSalon() {
    final initial = widget.initialSalon;
    if (initial == null) return;

    if (initial.containsKey('preselected_services') &&
        _preselectedServices == null) {
      final raw = initial['preselected_services'];
      if (raw is List && raw.isNotEmpty) {
        _preselectedServices = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        debugPrint(
          '🎯 Preselected services extracted: ${_preselectedServices!.length}',
        );
      }
    }

    if (initial.containsKey('skip_to_date')) {
      _skipToDate = initial['skip_to_date'] == true;
    }
    debugPrint('🎯 skip_to_date: $_skipToDate');
  }

  Map<String, dynamic>? _normalizedInitialSalon() {
    final initial = widget.initialSalon;
    if (initial == null) return null;

    final dynamic rawId = initial['id'];
    if (rawId == null) return null;

    final int salonId;
    if (rawId is int) {
      salonId = rawId;
    } else if (rawId is num) {
      salonId = rawId.toInt();
    } else {
      final parsed = int.tryParse(rawId.toString());
      if (parsed == null) return null;
      salonId = parsed;
    }

    if (salonId <= 0) return null;

    final normalized = Map<String, dynamic>.from(initial);
    normalized['id'] = salonId;
    normalized.remove('preselected_services');
    normalized.remove('skip_to_date');
    return normalized;
  }

  /// ✅ MediaQuery.sizeOf (only reacts to size changes)
  void _checkScreenSize() {
    final size = MediaQuery.sizeOf(context);
    final isWeb = size.width > 800;

    if (_isWeb != isWeb) {
      setState(() {
        _isWeb = isWeb;
      });
    }
  }

  // ============================================
  // OFFER + EXTRA HANDLING
  // ============================================

  void _checkForOffer() {
    final extra = GoRouterState.of(context).extra;

    if (extra == null) return;

    if (extra is Map) {
      final map = Map<String, dynamic>.from(extra);

      if (map.containsKey('offer') && map['offer'] is Map) {
        final offer = Map<String, dynamic>.from(map['offer'] as Map);
        if (_appliedOffer == null) {
          _appliedOffer = offer;
          debugPrint('🎁 [VIP] Offer from navigation: ${offer['title']}');
          final oid = offer['id'];
          if (oid is int) _loadOfferServices(oid);
        }
      }

      if (map.containsKey('preselected_services') &&
          _preselectedServices == null) {
        final raw = map['preselected_services'];
        if (raw is List && raw.isNotEmpty) {
          _preselectedServices = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      if (map.containsKey('skip_to_date')) {
        _skipToDate = map['skip_to_date'] == true;
        debugPrint('🎯 skip_to_date (from extra): $_skipToDate');
      }
    }
  }

  Future<void> _loadOfferServices(int offerId) async {
    try {
      final rows = await supabase
          .from('offer_services')
          .select('service_id')
          .eq('offer_id', offerId);
      if (!mounted) return;
      setState(() {
        offerServiceIds = rows.map<int>((r) => r['service_id'] as int).toSet();
      });
      _recalculateTotals();
    } catch (e) {
      debugPrint('❌ [VIP] Error loading offer services: $e');
    }
  }

  void _removeOffer() {
    setState(() {
      _appliedOffer = null;
      offerServiceIds = {};
      _discountAmount = 0;
      _finalTotalPrice = 0;
      _originalTotalPrice = 0;
      _serviceOffers.clear();
      for (int i = 0; i < _selectedServices.length; i++) {
        _selectedServices[i] = {
          ..._selectedServices[i],
          'offer': null,
          'offer_id': null,
          'discount_amount': 0,
          'final_price': _selectedServices[i]['price'],
        };
      }
    });
    debugPrint('🎁 [VIP] Offer removed');
  }

  // ============================================
  // PER-SERVICE OFFER HELPERS
  // ============================================

  String _serviceKey(int serviceId, int? variantId) =>
      '${serviceId}_${variantId ?? 0}';

  Future<List<Map<String, dynamic>>> _loadOffersForService(
    int serviceId,
    double price, {
    int? variantId,
  }) async {
    if (_selectedSalon == null) return [];

    try {
      final user = supabase.auth.currentUser;

      final result = await supabase.rpc(
        'get_offers_for_service',
        params: {
          'p_salon_id': _selectedSalon!['id'],
          'p_service_id': serviceId,
          'p_service_price': price,
          'p_customer_id': user?.id,
          'p_variant_id': variantId,
        },
      );

      if (result == null) return [];
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint(
        '⚠️ Error loading offers for service $serviceId (variant $variantId): $e',
      );
      return [];
    }
  }

  double _calculateOfferDiscount(double price, Map<String, dynamic>? offer) {
    if (offer == null) return 0;

    final discountType = offer['discount_type']?.toString();
    final discountValue = (offer['discount_value'] as num?)?.toDouble() ?? 0;

    double discount = 0;
    if (discountType == 'percentage') {
      discount = price * (discountValue / 100);
    } else if (discountType == 'fixed') {
      discount = discountValue;
    } else if (discountType == 'free_service') {
      discount = price;
    }

    return discount.clamp(0, price);
  }

  void _applyOfferToService(
    int serviceId,
    int variantId,
    Map<String, dynamic>? offer,
  ) {
    final key = _serviceKey(serviceId, variantId);
    final index = _selectedServices.indexWhere(
      (s) => s['id'] == serviceId && s['variant_id'] == variantId,
    );

    if (index < 0) return;

    final price = (_selectedServices[index]['price'] as num?)?.toDouble() ?? 0;
    final discount = _calculateOfferDiscount(price, offer);
    final finalPrice = price - discount;

    debugPrint(
      '🎯 [ApplyOffer] sid=$serviceId vid=$variantId '
      'offer=${offer?['title']} discount=$discount final=$finalPrice',
    );

    setState(() {
      _selectedServices[index] = {
        ..._selectedServices[index],
        'offer': offer,
        'offer_id': offer?['id'],
        'discount_amount': discount,
        'final_price': finalPrice,
      };

      if (offer == null) {
        _serviceOffers.remove(key);
      } else {
        _serviceOffers[key] = offer;
      }

      _recalculateTotals();
    });
  }

  void _recalculateTotals() {
    double subtotal = 0;
    double totalDiscount = 0;
    double finalTotal = 0;

    for (final service in _selectedServices) {
      final price = (service['price'] as num?)?.toDouble() ?? 0;
      final discount = (service['discount_amount'] as num?)?.toDouble() ?? 0;
      final finalPrice = (service['final_price'] as num?)?.toDouble() ?? price;

      subtotal += price;
      totalDiscount += discount;
      finalTotal += finalPrice;
    }

    setState(() {
      _originalTotalPrice = subtotal;
      _discountAmount = totalDiscount;
      _finalTotalPrice = finalTotal;
    });
  }

  void _showErrorSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================
  // TIMEZONE + CURRENCY INIT
  // ============================================

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString(TimezoneService.kUserTimezone) ??
        prefs.getString(TimezoneService.kCachedTimezone) ??
        TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    _lastTimezone = _userTimezone;

    // ✅ NEW: Load user currency
    try {
      _userCurrencyCode = await _currencySettings.getUserCurrency();
      debugPrint('✅ [VIP] User currency loaded: $_userCurrencyCode');
    } catch (e) {
      debugPrint('⚠️ [VIP] Failed to load user currency: $e');
      _userCurrencyCode = _kDefaultCurrency;
    }

    if (!mounted) return;
    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadAllSalons();
    await _initializeScreen();
  }

  Future<void> _checkTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString(TimezoneService.kUserTimezone) ??
        prefs.getString(TimezoneService.kCachedTimezone) ??
        TimezoneService.getCurrentTimezone();

    if (_lastTimezone != currentTimezone && _lastTimezone.isNotEmpty) {
      _userTimezone = currentTimezone;
      await TimezoneService.setTimezone(_userTimezone);
      _onTimezoneChanged();
    }
    _lastTimezone = currentTimezone;
  }

  void _onTimezoneChanged() async {
    if (_currentStep == 5 && _selectedDate != null && _selectedBarber != null) {
      setState(() {
        _allTimeSlots = [];
        _selectedSlot = null;
        _showingVipNumber = false;
        _generatedVipNumber = 0;
        _selectedStartTime = '';
        _slotErrorMessage = null;
        _slotErrorType = null;
        _isLoadingSlots = true;
      });
      await _loadAvailableSlots();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Timezone changed to ${TimezoneService.getTimezoneDisplayName()}',
            ),
            backgroundColor: AppTheme.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _initializeScreen() async {
    if (_isInitialized) return;
    if (widget.initialSalon == null) return;

    final normalized = _normalizedInitialSalon();
    if (normalized == null) {
      debugPrint('⚠️ [VIP] Invalid initialSalon — falling back to Salon step');
      setState(() {
        _selectedSalon = null;
        _currentStep = 0;
        _isInitialized = true;
      });
      return;
    }

    final hasPreselected =
        _preselectedServices != null && _preselectedServices!.isNotEmpty;

    final int startingStep;
    if (hasPreselected && _skipToDate) {
      startingStep = 2;
    } else {
      startingStep = 1;
    }

    debugPrint(
      '🎯 [VIP] Starting step: $startingStep '
      '(${startingStep == 2 ? "Date" : "Service"})',
    );

    setState(() {
      _selectedSalon = normalized;
      _currentStep = startingStep;
      _isInitialized = true;
    });

    // ✅ Load salon settings (TZ + currency + rate) FIRST
    await _loadSalonSettings();
    await _loadSalonServices();
    await _applyPreselectedServices();
    await _loadHolidays();
  }

  /// ✅ Load salon timezone + currency + exchange rate
  Future<void> _loadSalonSettings() async {
    if (_selectedSalon == null) return;

    try {
      final salonId = _selectedSalon!['id'] as int;
      final response = await supabase
          .from('salons')
          .select('timezone, currency_code')
          .eq('id', salonId)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        final tz = response['timezone'] as String?;
        final curr = response['currency_code'] as String?;

        setState(() {
          if (tz != null && tz.isNotEmpty) {
            _selectedSalonTimezone = tz;
          }
          if (curr != null && curr.isNotEmpty) {
            _salonCurrencyCode = curr;
          }
        });

        debugPrint(
          '✅ [VIP] Salon settings loaded: TZ=$_selectedSalonTimezone, '
          'Currency=$_salonCurrencyCode',
        );

        // ✅ NEW: Load exchange rate for this salon → user currency
        await _loadExchangeRate();
      }
    } catch (e) {
      debugPrint('❌ [VIP] Error loading salon settings: $e');
    }
  }

  /// ✅ NEW: Load exchange rate (salon → user)
  Future<void> _loadExchangeRate() async {
    if (!mounted) return;

    // Same currency → no rate needed
    if (_salonCurrencyCode == _userCurrencyCode) {
      setState(() {
        _exchangeRate = 1.0;
      });
      debugPrint('ℹ️ [VIP] Same currency, rate = 1.0');
      return;
    }

    try {
      final rate = await _currencySettings.getExchangeRate(
        fromCurrency: _salonCurrencyCode,
        toCurrency: _userCurrencyCode,
      );

      if (!mounted) return;
      setState(() {
        _exchangeRate = rate;
      });

      debugPrint(
        '✅ [VIP] Exchange rate loaded: 1 $_salonCurrencyCode = '
        '${rate?.toStringAsFixed(6) ?? "?"} $_userCurrencyCode',
      );
    } catch (e) {
      debugPrint('⚠️ [VIP] Failed to load exchange rate: $e');
      if (!mounted) return;
      setState(() {
        _exchangeRate = null;
      });
    }
  }

  // ==================== HELPERS ====================

  int _calculateTotalDuration() => _selectedServices.fold(
    0,
    (sum, s) => sum + ((s['duration'] as num?)?.toInt() ?? 30),
  );

  double _calculateTotalPrice() => _selectedServices.fold(
    0.0,
    (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0),
  );

  double _getDisplayTotalPrice() {
    if (_finalTotalPrice > 0 || _discountAmount > 0) {
      return _finalTotalPrice;
    }
    return _calculateTotalPrice();
  }

  String _getChildNameForBooking() =>
      _isSameAsCustomer ? '' : (_selectedChildName?.trim() ?? '');

  void _resetBooking() {
    setState(() {
      _currentStep = 0;
      _selectedSalon = null;
      _selectedDate = null;
      _selectedServices = [];
      _selectedBarber = null;
      _selectedSlot = null;
      _allTimeSlots = [];
      _showingVipNumber = false;
      _generatedVipNumber = 0;
      _selectedStartTime = '';
      _searchController.clear();
      _searchResults = List.from(_allSalons);
      _isInitialized = false;
      _servicesLoaded = false;
      _barbersLoaded = false;
      _availableBarbers = [];
      _salonServices = [];
      _holidays = {};
      _holidayNames = {};
      _isDateUnavailable = false;
      _isCheckingDate = false;
      _scheduleLoaded = false;
      _workingWeekdays = {};
      _calendarVersion++;
      _barberAvailability = {};
      _childNameController.clear();
      _selectedChildName = null;
      _isSameAsCustomer = true;
      _duplicateError = null;
      _slotErrorMessage = null;
      _slotErrorType = null;
      _appliedOffer = null;
      offerServiceIds = {};
      _discountAmount = 0;
      _originalTotalPrice = 0;
      _finalTotalPrice = 0;
      _preselectedServicesApplied = false;
      _availableOffersPerService.clear();
      _serviceOffers.clear();
      // ✅ Reset salon settings + rate
      _selectedSalonTimezone = _kDefaultSalonTimezone;
      _salonCurrencyCode = 'LKR';
      _exchangeRate = null;
    });
  }

  // ==================== STEP 0: SALON ====================

  Future<void> _loadAllSalons() async {
    setState(() {
      _isLoadingSalons = true;
      _allSalons = [];
    });

    try {
      final result = await supabase.rpc(
        'get_active_salons_for_booking',
        params: {'p_search_query': null, 'p_limit': 100, 'p_offset': 0},
      );

      if (!mounted) return;

      if (result != null && result.isNotEmpty) {
        final salons = List<Map<String, dynamic>>.from(result);
        setState(() {
          _allSalons = salons;
          _searchResults = List.from(salons);
          _isLoadingSalons = false;
        });
      } else {
        setState(() {
          _allSalons = [];
          _searchResults = [];
          _isLoadingSalons = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salons: $e');
      if (!mounted) return;
      setState(() {
        _allSalons = [];
        _searchResults = [];
        _isLoadingSalons = false;
      });
    }
  }

  Future<void> _searchSalons(String query) async {
    _salonSearchDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = List.from(_allSalons);
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _salonSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await supabase.rpc(
          'get_active_salons_for_booking',
          params: {
            'p_search_query': query.trim(),
            'p_limit': 50,
            'p_offset': 0,
          },
        );

        if (!mounted) return;

        setState(() {
          _searchResults = result != null
              ? List<Map<String, dynamic>>.from(result)
              : [];
          _isSearching = false;
        });
      } catch (e) {
        debugPrint('❌ Search error: $e');
        if (!mounted) return;
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _selectSalon(Map<String, dynamic> salon) async {
    final normalized = Map<String, dynamic>.from(salon);
    final dynamic rawId = normalized['id'];
    final int salonId = rawId is int
        ? rawId
        : (rawId is num
              ? rawId.toInt()
              : int.tryParse(rawId?.toString() ?? '') ?? 0);
    if (salonId <= 0) {
      _showErrorSnack('Invalid salon selection');
      return;
    }
    normalized['id'] = salonId;

    setState(() {
      _selectedSalon = normalized;
      _currentStep = 1;
      _servicesLoaded = false;
      _salonServices = [];
      _selectedServices = [];
      _selectedDate = null;
      _availableOffersPerService.clear();
      _serviceOffers.clear();
    });

    // ✅ Load salon settings (timezone + currency + rate) BEFORE services
    await _loadSalonSettings();
    await _loadSalonServices();
  }

  // ==================== STEP 1: SERVICE ====================

  Future<void> _loadSalonServices() async {
    if (_servicesLoaded) return;
    if (_selectedSalon == null) return;

    setState(() => _isLoadingServices = true);

    try {
      final dynamic rawSalonId = _selectedSalon!['id'];
      final int salonId = rawSalonId is int
          ? rawSalonId
          : (rawSalonId is num
                ? rawSalonId.toInt()
                : int.tryParse(rawSalonId?.toString() ?? '') ?? 0);

      if (salonId <= 0) {
        throw Exception('Invalid salon id: $rawSalonId');
      }

      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, is_active, category_id')
          .eq('salon_id', salonId)
          .eq('is_active', true);

      if (servicesResponse.isEmpty) {
        if (!mounted) return;
        setState(() {
          _salonServices = [];
          _isLoadingServices = false;
          _servicesLoaded = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('This salon has no services available yet.'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final serviceIds = servicesResponse.map((s) => s['id'] as int).toList();

      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, service_id, price, duration, salon_gender_id, salon_age_category_id, is_active',
          )
          .inFilter('service_id', serviceIds);

      final activeVariants = variantsResponse
          .where((v) => v['is_active'] != false)
          .toList();

      if (activeVariants.isEmpty) {
        if (!mounted) return;
        setState(() {
          _salonServices = [];
          _isLoadingServices = false;
          _servicesLoaded = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Services have no active variants. Please contact the salon.',
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final categoryIds = servicesResponse
          .map((s) => s['category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      Map<int, String> categoryMap = {};
      final Map<int, Map<String, dynamic>> categoryMeta = {};
      if (categoryIds.isNotEmpty) {
        try {
          final categoriesResponse = await supabase
              .from('salon_categories')
              .select('id, display_name, icon_name, color, display_order')
              .inFilter('id', categoryIds);

          for (var cat in categoriesResponse) {
            categoryMap[cat['id'] as int] =
                cat['display_name']?.toString() ?? 'Other';
            categoryMeta[cat['id'] as int] = {
              'icon_name': cat['icon_name'],
              'color': cat['color'],
              'display_order': (cat['display_order'] as num?)?.toInt() ?? 9999,
            };
          }
        } catch (e) {
          debugPrint('⚠️ Categories failed: $e');
        }
      }

      final genderIds = activeVariants
          .map((v) => v['salon_gender_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      Map<int, String> genderMap = {};
      if (genderIds.isNotEmpty) {
        try {
          final gendersResponse = await supabase
              .from('salon_genders')
              .select('id, display_name')
              .inFilter('id', genderIds);

          for (var g in gendersResponse) {
            genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('⚠️ Genders failed: $e');
        }
      }

      final ageIds = activeVariants
          .map((v) => v['salon_age_category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      Map<int, String> ageMap = {};
      final Map<int, String> ageRangeMap = {};
      if (ageIds.isNotEmpty) {
        try {
          final agesResponse = await supabase
              .from('salon_age_categories')
              .select('id, display_name, min_age, max_age')
              .inFilter('id', ageIds);

          for (var a in agesResponse) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
            ageRangeMap[a['id'] as int] = _ageRangeText(
              (a['min_age'] as num?)?.toInt(),
              (a['max_age'] as num?)?.toInt(),
            );
          }
        } catch (e) {
          debugPrint('⚠️ Age categories failed: $e');
        }
      }

      final Map<int, Map<String, dynamic>> groupedServices = {};

      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final categoryId = service['category_id'] as int?;
        final Map<String, dynamic>? catMeta = categoryId == null
            ? null
            : categoryMeta[categoryId];

        groupedServices[serviceId] = {
          'id': serviceId,
          'name': service['name']?.toString() ?? 'Service',
          'description': service['description']?.toString(),
          'category_id': categoryId,
          'category_name': categoryId != null
              ? (categoryMap[categoryId] ?? 'Other')
              : 'Other',
          'category_icon': catMeta == null ? null : catMeta['icon_name'],
          'category_color': catMeta == null ? null : catMeta['color'],
          'category_order': categoryId == null
              ? 99999
              : (catMeta == null ? 9999 : (catMeta['display_order'] as int)),
          'variants': [],
        };
      }

      for (var variant in activeVariants) {
        final serviceId = variant['service_id'] as int;
        final genderId = variant['salon_gender_id'] as int?;
        final ageId = variant['salon_age_category_id'] as int?;

        groupedServices[serviceId]?['variants'].add({
          'id': variant['id'],
          'gender': genderId != null ? (genderMap[genderId] ?? '') : '',
          'age': ageId != null ? (ageMap[ageId] ?? '') : '',
          'age_range': ageId != null ? (ageRangeMap[ageId] ?? '') : '',
          'price': (variant['price'] as num?)?.toDouble() ?? 0.0,
          'duration': variant['duration'] ?? 30,
        });
      }

      final servicesList = groupedServices.values
          .where((s) => (s['variants'] as List).isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _salonServices = servicesList;
        _isLoadingServices = false;
        _servicesLoaded = true;
      });

      unawaited(_preloadVariantOffers(servicesList));
    } catch (e, stackTrace) {
      debugPrint('❌ [SERVICE LOAD ERROR] $e');
      debugPrint('   Stack: $stackTrace');

      String errorMsg = 'Failed to load services';
      if (e is PostgrestException) {
        errorMsg = 'DB error: ${e.message}';
      } else {
        errorMsg = 'Error: ${e.toString().replaceFirst('Exception: ', '')}';
      }

      if (!mounted) return;
      setState(() {
        _isLoadingServices = false;
        _servicesLoaded = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) async {
    final int sid = service['id'] as int;
    final int vid = variant['id'] as int;
    final String serviceName = service['name']?.toString() ?? 'Service';
    final String gender = variant['gender']?.toString() ?? '';
    final String age = variant['age']?.toString() ?? '';
    final double price = (variant['price'] as num?)?.toDouble() ?? 0.0;
    final int duration = (variant['duration'] as num?)?.toInt() ?? 30;
    final key = _serviceKey(sid, vid);

    final existingIndex = _selectedServices.indexWhere(
      (s) => s['id'] == sid && s['variant_id'] == vid,
    );

    if (existingIndex >= 0) {
      setState(() {
        _selectedServices.removeAt(existingIndex);
        _serviceOffers.remove(key);
        _recalculateTotals();
      });
      return;
    }

    setState(() {
      _selectedServices.add({
        'id': sid,
        'name': serviceName,
        'variant_id': vid,
        'gender': gender,
        'age': age,
        'price': price,
        'duration': duration,
        'offer': null,
        'offer_id': null,
        'discount_amount': 0,
        'final_price': price,
      });
      _recalculateTotals();
    });

    var offers = _availableOffersPerService[key] ?? <Map<String, dynamic>>[];
    if (offers.isEmpty) {
      offers = await _loadOffersForService(sid, price, variantId: vid);
    }

    if (offers.isNotEmpty && mounted) {
      setState(() {
        _availableOffersPerService[key] = offers;
      });

      final claimedOffer = offers.firstWhere(
        (o) => o['is_claimed'] == true,
        orElse: () => <String, dynamic>{},
      );

      if (claimedOffer.isNotEmpty && claimedOffer['id'] != null) {
        debugPrint(
          '🎁 Auto-applying claimed offer: ${claimedOffer['title']} '
          '(ID: ${claimedOffer['id']})',
        );
        _applyOfferToService(sid, vid, claimedOffer);
      }
    }
  }

  Future<void> _preloadVariantOffers(
    List<Map<String, dynamic>> services,
  ) async {
    final tasks = <List<dynamic>>[];
    for (final svc in services) {
      for (final v in (svc['variants'] as List)) {
        tasks.add([svc['id'], v]);
      }
    }

    const batchSize = 8;
    for (int i = 0; i < tasks.length; i += batchSize) {
      if (!mounted) return;
      final chunk = tasks.skip(i).take(batchSize);
      await Future.wait(
        chunk.map((t) async {
          final int sid = t[0] as int;
          final Map v = t[1] as Map;
          final int vid = v['id'] as int;
          final double price = (v['price'] as num?)?.toDouble() ?? 0.0;
          final key = _serviceKey(sid, vid);
          if (_availableOffersPerService.containsKey(key)) return;

          final offers = await _loadOffersForService(
            sid,
            price,
            variantId: vid,
          );
          if (!mounted || offers.isEmpty) return;
          setState(() => _availableOffersPerService[key] = offers);
        }),
      );
    }
  }

  Future<void> _applyPreselectedServices() async {
    if (_preselectedServicesApplied) return;
    _preselectedServicesApplied = true;

    final toApply = _preselectedServices;
    if (toApply == null || toApply.isEmpty) return;
    if (_salonServices.isEmpty) return;

    for (final item in toApply) {
      final sid = item['service_id'] is int
          ? item['service_id'] as int
          : int.tryParse(item['service_id']?.toString() ?? '');
      final vid = item['variant_id'] is int
          ? item['variant_id'] as int
          : int.tryParse(item['variant_id']?.toString() ?? '');
      if (sid == null || vid == null) continue;

      Map<String, dynamic>? service;
      Map<String, dynamic>? variant;
      for (final s in _salonServices) {
        if (s['id'] == sid) {
          service = s;
          for (final v in (s['variants'] as List)) {
            if (v['id'] == vid) {
              variant = Map<String, dynamic>.from(v as Map);
              break;
            }
          }
          break;
        }
      }
      if (service == null || variant == null) continue;

      final already = _selectedServices.any(
        (x) => x['id'] == sid && x['variant_id'] == vid,
      );
      if (already) continue;

      await _toggleVariant(service, variant);
    }

    await _autoApplyClaimedOffers();
  }

  Future<void> _autoApplyClaimedOffers() async {
    debugPrint('🎁 [Auto-Apply] Checking claimed offers...');

    for (int i = 0; i < _selectedServices.length; i++) {
      final service = _selectedServices[i];
      final sid = service['id'] as int?;
      final vid = service['variant_id'] as int?;
      if (sid == null || vid == null) continue;

      if (service['offer_id'] != null) {
        debugPrint('   ✓ Service $sid already has offer');
        continue;
      }

      final key = _serviceKey(sid, vid);
      var offers = _availableOffersPerService[key] ?? [];

      if (offers.isEmpty) {
        final price = (service['price'] as num?)?.toDouble() ?? 0;
        offers = await _loadOffersForService(sid, price, variantId: vid);

        if (offers.isNotEmpty && mounted) {
          setState(() {
            _availableOffersPerService[key] = offers;
          });
        }
      }

      final claimed = offers.firstWhere(
        (o) => o['is_claimed'] == true,
        orElse: () => <String, dynamic>{},
      );

      if (claimed.isNotEmpty && claimed['id'] != null) {
        _applyOfferToService(sid, vid, claimed);
        debugPrint('   ✅ Auto-applied: ${claimed['title']} for service $sid');
      } else {
        debugPrint('   ℹ️ No claimed offer for service $sid');
      }
    }
  }

  // ==================== STEP 2: DATE ====================

  Future<void> _loadHolidays() async {
    if (_selectedSalon == null) return;
    try {
      final response = await supabase
          .from('salon_holidays')
          .select('holiday_date, name')
          .eq('salon_id', _selectedSalon!['id']);
      if (!mounted) return;
      setState(() {
        _holidays.clear();
        _holidayNames.clear();
        for (var holiday in response) {
          final date = DateTime.parse(holiday['holiday_date']);
          _holidays.add(date);
          _holidayNames[date] = holiday['name'];
        }
      });

      try {
        final schedules = await supabase
            .from('barber_schedules')
            .select('day_of_week')
            .eq('salon_id', _selectedSalon!['id'])
            .eq('is_working', true);
        if (!mounted) return;
        setState(() {
          _workingWeekdays = schedules
              .map<int>((r) => (r['day_of_week'] as num).toInt())
              .toSet();
          _scheduleLoaded = true;
        });
      } catch (e) {
        debugPrint('Error loading working weekdays: $e');
        _scheduleLoaded = false;
      }

      await _ensureDefaultDate();
    } catch (e) {
      debugPrint('Error loading holidays: $e');
    }
  }

  /// ✅ A day can be picked when it is not past (SALON time), not a holiday
  ///    and (if the schedule is known) at least one barber works that weekday.
  bool _isDaySelectable(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(_todayDate)) return false;
    if (_holidays.contains(d)) return false;
    if (_scheduleLoaded && !_workingWeekdays.contains(d.weekday)) return false;
    return true;
  }

  DateTime? _firstSelectableDate() {
    for (int i = 0; i <= 30; i++) {
      final d = _todayDate.add(Duration(days: i));
      if (_isDaySelectable(d)) return d;
    }
    return null;
  }

  Future<void> _ensureDefaultDate() async {
    if (!mounted) return;
    if (_selectedDate != null && _isDaySelectable(_selectedDate!)) return;

    final first = _firstSelectableDate();
    setState(() {
      _selectedDate = first;
      _isDateUnavailable = false;
      _unavailableReason = null;
      _calendarVersion++;
    });
    if (first != null) {
      await _checkDateAvailability(first);
    }
  }

  Future<void> _checkDateAvailability(DateTime date) async {
    if (_selectedSalon == null) return;
    if (mounted) setState(() => _isCheckingDate = true);
    try {
      final schedules = await supabase
          .from('barber_schedules')
          .select('barber_id')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('day_of_week', date.weekday)
          .eq('is_working', true);
      if (!mounted) return;
      if (_selectedDate != null && !DateUtils.isSameDay(_selectedDate, date)) {
        return;
      }
      setState(() {
        _isCheckingDate = false;
        _isDateUnavailable = schedules.isEmpty;
        _unavailableReason = schedules.isEmpty
            ? 'No barbers working on ${DateFormat('EEEE').format(date)}'
            : null;
        _barbersLoaded = false;
        _availableBarbers = [];
        _barberAvailability = {};
        _selectedBarber = null;
      });
    } catch (e) {
      debugPrint('Error checking date availability: $e');
      if (mounted) setState(() => _isCheckingDate = false);
    }
  }

  // ==================== STEP 3: BARBER ====================

  Future<Map<String, dynamic>> _checkBarberFullAvailability(
    String barberId,
    DateTime date,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    Map<String, dynamic> result = {
      'is_available': true,
      'reason': null,
      'has_special_schedule': false,
      'has_special_break': false,
    };

    try {
      final roleCheck = await supabase
          .from('user_roles')
          .select('''
            status,
            roles!inner (
              name
            )
          ''')
          .eq('user_id', barberId)
          .eq('roles.name', 'barber')
          .maybeSingle();

      if (roleCheck == null) {
        result['is_available'] = false;
        result['reason'] = 'Currently unavailable';
        return result;
      }

      final status = roleCheck['status'] as String? ?? 'active';
      if (status != 'active') {
        result['is_available'] = false;
        result['reason'] = 'Currently unavailable';
        return result;
      }

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', barberId)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          result['is_available'] = false;
          result['reason'] = 'Currently unavailable';
          return result;
        }
        if (profileCheck['is_active'] == false) {
          result['is_available'] = false;
          result['reason'] = 'Currently unavailable';
          return result;
        }
      }

      final salonBarberCheck = await supabase
          .from('salon_barbers')
          .select('status')
          .eq('barber_id', barberId)
          .eq('salon_id', _selectedSalon!['id'])
          .maybeSingle();

      if (salonBarberCheck != null) {
        final salonStatus = salonBarberCheck['status'] as String? ?? 'active';
        if (salonStatus != 'active') {
          result['is_available'] = false;
          result['reason'] = 'Currently unavailable';
          return result;
        }
      } else {
        result['is_available'] = false;
        result['reason'] = 'Currently unavailable';
        return result;
      }

      final scheduleResult = await supabase.rpc(
        'get_barber_effective_schedule',
        params: {
          'p_barber_id': barberId,
          'p_salon_id': _selectedSalon!['id'],
          'p_date': dateStr,
        },
      );

      final schedule = scheduleResult is List && scheduleResult.isNotEmpty
          ? scheduleResult[0]
          : scheduleResult;

      if (schedule != null) {
        result['has_special_schedule'] =
            schedule['has_special_schedule'] == true;
        result['has_special_break'] = schedule['has_special_break'] == true;

        final leaveType = schedule['leave_type'] as String?;
        if (leaveType == 'full_day') {
          result['is_available'] = false;
          result['reason'] = 'On leave on this date';
          return result;
        }

        final workStart = schedule['work_start'] as String?;
        if (workStart == null) {
          result['is_available'] = false;
          result['reason'] = 'Not working on this date';
          return result;
        }
      }

      result['is_available'] = true;
      result['reason'] = null;
      return result;
    } catch (e) {
      debugPrint('Error checking barber availability: $e');
      result['is_available'] = false;
      result['reason'] = 'Could not check availability';
      return result;
    }
  }

  Future<void> _loadAvailableBarbers() async {
    if (_isLoadingBarbers) return;
    if (_barbersLoaded && _availableBarbers.isNotEmpty) return;

    setState(() => _isLoadingBarbers = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _availableBarbers = [];
          _isLoadingBarbers = false;
          _barbersLoaded = true;
        });
        return;
      }

      final result = await supabase.rpc(
        'get_active_barbers_for_salon',
        params: {
          'p_salon_id': _selectedSalon!['id'],
          'p_date': DateFormat(
            'yyyy-MM-dd',
          ).format(_selectedDate ?? _todayDate),
        },
      );

      if (!mounted) return;

      if (result == null || result.isEmpty) {
        setState(() {
          _availableBarbers = [];
          _isLoadingBarbers = false;
          _barbersLoaded = true;
        });
        return;
      }

      List<Map<String, dynamic>> barberList = List<Map<String, dynamic>>.from(
        result,
      );

      for (var i = 0; i < barberList.length; i++) {
        barberList[i]['id'] = barberList[i]['barber_id'];
      }

      final dateToCheck = _selectedDate ?? _todayDate;

      for (var i = 0; i < barberList.length; i++) {
        final barber = barberList[i];
        final barberId = barber['barber_id'];

        final availability = await _checkBarberFullAvailability(
          barberId,
          dateToCheck,
        );

        _barberAvailability[barberId] = availability;

        barberList[i]['is_available'] = availability['is_available'];
        barberList[i]['unavailable_reason'] = availability['reason'];
        barberList[i]['has_special_schedule'] =
            availability['has_special_schedule'];
        barberList[i]['has_special_break'] = availability['has_special_break'];
      }

      barberList.sort((a, b) {
        if (a['is_available'] && !b['is_available']) return -1;
        if (!a['is_available'] && b['is_available']) return 1;
        return (b['avg_rating'] as num).compareTo(a['avg_rating'] as num);
      });

      if (!mounted) return;
      setState(() {
        _availableBarbers = barberList;
        _isLoadingBarbers = false;
        _barbersLoaded = true;
      });
    } catch (e) {
      debugPrint('❌ Error loading barbers: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingBarbers = false;
        _barbersLoaded = false;
        _availableBarbers = [];
      });
    }
  }

  // ==================== STEP 4: PERSON ====================

  Future<void> _checkDuplicateBooking() async {
    if (_selectedDate == null) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final childName = _isSameAsCustomer
        ? ''
        : (_selectedChildName?.trim() ?? '');

    if (!_isSameAsCustomer && childName.isEmpty) return;

    setState(() => _isCheckingDuplicate = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      // ✅ Match both 'myself' and named child
      final query = supabase
          .from('appointments')
          .select('id')
          .eq('customer_id', user.id)
          .eq('appointment_date', dateStr)
          .eq('is_vip', true)
          .not('status', 'in', '("cancelled","no_show")');

      final existing = childName.isEmpty
          ? await query.or('child_name.is.null,child_name.eq.')
          : await query.eq('child_name', childName);

      if (!mounted) return;
      setState(() {
        _duplicateError = existing.isNotEmpty
            ? '⚠️ You already have a VIP booking for '
                  '${childName.isEmpty ? "yourself" : childName} '
                  'on ${DateFormat('MMM dd').format(_selectedDate!)}.'
            : null;
      });
    } catch (e) {
      debugPrint('❌ [VIP] Error checking duplicate: $e');
    } finally {
      if (mounted) setState(() => _isCheckingDuplicate = false);
    }
  }

  bool _canProceedToTimeSlot() =>
      !_isCheckingDuplicate &&
      _duplicateError == null &&
      (_isSameAsCustomer ||
          (_selectedChildName != null &&
              _selectedChildName!.trim().isNotEmpty));

  Future<bool> _validateAndProceed() async {
    await _checkDuplicateBooking();
    return _duplicateError == null;
  }

  // ==================== STEP 5: TIME SLOT ====================

  Future<void> _loadAvailableSlots() async {
    if (_selectedDate == null) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Please select a date first.';
          _slotErrorType = 'date';
        });
      }
      return;
    }
    if (_selectedBarber == null) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Please select a barber first.';
          _slotErrorType = 'barber';
        });
      }
      return;
    }
    if (_selectedSalon == null) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Salon not selected.';
          _slotErrorType = 'general';
        });
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoadingSlots = true;
      _allTimeSlots = [];
      _selectedSlot = null;
      _showingVipNumber = false;
      _generatedVipNumber = 0;
      _selectedStartTime = '';
      _slotErrorMessage = null;
      _slotErrorType = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _isLoadingSlots = false;
            _slotErrorMessage = 'Please login again.';
            _slotErrorType = 'general';
          });
        }
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final totalDuration = _calculateTotalDuration();

      final barberId = _selectedBarber!['barber_id'] ?? _selectedBarber!['id'];

      final scheduleResult = await supabase.rpc(
        'get_barber_effective_schedule',
        params: {
          'p_barber_id': barberId,
          'p_salon_id': _selectedSalon!['id'],
          'p_date': dateStr,
        },
      );

      Map<String, dynamic> effectiveSchedule = {};
      if (scheduleResult != null) {
        if (scheduleResult is List && scheduleResult.isNotEmpty) {
          final firstItem = scheduleResult[0];
          if (firstItem is Map) {
            effectiveSchedule = Map<String, dynamic>.from(firstItem);
          }
        } else if (scheduleResult is Map) {
          effectiveSchedule = Map<String, dynamic>.from(scheduleResult);
        }
      }

      final leaveType = effectiveSchedule['leave_type'] as String?;
      if (leaveType == 'full_day') {
        if (mounted) {
          setState(() {
            _isLoadingSlots = false;
            _slotErrorMessage =
                '${_selectedBarber!['full_name']} is on leave on this date.';
            _slotErrorType = 'barber';
          });
        }
        return;
      }

      String workStartUTC =
          effectiveSchedule['work_start']?.toString() ?? '09:00';
      String workEndUTC =
          effectiveSchedule['work_end']?.toString() ?? '18:00';

      if (workStartUTC.length > 5) workStartUTC = workStartUTC.substring(0, 5);
      if (workEndUTC.length > 5) workEndUTC = workEndUTC.substring(0, 5);

      final workStartParts = workStartUTC.split(':');
      final workEndParts = workEndUTC.split(':');
      int workStartHour = int.parse(workStartParts[0]);
      int workStartMinute = workStartParts.length > 1
          ? int.parse(workStartParts[1])
          : 0;
      int workEndHour = int.parse(workEndParts[0]);
      int workEndMinute = workEndParts.length > 1
          ? int.parse(workEndParts[1])
          : 0;

      List<Map<String, dynamic>> breakRanges = [];

      String? breakStartUTC =
          effectiveSchedule['lunch_break_start']?.toString();
      String? breakEndUTC = effectiveSchedule['lunch_break_end']?.toString();
      bool hasSpecialBreak = effectiveSchedule['has_special_break'] == true;

      if (breakStartUTC != null &&
          breakEndUTC != null &&
          breakStartUTC.isNotEmpty &&
          breakEndUTC.isNotEmpty) {
        if (breakStartUTC.length > 5) {
          breakStartUTC = breakStartUTC.substring(0, 5);
        }
        if (breakEndUTC.length > 5) breakEndUTC = breakEndUTC.substring(0, 5);

        final breakStartParts = breakStartUTC.split(':');
        final breakEndParts = breakEndUTC.split(':');

        breakRanges.add({
          'start_hour': int.parse(breakStartParts[0]),
          'start_min': breakStartParts.length > 1
              ? int.parse(breakStartParts[1])
              : 0,
          'end_hour': int.parse(breakEndParts[0]),
          'end_min': breakEndParts.length > 1 ? int.parse(breakEndParts[1]) : 0,
          'type': hasSpecialBreak ? 'special' : 'regular',
        });
      }

      final existingAppointments = await supabase
          .from('appointments')
          .select('id, start_time, end_time, vip_queue_number, is_vip, status')
          .eq('barber_id', barberId)
          .eq('appointment_date', dateStr)
          .eq('is_vip', true)
          .neq('status', 'cancelled')
          .neq('status', 'no_show')
          .order('start_time', ascending: true);

      List<Map<String, dynamic>> bookedRanges = [];
      for (final apt in existingAppointments) {
        String startTimeUTC = apt['start_time'].toString();
        String endTimeUTC = apt['end_time'].toString();

        if (startTimeUTC.length > 5) {
          startTimeUTC = startTimeUTC.substring(0, 5);
        }
        if (endTimeUTC.length > 5) {
          endTimeUTC = endTimeUTC.substring(0, 5);
        }

        final startParts = startTimeUTC.split(':');
        final endParts = endTimeUTC.split(':');

        bookedRanges.add({
          'start_hour': int.parse(startParts[0]),
          'start_min': startParts.length > 1 ? int.parse(startParts[1]) : 0,
          'end_hour': int.parse(endParts[0]),
          'end_min': endParts.length > 1 ? int.parse(endParts[1]) : 0,
          'vip_number': apt['vip_queue_number'] ?? 0,
          'is_vip': true,
        });
      }

      final List<Map<String, dynamic>> slots = [];
      int slotNumber = 1;

      DateTime currentSlotStartUTC = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        workStartHour,
        workStartMinute,
      );

      DateTime workEndDateTimeUTC = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        workEndHour,
        workEndMinute,
      );

      if (workEndHour < workStartHour ||
          (workEndHour == workStartHour && workEndMinute <= workStartMinute)) {
        workEndDateTimeUTC = workEndDateTimeUTC.add(const Duration(days: 1));
      }

      bool isOverlapWithRanges(
        int startMin,
        int endMin,
        List<Map<String, dynamic>> ranges,
      ) {
        for (final range in ranges) {
          final rangeStartMin =
              (range['start_hour'] as int) * 60 + (range['start_min'] as int);
          int rangeEndMin =
              (range['end_hour'] as int) * 60 + (range['end_min'] as int);

          if (rangeEndMin < rangeStartMin) {
            rangeEndMin += 24 * 60;
          }

          int effectiveEndMin = endMin;
          if (endMin < startMin) {
            effectiveEndMin = endMin + 24 * 60;
          }

          if (startMin < rangeEndMin && effectiveEndMin > rangeStartMin) {
            return true;
          }
        }
        return false;
      }

      while (currentSlotStartUTC.isBefore(workEndDateTimeUTC)) {
        final slotStartUTC = currentSlotStartUTC;
        final slotEndUTC = currentSlotStartUTC.add(
          Duration(minutes: totalDuration),
        );

        if (slotEndUTC.isAfter(workEndDateTimeUTC)) {
          break;
        }

        int slotStartMin = slotStartUTC.hour * 60 + slotStartUTC.minute;
        int slotEndMin = slotEndUTC.hour * 60 + slotEndUTC.minute;

        bool isOverlappingWithBookings = isOverlapWithRanges(
          slotStartMin,
          slotEndMin,
          bookedRanges,
        );

        bool isOverlappingWithBreak = isOverlapWithRanges(
          slotStartMin,
          slotEndMin,
          breakRanges,
        );

        final utcStartStr =
            '${slotStartUTC.hour.toString().padLeft(2, '0')}:${slotStartUTC.minute.toString().padLeft(2, '0')}:00';

        final localSlotStart = TimezoneService.utcToLocalDateTimeForDateWithTimezone(
          utcStartStr,
          _selectedDate!,
          _selectedSalonTimezone,
        );

        bool isPast = _isSlotInPast(localSlotStart, totalDuration);

        bool isAvailable =
            !isOverlappingWithBookings && !isOverlappingWithBreak && !isPast;

        String statusText = '';
        int displayVipNumber = 0;

        if (isOverlappingWithBookings) {
          statusText = 'Booked';
          for (final booked in bookedRanges) {
            final bookedStartMin =
                (booked['start_hour'] as int) * 60 +
                (booked['start_min'] as int);
            final bookedEndMin =
                (booked['end_hour'] as int) * 60 + (booked['end_min'] as int);
            if (slotStartMin < bookedEndMin && slotEndMin > bookedStartMin) {
              displayVipNumber = booked['vip_number'];
              break;
            }
          }
        } else if (isOverlappingWithBreak) {
          statusText =
              breakRanges.isNotEmpty && breakRanges.first['type'] == 'special'
              ? 'Special Break'
              : 'Break';
        } else if (isPast) {
          statusText = 'Time Passed';
        } else {
          int vipCountBefore = 0;
          for (final booked in bookedRanges) {
            if (booked['is_vip'] == true) {
              final bookedStartMin =
                  (booked['start_hour'] as int) * 60 +
                  (booked['start_min'] as int);
              if (bookedStartMin < slotStartMin) {
                vipCountBefore++;
              }
            }
          }
          displayVipNumber = vipCountBefore + 1;
        }

        final localStartDateTime =
            TimezoneService.utcToLocalDateTimeForDateWithTimezone(
          utcStartStr,
          _selectedDate!,
          _selectedSalonTimezone,
        );

        final utcEndStr =
            '${slotEndUTC.hour.toString().padLeft(2, '0')}:${slotEndUTC.minute.toString().padLeft(2, '0')}:00';

        final localEndDateTime =
            TimezoneService.utcToLocalDateTimeForDateWithTimezone(
          utcEndStr,
          _selectedDate!,
          _selectedSalonTimezone,
        );

        final displayStartTime = _formatTimeWithAmPm(localStartDateTime);
        final displayEndTime = _formatTimeWithAmPm(localEndDateTime);

        slots.add({
          'start_time_display': displayStartTime,
          'end_time_display': displayEndTime,
          'utc_start_time': utcStartStr,
          'utc_end_time': utcEndStr,
          'slot_number': slotNumber,
          'vip_number': displayVipNumber,
          'is_available': isAvailable,
          'is_past': isPast,
          'is_booked': isOverlappingWithBookings,
          'is_break': isOverlappingWithBreak,
          'status_text': statusText,
          'duration': totalDuration,
        });

        slotNumber++;
        currentSlotStartUTC = currentSlotStartUTC.add(
          Duration(minutes: totalDuration),
        );
      }

      final availableSlots = slots
          .where((s) => s['is_available'] == true)
          .toList();
      final hasAnySlots = slots.isNotEmpty;
      final hasAvailableSlots = availableSlots.isNotEmpty;

      if (mounted) {
        setState(() {
          _allTimeSlots = slots;

          if (!hasAnySlots) {
            _slotErrorMessage =
                'No time slots available on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\n'
                'The barber has no working hours on this date.';
            _slotErrorType = 'barber';
          } else if (!hasAvailableSlots) {
            final allBooked = slots.every((s) => s['is_booked'] == true);
            final allPast = slots.every((s) => s['is_past'] == true);
            final allBreak = slots.every((s) => s['is_break'] == true);

            if (allBooked) {
              _slotErrorMessage =
                  'All VIP slots on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)} are booked.\n\n'
                  'Please select another date or try tomorrow.';
              _slotErrorType = 'date_full';
            } else if (allPast) {
              _slotErrorMessage =
                  'All VIP slots on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)} have passed.\n\n'
                  'Please select another date.';
              _slotErrorType = 'overflow';
            } else if (allBreak) {
              _slotErrorMessage =
                  'Barber is on break during all available hours on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\n'
                  'Please try another date.';
              _slotErrorType = 'date_full';
            } else {
              _slotErrorMessage =
                  'No available VIP slots on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\n'
                  'Some slots may be booked or the barber is on break. Please try another date or barber.';
              _slotErrorType = 'date_full';
            }
          } else {
            _slotErrorMessage = null;
            _slotErrorType = null;
          }

          _isLoadingSlots = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [VIP] Load slots error: $e');
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage =
              'Failed to load time slots.\n\nError: ${e.toString().replaceFirst('Exception: ', '')}';
          _slotErrorType = 'general';
          _allTimeSlots = [];
        });
      }
    } finally {
      if (mounted && _isLoadingSlots) {
        setState(() => _isLoadingSlots = false);
      }
    }
  }

  Future<void> _bookSlot(Map<String, dynamic> slot) async {
    if (!slot['is_available']) return;

    setState(() {
      _isLoadingSlots = true;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final selectedStartTime = slot['utc_start_time'];
      final selectedStartMin =
          int.parse(selectedStartTime.split(':')[0]) * 60 +
          int.parse(selectedStartTime.split(':')[1]);

      final barberId = _selectedBarber!['barber_id'] ?? _selectedBarber!['id'];

      final existingVIP = await supabase
          .from('appointments')
          .select('start_time, vip_queue_number')
          .eq('barber_id', barberId)
          .eq('appointment_date', dateStr)
          .eq('is_vip', true)
          .neq('status', 'cancelled')
          .neq('status', 'no_show')
          .order('start_time', ascending: true);

      int vipNumber = 1;
      for (final vip in existingVIP) {
        String vipStartTime = vip['start_time'].toString();
        if (vipStartTime.length > 5) {
          vipStartTime = vipStartTime.substring(0, 5);
        }
        final vipStartParts = vipStartTime.split(':');
        final vipStartMin =
            int.parse(vipStartParts[0]) * 60 + int.parse(vipStartParts[1]);
        if (vipStartMin < selectedStartMin) {
          vipNumber++;
        } else {
          break;
        }
      }

      if (mounted) {
        setState(() {
          _selectedSlot = slot;
          _selectedStartTime = slot['start_time_display'];
          _generatedVipNumber = vipNumber;
          _showingVipNumber = true;
          _isLoadingSlots = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _selectedSlot = slot;
          _selectedStartTime = slot['start_time_display'];
          _generatedVipNumber = slot['vip_number'];
          _showingVipNumber = true;
        });
      }
    }
  }

  // ==================== STEP 6: CONFIRM ====================

  Future<void> _confirmBooking() async {
    if (!mounted) return;
    setState(() => _isBooking = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please login');

      final barberId = _selectedBarber!['barber_id'] ?? _selectedBarber!['id'];

      final utcStartTime = _selectedSlot!['utc_start_time'];
      final utcEndTime = _selectedSlot!['utc_end_time'];

      final variantIds = _selectedServices
          .map((s) => s['variant_id'])
          .whereType<int>()
          .toList();

      if (variantIds.isEmpty) {
        throw Exception(
          'No valid services selected. Please go back and select services.',
        );
      }

      if (variantIds.length != _selectedServices.length) {
        throw Exception(
          'Some services have invalid variants. Please re-select your services.',
        );
      }

      final offerIds = _selectedServices
          .map((s) => s['offer_id'] as int?)
          .toList();

      final result = await supabase.rpc(
        'create_vip_booking',
        params: {
          'p_customer_id': user.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': barberId,
          'p_variant_ids': variantIds,
          'p_appointment_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
          'p_utc_start_time': utcStartTime,
          'p_utc_end_time': utcEndTime,
          'p_child_name': _getChildNameForBooking(),
          'p_notes': null,
          'p_offer_ids': offerIds,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final confirmedVipNumber =
            result['vip_number'] ?? _generatedVipNumber;

        // ✅ NEW: Extract confirmed amounts from response
        final confirmedRate =
            (result['exchange_rate_at_booking'] as num?)?.toDouble();
        final confirmedPrice =
            (result['price'] as num?)?.toDouble() ?? _getDisplayTotalPrice();
        final confirmedUserAmount =
            (confirmedRate != null &&
                confirmedRate > 0 &&
                _userCurrencyCode != _salonCurrencyCode)
            ? confirmedPrice * confirmedRate
            : null;
        final confirmedBookingNumber = result['booking_number']?.toString();

        setState(() => _isBooking = false);

        // ✅ NEW: Success dialog with dual currency
        _showVipBookingSuccessDialog(
          vipNumber: confirmedVipNumber,
          confirmedPrice: confirmedPrice,
          confirmedUserAmount: confirmedUserAmount,
          bookingNumber: confirmedBookingNumber,
        );
      } else {
        final errorMessage = result['message'] ?? 'VIP booking failed';
        final errorCode = result['error_code']?.toString() ?? '';
        throw Exception(
          errorCode.isNotEmpty ? '$errorMessage ($errorCode)' : errorMessage,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  // ✅ NEW: Success dialog with confirmed amounts
  void _showVipBookingSuccessDialog({
    required int vipNumber,
    required double confirmedPrice,
    double? confirmedUserAmount,
    String? bookingNumber,
  }) {
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.star,
            color: Colors.amber,
            size: 48,
          ),
        ),
        title: Text(
          '⭐ VIP Booking Confirmed!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bookingNumber != null) ...[
                Text(
                  'Booking #$bookingNumber',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.shade300,
                      Colors.amber.shade600,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'VIP-$vipNumber',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Amount',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                        Text(
                          _formatPrice(confirmedPrice),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    if (confirmedUserAmount != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '≈ Your currency',
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                          Text(
                            _formatUserPrice(confirmedUserAmount),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: isDark
                                ? Colors.orange.shade300
                                : Colors.orange.shade700,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Payment will be charged in $_salonCurrencyCode',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade700,
                              ),
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
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildConfirmationTile(
    IconData icon,
    String title,
    String value,
    dynamic subtitle,
  ) {
    final isDark = context.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppTheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (subtitle != null && subtitle is String) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
                if (subtitle != null && subtitle is Widget) subtitle,
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getServiceIcon(String? name) {
    if (name == null) return Icons.content_cut;
    final n = name.toLowerCase();
    if (n.contains('hair')) return Icons.content_cut;
    if (n.contains('face')) return Icons.face;
    if (n.contains('shave')) return Icons.face_retouching_natural;
    if (n.contains('massage')) return Icons.spa;
    return Icons.build;
  }

  /// ✅ Salon opening hours — SALON timezone, NOT user timezone
  String _getSalonLocalTime(Map<String, dynamic> salon) {
    final openTimeUTC = salon['open_time']?.toString() ?? '09:00:00';
    final closeTimeUTC = salon['close_time']?.toString() ?? '18:00:00';
    final referenceDate = _selectedDate ?? _todayDate;

    // ✅ FIXED: use SALON timezone
    final tz = _selectedSalonTimezone.isNotEmpty
        ? _selectedSalonTimezone
        : _kDefaultSalonTimezone;

    final openLocal = TimezoneService.utcToLocalTimeForDateWithTimezone(
      openTimeUTC,
      referenceDate,
      tz,
    );
    final closeLocal = TimezoneService.utcToLocalTimeForDateWithTimezone(
      closeTimeUTC,
      referenceDate,
      tz,
    );

    return '$openLocal - $closeLocal';
  }

  String _formatTimeWithAmPm(DateTime time) {
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final displayHour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$displayHour:${time.minute.toString().padLeft(2, '0')} $period';
  }

  bool _isSlotInPast(DateTime localSlotStart, int durationMinutes) {
    final now = DateTime.now();
    final slotEnd = localSlotStart.add(Duration(minutes: durationMinutes));

    if (slotEnd.isBefore(now) || slotEnd.isAtSameMomentAs(now)) {
      return true;
    }

    if (localSlotStart.isBefore(now) && slotEnd.isAfter(now)) {
      return true;
    }

    return false;
  }

  // ============================================
  // SHARED UI HELPERS
  // ============================================

  Widget _buildStepTitle(
    bool isDark,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
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
    );
  }

  Widget _buildSelectedDateRow(bool isDark) {
    if (_selectedDate == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 18, color: _secondaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
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

  Widget _buildBottomBar({
    required bool isDark,
    required bool enabled,
    required VoidCallback onPressed,
    required Widget child,
    bool backEnabled = true,
  }) {
    const double buttonHeight = 44;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: buttonHeight,
            child: OutlinedButton(
              onPressed: backEnabled
                  ? () => setState(() {
                      if (_currentStep > 0) _currentStep--;
                    })
                  : null,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: AppTheme.primary,
                side: BorderSide(
                  color: backEnabled ? AppTheme.primary : Colors.grey,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Icon(Icons.arrow_back, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: buttonHeight,
              child: ElevatedButton(
                onPressed: enabled ? onPressed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enabled
                      ? AppTheme.primary
                      : (isDark ? Colors.grey[700] : Colors.grey[400]),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (screenWidth < 300) return const Scaffold(body: SizedBox.shrink());

    final isMobile = screenWidth < 600;
    final isDark = context.isDarkMode;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : _bgLight,
        appBar: AppBar(
          title: const Text('VIP Booking'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Loading timezone...',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final stepSize = isMobile ? 32.0 : 42.0;
    final iconSize = isMobile ? 16.0 : 20.0;
    final stepFontSize = isMobile ? 9.0 : 11.0;
    final connectorWidth = isMobile ? 20.0 : 35.0;
    final showLabels = !isMobile;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : _bgLight,
      appBar: AppBar(
        title: Text(
          'VIP Booking',
          style: TextStyle(
            fontSize: isMobile ? 18 : 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_currentStep > 0)
            TextButton(
              onPressed: _resetBooking,
              child: Text(
                'Reset',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 300) return const SizedBox.shrink();

            final double safeHeight =
                (constraints.maxHeight.isFinite && constraints.maxHeight >= 200)
                ? constraints.maxHeight
                : 600.0;

            return OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: safeHeight,
              child: SizedBox(
                height: safeHeight,
                child: _isWeb
                    ? _buildWebLayout()
                    : Column(
                        children: [
                          _buildStepIndicatorRow(
                            isMobile,
                            stepSize,
                            iconSize,
                            stepFontSize,
                            connectorWidth,
                            showLabels,
                          ),
                          Expanded(child: _buildContent()),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            _buildStepIndicatorRow(false, 42, 20, 11, 35, true),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicatorRow(
    bool isMobile,
    double stepSize,
    double iconSize,
    double stepFontSize,
    double connectorWidth,
    bool showLabels,
  ) {
    const labels = [
      'Salon',
      'Service',
      'Date',
      'Barber',
      'Person',
      'Time',
      'Confirm',
    ];
    const icons = [
      Icons.store,
      Icons.content_cut,
      Icons.calendar_today,
      Icons.person,
      Icons.badge,
      Icons.access_time,
      Icons.check_circle,
    ];

    final children = <Widget>[];
    for (int i = 0; i < 7; i++) {
      children.add(
        _buildStepIndicatorResponsive(
          i,
          showLabels ? labels[i] : '',
          icons[i],
          stepSize,
          iconSize,
          stepFontSize,
        ),
      );
      if (i < 6) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: _currentStep > i ? AppTheme.primary : Colors.grey[300],
            ),
          ),
        );
      }
    }

    return Container(
      color: context.cardColor,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 12 : 16,
      ),
      child: Row(children: children),
    );
  }

  Widget _buildStepIndicatorResponsive(
    int step,
    String label,
    IconData icon,
    double size,
    double iconSize,
    double fontSize,
  ) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;
    final isDark = context.isDarkMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? AppTheme.primary
                : (isActive
                      ? AppTheme.primary.withValues(alpha: 0.1)
                      : (isDark ? Colors.grey[800] : Colors.grey[200])),
            border: Border.all(
              color: isActive
                  ? AppTheme.primary
                  : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
              width: isActive ? 2 : 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: iconSize, color: Colors.white)
                : Icon(
                    icon,
                    size: iconSize,
                    color: isActive ? AppTheme.primary : Colors.grey[500],
                  ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              color: isActive
                  ? AppTheme.primary
                  : (isDark ? Colors.white60 : Colors.grey[500]),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280) return const SizedBox.shrink();

        final double safeHeight =
            (constraints.maxHeight.isFinite && constraints.maxHeight >= 200)
            ? constraints.maxHeight
            : 600.0;

        return OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: safeHeight,
          child: SizedBox(
            height: safeHeight,
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildSalonSearchStep(),
                _buildServiceSelectionStep(),
                _buildDateSelectionStep(),
                _buildBarberSelectionStep(),
                _buildPersonSelectionStep(),
                _buildTimeSlotStep(),
                _buildConfirmationStep(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // STEP 0: SALON SEARCH
  // ============================================

  Widget _buildSalonSearchStep() {
    final isDark = context.isDarkMode;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _searchSalons,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Search salons by name or address...',
              hintStyle: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
              prefixIcon: Icon(
                Icons.search,
                color: isDark ? Colors.white70 : Colors.grey[400],
                size: 22,
              ),
              suffixIcon: _isSearching
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: isDark ? Colors.white70 : Colors.grey[400],
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _salonSearchDebounce?.cancel();
                              setState(() {
                                _searchResults = List.from(_allSalons);
                                _isSearching = false;
                              });
                            },
                          )
                        : null),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoadingSalons
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Loading salons...',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _searchResults.isEmpty && !_isSearching && _allSalons.isEmpty
              ? _buildEmptyState(isDark)
              : _searchResults.isEmpty && !_isSearching && _allSalons.isNotEmpty
              ? _buildNoResultsState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) =>
                      _buildSalonCard(_searchResults[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_mall_directory,
              size: 80,
              color: isDark ? Colors.white30 : Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              'No salons available',
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.white60 : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No active salons found',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAllSalons,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: isDark ? Colors.white30 : Colors.grey[300],
            ),
            const SizedBox(height: 20),
            Text(
              'No salons found matching "${_searchController.text}"',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                _salonSearchDebounce?.cancel();
                setState(() {
                  _searchResults = List.from(_allSalons);
                  _isSearching = false;
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Search'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalonCard(Map<String, dynamic> salon) {
    final isDark = context.isDarkMode;
    final logoUrl = salon['logo_url'];
    final avgRating = (salon['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final totalBookings = salon['total_bookings'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _selectSalon(salon),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  image: logoUrl != null && logoUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(logoUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: logoUrl == null || logoUrl.isEmpty
                    ? Center(
                        child: Text(
                          (salon['name'] as String?)
                                  ?.substring(0, 1)
                                  .toUpperCase() ??
                              'S',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salon['name'] ?? 'Salon',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (salon['address'] != null)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: isDark ? Colors.white60 : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              salon['address'],
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: isDark ? Colors.white60 : Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getSalonLocalTime(salon),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: isDark
                              ? Colors.amber.shade300
                              : Colors.amber[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          avgRating > 0 ? avgRating.toStringAsFixed(1) : 'New',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.event_available,
                          size: 14,
                          color: isDark ? Colors.white60 : Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$totalBookings bookings',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 28,
                color: isDark ? Colors.white30 : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // STEP 1: SERVICE SELECTION
  // ============================================

  Widget _buildServiceSelectionStep() {
    final isDark = context.isDarkMode;
    final tree = _buildServiceTree();

    return Column(
      children: [
        if (_selectedServices.isEmpty)
          _buildStepTitle(
            isDark,
            Icons.content_cut,
            'Choose your services',
            'Tick the options you want',
          ),

        if (_selectedServices.isNotEmpty)
          GestureDetector(
            onTap: () => _showSelectedServicesSheet(),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_selectedServices.length}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedServices.length > 1
                              ? 'Services selected'
                              : 'Service selected',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          () {
                            final names = _selectedServices
                                .map((s) => s['name']?.toString() ?? '')
                                .toList();
                            final shown = names.take(2).join(', ');
                            return names.length > 2
                                ? '$shown +${names.length - 2} more'
                                : shown;
                          }(),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_discountAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'You save ${_formatPrice(_discountAmount)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.green.shade300
                                    : Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ✅ UPDATED: dual display in panel
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_discountAmount > 0)
                        Text(
                          _formatPrice(_calculateTotalPrice()),
                          style: TextStyle(
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      Text(
                        _formatPrice(_getDisplayTotalPrice()),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      if (_showApprox)
                        Text(
                          '≈ ${_formatUserPrice(_getDisplayTotalPrice() * _exchangeRate!)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                  Icon(Icons.chevron_right, size: 20, color: AppTheme.primary),
                ],
              ),
            ),
          ),

        _buildLegacyOfferBanner(isDark),

        Expanded(
          child: _isLoadingServices
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : tree.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.content_cut,
                          size: 80,
                          color: isDark ? Colors.white30 : Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No services available',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white60 : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildServiceTreeList(tree, isDark),
        ),

        _buildBottomBar(
          isDark: isDark,
          enabled: _selectedServices.isNotEmpty,
          onPressed: () {
            setState(() {
              _currentStep = 2;
            });
            _loadHolidays();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _selectedServices.isEmpty
                    ? 'Select a Service'
                    : 'Continue to Date',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_selectedServices.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 18),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegacyOfferBanner(bool isDark) {
    if (_appliedOffer == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.green.shade900 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.green.shade700 : Colors.green.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.green.shade800 : Colors.green.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_offer,
              color: isDark ? Colors.green.shade300 : Colors.green.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎉 VIP Offer Detected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? Colors.green.shade300
                        : Colors.green.shade700,
                  ),
                ),
                Text(
                  _appliedOffer!['title']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.green.shade300
                        : Colors.green.shade600,
                  ),
                ),
                Text(
                  'Apply to a service below',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? Colors.green.shade300
                        : Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _removeOffer,
            style: TextButton.styleFrom(
              foregroundColor: isDark
                  ? Colors.green.shade300
                  : Colors.green.shade700,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // SERVICE TREE (Category → Service → Variant)
  // ============================================

  String _ageRangeText(int? minAge, int? maxAge) {
    if (minAge == null || maxAge == null) return '';
    if (maxAge >= 100) return '$minAge+ yrs';
    return '$minAge–$maxAge yrs';
  }

  Color _hexToTreeColor(String? hex) {
    if (hex != null && hex.startsWith('#') && hex.length >= 7) {
      try {
        return Color(int.parse('0xFF${hex.substring(1, 7)}'));
      } catch (_) {}
    }
    return AppTheme.primary;
  }

  IconData _treeIconFromName(String? name) {
    switch (name) {
      case 'content_cut':
        return Icons.content_cut;
      case 'face':
        return Icons.face;
      case 'face_retouching_natural':
        return Icons.face_retouching_natural;
      case 'spa':
        return Icons.spa;
      case 'handshake':
        return Icons.handshake;
      case 'build':
        return Icons.build;
      case 'brush':
        return Icons.brush;
      case 'water_drop':
        return Icons.water_drop;
      case 'masks':
        return Icons.masks;
      case 'spa_outlined':
        return Icons.spa_outlined;
      default:
        return Icons.content_cut;
    }
  }

  List<Map<String, dynamic>> _buildServiceTree() {
    final Map<String, Map<String, dynamic>> byCategory = {};

    for (final s in _salonServices) {
      final catName = s['category_name']?.toString() ?? 'Other';
      final entry = byCategory.putIfAbsent(
        catName,
        () => {
          'name': catName,
          'icon': s['category_icon'],
          'color': s['category_color'],
          'order': (s['category_order'] as num?)?.toInt() ?? 9999,
          'services': <Map<String, dynamic>>[],
        },
      );
      (entry['services'] as List<Map<String, dynamic>>).add(s);
    }

    final list = byCategory.values.toList()
      ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));

    for (final c in list) {
      (c['services'] as List<Map<String, dynamic>>).sort(
        (a, b) => (a['name']?.toString() ?? '').compareTo(
          b['name']?.toString() ?? '',
        ),
      );
    }
    return list;
  }

  Widget _buildServiceTreeList(List<Map<String, dynamic>> tree, bool isDark) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final hPad = isMobile ? 10.0 : 16.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          isMobile ? 8 : 14,
          6,
          isMobile ? 8 : 14,
          6,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ...tree.map((cat) => _buildTreeCategoryBlock(cat, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeCategoryBlock(Map<String, dynamic> cat, bool isDark) {
    final color = _hexToTreeColor(cat['color']?.toString());
    final icon = _treeIconFromName(cat['icon']?.toString());
    final services = cat['services'] as List<Map<String, dynamic>>;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.18),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cat['name']?.toString() ?? 'Category',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${services.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: services
                    .map((svc) => _buildTreeServiceBlock(svc, color, isDark))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeServiceBlock(
    Map<String, dynamic> service,
    Color catColor,
    bool isDark,
  ) {
    final variants = (service['variants'] as List?) ?? [];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 2,
                color: catColor.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service['name']?.toString() ?? 'Service',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (variants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 4),
              child: Text(
                'No pricing options yet',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: catColor.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Column(
                  children: variants
                      .map(
                        (v) => _buildVariantRow(
                          service,
                          Map<String, dynamic>.from(v as Map),
                          catColor,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
    Color catColor,
  ) {
    final isDark = context.isDarkMode;
    final int serviceId = service['id'] as int;
    final int variantId = variant['id'] as int;
    final key = _serviceKey(serviceId, variantId);

    final isSelected = _selectedServices.any(
      (s) => s['id'] == serviceId && s['variant_id'] == variantId,
    );

    final String gender = variant['gender']?.toString() ?? '';
    final String age = variant['age']?.toString() ?? '';
    final String ageRange = variant['age_range']?.toString() ?? '';
    final String ageText = age.isEmpty
        ? ''
        : (ageRange.isEmpty ? age : '$age ($ageRange)');

    final double price = (variant['price'] as num?)?.toDouble() ?? 0.0;
    final int duration = (variant['duration'] as num?)?.toInt() ?? 30;

    final availableOffers = _availableOffersPerService[key] ?? [];
    final selectedOffer = _serviceOffers[key];
    final discount = _calculateOfferDiscount(price, selectedOffer);
    final finalPrice = price - discount;
    final hasOffer = selectedOffer != null && discount > 0;

    final greenColor = isDark ? Colors.green.shade300 : Colors.green.shade700;

    final bool hasClaimed = availableOffers.any((o) => o['is_claimed'] == true);
    Widget? offerChip;
    if (isSelected && hasOffer) {
      offerChip = _buildInfoChip(
        Icons.card_giftcard,
        '${selectedOffer['title'] ?? 'Offer'} applied • save ${_formatPrice(discount)}',
        Colors.green.shade600,
      );
    } else if (availableOffers.isNotEmpty) {
      offerChip = _buildInfoChip(
        Icons.local_offer_outlined,
        hasClaimed
            ? 'Your claimed offer'
            : (availableOffers.length == 1
                  ? '1 offer available'
                  : '${availableOffers.length} offers available'),
        Colors.orange.shade700,
      );
    }

    final displayPrice = hasOffer && isSelected ? finalPrice : price;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 1.5,
                color: catColor.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggleVariant(service, variant),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary.withValues(alpha: 0.5)
                              : (isDark ? Colors.grey[700]! : Colors.grey[300]!)
                                    .withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) =>
                                  _toggleVariant(service, variant),
                              activeColor: AppTheme.primary,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (gender.isNotEmpty)
                                      _buildInfoChip(
                                        Icons.person_outline,
                                        gender,
                                        Colors.blue.shade400,
                                      ),
                                    if (ageText.isNotEmpty)
                                      _buildInfoChip(
                                        Icons.cake_outlined,
                                        ageText,
                                        Colors.purple.shade400,
                                      ),
                                    if (gender.isEmpty && ageText.isEmpty)
                                      _buildInfoChip(
                                        Icons.check_circle_outline,
                                        'Standard',
                                        Colors.grey.shade600,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 12,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$duration min',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                if (offerChip != null) ...[
                                  const SizedBox(height: 6),
                                  offerChip,
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // ✅ UPDATED: dual display in variant row
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (hasOffer && isSelected)
                                Text(
                                  _formatPrice(price),
                                  style: TextStyle(
                                    fontSize: 11,
                                    decoration: TextDecoration.lineThrough,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey[500],
                                  ),
                                ),
                              Text(
                                _formatPrice(displayPrice),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: hasOffer && isSelected
                                      ? greenColor
                                      : AppTheme.primary,
                                ),
                              ),
                              if (_showApprox)
                                Text(
                                  '≈ ${_formatUserPrice(displayPrice * _exchangeRate!)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSelectedServicesSheet() {
    final isDark = context.isDarkMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.checklist,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected Services',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              '${_selectedServices.length} service${_selectedServices.length > 1 ? 's' : ''} selected',
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
                      if (_selectedServices.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedServices.clear();
                              _serviceOffers.clear();
                              _recalculateTotals();
                            });
                            Navigator.pop(context);
                          },
                          child: Text(
                            'Clear All',
                            style: TextStyle(
                              color: isDark ? Colors.red.shade300 : Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _selectedServices.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 64,
                                    color: isDark
                                        ? Colors.white30
                                        : Colors.grey[300],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No services selected',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[500],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap on service variants to add',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _selectedServices.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final service = _selectedServices[index];
                              return _buildSelectedServiceItem(
                                service,
                                index,
                                setSheetState,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Duration',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white60 : Colors.grey,
                              ),
                            ),
                            Text(
                              '${_calculateTotalDuration()} min',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_discountAmount > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Subtotal',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white60 : Colors.grey,
                                ),
                              ),
                              Text(
                                _formatPrice(_calculateTotalPrice()),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white70 : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_offer,
                                    size: 14,
                                    color: isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Total Discount',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '− ${_formatPrice(_discountAmount)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Price',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white60 : Colors.grey,
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatPrice(_getDisplayTotalPrice()),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                // ✅ NEW: approx user currency
                                if (_showApprox)
                                  Text(
                                    '≈ ${_formatUserPrice(_getDisplayTotalPrice() * _exchangeRate!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectedServiceItem(
    Map<String, dynamic> service,
    int index,
    StateSetter setSheetState,
  ) {
    final isDark = context.isDarkMode;
    final String serviceName = service['name']?.toString() ?? 'Service';
    final String gender = service['gender']?.toString() ?? '';
    final String age = service['age']?.toString() ?? '';
    final String variantLabel = (gender.isEmpty && age.isEmpty)
        ? 'Standard'
        : '$gender $age'.trim();
    final double price = (service['price'] as num?)?.toDouble() ?? 0.0;
    final double discount =
        (service['discount_amount'] as num?)?.toDouble() ?? 0;
    final double finalPrice =
        (service['final_price'] as num?)?.toDouble() ?? price;
    final int duration = (service['duration'] as num?)?.toInt() ?? 30;
    final offer = service['offer'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _cardColors[index % _cardColors.length],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    _getServiceIcon(serviceName),
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$variantLabel • $duration min',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ UPDATED: dual display
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (discount > 0)
                    Text(
                      _formatPrice(price),
                      style: TextStyle(
                        fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  Text(
                    _formatPrice(finalPrice),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: discount > 0
                          ? (isDark
                                ? Colors.green.shade300
                                : Colors.green.shade700)
                          : AppTheme.primary,
                    ),
                  ),
                  if (_showApprox)
                    Text(
                      '≈ ${_formatUserPrice(finalPrice * _exchangeRate!)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final removed = _selectedServices[index];
                  final key = _serviceKey(
                    removed['id'] as int,
                    removed['variant_id'] as int?,
                  );
                  setSheetState(() {
                    _selectedServices.removeAt(index);
                    _serviceOffers.remove(key);
                  });
                  _recalculateTotals();
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: isDark ? Colors.red.shade300 : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          if (offer != null && discount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.local_offer,
                    size: 11,
                    color: isDark
                        ? Colors.green.shade300
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${offer['title']} — save ${_formatPrice(discount)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.green.shade300
                          : Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================
  // STEP 2: DATE SELECTION
  // ============================================

  Widget _buildDateSelectionStep() {
    final isDark = context.isDarkMode;
    final today = _todayDate;
    final maxDate = today.add(const Duration(days: 30));

    final firstSelectable = _firstSelectableDate();
    final noDatesAvailable = _scheduleLoaded && firstSelectable == null;
    final calendarInitial =
        (_selectedDate != null && _isDaySelectable(_selectedDate!))
        ? _selectedDate!
        : (firstSelectable ?? today);

    final bool canContinue =
        _selectedDate != null &&
        !_isDateUnavailable &&
        !_isCheckingDate &&
        !_holidays.contains(_selectedDate) &&
        _isDaySelectable(_selectedDate!);

    final isSelectedDateHoliday =
        _selectedDate != null && _holidays.contains(_selectedDate);
    final selectedHolidayName = isSelectedDateHoliday
        ? _holidayNames[_selectedDate]
        : null;
    final isSelectedToday =
        _selectedDate != null && _selectedDate!.isAtSameMomentAs(today);

    return Column(
      children: [
        _buildStepTitle(
          isDark,
          Icons.calendar_today,
          'Pick a date',
          'Choose the day for your visit',
        ),
        if (_selectedServices.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Row(
              children: [
                Icon(Icons.content_cut, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_selectedServices.length} service${_selectedServices.length > 1 ? 's' : ''} • ${_calculateTotalDuration()} min',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _formatPrice(_getDisplayTotalPrice()),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                          // ✅ NEW: approx user currency
                          if (_showApprox) ...[
                            const SizedBox(width: 6),
                            Text(
                              '≈ ${_formatUserPrice(_getDisplayTotalPrice() * _exchangeRate!)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color:
                                    isDark ? Colors.white60 : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_holidays.contains(today))
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.red.shade900 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.red.shade700
                            : Colors.red.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_busy,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🚫 Today is a Holiday!',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade700,
                                ),
                              ),
                              Text(
                                _holidayNames[today] ?? 'Salon is closed today',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade600,
                                ),
                              ),
                              Text(
                                'Auto-selected next available date: ${DateFormat('EEEE, MMM dd').format(_selectedDate ?? firstSelectable ?? today)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                if (noDatesAvailable)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.shade900
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_busy,
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No dates available in the next 30 days.',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.orange.shade300
                                  : Colors.orange.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Card(
                    elevation: 3,
                    color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: CalendarDatePicker(
                        key: ValueKey('cal_$_calendarVersion'),
                        initialDate: calendarInitial,
                        firstDate: today,
                        lastDate: maxDate,
                        selectableDayPredicate: (date) =>
                            _isDaySelectable(date),
                        onDateChanged: (date) async {
                          setState(() {
                            _selectedDate = date;
                            _isDateUnavailable = false;
                            _unavailableReason = null;
                          });
                          await _checkDateAvailability(date);
                        },
                      ),
                    ),
                  ),

                _buildUnavailableDaysHint(isDark, today, maxDate),

                if (isSelectedDateHoliday)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.red.shade900 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.red.shade700
                            : Colors.red.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.red.shade800
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.event_busy,
                            color: isDark
                                ? Colors.red.shade300
                                : Colors.red.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isSelectedToday
                                    ? '🚫 TODAY IS A HOLIDAY'
                                    : '⛔ HOLIDAY',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${selectedHolidayName ?? 'Salon is closed'} ${isSelectedToday ? 'today' : 'on this date'}',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_isDateUnavailable &&
                    !_holidays.contains(_selectedDate) &&
                    _selectedDate != null)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.shade900
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _unavailableReason ??
                                '⚠️ No barbers available on this day',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.orange.shade300
                                  : Colors.orange.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_selectedDate != null && !_holidays.contains(_selectedDate))
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.green.shade900
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.green.shade700
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '✅ Selected: ${DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!)}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade700,
                              fontSize: 14,
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

        _buildBottomBar(
          isDark: isDark,
          enabled: canContinue,
          onPressed: () async {
            setState(() {
              _currentStep = 3;
              _barbersLoaded = false;
              _barberAvailability.clear();
              _availableBarbers = [];
              _selectedBarber = null;
            });
            await _loadAvailableBarbers();
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _selectedDate == null
                      ? (noDatesAvailable
                            ? 'No Dates Available'
                            : 'Please Select a Date')
                      : (_holidays.contains(_selectedDate)
                            ? '🚫 Holiday - Not Available'
                            : (_isDateUnavailable
                                  ? 'No Barbers Available'
                                  : (_isCheckingDate
                                        ? 'Checking availability...'
                                        : 'Continue to Barber'))),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canContinue) const SizedBox(width: 8),
              if (canContinue) const Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailableDaysHint(
    bool isDark,
    DateTime today,
    DateTime maxDate,
  ) {
    final reasons = <String>[];

    if (_scheduleLoaded) {
      final closedDays = <int>[
        for (int d = 1; d <= 7; d++)
          if (!_workingWeekdays.contains(d)) d,
      ];
      if (closedDays.isNotEmpty && closedDays.length < 7) {
        final names = closedDays
            .map((d) => DateFormat('EEE').format(DateTime(2024, 1, d)))
            .join(', ');
        reasons.add('No barbers on $names');
      }
    }

    final upcomingHolidays =
        _holidays
            .where((h) => !h.isBefore(today) && !h.isAfter(maxDate))
            .toList()
          ..sort();
    for (final h in upcomingHolidays.take(3)) {
      final name = _holidayNames[h];
      reasons.add(
        '${DateFormat('MMM dd').format(h)} holiday'
        '${name != null && name.isNotEmpty ? ' ($name)' : ''}',
      );
    }

    if (reasons.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
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
              Icon(
                Icons.info_outline,
                size: 14,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                'Greyed-out days are unavailable',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...reasons.map(
            (r) => Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '• $r',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // STEP 3: BARBER SELECTION
  // ============================================

  Widget _buildBarberSelectionStep() {
    final isDark = context.isDarkMode;

    if (!_barbersLoaded &&
        !_isLoadingBarbers &&
        _selectedSalon != null &&
        _selectedBarber == null) {
      Future.microtask(() => _loadAvailableBarbers());
    }

    return Column(
      children: [
        _buildStepTitle(
          isDark,
          Icons.person,
          'Choose your barber',
          _selectedDate == null
              ? 'Tap a barber to select'
              : 'Availability on ${DateFormat('EEE, MMM dd').format(_selectedDate!)}',
        ),
        Expanded(
          child: _isLoadingBarbers
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _availableBarbers.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_off,
                          size: 80,
                          color: isDark ? Colors.white30 : Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No barbers available',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _barbersLoaded = false;
                              _isLoadingBarbers = false;
                              _availableBarbers = [];
                              _selectedBarber = null;
                            });
                            _loadAvailableBarbers();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _availableBarbers.length,
                  itemBuilder: (context, index) =>
                      _buildBarberCard(_availableBarbers[index]),
                ),
        ),
        _buildBottomBar(
          isDark: isDark,
          enabled: _selectedBarber != null,
          onPressed: () {
            setState(() {
              _currentStep = 4;
              _childNameController.clear();
              _selectedChildName = null;
              _isSameAsCustomer = true;
              _duplicateError = null;
            });
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _selectedBarber == null
                    ? 'Select a Barber'
                    : 'Continue to Person',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_selectedBarber != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 18),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final isDark = context.isDarkMode;
    final isSelected = _selectedBarber?['id'] == barber['id'];
    final availability = _barberAvailability[barber['id']];
    final isAvailable = availability?['is_available'] ?? true;

    final String barberName = barber['full_name']?.toString() ?? 'Barber';
    final String avatarUrl = barber['avatar_url']?.toString() ?? '';
    final double avgRating = (barber['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final int todayAppointments = barber['today_appointments'] ?? 0;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 3,
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected
                ? AppTheme.primary
                : (isAvailable ? Colors.transparent : Colors.red.shade200),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: isAvailable
              ? () => setState(() => _selectedBarber = barber)
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          barberName.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            fontSize: 28,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
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
                          Expanded(
                            child: Text(
                              barberName,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (!isAvailable)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Text(
                                'Unavailable',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 16,
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            avgRating > 0
                                ? avgRating.toStringAsFixed(1)
                                : 'New',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.work,
                            size: 16,
                            color: isDark ? Colors.white60 : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$todayAppointments today',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      if (!isAvailable && availability?['reason'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.orange.shade900
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              availability!['reason']!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isAvailable)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? AppTheme.primary : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                if (!isAvailable)
                  Icon(
                    Icons.block,
                    color: isDark ? Colors.red.shade300 : Colors.red,
                    size: 28,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // STEP 4: PERSON SELECTION
  // ============================================

  Widget _buildPersonSelectionStep() {
    final isDark = context.isDarkMode;
    final user = supabase.auth.currentUser;
    final customerName =
        user?.userMetadata?['full_name']?.toString() ??
        user?.email?.split('@').first ??
        'Customer';

    return Column(
      children: [
        _buildSelectedDateRow(isDark),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 10),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                ),
                                child: Icon(
                                  Icons.badge,
                                  size: 22,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Who is this VIP booking for?',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose one option',
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
                      ),

                      Row(
                        children: [
                          Icon(
                            Icons.person_pin_circle_outlined,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Booking for',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: AppTheme.primary.withValues(alpha: 0.4),
                                width: 2,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildPersonOption(
                                isSelected: _isSameAsCustomer,
                                icon: Icons.person,
                                title: 'Myself',
                                subtitle: customerName,
                                onTap: () {
                                  setState(() {
                                    _isSameAsCustomer = true;
                                    _selectedChildName = null;
                                    _childNameController.clear();
                                    _duplicateError = null;
                                  });
                                  _checkDuplicateBooking();
                                },
                              ),
                              _buildPersonOption(
                                isSelected: !_isSameAsCustomer,
                                icon: Icons.group,
                                title: 'Someone else',
                                subtitle: 'Family member, friend or child',
                                onTap: () => setState(() {
                                  _isSameAsCustomer = false;
                                  _duplicateError = null;
                                }),
                              ),
                              if (!_isSameAsCustomer)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 20,
                                    top: 8,
                                  ),
                                  child: TextField(
                                    controller: _childNameController,
                                    autofocus: true,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: "Enter the person's name",
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey[400],
                                      ),
                                      prefixIcon: Icon(
                                        Icons.edit_outlined,
                                        color: AppTheme.primary,
                                        size: 18,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: AppTheme.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.grey[50],
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                    ),
                                    onChanged: (v) {
                                      setState(() {
                                        _selectedChildName = v.trim();
                                        _duplicateError = null;
                                      });
                                      _checkDuplicateBooking();
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_duplicateError != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.red.shade900 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _duplicateError!,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade700,
                              fontSize: 13,
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
        _buildBottomBar(
          isDark: isDark,
          enabled: _canProceedToTimeSlot(),
          onPressed: () async {
            if (await _validateAndProceed()) {
              setState(() {
                _currentStep = 5;
                _allTimeSlots = [];
                _selectedSlot = null;
                _showingVipNumber = false;
                _generatedVipNumber = 0;
                _selectedStartTime = '';
                _isLoadingSlots = true;
                _slotErrorMessage = null;
                _slotErrorType = null;
              });
              await _loadAvailableSlots();
            }
          },
          child: _isCheckingDuplicate
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Continue to Time Slot',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildPersonOption({
    required bool isSelected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 2,
            color: AppTheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.5)
                          : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.white54 : Colors.grey[500]),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 18, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? AppTheme.primary
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // STEP 5: TIME SLOT SELECTION
  // ============================================

  /// ✅ Timezone indicator: Salon time (main) + User reference
  Widget _buildTimezoneIndicator() {
    final isDark = context.isDarkMode;
    final showUserTz = _isDifferentTimezone;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.store,
                size: 14,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Salon times: ${_getSalonTimezoneDisplay()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ),
              if (_isDST()) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.amber.shade900
                        : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'DST',
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark
                          ? Colors.amber.shade300
                          : Colors.amber.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (showUserTz) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 12,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You are in: ${_getUserTimezoneDisplay()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeSlotStep() {
    final isDark = context.isDarkMode;
    final availableSlots = _allTimeSlots
        .where((s) => s['is_available'] == true)
        .toList();
    final unavailableSlots = _allTimeSlots
        .where((s) => s['is_available'] != true)
        .toList();
    final canContinue = _selectedSlot != null && _showingVipNumber;

    return Column(
      children: [
        _buildSelectedDateRow(isDark),
        _buildTimezoneIndicator(),
        Expanded(
          child: _isLoadingSlots
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : (_slotErrorMessage != null ||
                    _allTimeSlots.isEmpty ||
                    _allTimeSlots.every((s) => s['is_available'] != true))
              ? _buildNoSlotsState(isDark)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Select VIP Time Slot',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose your preferred time',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_showingVipNumber && _selectedSlot != null) ...[
                        Center(
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            elevation: 6,
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: const BorderSide(
                                color: AppTheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Your VIP Number',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'VIP-$_generatedVipNumber',
                                    style: TextStyle(
                                      fontSize: 56,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(40),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 22,
                                          color: AppTheme.primary,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _selectedStartTime,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : _textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (availableSlots.isNotEmpty) ...[
                        Text(
                          'Available Slots',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: availableSlots.map((slot) {
                            final isSelected = _selectedSlot == slot;
                            final displayTime = slot['start_time_display'];
                            final willGetVipNumber = slot['vip_number'];

                            return ElevatedButton(
                              onPressed: () => _bookSlot(slot),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isSelected && _showingVipNumber
                                    ? AppTheme.primary
                                    : (isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.white),
                                foregroundColor: isSelected && _showingVipNumber
                                    ? Colors.white
                                    : AppTheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                  side: BorderSide(
                                    color: isSelected && _showingVipNumber
                                        ? AppTheme.primary
                                        : AppTheme.primary.withValues(
                                            alpha: 0.5,
                                          ),
                                    width: 1.5,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                elevation: isSelected && _showingVipNumber
                                    ? 2
                                    : 0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayTime,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight:
                                          isSelected && _showingVipNumber
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected && _showingVipNumber
                                          ? Colors.white
                                          : (isDark
                                                ? Colors.white
                                                : Colors.black87),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'VIP-$willGetVipNumber',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected && _showingVipNumber
                                          ? Colors.white70
                                          : AppTheme.primary.withValues(
                                              alpha: 0.7,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (unavailableSlots.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Unavailable Slots',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: unavailableSlots.map((slot) {
                            final displayTime = slot['start_time_display'];
                            final statusText = slot['status_text'] ?? '';
                            final isBooked = slot['is_booked'] == true;
                            final isBreak = slot['is_break'] == true;
                            final isPast = slot['is_past'] == true;

                            String displayStatus = '';
                            Color statusColor = Colors.grey[500]!;

                            if (isBooked) {
                              displayStatus = 'Booked';
                              statusColor = Colors.red.shade400;
                            } else if (isBreak) {
                              displayStatus = 'Break';
                              statusColor = Colors.orange.shade600;
                            } else if (isPast) {
                              displayStatus = 'Time Passed';
                              statusColor = Colors.grey[500]!;
                            } else if (statusText.isNotEmpty) {
                              displayStatus = statusText;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayTime,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey[500],
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  if (displayStatus.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        displayStatus,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: statusColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        _buildBottomBar(
          isDark: isDark,
          enabled: canContinue,
          onPressed: () => setState(() => _currentStep = 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Continue to Confirmation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoSlotsState(bool isDark) {
    final errorType = _slotErrorType ?? 'general';
    final showDateButtons =
        errorType == 'date' ||
        errorType == 'overflow' ||
        errorType == 'salon_closed' ||
        errorType == 'date_full';
    final showBarberButton = errorType == 'barber';
    final showGoBack = errorType == 'general';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: isDark ? Colors.orange.shade400 : Colors.orange.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              'No VIP Slots Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(
                _slotErrorMessage ?? 'No slots available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                if (showDateButtons)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _slotErrorMessage = null;
                        _slotErrorType = null;
                        _currentStep = 2;
                        _allTimeSlots = [];
                        _showingVipNumber = false;
                        _selectedSlot = null;
                      });
                    },
                    icon: Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                    label: const Text('Change Date'),
                  ),
                if (showDateButtons)
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (_selectedDate == null) return;
                      final tomorrow = _selectedDate!.add(
                        const Duration(days: 1),
                      );
                      final savedBarber = _selectedBarber;
                      final savedSalon = _selectedSalon;

                      setState(() {
                        _selectedDate = tomorrow;
                        _allTimeSlots = [];
                        _showingVipNumber = false;
                        _selectedSlot = null;
                        _isLoadingSlots = true;
                        _slotErrorMessage = null;
                        _slotErrorType = null;
                      });

                      try {
                        final isHoliday = _holidays.contains(tomorrow);
                        if (isHoliday) {
                          if (!mounted) return;
                          setState(() {
                            _isLoadingSlots = false;
                            _slotErrorMessage =
                                '${_holidayNames[tomorrow] ?? 'Holiday'} — Salon is closed tomorrow.';
                            _slotErrorType = 'salon_closed';
                          });
                          return;
                        }

                        if (savedBarber == null || savedSalon == null) {
                          if (!mounted) return;
                          setState(() {
                            _isLoadingSlots = false;
                            _selectedBarber = null;
                            _barbersLoaded = false;
                            _barberAvailability = {};
                            _availableBarbers = [];
                            _currentStep = 3;
                          });
                          return;
                        }

                        final availability = await _checkBarberFullAvailability(
                          savedBarber['barber_id'] ?? savedBarber['id'],
                          tomorrow,
                        );

                        if (!mounted) return;

                        if (availability['is_available'] != true) {
                          setState(() {
                            _selectedBarber = null;
                            _barbersLoaded = false;
                            _barberAvailability = {};
                            _availableBarbers = [];
                            _isLoadingSlots = false;
                            _currentStep = 3;
                          });
                          await _loadAvailableBarbers();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${savedBarber['full_name']} is not available on '
                                '${DateFormat('MMM dd').format(tomorrow)}.',
                              ),
                              backgroundColor: Colors.orange.shade800,
                            ),
                          );
                          return;
                        }

                        setState(() {
                          _selectedBarber = savedBarber;
                          _barberAvailability = {
                            savedBarber['id']: availability,
                          };
                          _barbersLoaded = false;
                          _availableBarbers = [];
                        });

                        await _loadAvailableSlots();
                      } catch (e) {
                        if (!mounted) return;
                        setState(() {
                          _isLoadingSlots = false;
                          _slotErrorMessage = 'Error: ${e.toString()}';
                          _slotErrorType = 'general';
                        });
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(
                      'Try ${DateFormat('MMM dd').format(_selectedDate != null ? _selectedDate!.add(const Duration(days: 1)) : _todayDate)}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
              ],
            ),
            if (showBarberButton) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _slotErrorMessage = null;
                    _slotErrorType = null;
                    _selectedBarber = null;
                    _barbersLoaded = false;
                    _barberAvailability = {};
                    _availableBarbers = [];
                    _currentStep = 3;
                  });
                },
                icon: Icon(Icons.person, size: 18, color: AppTheme.primary),
                label: Text(
                  'Try Another Barber',
                  style: TextStyle(color: AppTheme.primary),
                ),
              ),
            ],
            if (showGoBack) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _slotErrorMessage = null;
                    _slotErrorType = null;
                    _currentStep = 3;
                  });
                },
                icon: Icon(Icons.arrow_back, size: 18, color: AppTheme.primary),
                label: Text(
                  'Go Back',
                  style: TextStyle(color: AppTheme.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================
  // STEP 6: CONFIRMATION
  // ============================================

  Widget _buildConfirmationStep() {
    final isDark = context.isDarkMode;

    if (_selectedSalon == null ||
        _selectedServices.isEmpty ||
        _selectedBarber == null ||
        _selectedSlot == null ||
        _selectedDate == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Missing information. Please go back and complete all steps.',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey[600],
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                    _resetBooking();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Start Over'),
              ),
            ],
          ),
        ),
      );
    }

    final user = supabase.auth.currentUser;
    final customerName =
        user?.userMetadata?['full_name']?.toString() ??
        user?.email?.split('@').first ??
        'Customer';
    final displayName = _isSameAsCustomer
        ? customerName
        : _getChildNameForBooking();

    final salonName = _selectedSalon!['name']?.toString() ?? 'Salon';
    final salonAddress = _selectedSalon!['address']?.toString() ?? '';
    final startTime =
        _selectedSlot!['start_time_display']?.toString() ?? '--:--';
    final endTime = _selectedSlot!['end_time_display']?.toString() ?? '--:--';
    final barberName = _selectedBarber!['full_name']?.toString() ?? 'Barber';
    final barberRating =
        (_selectedBarber!['avg_rating'] as num?)?.toStringAsFixed(1) ?? 'New';
    final totalDuration = _calculateTotalDuration();
    final totalPrice = _getDisplayTotalPrice();
    final vipNumber = _generatedVipNumber;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildConfirmationTile(
                  Icons.star,
                  'VIP Booking',
                  'VIP-$vipNumber',
                  '',
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.store,
                  'Salon',
                  salonName,
                  salonAddress,
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.calendar_today,
                  'Date & Time',
                  DateFormat('EEEE, MMM dd').format(_selectedDate!),
                  '$startTime - $endTime',
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.badge,
                  'Booking For',
                  displayName,
                  _isSameAsCustomer ? 'Self' : 'Family/Friend',
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.content_cut,
                  'Services (${_selectedServices.length})',
                  '$totalDuration min',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._selectedServices.map((s) {
                        final price = (s['price'] as num?)?.toDouble() ?? 0.0;
                        final discount =
                            (s['discount_amount'] as num?)?.toDouble() ?? 0.0;
                        final finalPrice =
                            (s['final_price'] as num?)?.toDouble() ?? price;
                        final offer = s['offer'] as Map<String, dynamic>?;
                        final gender = s['gender']?.toString() ?? '';
                        final age = s['age']?.toString() ?? '';
                        final details = (gender.isEmpty && age.isEmpty)
                            ? 'Standard'
                            : '$gender $age'.trim();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '• ${s['name']?.toString() ?? 'Service'}${details.isNotEmpty ? ' ($details)' : ''}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  if (discount > 0)
                                    Text(
                                      _formatPrice(price),
                                      style: TextStyle(
                                        fontSize: 12,
                                        decoration: TextDecoration.lineThrough,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey,
                                      ),
                                    ),
                                  if (discount > 0) const SizedBox(width: 4),
                                  Text(
                                    _formatPrice(finalPrice),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: discount > 0
                                          ? (isDark
                                                ? Colors.green.shade300
                                                : Colors.green.shade700)
                                          : (isDark
                                                ? Colors.white70
                                                : Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                              if (offer != null && discount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    top: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.local_offer,
                                        size: 11,
                                        color: isDark
                                            ? Colors.green.shade300
                                            : Colors.green.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '🎁 ${offer['title']} — save ${_formatPrice(discount)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.green.shade300
                                                : Colors.green.shade700,
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
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Services Subtotal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.grey[800],
                            ),
                          ),
                          Text(
                            _formatPrice(_originalTotalPrice),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      if (_discountAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_offer,
                                    size: 14,
                                    color: isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Total Discount',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '− ${_formatPrice(_discountAmount)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.person,
                  'Barber',
                  barberName,
                  '⭐ $barberRating rating',
                ),
                const SizedBox(height: 12),
                // ✅ UPDATED: Estimated Amount with dual currency
                _buildConfirmationTile(
                  Icons.attach_money,
                  'Estimated Amount',
                  _formatPrice(totalPrice),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ NEW: approx user currency
                      if (_showApprox)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '≈ ${_formatUserPrice(totalPrice * _exchangeRate!)} in your currency',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      if (_discountAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Saved ${_formatPrice(_discountAmount)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: isDark
                                ? Colors.orange.shade300
                                : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Price may change after your service. The barber '
                              'can charge extra for additional work, so this '
                              'may not be the final bill. Payment is charged in '
                              '$_salonCurrencyCode.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade800,
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
          ),
        ),
        _buildBottomBar(
          isDark: isDark,
          enabled: !_isBooking,
          backEnabled: !_isBooking,
          onPressed: _confirmBooking,
          child: _isBooking
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Confirm VIP Booking',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}