import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';

class VIPBookingScreen extends StatefulWidget {
  final Map<String, dynamic>? initialSalon;
  const VIPBookingScreen({super.key, this.initialSalon});

  @override
  State<VIPBookingScreen> createState() => _VIPBookingScreenState();
}

class _VIPBookingScreenState extends State<VIPBookingScreen> {
  final supabase = Supabase.instance.client;

  // Step tracking
  int _currentStep = 0;

  // Step 1: Salon
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedSalon;

  // Step 2: Date
  DateTime? _selectedDate;
  Set<DateTime> _holidays = {};
  Map<DateTime, String> _holidayNames = {};
  bool _isDateUnavailable = false;
  String? _unavailableReason;

  // Step 3: Service
  List<Map<String, dynamic>> _salonServices = [];
  List<Map<String, dynamic>> _selectedServices = [];
  bool _isLoadingServices = false;
  bool _servicesLoaded = false;
  String? _selectedCategoryTab;

  // Step 4: Barber
  List<Map<String, dynamic>> _availableBarbers = [];
  Map<String, dynamic>? _selectedBarber;
  bool _isLoadingBarbers = false;
  bool _barbersLoaded = false;
  Map<String, Map<String, dynamic>> _barberAvailability = {};

  // Step 5: Person
  final TextEditingController _childNameController = TextEditingController();
  String? _selectedChildName;
  bool _isSameAsCustomer = true;
  bool _isCheckingDuplicate = false;
  String? _duplicateError;

  // Step 6: Time Slot (VIP)
  List<Map<String, dynamic>> _allTimeSlots = [];
  Map<String, dynamic>? _selectedSlot;
  bool _isLoadingSlots = false;
  String? _slotErrorMessage;
  bool _showingVipNumber = false;
  int _generatedVipNumber = 0;
  String _selectedStartTime = '';

  // Step 7: Confirm
  bool _isBooking = false;
  bool _isInitialized = false;

  // 🆕 OFFER RELATED VARIABLES
  Map<String, dynamic>? _appliedOffer;
  double _discountAmount = 0;
  double _originalTotalPrice = 0;
  double _finalTotalPrice = 0;

  // Timezone Variables
  String _userTimezone = '';
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  // Colors
  final Color _primaryColor = const Color(0xFFFF6B8B);
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
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkTimezoneChange();
    _checkForOffer();
  }

  // ============================================
  // 🆕 CHECK FOR OFFER FROM NAVIGATION
  // ============================================

  void _checkForOffer() {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra != null && extra.containsKey('offer')) {
      final offer = extra['offer'] as Map<String, dynamic>;
      if (_appliedOffer == null) {
        _appliedOffer = offer;
        _calculateDiscount();
        debugPrint('🎁 VIP Offer applied: ${offer['title']}');
      }
    }
  }

  // ============================================
  // 🆕 DISCOUNT CALCULATION METHODS
  // ============================================

  void _calculateDiscount() {
    if (_appliedOffer == null) return;

    _originalTotalPrice = _calculateTotalPrice();

    final discountType = _appliedOffer!['discount_type'];
    final discountValue = _appliedOffer!['discount_value'];

    if (discountType == 'percentage') {
      _discountAmount = _originalTotalPrice * (discountValue / 100);
    } else if (discountType == 'fixed') {
      _discountAmount = discountValue.toDouble();
    } else if (discountType == 'free_service') {
      _discountAmount = _originalTotalPrice;
    }

    _finalTotalPrice = _originalTotalPrice - _discountAmount;
    if (_finalTotalPrice < 0) _finalTotalPrice = 0;

    debugPrint(
      '💰 VIP Discount calculated: $_discountAmount, Final: $_finalTotalPrice',
    );
  }

  void _updateTotalAndDiscount() {
    _originalTotalPrice = _calculateTotalPrice();
    _calculateDiscount();
  }

  double _getDisplayTotalPrice() {
    if (_appliedOffer != null && _discountAmount > 0) {
      return _finalTotalPrice;
    }
    return _calculateTotalPrice();
  }

  String _getDiscountText() {
    if (_appliedOffer == null) return '';
    if (_appliedOffer!['discount_type'] == 'percentage') {
      return '${_appliedOffer!['discount_value']}% OFF';
    } else if (_appliedOffer!['discount_type'] == 'fixed') {
      return 'Rs. ${_appliedOffer!['discount_value']} OFF';
    } else {
      return 'FREE SERVICE';
    }
  }

  void _removeOffer() {
    setState(() {
      _appliedOffer = null;
      _discountAmount = 0;
      _finalTotalPrice = 0;
      _originalTotalPrice = 0;
    });
    debugPrint('🎁 VIP Offer removed');
  }

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    _lastTimezone = _userTimezone;

    setState(() {
      _isTimezoneLoaded = true;
    });

    _initializeScreen();
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
        _allTimeSlots = [];
        _selectedSlot = null;
        _showingVipNumber = false;
        _generatedVipNumber = 0;
        _selectedStartTime = '';
        _slotErrorMessage = null;
        _isLoadingSlots = true;
      });
      await _loadAvailableSlots();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Timezone changed to ${TimezoneService.getTimezoneDisplayName()}',
            ),
            backgroundColor: _primaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _initializeScreen() async {
    if (widget.initialSalon != null && !_isInitialized) {
      _selectedSalon = widget.initialSalon;
      _currentStep = 1;
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  // ============================================
  // HELPER FUNCTIONS
  // ============================================

  int _calculateTotalDuration() =>
      _selectedServices.fold(0, (sum, s) => sum + (s['duration'] as int));

  double _calculateTotalPrice() => _selectedServices.fold(
    0.0,
    (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0),
  );

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

  String _getTimezoneDisplay() {
    return '${TimezoneService.getCurrentFlag()} ${TimezoneService.getTimezoneDisplayName()} (${TimezoneService.getUtcOffsetString()})';
  }

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
      _searchResults = [];
      _isInitialized = false;
      _servicesLoaded = false;
      _barbersLoaded = false;
      _availableBarbers = [];
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
      // 🆕 Reset offer
      _appliedOffer = null;
      _discountAmount = 0;
      _originalTotalPrice = 0;
      _finalTotalPrice = 0;
    });
  }

  // ============================================
  // TIMEZONE FLAG DISPLAY
  // ============================================

  Widget _buildTimezoneFlag() {
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
          if (_isDST()) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'DST',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== STEP 1: SALON SEARCH ====================

  Widget _buildSalonSearchStep() => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: _searchSalons,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search VIP salon by name...',
            hintStyle: TextStyle(fontSize: 15, color: Colors.grey[400]),
            prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 22),
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
                          icon: Icon(Icons.clear, color: Colors.grey[400]),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults = [];
                              _isSearching = false;
                            });
                          },
                        )
                      : null),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _primaryColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
      Expanded(
        child:
            _searchResults.isEmpty &&
                !_isSearching &&
                _searchController.text.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text(
                      'Search for a VIP salon',
                      style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
            : _searchResults.isEmpty && !_isSearching
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text(
                      'No VIP salons found',
                      style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) =>
                    _buildSalonCard(_searchResults[index]),
              ),
      ),
    ],
  );

  Widget _buildSalonCard(Map<String, dynamic> salon) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: InkWell(
      onTap: () => _selectSalon(salon),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  (salon['name'] as String?)?.substring(0, 1).toUpperCase() ??
                      'S',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon['name'] ?? 'Salon',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (salon['address'] != null)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            salon['address'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
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
                        size: 16,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getSalonLocalTime(salon),
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 28, color: Colors.grey[400]),
          ],
        ),
      ),
    ),
  );

  String _getSalonLocalTime(Map<String, dynamic> salon) {
    final openTimeUTC = salon['open_time']?.toString() ?? '09:00:00';
    final closeTimeUTC = salon['close_time']?.toString() ?? '18:00:00';
    final referenceDate = _selectedDate ?? DateTime.now();

    final openLocal = TimezoneService.utcToLocalTime(
      openTimeUTC,
      referenceDate,
    );
    final closeLocal = TimezoneService.utcToLocalTime(
      closeTimeUTC,
      referenceDate,
    );

    return '$openLocal - $closeLocal';
  }

  Future<void> _searchSalons(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await supabase
          .from('salons')
          .select('id, name, address, open_time, close_time, logo_url')
          .ilike('name', '%$query%')
          .eq('is_active', true)
          .limit(20);
      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  void _selectSalon(Map<String, dynamic> salon) {
    setState(() {
      _selectedSalon = salon;
      _currentStep = 1;
      _servicesLoaded = false;
      _salonServices = [];
      _selectedServices = [];
      _selectedDate = null;
    });
    _loadHolidays();
  }

  // ==================== STEP 2: DATE SELECTION ====================

  Future<void> _loadHolidays() async {
    if (_selectedSalon == null) return;
    try {
      final response = await supabase
          .from('salon_holidays')
          .select('holiday_date, name')
          .eq('salon_id', _selectedSalon!['id']);
      setState(() {
        _holidays.clear();
        _holidayNames.clear();
        for (var holiday in response) {
          final date = DateTime.parse(holiday['holiday_date']);
          _holidays.add(date);
          _holidayNames[date] = holiday['name'];
        }
      });
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
      setState(() {
        _isDateUnavailable = schedules.isEmpty;
        _unavailableReason = schedules.isEmpty
            ? 'No barbers working on ${DateFormat('EEEE').format(date)}'
            : null;
      });
    } catch (e) {
      debugPrint('Error checking date availability: $e');
    }
  }

  Widget _buildDateSelectionStep() {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final maxDate = today.add(const Duration(days: 30));
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected VIP Salon',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedSalon?['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: Text(
                  'Change',
                  style: TextStyle(color: _primaryColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CalendarDatePicker(
                      initialDate: today,
                      firstDate: today,
                      lastDate: maxDate,
                      selectableDayPredicate: (date) =>
                          !_holidays.contains(date),
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
                if (_selectedDate != null && _holidays.contains(_selectedDate))
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_busy, color: Colors.red.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Holiday: ${_holidayNames[_selectedDate]}',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isDateUnavailable && !_holidays.contains(_selectedDate))
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _unavailableReason ?? 'No barbers available',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        (_selectedDate != null &&
                            !_isDateUnavailable &&
                            !_holidays.contains(_selectedDate))
                        ? () async {
                            setState(() => _currentStep = 2);
                            await _loadSalonServices();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          (_selectedDate != null &&
                              !_isDateUnavailable &&
                              !_holidays.contains(_selectedDate))
                          ? _primaryColor
                          : Colors.grey[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      _selectedDate == null
                          ? 'Select Date'
                          : (_holidays.contains(_selectedDate)
                                ? 'Holiday - Not Available'
                                : (_isDateUnavailable
                                      ? 'No Barbers Available'
                                      : 'Continue to Services →')),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== STEP 3: SERVICE SELECTION ====================

  Future<void> _loadSalonServices() async {
    if (_servicesLoaded) return;
    setState(() => _isLoadingServices = true);
    try {
      final response = await supabase
          .from('salon_services_with_details')
          .select()
          .eq('salon_id', _selectedSalon!['id'])
          .eq('service_active', true);
      final categories = await supabase
          .from('salon_categories')
          .select('id, display_name')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('is_active', true);
      final Map<int, String> categoryMap = {
        for (var cat in categories) cat['id']: cat['display_name'],
      };
      final Map<int, Map<String, dynamic>> groupedServices = {};
      for (var service in response) {
        final serviceId = service['service_id'] as int;
        if (!groupedServices.containsKey(serviceId)) {
          groupedServices[serviceId] = {
            'id': serviceId,
            'name': service['service_name'] ?? 'Service',
            'description': service['description'],
            'category_name':
                categoryMap[service['salon_category_id']] ?? 'Other',
            'variants': [],
          };
        }
        if (service['variant_id'] != null) {
          groupedServices[serviceId]!['variants'].add({
            'id': service['variant_id'],
            'gender': service['gender_display_name'] ?? '',
            'age': service['age_category_display_name'] ?? '',
            'price': (service['price'] as num?)?.toDouble() ?? 0.0,
            'duration': service['duration'] ?? 30,
          });
        }
      }
      setState(() {
        _salonServices = groupedServices.values.toList();
        _isLoadingServices = false;
        _servicesLoaded = true;
      });
    } catch (e) {
      setState(() => _isLoadingServices = false);
    }
  }

  void _toggleVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final sid = service['id'] as int;
    final vid = variant['id'] as int;
    if (_selectedServices.any(
      (s) => s['id'] == sid && s['variant_id'] == vid,
    )) {
      setState(
        () => _selectedServices.removeWhere(
          (s) => s['id'] == sid && s['variant_id'] == vid,
        ),
      );
    } else {
      setState(
        () => _selectedServices.add({
          'id': sid,
          'name': service['name'],
          'variant_id': vid,
          'gender': variant['gender'],
          'age': variant['age'],
          'price': variant['price'],
          'duration': variant['duration'],
        }),
      );
    }
    _updateTotalAndDiscount();
  }

  // 🆕 Build Offer Banner Widget for VIP
  Widget _buildOfferBanner() {
    if (_appliedOffer == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_offer,
              color: Colors.green.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎉 VIP Offer Applied!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  _appliedOffer!['title'],
                  style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                ),
                Text(
                  'Save ${_getDiscountText()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _removeOffer,
            style: TextButton.styleFrom(foregroundColor: Colors.green.shade700),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceSelectionStep() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var s in _salonServices) {
      (grouped[s['category_name']] ??= []).add(s);
    }
    final categories = grouped.keys.toList();
    if (_selectedCategoryTab == null && categories.isNotEmpty) {
      _selectedCategoryTab = categories.first;
    }
    final servicesToShow = _selectedCategoryTab == null
        ? _salonServices
        : grouped[_selectedCategoryTab] ?? [];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected VIP Salon',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedSalon?['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: Text(
                  'Change',
                  style: TextStyle(color: _primaryColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        // 🆕 Offer Banner
        _buildOfferBanner(),
        if (_selectedServices.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                const Text(
                  'Selected Services:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedServices
                      .map(
                        (s) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Text(
                            s['name'],
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_discountAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'Original: Rs. ${_originalTotalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    Text(
                      'Total: ${_calculateTotalDuration()} min | Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FilterChip(
                label: const Text('All', style: TextStyle(fontSize: 13)),
                selected: _selectedCategoryTab == null,
                onSelected: (_) => setState(() => _selectedCategoryTab = null),
                backgroundColor: Colors.white,
                selectedColor: _primaryColor,
                labelStyle: TextStyle(
                  color: _selectedCategoryTab == null
                      ? Colors.white
                      : Colors.grey[700],
                ),
              ),
              const SizedBox(width: 8),
              ...categories.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(c, style: const TextStyle(fontSize: 13)),
                    selected: _selectedCategoryTab == c,
                    onSelected: (_) => setState(() => _selectedCategoryTab = c),
                    backgroundColor: Colors.white,
                    selectedColor: _primaryColor,
                    labelStyle: TextStyle(
                      color: _selectedCategoryTab == c
                          ? Colors.white
                          : Colors.grey[700],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingServices
              ? const Center(child: CircularProgressIndicator())
              : servicesToShow.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.content_cut,
                        size: 80,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No services available',
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: servicesToShow.length,
                  itemBuilder: (context, index) =>
                      _buildServiceCard(servicesToShow[index], index),
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
                        _currentStep = 3;
                        _barbersLoaded = false;
                        _barberAvailability.clear();
                        _availableBarbers = [];
                        _selectedBarber = null;
                      });
                      _loadAvailableBarbers();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedServices.isNotEmpty
                    ? _primaryColor
                    : Colors.grey[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              child: Text(
                _selectedServices.isEmpty
                    ? 'Please select a service'
                    : 'Continue to Barber →',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _selectedServices.any((s) => s['id'] == service['id'])
              ? _primaryColor
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: _cardColors[index % _cardColors.length],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getServiceIcon(service['name']),
                      color: _primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] ?? 'Service',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          service['category_name'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
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
      ),
    );
  }

  Widget _buildVariantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final isSelected = _selectedServices.any(
      (s) => s['id'] == service['id'] && s['variant_id'] == variant['id'],
    );
    return GestureDetector(
      onTap: () => _toggleVariant(service, variant),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryColor.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _primaryColor : Colors.grey[200]!,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _getGenderIcon(variant['gender'] ?? ''),
              size: 24,
              color: isSelected ? _primaryColor : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${variant['gender'] ?? ''} ${variant['age'] ?? ''}'.trim(),
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 15,
                      color: isSelected ? _primaryColor : _textDark,
                    ),
                  ),
                  Row(
                    children: [
                      if (_discountAmount > 0 && isSelected)
                        Text(
                          'Rs. ${variant['price']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      if (_discountAmount > 0 && isSelected)
                        const SizedBox(width: 8),
                      Text(
                        'Rs. ${_getDiscountedPrice(variant['price'])}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _discountAmount > 0 && isSelected
                              ? Colors.green.shade700
                              : Colors.grey[600],
                          fontWeight: _discountAmount > 0 && isSelected
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${variant['duration']} min',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? _primaryColor : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  double _getDiscountedPrice(double originalPrice) {
    if (_appliedOffer == null) return originalPrice;
    final discountType = _appliedOffer!['discount_type'];
    final discountValue = _appliedOffer!['discount_value'];
    if (discountType == 'percentage') {
      return originalPrice * (1 - discountValue / 100);
    } else if (discountType == 'fixed') {
      return (originalPrice - discountValue).clamp(0, double.infinity);
    } else if (discountType == 'free_service') {
      return 0;
    }
    return originalPrice;
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

  IconData _getGenderIcon(String g) {
    final gl = g.toLowerCase();
    if (gl.contains('male')) return Icons.male;
    if (gl.contains('female')) return Icons.female;
    return Icons.people;
  }

  // ==================== STEP 4: BARBER SELECTION ====================

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
      }
    } catch (e) {
      debugPrint('Error checking barber availability: $e');
    }
    return result;
  }

  Widget _buildBarberSelectionStep() {
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
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Services: ${_selectedServices.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_calculateTotalDuration()} min total • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: Text(
                  'Change',
                  style: TextStyle(color: _primaryColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingBarbers
              ? const Center(child: CircularProgressIndicator())
              : _availableBarbers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No barbers available',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _availableBarbers.length,
                  itemBuilder: (context, index) =>
                      _buildBarberCard(_availableBarbers[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
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
                    ? _primaryColor
                    : Colors.grey[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              child: Text(
                _selectedBarber == null
                    ? 'Please select a barber'
                    : 'Continue to Person →',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final isSelected = _selectedBarber?['id'] == barber['id'];
    final availability = _barberAvailability[barber['id']];
    final isAvailable = availability?['is_available'] ?? true;
    final hasSpecialSchedule = availability?['has_special_schedule'] ?? false;
    final hasSpecialBreak = availability?['has_special_break'] ?? false;
    return Opacity(
      opacity: isAvailable ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected
                ? _primaryColor
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
                  backgroundColor: _primaryColor.withValues(alpha: 0.1),
                  backgroundImage: barber['avatar_url'] != null
                      ? NetworkImage(barber['avatar_url'])
                      : null,
                  child: barber['avatar_url'] == null
                      ? Text(
                          barber['full_name']?.substring(0, 1).toUpperCase() ??
                              'B',
                          style: TextStyle(
                            fontSize: 28,
                            color: _primaryColor,
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
                              barber['full_name'] ?? 'Barber',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
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
                          Icon(Icons.star, size: 16, color: Colors.amber[700]),
                          const SizedBox(width: 4),
                          Text(
                            (barber['avg_rating'] as num?)?.toStringAsFixed(
                                  1,
                                ) ??
                                '0.0',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.work, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '${barber['today_appointments'] ?? 0} today',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
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
                                color: Colors.amber.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Special schedule today',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade700,
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
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Special break today',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
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
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              availability!['reason']!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
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
                      color: isSelected ? _primaryColor : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? _primaryColor : Colors.grey[400]!,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                if (!isAvailable)
                  const Icon(Icons.block, color: Colors.red, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadAvailableBarbers() async {
    if (_isLoadingBarbers) return;
    if (_barbersLoaded && _availableBarbers.isNotEmpty) return;
    setState(() => _isLoadingBarbers = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _availableBarbers = [];
          _isLoadingBarbers = false;
          _barbersLoaded = true;
        });
        return;
      }
      final salonBarbers = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('status', 'active');
      if (salonBarbers.isEmpty) {
        setState(() {
          _availableBarbers = [];
          _isLoadingBarbers = false;
          _barbersLoaded = true;
        });
        return;
      }
      final List<String> barberIds = salonBarbers
          .map<String>((b) => b['barber_id'].toString())
          .toList();
      final profiles = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', barberIds);
      final List<Map<String, dynamic>> barberList = [];
      final dateToCheck = _selectedDate ?? DateTime.now();
      for (var profile in profiles) {
        final barberId = profile['id'];
        final availability = await _checkBarberFullAvailability(
          barberId,
          dateToCheck,
        );
        _barberAvailability[barberId] = availability;
        final todayAppointments = await supabase
            .from('appointments')
            .select('id')
            .eq('barber_id', barberId)
            .eq(
              'appointment_date',
              DateFormat('yyyy-MM-dd').format(DateTime.now()),
            )
            .inFilter('status', ['confirmed', 'pending']);
        final ratings = await supabase
            .from('reviews')
            .select('overall_rating')
            .eq('barber_id', barberId);
        double avgRating = 0.0;
        if (ratings.isNotEmpty) {
          double total = 0;
          for (var r in ratings) {
            total += (r['overall_rating'] as num?)?.toDouble() ?? 0;
          }
          avgRating = total / ratings.length;
        }
        barberList.add({
          'id': barberId,
          'full_name': profile['full_name'] ?? 'Barber',
          'avatar_url': profile['avatar_url'],
          'avg_rating': avgRating,
          'today_appointments': todayAppointments.length,
          'is_available': availability['is_available'],
          'unavailable_reason': availability['reason'],
          'has_special_schedule': availability['has_special_schedule'],
          'has_special_break': availability['has_special_break'],
        });
      }
      barberList.sort((a, b) {
        if (a['is_available'] && !b['is_available']) return -1;
        if (!a['is_available'] && b['is_available']) return 1;
        return (b['avg_rating'] as double).compareTo(a['avg_rating'] as double);
      });
      setState(() {
        _availableBarbers = barberList;
        _isLoadingBarbers = false;
        _barbersLoaded = true;
      });
    } catch (e) {
      setState(() {
        _isLoadingBarbers = false;
        _barbersLoaded = false;
        _availableBarbers = [];
      });
    }
  }

  // ==================== STEP 5: PERSON SELECTION ====================

  Widget _buildPersonSelectionStep() {
    final user = supabase.auth.currentUser;
    final customerName =
        user?.userMetadata?['full_name'] ??
        user?.email?.split('@').first ??
        'Customer';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _primaryColor.withValues(alpha: 0.1),
                    child: Text(
                      _selectedBarber?['full_name']
                              ?.substring(0, 1)
                              .toUpperCase() ??
                          'B',
                      style: TextStyle(
                        color: _primaryColor,
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
                          _selectedBarber?['full_name'] ?? 'Barber',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_calculateTotalDuration()} min service • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 3),
                    child: Text(
                      'Change',
                      style: TextStyle(color: _primaryColor, fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (_selectedDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: _secondaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 1),
                        child: Text(
                          'Change',
                          style: TextStyle(color: _primaryColor, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Who is this VIP appointment for?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Select who will receive the VIP service',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                _buildPersonOption(
                  isSelected: _isSameAsCustomer,
                  icon: Icons.person,
                  title: 'Myself',
                  subtitle: customerName,
                  description: 'VIP booking for yourself',
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
                      ? 'Will book VIP for: $_selectedChildName'
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
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Enter full name',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[400],
                      ),
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: _primaryColor,
                        size: 22,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
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
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _duplicateError!,
                            style: TextStyle(
                              color: Colors.red.shade700,
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
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Each person can only have one VIP booking per day.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade700,
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canProceedToTimeSlot()
                  ? () async {
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
                        });
                        await _loadAvailableSlots();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canProceedToTimeSlot()
                    ? _primaryColor
                    : Colors.grey[400],
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
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? _primaryColor : Colors.grey[200]!,
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
                  color: _primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon, size: 30, color: _primaryColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    if (description != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: _primaryColor,
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
                  color: isSelected ? _primaryColor : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? _primaryColor : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canProceedToTimeSlot() =>
      !_isCheckingDuplicate &&
      _duplicateError == null &&
      (_isSameAsCustomer ||
          (_selectedChildName != null &&
              _selectedChildName!.trim().isNotEmpty));

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
          .eq('child_name', childName)
          .not('status', 'in', '("cancelled","no_show")');
      setState(() {
        _duplicateError = existing.isNotEmpty
            ? '⚠️ You already have a VIP booking for ${childName.isEmpty ? "yourself" : childName} on ${DateFormat('MMM dd').format(_selectedDate!)}.'
            : null;
      });
    } catch (e) {
      debugPrint('Error checking duplicate: $e');
    } finally {
      setState(() => _isCheckingDuplicate = false);
    }
  }

  Future<bool> _validateAndProceed() async {
    await _checkDuplicateBooking();
    return _duplicateError == null;
  }

  // ==================== STEP 6: VIP TIME SLOT SELECTION ====================

  Widget _buildTimezoneIndicator() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: Colors.grey[200]!),
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
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '(${TimezoneService.getUtcOffsetString()})',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        if (_isDST()) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'DST',
              style: TextStyle(
                fontSize: 9,
                color: Colors.amber.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  bool _isSlotInPast(DateTime localSlotStart, int durationMinutes) {
    final now = DateTime.now();
    final slotEnd = localSlotStart.add(Duration(minutes: durationMinutes));

    if (localSlotStart.isBefore(now)) {
      if (slotEnd.isBefore(now)) {
        return true;
      }
    }
    return false;
  }

  String _formatTimeWithAmPm(DateTime time) {
    try {
      final period = time.hour >= 12 ? 'PM' : 'AM';
      final displayHour = time.hour % 12 == 0 ? 12 : time.hour % 12;
      return '$displayHour:${time.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _loadAvailableSlots() async {
    if (!mounted) return;

    setState(() {
      _isLoadingSlots = true;
      _allTimeSlots = [];
      _selectedSlot = null;
      _showingVipNumber = false;
      _generatedVipNumber = 0;
      _selectedStartTime = '';
      _slotErrorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingSlots = false);
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final totalDuration = _calculateTotalDuration();

      final scheduleResult = await supabase.rpc(
        'get_barber_effective_schedule',
        params: {
          'p_barber_id': _selectedBarber!['id'],
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
          });
        }
        return;
      }

      String workStartUTC =
          effectiveSchedule['work_start']?.toString() ?? '09:00';
      String workEndUTC = effectiveSchedule['work_end']?.toString() ?? '18:00';

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

      String? breakStartUTC = effectiveSchedule['lunch_break_start']
          ?.toString();
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
          .eq('barber_id', _selectedBarber!['id'])
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
        if (endTimeUTC.length > 5) endTimeUTC = endTimeUTC.substring(0, 5);

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

        final localSlotStart = TimezoneService.utcToLocalDateTime(
          '${slotStartUTC.hour.toString().padLeft(2, '0')}:${slotStartUTC.minute.toString().padLeft(2, '0')}',
          _selectedDate!,
        );
        bool isPast = _isSlotInPast(localSlotStart, totalDuration);

        bool isAvailable =
            !isOverlappingWithBookings && !isPast && !isOverlappingWithBreak;

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

        final localStartDateTime = TimezoneService.utcToLocalDateTime(
          '${slotStartUTC.hour.toString().padLeft(2, '0')}:${slotStartUTC.minute.toString().padLeft(2, '0')}',
          _selectedDate!,
        );
        final localEndDateTime = TimezoneService.utcToLocalDateTime(
          '${slotEndUTC.hour.toString().padLeft(2, '0')}:${slotEndUTC.minute.toString().padLeft(2, '0')}',
          _selectedDate!,
        );

        final displayStartTime = _formatTimeWithAmPm(localStartDateTime);
        final displayEndTime = _formatTimeWithAmPm(localEndDateTime);

        final utcStartTimeStr =
            '${slotStartUTC.hour.toString().padLeft(2, '0')}:${slotStartUTC.minute.toString().padLeft(2, '0')}:00';
        final utcEndTimeStr =
            '${slotEndUTC.hour.toString().padLeft(2, '0')}:${slotEndUTC.minute.toString().padLeft(2, '0')}:00';

        slots.add({
          'start_time_display': displayStartTime,
          'end_time_display': displayEndTime,
          'utc_start_time': utcStartTimeStr,
          'utc_end_time': utcEndTimeStr,
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

      if (mounted) {
        setState(() {
          _allTimeSlots = slots;
          _isLoadingSlots = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotErrorMessage = 'Failed to load time slots. Please try again.';
          _allTimeSlots = [];
        });
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

      final existingVIP = await supabase
          .from('appointments')
          .select('start_time, vip_queue_number')
          .eq('barber_id', _selectedBarber!['id'])
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

  Widget _buildTimeSlotStep() {
    final availableSlots = _allTimeSlots
        .where((s) => s['is_available'] == true)
        .toList();
    final unavailableSlots = _allTimeSlots
        .where((s) => !s['is_available'])
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _primaryColor.withValues(alpha: 0.1),
                child: Text(
                  _selectedBarber?['full_name']
                          ?.substring(0, 1)
                          .toUpperCase() ??
                      'B',
                  style: TextStyle(
                    color: _primaryColor,
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
                      _selectedBarber?['full_name'] ?? 'Barber',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_calculateTotalDuration()} min service • Rs. ${_getDisplayTotalPrice().toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 3),
                child: Text(
                  'Change',
                  style: TextStyle(color: _primaryColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),

        if (_selectedDate != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: _secondaryColor),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: Text(
                    'Change',
                    style: TextStyle(color: _primaryColor, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

        _buildTimezoneIndicator(),

        Expanded(
          child: _isLoadingSlots
              ? const Center(child: CircularProgressIndicator())
              : _slotErrorMessage != null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 64,
                          color: Colors.orange.shade300,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No VIP Slots Available',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Text(
                            _slotErrorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedDate = null;
                                  _currentStep = 1;
                                  _slotErrorMessage = null;
                                });
                              },
                              icon: Icon(
                                Icons.calendar_today,
                                size: 18,
                                color: Colors.grey[600],
                              ),
                              label: const Text('Change Date'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (_selectedDate == null) return;
                                final tomorrow = _selectedDate!.add(
                                  const Duration(days: 1),
                                );
                                setState(() {
                                  _selectedDate = tomorrow;
                                  _allTimeSlots = [];
                                  _isLoadingSlots = true;
                                  _slotErrorMessage = null;
                                  _showingVipNumber = false;
                                });
                                await _checkDateAvailability(tomorrow);
                                await _loadAvailableSlots();
                              },
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: Text(
                                'Try ${DateFormat('MMM dd').format(_selectedDate!.add(const Duration(days: 1)))}',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Select VIP Time Slot',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose your preferred time',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                            color: _primaryColor.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(color: _primaryColor, width: 2),
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
                                      color: Colors.grey[600],
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
                                      color: _primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(40),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 22,
                                          color: _primaryColor,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _selectedStartTime,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: _textDark,
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
                        const Text(
                          'Available Slots',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
                                    ? _primaryColor
                                    : Colors.white,
                                foregroundColor: isSelected && _showingVipNumber
                                    ? Colors.white
                                    : _primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                  side: BorderSide(
                                    color: isSelected && _showingVipNumber
                                        ? _primaryColor
                                        : _primaryColor.withValues(alpha: 0.5),
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
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'VIP-$willGetVipNumber',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w400,
                                      color: isSelected && _showingVipNumber
                                          ? Colors.white70
                                          : _primaryColor.withValues(
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
                        const Text(
                          'Unavailable Slots',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
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
                              statusColor = Colors.grey[500]!;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayTime,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
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

                      if (availableSlots.isEmpty &&
                          unavailableSlots.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'No available slots on this date.',
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  if (_selectedDate == null) return;
                                  final nextDate = _selectedDate!.add(
                                    const Duration(days: 1),
                                  );
                                  setState(() {
                                    _selectedDate = nextDate;
                                    _allTimeSlots = [];
                                    _isLoadingSlots = true;
                                    _slotErrorMessage = null;
                                    _showingVipNumber = false;
                                    _selectedSlot = null;
                                  });
                                  await _checkDateAvailability(nextDate);
                                  await _loadAvailableSlots();
                                },
                                icon: const Icon(Icons.arrow_forward, size: 18),
                                label: Text(
                                  'Try Next Day (${DateFormat('MMM dd').format(_selectedDate!.add(const Duration(days: 1)))})',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
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

        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedSlot != null && _showingVipNumber)
                  ? () => setState(() => _currentStep = 6)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: (_selectedSlot != null && _showingVipNumber)
                    ? _primaryColor
                    : Colors.grey[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              child: const Text(
                'Continue to Confirmation →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== STEP 7: CONFIRMATION ====================

  Widget _buildConfirmationStep() {
    if (_selectedSalon == null ||
        _selectedServices.isEmpty ||
        _selectedBarber == null ||
        _selectedSlot == null ||
        _selectedDate == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Missing information. Please go back and complete all steps.',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Start Over'),
            ),
          ],
        ),
      );
    }

    final user = supabase.auth.currentUser;
    final customerName =
        user?.userMetadata?['full_name'] ??
        user?.email?.split('@').first ??
        'Customer';
    final displayName = _isSameAsCustomer
        ? customerName
        : _getChildNameForBooking();

    final salonName = _selectedSalon!['name'] ?? 'Salon';

    final startTime = _selectedSlot!['start_time_display'] ?? '--:--';
    final endTime = _selectedSlot!['end_time_display'] ?? '--:--';

    final vipNumber = _generatedVipNumber;
    final barberName = _selectedBarber!['full_name'] ?? 'Barber';
    final barberRating =
        (_selectedBarber!['avg_rating'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final totalDuration = _calculateTotalDuration();
    final totalPrice = _getDisplayTotalPrice();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 20,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '⏰ Times shown in your local timezone: $_getTimezoneDisplay()',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                  _selectedSalon!['address'] ?? '',
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
                      ..._selectedServices.map(
                        (s) => Text(
                          '• ${s['name']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
                // 🆕 Offer Discount Section for VIP
                if (_appliedOffer != null && _discountAmount > 0) ...[
                  const SizedBox(height: 12),
                  _buildConfirmationTile(
                    Icons.local_offer,
                    'Discount Applied',
                    '- Rs. ${_discountAmount.toStringAsFixed(2)}',
                    _appliedOffer!['title'],
                  ),
                ],
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  Icons.person,
                  'Barber',
                  barberName,
                  '⭐ $barberRating rating',
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
                backgroundColor: _primaryColor,
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
                      'Confirm VIP Booking',
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

  Widget _buildConfirmationTile(
    IconData icon,
    String title,
    String value,
    dynamic subtitle,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey[200]!),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.shade100,
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
            color: _primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: _primaryColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null && subtitle is String) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
              if (subtitle != null && subtitle is Widget) subtitle,
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _confirmBooking() async {
    if (!mounted) return;
    setState(() => _isBooking = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please login');

      final utcStartTime = _selectedSlot!['utc_start_time'];
      final utcEndTime = _selectedSlot!['utc_end_time'];

      final result = await supabase.rpc(
        'create_vip_booking',
        params: {
          'p_customer_id': user.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': _selectedBarber!['id'],
          'p_service_id': _selectedServices.first['id'],
          'p_variant_id': _selectedServices.first['variant_id'],
          'p_appointment_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
          'p_utc_start_time': utcStartTime,
          'p_utc_end_time': utcEndTime,
          'p_child_name': _getChildNameForBooking(),
          'p_notes': _selectedServices.length > 1
              ? 'Combined: ${_selectedServices.map((s) => s['name']).join(", ")}'
              : null,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // 🆕 Update offer status if offer was applied
        if (_appliedOffer != null) {
          await supabase
              .from('customer_offers')
              .update({
                'status': 'used',
                'used_at': DateTime.now().toIso8601String(),
              })
              .eq('customer_id', user.id)
              .eq('offer_id', _appliedOffer!['id']);
        }

        final confirmedVipNumber = result['vip_number'] ?? _generatedVipNumber;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ VIP Booking Confirmed! VIP-$confirmedVipNumber'),
              backgroundColor: _secondaryColor,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(result['message'] ?? 'VIP booking failed');
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

  // ==================== MAIN BUILD METHOD ====================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final stepSize = isMobile ? 36.0 : 42.0;
    final iconSize = isMobile ? 18.0 : 20.0;
    final stepFontSize = isMobile ? 9.0 : 11.0;
    final connectorWidth = isMobile ? 20.0 : 35.0;
    final showLabels = !isMobile;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: _bgLight,
        appBar: AppBar(
          title: const Text('VIP Booking'),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: Text(
          'VIP Booking',
          style: TextStyle(
            fontSize: isMobile ? 18 : 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
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
        child: Column(
          children: [
            Container(
              color: Colors.white,
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
                        color: _currentStep > 0
                            ? _primaryColor
                            : Colors.grey[300],
                      ),
                      _buildStepIndicatorResponsive(
                        1,
                        showLabels ? 'Date' : '',
                        Icons.calendar_today,
                        stepSize,
                        iconSize,
                        stepFontSize,
                      ),
                      Container(
                        width: connectorWidth,
                        height: 2,
                        color: _currentStep > 1
                            ? _primaryColor
                            : Colors.grey[300],
                      ),
                      _buildStepIndicatorResponsive(
                        2,
                        showLabels ? 'Service' : '',
                        Icons.content_cut,
                        stepSize,
                        iconSize,
                        stepFontSize,
                      ),
                      Container(
                        width: connectorWidth,
                        height: 2,
                        color: _currentStep > 2
                            ? _primaryColor
                            : Colors.grey[300],
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
                        color: _currentStep > 3
                            ? _primaryColor
                            : Colors.grey[300],
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
                        color: _currentStep > 4
                            ? _primaryColor
                            : Colors.grey[300],
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
                        color: _currentStep > 5
                            ? _primaryColor
                            : Colors.grey[300],
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
            ),
            Expanded(
              child: IndexedStack(
                index: _currentStep,
                children: [
                  _buildSalonSearchStep(),
                  _buildDateSelectionStep(),
                  _buildServiceSelectionStep(),
                  _buildBarberSelectionStep(),
                  _buildPersonSelectionStep(),
                  _buildTimeSlotStep(),
                  _buildConfirmationStep(),
                ],
              ),
            ),
          ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? _primaryColor
                : (isActive
                      ? _primaryColor.withValues(alpha: 0.1)
                      : Colors.grey[200]),
            border: Border.all(
              color: isActive ? _primaryColor : Colors.grey[300]!,
              width: isActive ? 2 : 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: _primaryColor.withValues(alpha: 0.3),
                      blurRadius: 8,
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
                    color: isActive ? _primaryColor : Colors.grey[500],
                  ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              color: isActive ? _primaryColor : Colors.grey[500],
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }
}
