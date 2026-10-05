import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../services/timezone_service.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class BookingFlowScreen extends StatefulWidget {
  final Map<String, dynamic>? initialSalon;
  const BookingFlowScreen({super.key, this.initialSalon});

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
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
  String? _selectedCategoryTab;
  int? _expandedServiceId;

  final Map<String, List<Map<String, dynamic>>> _availableOffersPerService = {};
  final Map<String, Map<String, dynamic>> _serviceOffers = {};

  // Step 2: Date
  DateTime? _selectedDate;
  Set<DateTime> _holidays = {};
  Map<DateTime, String> _holidayNames = {};
  bool _isDateUnavailable = false;
  String? _unavailableReason;

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

  // Step 5: Time Slot
  int _selectedTravelTime = 0;
  bool _showTravelTimeSelector = false;
  final List<int> _travelTimeOptions = [5, 10, 15, 20, 25, 30, 45, 60];
  List<Map<String, dynamic>> _availableSlots = [];
  Map<String, dynamic>? _selectedSlot;
  bool _isLoadingSlots = false;
  String? _slotErrorMessage;
  String? _slotErrorType; // ✅ NEW: 'date' | 'barber' | 'salon_closed' | 'overflow' | 'date_full' | 'general'

  // Step 6: Confirm
  bool _isBooking = false;
  bool _isInitialized = false;

  Map<String, dynamic>? _appliedOffer;

  List<Map<String, dynamic>>? _preselectedServices;
  bool _preselectedServicesApplied = false;

  double _discountAmount = 0;
  double _originalTotalPrice = 0;
  double _finalTotalPrice = 0;

  // Timezone
  String _userTimezone = '';
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  // Responsive
  bool _isLargeScreen = false;
  bool _isTablet = false;
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
  }

  Map<String, dynamic>? _normalizedInitialSalon() {
    final initial = widget.initialSalon;
    if (initial == null) return null;

    final dynamic rawId = initial['id'];
    if (rawId == null) {
      debugPrint('❌ initialSalon has NO id field: $initial');
      return null;
    }

    final int salonId;
    if (rawId is int) {
      salonId = rawId;
    } else if (rawId is num) {
      salonId = rawId.toInt();
    } else {
      final parsed = int.tryParse(rawId.toString());
      if (parsed == null) {
        debugPrint('❌ initialSalon id unparseable: $rawId');
        return null;
      }
      salonId = parsed;
    }

    if (salonId <= 0) {
      debugPrint('❌ initialSalon id invalid: $salonId');
      return null;
    }

    final normalized = Map<String, dynamic>.from(initial);
    normalized['id'] = salonId;
    normalized.remove('preselected_services');
    return normalized;
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isLarge = size.width > 800 || size.height > 800;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isLargeScreen != isLarge || _isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isLargeScreen = isLarge;
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  // ============================================
  // OFFER + EXTRA HANDLING
  // ============================================

  void _checkForOffer() {
    final extra = GoRouterState.of(context).extra;

    if (extra == null) {
      debugPrint('ℹ️ No `extra` passed to BookingFlowScreen');
      return;
    }

    if (extra is Map) {
      final map = Map<String, dynamic>.from(extra);

      if (map.containsKey('offer') && map['offer'] is Map) {
        final offer = Map<String, dynamic>.from(map['offer'] as Map);
        if (_appliedOffer == null) {
          _appliedOffer = offer;
          debugPrint('🎁 Offer from navigation: ${offer['title']}');
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
          debugPrint(
            '🎯 Preselected services (via extra): ${_preselectedServices!.length}',
          );
        }
      }
    }
  }

  // ============================================
  // PER-SERVICE OFFER HELPERS
  // ============================================

  String _serviceKey(int serviceId, int? variantId) =>
      '${serviceId}_${variantId ?? 0}';

  Future<List<Map<String, dynamic>>> _loadOffersForService(
    int serviceId,
    double price,
  ) async {
    if (_selectedSalon == null) return [];

    try {
      final result = await supabase.rpc(
        'get_offers_for_service',
        params: {
          'p_salon_id': _selectedSalon!['id'],
          'p_service_id': serviceId,
          'p_service_price': price,
        },
      );

      if (result == null) return [];
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('⚠️ Error loading offers for service $serviceId: $e');
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

  String _getOfferLabel(Map<String, dynamic> offer) {
    final title = offer['title']?.toString() ?? 'Offer';
    final type = offer['discount_type']?.toString();
    final value = (offer['discount_value'] as num?)?.toDouble() ?? 0;

    if (type == 'percentage') {
      return '$title (${value.toStringAsFixed(0)}% OFF)';
    } else if (type == 'fixed') {
      return '$title (Rs. ${value.toStringAsFixed(0)} OFF)';
    } else if (type == 'free_service') {
      return '$title (FREE)';
    }
    return title;
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
  // TIMEZONE
  // ============================================

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    _lastTimezone = _userTimezone;

    if (!mounted) return;
    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadAllSalons();
    await _initializeScreen();
  }

  void _checkTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString('cached_timezone') ??
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
        _availableSlots = [];
        _selectedSlot = null;
        _showTravelTimeSelector = false;
        _selectedTravelTime = 0;
        _slotErrorMessage = null;
        _slotErrorType = null;
        _isLoadingSlots = true;
      });
      await _loadAvailableSlots();
    }
  }

  Future<void> _initializeScreen() async {
    if (_isInitialized) return;
    if (widget.initialSalon == null) return;

    debugPrint('════════════════════════════════════════');
    debugPrint('🎯 [INIT] Received initialSalon from navigation');
    debugPrint('   Keys: ${widget.initialSalon!.keys.toList()}');
    debugPrint('   id: ${widget.initialSalon!['id']}');
    debugPrint('   id type: ${widget.initialSalon!['id'].runtimeType}');
    debugPrint('   name: ${widget.initialSalon!['name']}');
    debugPrint('════════════════════════════════════════');

    final normalized = _normalizedInitialSalon();
    if (normalized == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Salon data is incomplete. Please go back and try again.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    debugPrint('✅ Normalized salon_id: ${normalized['id']}');

    final hasPreselected =
        _preselectedServices != null && _preselectedServices!.isNotEmpty;

    debugPrint(
      '🎯 Has preselected: $hasPreselected '
      '(${_preselectedServices?.length ?? 0} items)',
    );

    setState(() {
      _selectedSalon = normalized;
      _currentStep = hasPreselected ? 2 : 1;
      _isInitialized = true;
    });

    await _loadSalonServices();
    await _applyPreselectedServices();

    if (hasPreselected) {
      await _loadHolidays();
      debugPrint('✅ Jumped to Date step (preselected services applied)');
    }

    try {
      await supabase.rpc('cleanup_old_queues');
    } catch (e) {
      debugPrint('⚠️ Cleanup queues failed (non-critical): $e');
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

  bool _isDST() {
    final timezone = _userTimezone;
    if (!timezone.contains('America/') && !timezone.contains('Europe/')) {
      return false;
    }
    final now = DateTime.now();
    final month = now.month;
    return month > 3 && month < 11;
  }

  void _resetBooking() {
    setState(() {
      _currentStep = 0;
      _selectedSalon = null;
      _selectedDate = null;
      _selectedServices = [];
      _selectedBarber = null;
      _selectedSlot = null;
      _selectedTravelTime = 0;
      _showTravelTimeSelector = false;
      _searchController.clear();
      _searchResults = List.from(_allSalons);
      _isInitialized = false;
      _servicesLoaded = false;
      _barbersLoaded = false;
      _availableBarbers = [];
      _availableSlots = [];
      _selectedCategoryTab = null;
      _salonServices = [];
      _holidays = {};
      _holidayNames = {};
      _isDateUnavailable = false;
      _barberAvailability = {};
      _childNameController.clear();
      _selectedChildName = null;
      _isSameAsCustomer = true;
      _duplicateError = null;
      _slotErrorMessage = null;
      _slotErrorType = null;
      _expandedServiceId = null;
      _appliedOffer = null;
      _availableOffersPerService.clear();
      _serviceOffers.clear();
      _discountAmount = 0;
      _originalTotalPrice = 0;
      _finalTotalPrice = 0;
    });
  }

  Widget _buildTimezoneFlag() {
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TimezoneService.getCurrentFlag(),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 4),
          if (_isDST())
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.amber.shade900 : Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'DST',
                style: TextStyle(
                  fontSize: 8,
                  color:
                      isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
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
        debugPrint('✅ Loaded ${salons.length} salons');
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

  void _selectSalon(Map<String, dynamic> salon) {
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
    _loadSalonServices();
  }

  // ==================== STEP 1: SERVICE ====================

  Future<void> _loadSalonServices() async {
    if (_servicesLoaded) return;
    if (_selectedSalon == null) {
      debugPrint('⚠️ _loadSalonServices: no salon selected yet');
      return;
    }

    setState(() => _isLoadingServices = true);

    try {
      final dynamic rawSalonId = _selectedSalon!['id'];
      final int salonId = rawSalonId is int
          ? rawSalonId
          : (rawSalonId is num
              ? rawSalonId.toInt()
              : int.tryParse(rawSalonId?.toString() ?? '') ?? 0);

      debugPrint('🔍 [SERVICE] Loading services for salon_id: $salonId');

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

      final activeVariants =
          variantsResponse.where((v) => v['is_active'] != false).toList();

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
      if (categoryIds.isNotEmpty) {
        try {
          final categoriesResponse = await supabase
              .from('salon_categories')
              .select('id, display_name')
              .inFilter('id', categoryIds);

          for (var cat in categoriesResponse) {
            categoryMap[cat['id'] as int] =
                cat['display_name']?.toString() ?? 'Other';
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
      if (ageIds.isNotEmpty) {
        try {
          final agesResponse = await supabase
              .from('salon_age_categories')
              .select('id, display_name')
              .inFilter('id', ageIds);

          for (var a in agesResponse) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('⚠️ Age categories failed: $e');
        }
      }

      final Map<int, Map<String, dynamic>> groupedServices = {};

      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final categoryId = service['category_id'] as int?;

        groupedServices[serviceId] = {
          'id': serviceId,
          'name': service['name']?.toString() ?? 'Service',
          'description': service['description']?.toString(),
          'category_name': categoryId != null
              ? (categoryMap[categoryId] ?? 'Other')
              : 'Other',
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

      debugPrint('✅ Grouped ${servicesList.length} services with variants');
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ [SERVICE LOAD ERROR] ❌❌❌');
      debugPrint('   Error: $e');
      debugPrint('   Type: ${e.runtimeType}');
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
        _availableOffersPerService.remove(key);
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

    final offers = await _loadOffersForService(sid, price);

    if (offers.isNotEmpty && mounted) {
      setState(() {
        _availableOffersPerService[key] = offers;
      });
    }
  }

  Future<void> _applyPreselectedServices() async {
    if (_preselectedServicesApplied) return;
    _preselectedServicesApplied = true;

    final toApply = _preselectedServices;
    if (toApply == null || toApply.isEmpty) {
      debugPrint('ℹ️ No preselected services to apply');
      return;
    }
    if (_salonServices.isEmpty) {
      debugPrint('⚠️ Cannot apply preselected — services not loaded');
      return;
    }

    debugPrint('🎯 Applying ${toApply.length} preselected service(s)');

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
      if (service == null || variant == null) {
        debugPrint('⚠️ Preselected service/variant not found: $sid/$vid');
        continue;
      }

      final already = _selectedServices.any(
        (x) => x['id'] == sid && x['variant_id'] == vid,
      );
      if (already) continue;

      await _toggleVariant(service, variant);
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

      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      if (_holidays.contains(today) && _selectedDate == null) {
        DateTime nextDate = today.add(const Duration(days: 1));
        for (int i = 0; i < 30; i++) {
          if (!_holidays.contains(nextDate)) {
            setState(() {
              _selectedDate = nextDate;
            });
            await _checkDateAvailability(nextDate);
            break;
          }
          nextDate = nextDate.add(const Duration(days: 1));
        }
      }
    } catch (e) {
      debugPrint('Error loading holidays: $e');
    }
  }

  Future<void> _checkDateAvailability(DateTime date) async {
    if (_selectedSalon == null) return;
    try {
      final schedules = await supabase
          .from('barber_schedules')
          .select('barber_id')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('day_of_week', date.weekday)
          .eq('is_working', true);
      if (!mounted) return;
      setState(() {
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
        result['reason'] = 'Barber profile not found';
        return result;
      }

      final status = roleCheck['status'] as String? ?? 'active';
      if (status != 'active') {
        String reason = 'Barber account is ';
        switch (status) {
          case 'inactive':
            reason += 'deactivated';
            break;
          case 'scheduled_for_deletion':
            reason += 'scheduled for deletion';
            break;
          case 'deleted':
            reason += 'deleted';
            break;
          default:
            reason += 'not active';
        }
        result['is_available'] = false;
        result['reason'] = reason;
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
          result['reason'] = 'Barber account is blocked';
          return result;
        }
        if (profileCheck['is_active'] == false) {
          result['is_available'] = false;
          result['reason'] = 'Barber profile is inactive';
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
          result['reason'] = 'Barber is not assigned to this salon';
          return result;
        }
      } else {
        result['is_available'] = false;
        result['reason'] = 'Barber not found in this salon';
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
          result['reason'] = 'On full day leave';
          return result;
        }

        final workStart = schedule['work_start'] as String?;
        if (workStart == null) {
          result['is_available'] = false;
          result['reason'] = 'Not working on this day';
          return result;
        }
      }

      result['is_available'] = true;
      result['reason'] = null;

      return result;
    } catch (e) {
      debugPrint('Error checking barber availability: $e');
      result['is_available'] = false;
      result['reason'] = 'Error checking availability';
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
          ).format(_selectedDate ?? DateTime.now()),
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

      List<Map<String, dynamic>> barberList =
          List<Map<String, dynamic>>.from(result);

      for (var i = 0; i < barberList.length; i++) {
        barberList[i]['id'] = barberList[i]['barber_id'];
      }

      final dateToCheck = _selectedDate ?? DateTime.now();

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
      final existing = await supabase
          .from('appointments')
          .select('id')
          .eq('customer_id', user.id)
          .eq('appointment_date', dateStr)
          .or('child_name.eq.$childName,child_name.is.null')
          .not('status', 'in', '("cancelled","no_show")');
      if (!mounted) return;
      setState(() {
        _duplicateError = existing.isNotEmpty
            ? '⚠️ You already have a booking for ${childName.isEmpty ? "yourself" : childName} on ${DateFormat('MMM dd').format(_selectedDate!)}.'
            : null;
      });
    } catch (e) {
      debugPrint('Error checking duplicate: $e');
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

  Widget _buildTimezoneIndicator() {
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TimezoneService.getCurrentFlag(),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Text(
            TimezoneService.getTimezoneDisplayName(),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${TimezoneService.getUtcOffsetString()})',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.grey[500],
            ),
          ),
          if (_isDST()) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.amber.shade900 : Colors.amber.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'DST',
                style: TextStyle(
                  fontSize: 9,
                  color:
                      isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadAvailableSlots() async {
    // ═══════════════════════════════════════════════════
    // GUARD: Required values MUST be non-null
    // ═══════════════════════════════════════════════════
    if (_selectedDate == null) {
      debugPrint('⚠️ _loadAvailableSlots: _selectedDate is null');
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
      debugPrint('⚠️ _loadAvailableSlots: _selectedBarber is null');
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
      debugPrint('⚠️ _loadAvailableSlots: _selectedSalon is null');
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Salon not selected.';
          _slotErrorType = 'general';
        });
      }
      return;
    }

    final dynamic rawBarberId = _selectedBarber!['id'];
    if (rawBarberId == null) {
      debugPrint('⚠️ _loadAvailableSlots: barber id is null');
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Barber data incomplete.';
          _slotErrorType = 'barber';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingSlots = true;
        _availableSlots = [];
        _selectedSlot = null;
        _showTravelTimeSelector = false;
        _slotErrorMessage = null;
        _slotErrorType = null;
      });
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Please login again.';
          _slotErrorType = 'general';
        });
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final totalDuration = _calculateTotalDuration();
      final isToday = _selectedDate!.isAtSameMomentAs(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );

      final result = await supabase
          .rpc(
            'calculate_next_queue_start_advanced',
            params: {
              'p_barber_id': _selectedBarber!['id'],
              'p_appointment_date': dateStr,
              'p_service_duration': totalDuration,
              'p_travel_time_minutes': _selectedTravelTime,
              'p_salon_id': _selectedSalon!['id'],
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (result == null) throw Exception('No response');
      final data = result is List && result.isNotEmpty ? result[0] : result;

      final conflictType = data['conflict_type']?.toString() ?? '';
      final extensionMinutes = data['extension_minutes'] ?? 0;

      // ─── Date-related errors ───
      if (isToday &&
          (conflictType == 'OVERFLOW' || conflictType == 'MOVE_TO_NEXT_DAY')) {
        setState(() {
          _slotErrorMessage =
              'No appointments available on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\n'
              'Your requested time would exceed salon closing time by $extensionMinutes minutes.\n\n'
              'Please select another date or try tomorrow.';
          _slotErrorType = 'overflow';
          _isLoadingSlots = false;
        });
        return;
      }

      if (conflictType == 'SALON_CLOSED') {
        setState(() {
          _slotErrorMessage =
              'Salon is closed on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\nPlease select another date.';
          _slotErrorType = 'salon_closed';
          _isLoadingSlots = false;
        });
        return;
      }

      // ─── Barber-related error ───
      if (conflictType == 'BARBER_UNAVAILABLE') {
        setState(() {
          _slotErrorMessage =
              '${_selectedBarber!['full_name']} is not working on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\nPlease select another barber.';
          _slotErrorType = 'barber';
          _isLoadingSlots = false;
        });
        return;
      }

      // ─── Date-full error ───
      if (conflictType == 'NO_SLOTS_REMAINING') {
        setState(() {
          _slotErrorMessage =
              'No appointments available on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\nAll time slots are fully booked. Please select another date.';
          _slotErrorType = 'date_full';
          _isLoadingSlots = false;
        });
        return;
      }

      if (data['needs_travel_selector'] == true &&
          _selectedTravelTime == 0 &&
          isToday) {
        setState(() {
          _showTravelTimeSelector = true;
          _isLoadingSlots = false;
        });
        return;
      }

      String utcStart = data['new_start_time']?.toString() ?? '--:--';
      String utcEnd = data['new_end_time']?.toString() ?? '--:--';

      String localStart = TimezoneService.utcToLocalTimeForDate(
        utcStart,
        _selectedDate!,
      );
      String localEnd = TimezoneService.utcToLocalTimeForDate(
        utcEnd,
        _selectedDate!,
      );

      final queueNum = data['new_queue_number'] is int
          ? data['new_queue_number']
          : 1;
      final wait = data['estimated_wait_minutes'] is int
          ? data['estimated_wait_minutes']
          : 0;
      final extMins = data['extension_minutes'] is int
          ? data['extension_minutes']
          : 0;
      final willExtend = data['salon_will_extend'] == true;
      final adjusted = data['adjusted_for']?.toString() ?? '';

      final newSlot = {
        'start_time': localStart,
        'end_time': localEnd,
        'utc_start_time': utcStart,
        'utc_end_time': utcEnd,
        'queue_number': queueNum,
        'is_available': true,
        'duration': totalDuration,
        'estimated_wait_minutes': wait,
        'travel_time_used': _selectedTravelTime,
        'salon_will_extend': willExtend,
        'extension_minutes': extMins,
        'adjusted_for': adjusted,
      };

      setState(() {
        _availableSlots = [newSlot];
        _selectedSlot = newSlot;
        _isLoadingSlots = false;
        _slotErrorMessage = null;
        _slotErrorType = null;
        _showTravelTimeSelector = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _slotErrorMessage =
            'Failed to load time slots.\n\nError: ${e.toString().replaceFirst('Exception: ', '')}';
        _slotErrorType = 'general';
        _availableSlots = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted && _isLoadingSlots) {
        setState(() => _isLoadingSlots = false);
      }
    }
  }

  // ==================== STEP 6: CONFIRM ====================

  String _getAdjustedForDisplay(String adjustedFor) {
    if (adjustedFor.contains('VIP_AFTER')) {
      return 'Time adjusted - After VIP appointment';
    }
    if (adjustedFor.contains('VIP_PUSHED')) {
      return 'VIP appointment rescheduled after this';
    }
    if (adjustedFor.contains('BREAK_AFTER')) {
      return 'Time adjusted - After barber break';
    }
    if (adjustedFor.contains('LEAVE_AFTER')) {
      return 'Time adjusted - After barber leave';
    }
    if (adjustedFor.contains('SALON_EXTEND')) {
      return 'Salon hours extended for this appointment';
    }
    if (adjustedFor.contains('TRAVEL')) return 'Travel time added';
    if (adjustedFor.contains('AFTER_EFFECTIVE')) {
      return 'Adjusted due to previous appointment';
    }
    return 'Time adjusted based on availability';
  }

  Future<void> _confirmBooking() async {
    if (!mounted) return;

    if (_selectedServices.isEmpty) {
      _showErrorSnack('Please select at least one service');
      return;
    }

    for (final s in _selectedServices) {
      if (s['variant_id'] == null) {
        _showErrorSnack('Invalid service: ${s['name']} has no variant');
        return;
      }
    }

    if (_selectedSalon == null ||
        _selectedBarber == null ||
        _selectedDate == null ||
        _selectedSlot == null) {
      _showErrorSnack('Missing booking information. Please complete all steps.');
      return;
    }

    setState(() => _isBooking = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please login to continue');

      final variantIds = <int>[];
      final offerIds = <int?>[];

      for (final s in _selectedServices) {
        final vid = s['variant_id'] as int?;
        if (vid == null) continue;
        variantIds.add(vid);
        offerIds.add(s['offer_id'] as int?);
      }

      if (variantIds.isEmpty) {
        throw Exception('No valid services selected.');
      }
      if (variantIds.length != _selectedServices.length) {
        throw Exception('Some services have invalid variants.');
      }

      final result = await supabase.rpc(
        'create_new_appointment_advanced',
        params: {
          'p_customer_id': user.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': _selectedBarber!['id'],
          'p_variant_ids': variantIds,
          'p_offer_ids': offerIds,
          'p_appointment_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
          'p_utc_start_time': _selectedSlot!['utc_start_time'],
          'p_utc_end_time': _selectedSlot!['utc_end_time'],
          'p_child_name': _getChildNameForBooking(),
          'p_travel_time_minutes': _selectedSlot!['travel_time_used'] ?? 0,
          'p_notes': null,
          'p_is_vip': false,
          'p_vip_booking_id': null,
          'p_confirm_overflow': true,
        },
      );

      if (!mounted) return;

      if (result == null || result['success'] != true) {
        final msg = result?['message']?.toString() ?? 'Booking failed';
        final code = result?['error_code']?.toString() ?? '';
        throw Exception(code.isNotEmpty ? '$msg ($code)' : msg);
      }

      final queueDisplay =
          result['display_queue']?.toString() ??
          result['regular_queue_number']?.toString() ??
          'N/A';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('✅ Booking Confirmed! Queue $queueDisplay')),
            ],
          ),
          backgroundColor: _secondaryColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ BOOKING FAILED: $e');
      debugPrint('   Stack: $stackTrace');

      if (!mounted) return;
      setState(() {
        _isBooking = false;
        _slotErrorMessage =
            'Booking failed: ${e.toString().replaceFirst('Exception: ', '')}';
        _slotErrorType = 'general';
        _currentStep = 5;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Booking failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
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

  String _getSalonLocalTime(Map<String, dynamic> salon) {
    final openTimeUTC = salon['open_time']?.toString() ?? '09:00:00';
    final closeTimeUTC = salon['close_time']?.toString() ?? '18:00:00';

    final openLocal = TimezoneService.utcToLocalTimeRecurring(openTimeUTC);
    final closeLocal = TimezoneService.utcToLocalTimeRecurring(closeTimeUTC);

    return '$openLocal - $closeLocal';
  }

  // ============================================
  // BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isDark = context.isDarkMode;

    _checkScreenSize();

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : _bgLight,
        appBar: AppBar(
          title: const Text('Book Appointment'),
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

    final stepSize = isMobile ? 36.0 : 42.0;
    final iconSize = isMobile ? 18.0 : 20.0;
    final stepFontSize = isMobile ? 9.0 : 11.0;
    final connectorWidth = isMobile ? 20.0 : 35.0;
    final showLabels = !isMobile;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : _bgLight,
      appBar: AppBar(
        title: Text(
          'Book Appointment',
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
            // ✅ Smart back: if preselected + on Date step → go to Salon
            final hasPreselected = _preselectedServices != null &&
                _preselectedServices!.isNotEmpty;

            if (_currentStep == 2 && hasPreselected) {
              setState(() => _currentStep = 0);
            } else if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          _buildTimezoneFlag(),
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
            final double safeHeight =
                (constraints.maxHeight.isFinite &&
                        constraints.maxHeight >= 200)
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
    return Container(
      color: context.cardColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 20,
            vertical: isMobile ? 12 : 16,
          ),
          child: Row(
            children: [
              _buildStepIndicatorResponsive(
                0,
                showLabels ? 'Salon' : '',
                Icons.store,
                stepSize,
                iconSize,
                stepFontSize,
              ),
              Container(
                width: connectorWidth,
                height: 2,
                color: _currentStep > 0 ? AppTheme.primary : Colors.grey[300],
              ),
              _buildStepIndicatorResponsive(
                1,
                showLabels ? 'Service' : '',
                Icons.content_cut,
                stepSize,
                iconSize,
                stepFontSize,
              ),
              Container(
                width: connectorWidth,
                height: 2,
                color: _currentStep > 1 ? AppTheme.primary : Colors.grey[300],
              ),
              _buildStepIndicatorResponsive(
                2,
                showLabels ? 'Date' : '',
                Icons.calendar_today,
                stepSize,
                iconSize,
                stepFontSize,
              ),
              Container(
                width: connectorWidth,
                height: 2,
                color: _currentStep > 2 ? AppTheme.primary : Colors.grey[300],
              ),
              _buildStepIndicatorResponsive(
                3,
                showLabels ? 'Barber' : '',
                Icons.person,
                stepSize,
                iconSize,
                stepFontSize,
              ),
              Container(
                width: connectorWidth,
                height: 2,
                color: _currentStep > 3 ? AppTheme.primary : Colors.grey[300],
              ),
              _buildStepIndicatorResponsive(
                4,
                showLabels ? 'Person' : '',
                Icons.badge,
                stepSize,
                iconSize,
                stepFontSize,
              ),
              Container(
                width: connectorWidth,
                height: 2,
                color: _currentStep > 4 ? AppTheme.primary : Colors.grey[300],
              ),
              _buildStepIndicatorResponsive(
                5,
                showLabels ? 'Time' : '',
                Icons.access_time,
                stepSize,
                iconSize,
                stepFontSize,
              ),
              Container(
                width: connectorWidth,
                height: 2,
                color: _currentStep > 5 ? AppTheme.primary : Colors.grey[300],
              ),
              _buildStepIndicatorResponsive(
                6,
                showLabels ? 'Confirm' : '',
                Icons.check_circle,
                stepSize,
                iconSize,
                stepFontSize,
              ),
            ],
          ),
        ),
      ),
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
                  : _searchResults.isEmpty &&
                          !_isSearching &&
                          _allSalons.isNotEmpty
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
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var s in _salonServices) {
      final catName = s['category_name']?.toString() ?? 'Other';
      (grouped[catName] ??= []).add(s);
    }
    final categories = grouped.keys.toList();
    if (_selectedCategoryTab == null && categories.isNotEmpty) {
      _selectedCategoryTab = categories.first;
    }
    final servicesToShow = _selectedCategoryTab == null
        ? _salonServices
        : grouped[_selectedCategoryTab] ?? [];

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  image:
                      (_selectedSalon?['logo_url'] as String?) != null &&
                              (_selectedSalon!['logo_url'] as String)
                                  .isNotEmpty
                          ? DecorationImage(
                              image:
                                  NetworkImage(_selectedSalon!['logo_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                ),
                child:
                    (_selectedSalon?['logo_url'] == null ||
                            (_selectedSalon!['logo_url'] as String).isEmpty)
                        ? Center(
                            child: Text(
                              (_selectedSalon?['name'] as String?)
                                      ?.substring(0, 1)
                                      .toUpperCase() ??
                                  'S',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
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
                      'Selected Salon',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedSalon?['name'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: Text(
                  'Change',
                  style: TextStyle(color: AppTheme.primary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),

        if (_selectedServices.isNotEmpty)
          GestureDetector(
            onTap: () => _showSelectedServicesSheet(),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedServices.length}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_selectedServices.length} Service${_selectedServices.length > 1 ? 's' : ''} Selected',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedServices
                              .map((s) => s['name']?.toString() ?? '')
                              .take(2)
                              .join(', '),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        if (_discountAmount > 0) ...[
                          Text(
                            'Rs. ${_calculateTotalPrice().toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.7),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          'Rs. ${_getDisplayTotalPrice().toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        _buildLegacyOfferBanner(isDark),

        SizedBox(
          height: 45,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FilterChip(
                label: Text(
                  'All',
                  style: TextStyle(
                    fontSize: 13,
                    color: _selectedCategoryTab == null
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.grey[700]),
                  ),
                ),
                selected: _selectedCategoryTab == null,
                onSelected: (_) => setState(() => _selectedCategoryTab = null),
                backgroundColor:
                    isDark ? const Color(0xFF2A2A2A) : Colors.white,
                selectedColor: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              ...categories.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        fontSize: 13,
                        color: _selectedCategoryTab == c
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.grey[700]),
                      ),
                    ),
                    selected: _selectedCategoryTab == c,
                    onSelected: (_) =>
                        setState(() => _selectedCategoryTab = c),
                    backgroundColor:
                        isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    selectedColor: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _isLoadingServices
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : servicesToShow.isEmpty
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
                              color:
                                  isDark ? Colors.white30 : Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No services available',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: servicesToShow.length,
                      itemBuilder: (context, index) => _buildServiceCard(
                        servicesToShow[index],
                        index,
                        isMobile,
                      ),
                    ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedServices.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _currentStep = 2;
                      });
                      _loadHolidays();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedServices.isNotEmpty
                    ? AppTheme.primary
                    : (isDark ? Colors.grey[700] : Colors.grey[400]),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
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
                  '🎉 Offer Detected',
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
            onPressed: () {
              setState(() => _appliedOffer = null);
            },
            style: TextButton.styleFrom(
              foregroundColor:
                  isDark ? Colors.green.shade300 : Colors.green.shade700,
            ),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(
    Map<String, dynamic> service,
    int index,
    bool isMobile,
  ) {
    final isDark = context.isDarkMode;
    final variants = service['variants'] as List? ?? [];
    final isAnyVariantSelected = _selectedServices.any(
      (s) => s['id'] == service['id'],
    );
    final int serviceId = service['id'] as int;
    final isExpanded = _expandedServiceId == serviceId;

    final String serviceName = service['name']?.toString() ?? 'Service';
    final String categoryName = service['category_name']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: isDark
          ? const Color(0xFF2A2A2A)
          : _cardColors[index % _cardColors.length],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isAnyVariantSelected ? AppTheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? const Color(0xFF2A2A2A)
              : _cardColors[index % _cardColors.length],
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                if (isMobile && variants.isNotEmpty) {
                  setState(() {
                    if (isExpanded) {
                      _expandedServiceId = null;
                    } else {
                      _expandedServiceId = serviceId;
                    }
                  });
                }
              },
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF3A3A3A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getServiceIcon(serviceName),
                        color: AppTheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serviceName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            categoryName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                          if (isAnyVariantSelected) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedServices.where((s) => s['id'] == service['id']).length} selected',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isMobile && variants.isNotEmpty)
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: isDark ? Colors.white60 : Colors.grey[500],
                        size: 24,
                      ),
                  ],
                ),
              ),
            ),

            if (variants.isNotEmpty && (!isMobile || isExpanded))
              Column(
                children: [
                  const Divider(color: Colors.grey, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: variants
                          .map((v) => _buildVariantRow(service, v))
                          .toList(),
                    ),
                  ),
                ],
              ),

            if (variants.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'No variants available',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark ? Colors.white60 : Colors.grey[600],
                        ),
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

  Widget _buildVariantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final isDark = context.isDarkMode;
    final int serviceId = service['id'] as int;
    final int variantId = variant['id'] as int;
    final key = _serviceKey(serviceId, variantId);

    final isSelected = _selectedServices.any(
      (s) => s['id'] == serviceId && s['variant_id'] == variantId,
    );
    final isMobile = MediaQuery.of(context).size.width < 600;

    final String gender = variant['gender']?.toString() ?? '';
    final String age = variant['age']?.toString() ?? '';
    final String genderLower = gender.toLowerCase();

    IconData genderIcon;
    if (genderLower.contains('male')) {
      genderIcon = Icons.male;
    } else if (genderLower.contains('female')) {
      genderIcon = Icons.female;
    } else {
      genderIcon = Icons.people;
    }

    final double price = (variant['price'] as num?)?.toDouble() ?? 0.0;
    final int duration = (variant['duration'] as num?)?.toInt() ?? 30;

    final availableOffers = _availableOffersPerService[key] ?? [];
    final selectedOffer = _serviceOffers[key];
    final discount = _calculateOfferDiscount(price, selectedOffer);
    final finalPrice = price - discount;
    final hasOffer = selectedOffer != null && discount > 0;

    final String displayText = '$gender $age'.trim();

    return Column(
      children: [
        GestureDetector(
          onTap: () => _toggleVariant(service, variant),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary
                    : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: isMobile ? 40 : 44,
                  height: isMobile ? 40 : 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.2)
                        : (isDark ? const Color(0xFF3A3A3A) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    genderIcon,
                    size: isMobile ? 22 : 24,
                    color: isSelected
                        ? AppTheme.primary
                        : (isDark ? Colors.white60 : Colors.grey[600]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayText.isEmpty ? 'Variant' : displayText,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: isMobile ? 13 : 15,
                          color: isSelected
                              ? AppTheme.primary
                              : (isDark ? Colors.white : _textDark),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.currency_rupee,
                                size: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 2),
                              if (hasOffer && isSelected)
                                Text(
                                  price.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey[500],
                                    decoration:
                                        TextDecoration.lineThrough,
                                  ),
                                ),
                              if (hasOffer && isSelected)
                                const SizedBox(width: 4),
                              Text(
                                (isSelected && hasOffer ? finalPrice : price)
                                    .toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: hasOffer && isSelected
                                      ? (isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade700)
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer,
                                size: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 2),
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
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 12,
                    vertical: isMobile ? 6 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : (isDark ? Colors.grey[800] : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? Icons.check : Icons.add,
                        size: isMobile ? 14 : 16,
                        color:
                            isSelected ? Colors.white : AppTheme.primary,
                      ),
                      if (!isMobile) ...[
                        const SizedBox(width: 4),
                        Text(
                          isSelected ? 'Selected' : 'Select',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        if (isSelected && availableOffers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.2)
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.amber.shade700
                      : Colors.amber.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_offer,
                        size: 14,
                        color: isDark
                            ? Colors.amber.shade300
                            : Colors.amber.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Available Offers (${availableOffers.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Map<String, dynamic>?>(
                    initialValue: selectedOffer,
                    isExpanded: true,
                    isDense: true,
                    decoration: InputDecoration(
                      hintText: 'No offer applied',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    items: [
                      DropdownMenuItem<Map<String, dynamic>?>(
                        value: null,
                        child: Text(
                          'No offer',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey,
                          ),
                        ),
                      ),
                      ...availableOffers.map((offer) {
                        return DropdownMenuItem<Map<String, dynamic>?>(
                          value: offer,
                          child: Text(
                            _getOfferLabel(offer),
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (offer) {
                      _applyOfferToService(serviceId, variantId, offer);
                    },
                  ),
                  if (hasOffer) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.green.shade900.withValues(alpha: 0.5)
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: isDark
                                ? Colors.green.shade300
                                : Colors.green.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Save Rs. ${discount.toStringAsFixed(2)} → Pay Rs. ${finalPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.green.shade200
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
      builder: (context) => DraggableScrollableSheet(
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
                              color:
                                  isDark ? Colors.white : Colors.black87,
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
                            _availableOffersPerService.clear();
                            _serviceOffers.clear();
                            _recalculateTotals();
                          });
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear All',
                          style: TextStyle(
                            color:
                                isDark ? Colors.red.shade300 : Colors.red,
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
                              color:
                                  isDark ? Colors.white60 : Colors.grey,
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
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey,
                              ),
                            ),
                            Text(
                              'Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
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
                              '− Rs. ${_discountAmount.toStringAsFixed(2)}',
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
                              color:
                                  isDark ? Colors.white60 : Colors.grey,
                            ),
                          ),
                          Text(
                            'Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
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
    );
  }

  Widget _buildSelectedServiceItem(
    Map<String, dynamic> service,
    int index,
  ) {
    final isDark = context.isDarkMode;
    final String serviceName = service['name']?.toString() ?? 'Service';
    final String gender = service['gender']?.toString() ?? '';
    final String age = service['age']?.toString() ?? '';
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
                      '$gender $age • $duration min',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (discount > 0)
                    Text(
                      'Rs. ${price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        decoration: TextDecoration.lineThrough,
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  Text(
                    'Rs. ${finalPrice.toStringAsFixed(2)}',
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
                ],
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    final removed = _selectedServices.removeAt(index);
                    final key = _serviceKey(
                      removed['id'] as int,
                      removed['variant_id'] as int?,
                    );
                    _serviceOffers.remove(key);
                    _availableOffersPerService.remove(key);
                    _recalculateTotals();
                  });
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
                    '${offer['title']} — save Rs. ${discount.toStringAsFixed(2)}',
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
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final maxDate = today.add(const Duration(days: 30));
    final isMobile = MediaQuery.of(context).size.width < 600;

    bool isDateSelectable(DateTime date) {
      if (_holidays.contains(date)) return false;
      if (date.isBefore(today)) return false;
      return true;
    }

    DateTime getFirstAvailableDate() {
      DateTime checkDate = today;
      if (!_holidays.contains(checkDate)) {
        return checkDate;
      }
      for (int i = 1; i < 30; i++) {
        checkDate = today.add(Duration(days: i));
        if (!_holidays.contains(checkDate)) {
          return checkDate;
        }
      }
      return today.add(const Duration(days: 1));
    }

    void initializeDefaultDate() {
      if (_selectedDate == null) {
        final firstAvailable = getFirstAvailableDate();
        if (_holidays.contains(today)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _selectedDate = firstAvailable;
              _isDateUnavailable = false;
            });
            _checkDateAvailability(firstAvailable);
          });
        }
      }
    }

    initializeDefaultDate();

    final isSelectedDateHoliday =
        _selectedDate != null && _holidays.contains(_selectedDate);
    final selectedHolidayName = isSelectedDateHoliday
        ? _holidayNames[_selectedDate]
        : null;
    final isSelectedToday =
        _selectedDate != null && _selectedDate!.isAtSameMomentAs(today);

    return Column(
      children: [
        if (_selectedServices.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Row(
              children: [
                Icon(Icons.content_cut, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedServices.length} service${_selectedServices.length > 1 ? 's' : ''} • ${_calculateTotalDuration()} min • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: Text(
                    'Change',
                    style:
                        TextStyle(color: AppTheme.primary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: isMobile ? 100 : 16,
            ),
            child: Column(
              children: [
                if (_holidays.contains(today))
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color:
                          isDark ? Colors.red.shade900 : Colors.red.shade50,
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
                                _holidayNames[today] ??
                                    'Salon is closed today',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade600,
                                ),
                              ),
                              Text(
                                'Auto-selected next available date: ${DateFormat('EEEE, MMM dd').format(_selectedDate ?? getFirstAvailableDate())}',
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

                Card(
                  elevation: 3,
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CalendarDatePicker(
                      initialDate: getFirstAvailableDate(),
                      firstDate: today,
                      lastDate: maxDate,
                      selectableDayPredicate: (date) =>
                          isDateSelectable(date),
                      onDateChanged: (date) async {
                        setState(() {
                          _selectedDate = date;
                          _isDateUnavailable = false;
                        });
                        await _checkDateAvailability(date);
                      },
                    ),
                  ),
                ),

                if (isSelectedDateHoliday)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          isDark ? Colors.red.shade900 : Colors.red.shade50,
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

                if (_selectedDate != null &&
                    !_holidays.contains(_selectedDate))
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

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.2 : 0.1,
                ),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_selectedDate != null &&
                          !_isDateUnavailable &&
                          !_holidays.contains(_selectedDate))
                      ? () async {
                          setState(() {
                            _currentStep = 3;
                            _barbersLoaded = false;
                            _barberAvailability.clear();
                            _availableBarbers = [];
                            _selectedBarber = null;
                          });
                          await _loadAvailableBarbers();
                        }
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    (_selectedDate != null &&
                            !_isDateUnavailable &&
                            !_holidays.contains(_selectedDate))
                        ? AppTheme.primary
                        : (isDark ? Colors.grey[700] : Colors.grey[400]),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedDate == null
                        ? 'Please Select a Date'
                        : (_holidays.contains(_selectedDate)
                            ? '🚫 Holiday - Not Available'
                            : (_isDateUnavailable
                                ? 'No Barbers Available'
                                : 'Continue to Barber')),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_selectedDate != null &&
                      !_isDateUnavailable &&
                      !_holidays.contains(_selectedDate))
                    const SizedBox(width: 8),
                  if (_selectedDate != null &&
                      !_isDateUnavailable &&
                      !_holidays.contains(_selectedDate))
                    const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
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
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  image:
                      (_selectedSalon?['logo_url'] as String?) != null &&
                              (_selectedSalon!['logo_url'] as String)
                                  .isNotEmpty
                          ? DecorationImage(
                              image:
                                  NetworkImage(_selectedSalon!['logo_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                ),
                child:
                    (_selectedSalon?['logo_url'] == null ||
                            (_selectedSalon!['logo_url'] as String).isEmpty)
                        ? Center(
                            child: Text(
                              (_selectedSalon?['name'] as String?)
                                      ?.substring(0, 1)
                                      .toUpperCase() ??
                                  'S',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
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
                      'Services: ${_selectedServices.length}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_calculateTotalDuration()} min total • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: Text(
                  'Change',
                  style: TextStyle(color: AppTheme.primary, fontSize: 14),
                ),
              ),
            ],
          ),
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
                              color:
                                  isDark ? Colors.white30 : Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No barbers available',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.2 : 0.1,
                ),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedBarber == null
                  ? null
                  : () {
                      setState(() {
                        _currentStep = 4;
                        _childNameController.clear();
                        _selectedChildName = null;
                        _isSameAsCustomer = true;
                        _duplicateError = null;
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedBarber != null
                    ? AppTheme.primary
                    : (isDark ? Colors.grey[700] : Colors.grey[400]),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
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
    final hasSpecialSchedule =
        availability?['has_special_schedule'] ?? false;
    final hasSpecialBreak = availability?['has_special_break'] ?? false;

    final String barberName =
        barber['full_name']?.toString() ?? 'Barber';
    final String avatarUrl = barber['avatar_url']?.toString() ?? '';
    final double avgRating =
        (barber['avg_rating'] as num?)?.toDouble() ?? 0.0;
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
                : (isAvailable
                    ? Colors.transparent
                    : Colors.red.shade200),
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
                  backgroundColor:
                      AppTheme.primary.withValues(alpha: 0.1),
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
                                color: isDark
                                    ? Colors.white
                                    : Colors.black87,
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
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.work,
                            size: 16,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$todayAppointments today',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      if (hasSpecialSchedule)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: isDark
                                    ? Colors.amber.shade300
                                    : Colors.amber.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Special schedule today',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.amber.shade300
                                      : Colors.amber.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasSpecialBreak)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.free_breakfast,
                                size: 14,
                                color: isDark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Special break today',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!isAvailable &&
                          availability?['reason'] != null)
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
                      color: isSelected
                          ? AppTheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark
                                ? Colors.grey[600]!
                                : Colors.grey[400]!),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
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
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  _selectedBarber?['full_name']
                          ?.toString()
                          .substring(0, 1)
                          .toUpperCase() ??
                      'B',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedBarber?['full_name']?.toString() ??
                          'Barber',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${_calculateTotalDuration()} min service • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
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
              TextButton(
                onPressed: () => setState(() => _currentStep = 3),
                child: Text(
                  'Change',
                  style: TextStyle(color: AppTheme.primary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        if (_selectedDate != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 18, color: _secondaryColor),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy')
                      .format(_selectedDate!),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 2),
                  child: Text(
                    'Change',
                    style:
                        TextStyle(color: AppTheme.primary, fontSize: 14),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Who is this appointment for?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Select who will receive the service',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                _buildPersonOption(
                  isSelected: _isSameAsCustomer,
                  icon: Icons.person,
                  title: 'Myself',
                  subtitle: customerName,
                  description: 'Booking for yourself',
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
                const SizedBox(height: 12),
                _buildPersonOption(
                  isSelected: !_isSameAsCustomer,
                  icon: Icons.group,
                  title: 'Someone else',
                  subtitle: 'Family member, friend, or child',
                  description:
                      !_isSameAsCustomer &&
                              _selectedChildName != null &&
                              _selectedChildName!.isNotEmpty
                          ? 'Will book for: $_selectedChildName'
                          : null,
                  onTap: () => setState(() {
                    _isSameAsCustomer = false;
                    _duplicateError = null;
                  }),
                ),
                if (!_isSameAsCustomer) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _childNameController,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter full name',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color:
                            isDark ? Colors.white70 : Colors.grey[400],
                      ),
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
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
                ],
                if (_duplicateError != null)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.red.shade900
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
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
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.shade900
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Each person can only have one booking per day.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade700,
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.2 : 0.1,
                ),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canProceedToTimeSlot()
                  ? () async {
                      if (await _validateAndProceed()) {
                        setState(() {
                          _currentStep = 5;
                          _showTravelTimeSelector = false;
                          _selectedTravelTime = 0;
                          _availableSlots = [];
                          _selectedSlot = null;
                          _isLoadingSlots = true;
                          _slotErrorMessage = null;
                          _slotErrorType = null;
                        });
                        await _loadAvailableSlots();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canProceedToTimeSlot()
                    ? AppTheme.primary
                    : (isDark ? Colors.grey[700] : Colors.grey[400]),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
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
    String? description,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDarkMode;

    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      elevation: isSelected ? 4 : 1,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon, size: 30, color: AppTheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                    if (description != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected ? AppTheme.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primary
                        : (isDark
                            ? Colors.grey[600]!
                            : Colors.grey[400]!),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // STEP 5: TIME SLOT SELECTION
  // ============================================

  Widget _buildTimeSlotStep() {
    final isDark = context.isDarkMode;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  _selectedBarber?['full_name']
                          ?.toString()
                          .substring(0, 1)
                          .toUpperCase() ??
                      'B',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedBarber?['full_name']?.toString() ??
                          'Barber',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${_calculateTotalDuration()} min service • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
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
              TextButton(
                onPressed: () => setState(() => _currentStep = 3),
                child: Text(
                  'Change',
                  style: TextStyle(color: AppTheme.primary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        if (_selectedDate != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 18, color: _secondaryColor),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy')
                      .format(_selectedDate!),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 2),
                  child: Text(
                    'Change',
                    style:
                        TextStyle(color: AppTheme.primary, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        _buildTimezoneIndicator(),
        Expanded(
          child: _isLoadingSlots
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _slotErrorMessage != null
                  ? _buildNoSlotsState(isDark)
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding:
                          EdgeInsets.only(bottom: isMobile ? 100 : 16),
                      child: Column(
                        children: [
                          if (_availableSlots.isNotEmpty)
                            _buildTimeSlotCard(_availableSlots.first),
                          if (_showTravelTimeSelector)
                            _buildTravelTimeSelector(),
                        ],
                      ),
                    ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isDark ? 0.2 : 0.1,
                ),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_selectedSlot != null &&
                          !_isLoadingSlots &&
                          _availableSlots.isNotEmpty &&
                          _slotErrorMessage == null)
                      ? () => setState(() => _currentStep = 6)
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    (_selectedSlot != null &&
                            !_isLoadingSlots &&
                            _availableSlots.isNotEmpty &&
                            _slotErrorMessage == null)
                        ? AppTheme.primary
                        : (isDark ? Colors.grey[700] : Colors.grey[400]),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Continue to Confirmation',
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
          ),
        ),
      ],
    );
  }

  // ✅ DYNAMIC BUTTONS based on error type
  Widget _buildNoSlotsState(bool isDark) {
    final errorType = _slotErrorType ?? 'general';

    // ✅ Date-related errors → "Change Date" + "Try Tomorrow"
    final showDateButtons = errorType == 'date' ||
        errorType == 'overflow' ||
        errorType == 'salon_closed' ||
        errorType == 'date_full';

    // ✅ Barber-related errors → "Try Another Barber"
    final showBarberButton = errorType == 'barber';

    // ✅ General errors → "Go Back"
    final showGoBack = errorType == 'general';

    debugPrint('🎨 [NoSlotsState] type: $errorType');
    debugPrint('   showDateButtons: $showDateButtons');
    debugPrint('   showBarberButton: $showBarberButton');

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
              color:
                  isDark ? Colors.orange.shade400 : Colors.orange.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              'No Appointments Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              child: Text(
                _slotErrorMessage ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ═══════════════════════════════════════════════════
            // DYNAMIC BUTTONS — based on error type
            // ═══════════════════════════════════════════════════
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                // ✅ Date-related: "Change Date" button
                if (showDateButtons)
                  OutlinedButton.icon(
                    onPressed: () {
                      debugPrint('🔄 [Change Date] → Step 2');
                      setState(() {
                        _slotErrorMessage = null;
                        _slotErrorType = null;
                        _currentStep = 2;
                        _showTravelTimeSelector = false;
                        _selectedTravelTime = 0;
                        _availableSlots = [];
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

                // ✅ Date-related: "Try Tomorrow" button
                if (showDateButtons)
                  ElevatedButton.icon(
onPressed: () async {
  if (_selectedDate == null) return;

  final tomorrow = _selectedDate!.add(const Duration(days: 1));

  // ✅ Save current barber BEFORE any state change
  final savedBarber = _selectedBarber;
  final savedSalon = _selectedSalon;

  debugPrint('════════════════════════════════════════');
  debugPrint('🔄 [Try Tomorrow] Clicked');
  debugPrint('   From date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}');
  debugPrint('   To date:   ${DateFormat('yyyy-MM-dd').format(tomorrow)}');
  debugPrint('   Saved barber: ${savedBarber?['id']}');
  debugPrint('   Saved salon: ${savedSalon?['id']}');
  debugPrint('════════════════════════════════════════');

  setState(() {
    _selectedDate = tomorrow;
    _showTravelTimeSelector = false;
    _selectedTravelTime = 0;
    _availableSlots = [];
    _selectedSlot = null;
    _isLoadingSlots = true;
    _slotErrorMessage = null;
    _slotErrorType = null;
  });

  try {
    // ═══════════════════════════════════════════════════
    // STEP 1: Check holiday (manually - don't reset barber)
    // ═══════════════════════════════════════════════════
    final isHoliday = _holidays.contains(tomorrow);
    if (isHoliday) {
      debugPrint('⚠️ Tomorrow is a holiday');
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _slotErrorMessage =
            '${_holidayNames[tomorrow] ?? 'Holiday'} — Salon is closed tomorrow.\n\nPlease select another date.';
        _slotErrorType = 'salon_closed';
      });
      return;
    }

    // ═══════════════════════════════════════════════════
    // STEP 2: Validate that current barber works tomorrow
    //         (using the barber we saved earlier)
    // ═══════════════════════════════════════════════════
    if (savedBarber == null || savedSalon == null) {
      debugPrint('⚠️ No saved barber/salon');
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _selectedBarber = null;
        _barbersLoaded = false;
        _barberAvailability = {};
        _availableBarbers = [];
        _currentStep = 3; // Barber step
      });
      return;
    }

    debugPrint('🔍 Validating barber ${savedBarber['id']} for tomorrow...');

    final availability = await _checkBarberFullAvailability(
      savedBarber['id'] as String,
      tomorrow,
    );

    debugPrint('   Available: ${availability['is_available']}');
    debugPrint('   Reason: ${availability['reason']}');

    if (!mounted) return;

    // ═══════════════════════════════════════════════════
    // STEP 3A: Barber NOT available tomorrow
    //          → Send user to Barber step to pick another
    // ═══════════════════════════════════════════════════
    if (availability['is_available'] != true) {
      debugPrint('❌ Barber not available tomorrow');

      setState(() {
        _selectedBarber = null;
        _barbersLoaded = false;
        _barberAvailability = {};
        _availableBarbers = [];
        _isLoadingSlots = false;
        _currentStep = 3; // Barber step
      });

      await _loadAvailableBarbers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${savedBarber['full_name']} is not available on '
            '${DateFormat('MMM dd').format(tomorrow)}. '
            'Please select another barber.',
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // ═══════════════════════════════════════════════════
    // STEP 3B: Barber IS available tomorrow ✅
    //          → Keep same barber, load slots (STAY on Time step)
    // ═══════════════════════════════════════════════════
    debugPrint('✅ Barber available — keeping barber, loading slots');

    setState(() {
      // ✅ Re-select the same barber (still valid)
      _selectedBarber = savedBarber;
      _barberAvailability = {
        savedBarber['id']: availability,
      };
      // Reset barber list cache so it can be refreshed later if needed
      _barbersLoaded = false;
      _availableBarbers = [];
    });

    // Load slots for the new date
    await _loadAvailableSlots();

    if (!mounted) return;

    // ✅ Show confirmation snackbar
    if (_slotErrorMessage == null && _availableSlots.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Date changed to ${DateFormat('MMM dd').format(tomorrow)}. '
            'Same barber (${savedBarber['full_name']}) confirmed.',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e, st) {
    debugPrint('❌ [Try Tomorrow] ERROR: $e');
    debugPrint('   Stack: $st');

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
                      'Try ${DateFormat('MMM dd').format(_selectedDate != null ? _selectedDate!.add(const Duration(days: 1)) : DateTime.now())}',
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

            // ✅ Barber-related: "Try Another Barber" button
            if (showBarberButton) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  debugPrint('🔄 [Try Another Barber] → Step 3');
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
                icon: Icon(
                  Icons.person,
                  size: 18,
                  color: AppTheme.primary,
                ),
                label: Text(
                  'Try Another Barber',
                  style: TextStyle(color: AppTheme.primary),
                ),
              ),
            ],

            // ✅ General errors: "Go Back" button
            if (showGoBack) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  debugPrint('🔄 [Go Back] → Step 3');
                  setState(() {
                    _slotErrorMessage = null;
                    _slotErrorType = null;
                    _currentStep = 3;
                  });
                },
                icon: Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppTheme.primary,
                ),
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

  Widget _buildTravelTimeSelector() {
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.directions_car,
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Travel Time Required',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'Select travel time to adjust your appointment',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Select travel time:',
            style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _travelTimeOptions.map((time) {
              final isSelected = _selectedTravelTime == time;
              return ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _selectedTravelTime = time;
                    _isLoadingSlots = true;
                  });
                  await _loadAvailableSlots();
                  if (mounted) {
                    setState(() {
                      _showTravelTimeSelector = true;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? AppTheme.primary
                      : (isDark ? Colors.grey[800] : Colors.grey[100]),
                  foregroundColor: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.grey[700]),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  elevation: isSelected ? 2 : 0,
                ),
                child: Text(
                  '$time min',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.blue.shade900 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: isDark
                      ? Colors.blue.shade300
                      : Colors.blue.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedTravelTime > 0
                        ? '✓ Travel time $_selectedTravelTime min added to your appointment'
                        : 'Select travel time to add to your appointment start time',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.blue.shade300
                          : Colors.blue.shade700,
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
  }

  Widget _buildTimeSlotCard(Map<String, dynamic> slot) {
    final isDark = context.isDarkMode;
    final isSelected =
        _selectedSlot?['start_time'] == slot['start_time'];
    final queueNumber = slot['queue_number'] ?? 0;
    final startTime = slot['start_time']?.toString() ?? '--:--';
    final endTime = slot['end_time']?.toString() ?? '--:--';
    final waitMinutes = slot['estimated_wait_minutes'] ?? 0;
    final travelTimeUsed = slot['travel_time_used'] ?? 0;
    final salonWillExtend = slot['salon_will_extend'] ?? false;
    final extensionMinutes = slot['extension_minutes'] ?? 0;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: isSelected ? 6 : 2,
      color: isSelected
          ? AppTheme.primary.withValues(alpha: 0.08)
          : (isDark ? const Color(0xFF2A2A2A) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedSlot = slot),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your Queue Number',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$queueNumber',
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
                      ? const Color(0xFF1E1E1E)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time,
                        size: 22, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      '$startTime - $endTime',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : _textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (waitMinutes > 0 && waitMinutes <= 200)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.shade900
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '⏱️ ~ $waitMinutes min wait time',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (travelTimeUsed > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '🚗 +$travelTimeUsed min travel time included',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (salonWillExtend)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⏰ Salon will close $extensionMinutes min late for you',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.green.shade300
                          : Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (waitMinutes > 200)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '⚠️ Long wait time. Consider another date.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.red.shade300
                          : Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
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
    final startTime = _selectedSlot!['start_time']?.toString() ?? '--:--';
    final endTime = _selectedSlot!['end_time']?.toString() ?? '--:--';
    final queueNumber = _selectedSlot!['queue_number'] ?? '?';
    final travelTimeUsed = _selectedSlot!['travel_time_used'] ?? 0;
    final salonWillExtend = _selectedSlot!['salon_will_extend'] ?? false;
    final extensionMinutes = _selectedSlot!['extension_minutes'] ?? 0;
    final adjustedFor =
        _selectedSlot!['adjusted_for']?.toString() ?? '';
    final barberName =
        _selectedBarber!['full_name']?.toString() ?? 'Barber';
    final barberRating =
        (_selectedBarber!['avg_rating'] as num?)?.toStringAsFixed(1) ??
            'New';
    final totalDuration = _calculateTotalDuration();
    final totalPrice = _getDisplayTotalPrice();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
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
                  '$startTime - $endTime • Queue $queueNumber',
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
                        final price =
                            (s['price'] as num?)?.toDouble() ?? 0.0;
                        final discount =
                            (s['discount_amount'] as num?)?.toDouble() ??
                                0.0;
                        final finalPrice =
                            (s['final_price'] as num?)?.toDouble() ??
                                price;
                        final offer =
                            s['offer'] as Map<String, dynamic>?;
                        final gender = s['gender']?.toString() ?? '';
                        final age = s['age']?.toString() ?? '';
                        final details = '$gender $age'.trim();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                                      'Rs. ${price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        decoration: TextDecoration
                                            .lineThrough,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey,
                                      ),
                                    ),
                                  if (discount > 0)
                                    const SizedBox(width: 4),
                                  Text(
                                    'Rs. ${finalPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: discount > 0
                                          ? (isDark
                                              ? Colors.green.shade300
                                              : Colors
                                                  .green.shade700)
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
                                          '🎁 ${offer['title']} — save Rs. ${discount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors
                                                    .green.shade300
                                                : Colors
                                                    .green.shade700,
                                            fontWeight:
                                                FontWeight.w500,
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
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Services Subtotal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey[800],
                            ),
                          ),
                          Text(
                            'Rs. ${_originalTotalPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      if (_discountAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
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
                                '− Rs. ${_discountAmount.toStringAsFixed(2)}',
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
                if (travelTimeUsed > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildConfirmationTile(
                      Icons.directions_car,
                      'Travel Time',
                      '$travelTimeUsed minutes',
                      '',
                    ),
                  ),
                if (salonWillExtend)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildConfirmationTile(
                      Icons.access_time,
                      'Salon Hours',
                      'Extended by $extensionMinutes minutes',
                      'Salon will stay open later',
                    ),
                  ),
                if (adjustedFor.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildConfirmationTile(
                      Icons.info,
                      'Note',
                      _getAdjustedForDisplay(adjustedFor),
                      '',
                    ),
                  ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.attach_money,
                  'Final Amount',
                  'Rs. ${totalPrice.toStringAsFixed(2)}',
                  _discountAmount > 0
                      ? 'Saved Rs. ${_discountAmount.toStringAsFixed(2)}'
                      : '',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBooking ? null : _confirmBooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
              ),
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
                      'Confirm Booking',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}