import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../services/timezone_service.dart';

class BookingFlowScreen extends StatefulWidget {
  final Map<String, dynamic>? initialSalon;
  const BookingFlowScreen({super.key, this.initialSalon});

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final supabase = Supabase.instance.client;

  // Step tracking
  int _currentStep = 0;

  // Step 1: Salon
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _followedSalons = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _selectedSalon;
  bool _isLoadingFollowedSalons = true;

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
  int? _expandedServiceId; // ✅ FIXED: Changed from String? to int?

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

  // Step 6: Time Slot
  int _selectedTravelTime = 0;
  bool _showTravelTimeSelector = false;
  final List<int> _travelTimeOptions = [5, 10, 15, 20, 25, 30, 45, 60];
  List<Map<String, dynamic>> _availableSlots = [];
  Map<String, dynamic>? _selectedSlot;
  bool _isLoadingSlots = false;
  String? _slotErrorMessage;

  // Step 7: Confirm
  bool _isBooking = false;
  bool _isInitialized = false;

  // Offer related variables
  Map<String, dynamic>? _appliedOffer;
  double _discountAmount = 0;
  double _originalTotalPrice = 0;
  double _finalTotalPrice = 0;

  // Timezone variables
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
  // CHECK FOR OFFER FROM NAVIGATION
  // ============================================

  void _checkForOffer() {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra != null && extra.containsKey('offer')) {
      final offer = extra['offer'] as Map<String, dynamic>;
      if (_appliedOffer == null) {
        _appliedOffer = offer;
        _calculateDiscount();
        debugPrint('🎁 Offer applied: ${offer['title']}');
      }
    }
  }

  // ============================================
  // DISCOUNT CALCULATION METHODS
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

    debugPrint('💰 Discount calculated: $_discountAmount, Final: $_finalTotalPrice');
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
    debugPrint('🎁 Offer removed');
  }

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone = prefs.getString('cached_timezone') ?? TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    _lastTimezone = _userTimezone;

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadFollowedSalons();
    _initializeScreen();
  }

  void _checkTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone = prefs.getString('cached_timezone') ?? TimezoneService.getCurrentTimezone();

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
        _isLoadingSlots = true;
      });
      await _loadAvailableSlots();
    }
  }

  Future<void> _initializeScreen() async {
    if (widget.initialSalon != null && !_isInitialized) {
      _selectedSalon = widget.initialSalon;
      _currentStep = 1;
      _isInitialized = true;
      await supabase.rpc('cleanup_old_queues');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  // ==================== HELPER FUNCTIONS ====================

  int _calculateTotalDuration() =>
      _selectedServices.fold(0, (sum, s) => sum + (s['duration'] as int));

  double _calculateTotalPrice() => _selectedServices.fold(
    0.0,
    (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0),
  );

  String _getChildNameForBooking() =>
      _isSameAsCustomer ? '' : (_selectedChildName?.trim() ?? '');

  String _getTimezoneDisplay() {
    return '${TimezoneService.getCurrentFlag()} ${TimezoneService.getTimezoneDisplayName()} (${TimezoneService.getUtcOffsetString()})';
  }

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
      _searchResults = [];
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
      _expandedServiceId = null;
      _appliedOffer = null;
      _discountAmount = 0;
      _originalTotalPrice = 0;
      _finalTotalPrice = 0;
    });
  }

  // ==================== TIMEZONE DISPLAY ====================

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
          const SizedBox(width: 4),
          if (_isDST())
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
      ),
    );
  }

  // ==================== STEP 1: SALON SEARCH ====================

  Future<void> _loadFollowedSalons() async {
    setState(() {
      _isLoadingFollowedSalons = true;
      _followedSalons = [];
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingFollowedSalons = false);
        return;
      }

      final result = await supabase.rpc(
        'get_followed_salons_with_counts',
        params: {'p_customer_id': user.id},
      );

      if (result != null && result.isNotEmpty) {
        setState(() {
          _followedSalons = List<Map<String, dynamic>>.from(result);
          _searchResults = List.from(_followedSalons);
          _isLoadingFollowedSalons = false;
        });
        debugPrint('✅ Loaded ${_followedSalons.length} followed salons');
      } else {
        setState(() {
          _followedSalons = [];
          _searchResults = [];
          _isLoadingFollowedSalons = false;
        });
        debugPrint('ℹ️ No followed salons found');
      }
    } catch (e) {
      debugPrint('❌ Error loading followed salons: $e');
      setState(() {
        _followedSalons = [];
        _searchResults = [];
        _isLoadingFollowedSalons = false;
      });
    }
  }

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
            hintText: 'Search your followed salons...',
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
                              _searchResults = List.from(_followedSalons);
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
        child: _isLoadingFollowedSalons
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading your followed salons...'),
                  ],
                ),
              )
            : _searchResults.isEmpty && !_isSearching && _followedSalons.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.store_mall_directory, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text(
                      'No salons followed yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Follow salons to book appointments',
                      style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/customer/search-salons'),
                      icon: const Icon(Icons.search),
                      label: const Text('Find Salons to Follow'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : _searchResults.isEmpty && !_isSearching && _followedSalons.isNotEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 20),
                    Text(
                      'No salons found matching "${_searchController.text}"',
                      style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = List.from(_followedSalons);
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear Search'),
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

  Widget _buildSalonCard(Map<String, dynamic> salon) {
    final logoUrl = salon['logo_url'];
    final followerCount = salon['follower_count'] ?? 0;
    final bookingCount = salon['booking_count'] ?? 0;

    return Card(
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
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
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
                          (salon['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'S',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
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
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              salon['address'],
                              style: TextStyle(
                                fontSize: 12,
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
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getSalonLocalTime(salon),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$followerCount followers',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.event_available,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$bookingCount bookings',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
  }

  Future<void> _searchSalons(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = List.from(_followedSalons);
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final filtered = _followedSalons.where((salon) {
      final name = (salon['name'] as String?)?.toLowerCase() ?? '';
      final address = (salon['address'] as String?)?.toLowerCase() ?? '';
      final searchTerm = query.toLowerCase();
      return name.contains(searchTerm) || address.contains(searchTerm);
    }).toList();

    setState(() {
      _searchResults = filtered;
      _isSearching = false;
    });
  }

  String _getSalonLocalTime(Map<String, dynamic> salon) {
    final openTimeUTC = salon['open_time']?.toString() ?? '09:00:00';
    final closeTimeUTC = salon['close_time']?.toString() ?? '18:00:00';

    final openLocal = TimezoneService.utcToLocalTimeRecurring(openTimeUTC);
    final closeLocal = TimezoneService.utcToLocalTimeRecurring(closeTimeUTC);

    return '$openLocal - $closeLocal';
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
  final isMobile = MediaQuery.of(context).size.width < 600;

  // ✅ Check if date is selectable
  bool isDateSelectable(DateTime date) {
    // Disable holidays
    if (_holidays.contains(date)) return false;
    
    // Disable today (current day)
    if (date.isAtSameMomentAs(today)) return false;
    
    // Disable past dates (before today)
    if (date.isBefore(today)) return false;
    
    return true;
  }

  DateTime getValidInitialDate() {
    DateTime checkDate = today.add(const Duration(days: 1));
    for (int i = 0; i < 30; i++) {
      if (isDateSelectable(checkDate)) {
        return checkDate;
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }
    return today.add(const Duration(days: 1));
  }

  return Column(
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                image: (_selectedSalon?['logo_url'] as String?) != null && (_selectedSalon!['logo_url'] as String).isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(_selectedSalon!['logo_url']),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (_selectedSalon?['logo_url'] == null || (_selectedSalon!['logo_url'] as String).isEmpty)
                  ? Center(
                      child: Text(
                        (_selectedSalon?['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'S',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
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
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: isMobile ? 100 : 16,
          ),
          child: Column(
            children: [
              // ✅ Info Banner - Today is disabled
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📅 ${DateFormat('EEEE, MMM dd').format(today)} is not available',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          Text(
                            'Please select a future date (tomorrow or later)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade600,
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: CalendarDatePicker(
                    initialDate: getValidInitialDate(),
                    firstDate: today.add(const Duration(days: 1)),
                    lastDate: maxDate,
                    selectableDayPredicate: (date) => isDateSelectable(date),
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
                          '⛔ Holiday: ${_holidayNames[_selectedDate]}',
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
                          _unavailableReason ?? '⚠️ No barbers available on this day',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
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
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
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
                    !_holidays.contains(_selectedDate) &&
                    !_selectedDate!.isAtSameMomentAs(today) &&
                    _selectedDate!.isAfter(today))
                ? () async {
                    setState(() => _currentStep = 2);
                    await _loadSalonServices();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  (_selectedDate != null &&
                      !_isDateUnavailable &&
                      !_holidays.contains(_selectedDate) &&
                      !_selectedDate!.isAtSameMomentAs(today) &&
                      _selectedDate!.isAfter(today))
                  ? _primaryColor
                  : Colors.grey[400],
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
                      ? 'Select Date'
                      : (_selectedDate!.isAtSameMomentAs(today)
                          ? 'Today Not Available'
                          : (_holidays.contains(_selectedDate)
                              ? 'Holiday - Not Available'
                              : (_isDateUnavailable
                                  ? 'No Barbers Available'
                                  : 'Continue to Services'))),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_selectedDate != null &&
                    !_isDateUnavailable &&
                    !_holidays.contains(_selectedDate) &&
                    !_selectedDate!.isAtSameMomentAs(today) &&
                    _selectedDate!.isAfter(today))
                  const SizedBox(width: 8),
                if (_selectedDate != null &&
                    !_isDateUnavailable &&
                    !_holidays.contains(_selectedDate) &&
                    !_selectedDate!.isAtSameMomentAs(today) &&
                    _selectedDate!.isAfter(today))
                  const Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

  // ==================== STEP 3: SERVICE SELECTION ====================

  // Future<void> _loadSalonServices() async {
  //   if (_servicesLoaded) return;
  //   setState(() => _isLoadingServices = true);
  //   try {
  //     final response = await supabase
  //         .from('salon_services_with_details')
  //         .select()
  //         .eq('salon_id', _selectedSalon!['id'])
  //         .eq('service_active', true);
  //     final categories = await supabase
  //         .from('salon_categories')
  //         .select('id, display_name')
  //         .eq('salon_id', _selectedSalon!['id'])
  //         .eq('is_active', true);
  //     final Map<int, String> categoryMap = {
  //       for (var cat in categories) cat['id']: cat['display_name'],
  //     };
  //     final Map<int, Map<String, dynamic>> groupedServices = {};
  //     for (var service in response) {
  //       final serviceId = service['service_id'] as int;
  //       if (!groupedServices.containsKey(serviceId)) {
  //         groupedServices[serviceId] = {
  //           'id': serviceId,
  //           'name': service['service_name']?.toString() ?? 'Service',
  //           'description': service['description']?.toString(),
  //           'category_name':
  //               categoryMap[service['salon_category_id']] ?? 'Other',
  //           'variants': [],
  //         };
  //       }
  //       if (service['variant_id'] != null) {
  //         groupedServices[serviceId]!['variants'].add({
  //           'id': service['variant_id'],
  //           'gender': service['gender_display_name']?.toString() ?? '',
  //           'age': service['age_category_display_name']?.toString() ?? '',
  //           'price': (service['price'] as num?)?.toDouble() ?? 0.0,
  //           'duration': service['duration'] ?? 30,
  //         });
  //       }
  //     }
  //     setState(() {
  //       _salonServices = groupedServices.values.toList();
  //       _isLoadingServices = false;
  //       _servicesLoaded = true;
  //     });
  //   } catch (e) {
  //     setState(() => _isLoadingServices = false);
  //   }
  // }

  //--------------------without view----------------------
   Future<void> _loadSalonServices() async {
    if (_servicesLoaded) return;
    setState(() => _isLoadingServices = true);

    try {
      final salonId = _selectedSalon!['id'];

      // Single query with all joins
      final response = await supabase
          .from('services')
          .select('''
          id,
          name,
          description,
          is_active,
          category_id,
          salon_categories!inner (
            display_name
          ),
          service_variants!inner (
            id,
            price,
            duration,
            salon_gender_id,
            salon_age_category_id,
            salon_genders!inner (
              display_name
            ),
            salon_age_categories!inner (
              display_name
            )
          )
        ''')
          .eq('salon_id', salonId)
          .eq('is_active', true)
          .eq('service_variants.is_active', true);

      final Map<int, Map<String, dynamic>> groupedServices = {};

      for (var service in response) {
        final serviceId = service['id'] as int;

        // Initialize service if not exists
        if (!groupedServices.containsKey(serviceId)) {
          groupedServices[serviceId] = {
            'id': serviceId,
            'name': service['name']?.toString() ?? 'Service',
            'description': service['description']?.toString(),
            'category_name':
                service['salon_categories']?['display_name'] ?? 'Other',
            'variants': [],
          };
        }

        // Add variants
        final variants = service['service_variants'] as List? ?? [];
        for (var variant in variants) {
          groupedServices[serviceId]!['variants'].add({
            'id': variant['id'],
            'gender': variant['salon_genders']?['display_name'] ?? '',
            'age': variant['salon_age_categories']?['display_name'] ?? '',
            'price': (variant['price'] as num?)?.toDouble() ?? 0.0,
            'duration': variant['duration'] ?? 30,
          });
        }
      }

      // Convert to list
      final servicesList = groupedServices.values.toList();

      setState(() {
        _salonServices = servicesList;
        _isLoadingServices = false;
        _servicesLoaded = true;
      });
    } catch (e) {
      setState(() => _isLoadingServices = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load services: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final int sid = service['id'] as int;
    final int vid = variant['id'] as int;
    final String serviceName = service['name']?.toString() ?? 'Service';
    final String gender = variant['gender']?.toString() ?? '';
    final String age = variant['age']?.toString() ?? '';
    final double price = (variant['price'] as num?)?.toDouble() ?? 0.0;
    final int duration = variant['duration'] ?? 30;

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
          'name': serviceName,
          'variant_id': vid,
          'gender': gender,
          'age': age,
          'price': price,
          'duration': duration,
        }),
      );
    }
    _updateTotalAndDiscount();
  }

  void _showSelectedServicesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
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
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.checklist,
                        color: _primaryColor,
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_selectedServices.length} service${_selectedServices.length > 1 ? 's' : ''} selected',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
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
                            _updateTotalAndDiscount();
                          });
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Clear All',
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _selectedServices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 64,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No services selected',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap on service variants to add',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _selectedServices.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final service = _selectedServices[index];
                            return _buildSelectedServiceItem(service, index);
                          },
                        ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Duration',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            '${_calculateTotalDuration()} min',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Price',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            'Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
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
                      backgroundColor: _primaryColor,
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

  Widget _buildSelectedServiceItem(Map<String, dynamic> service, int index) {
    final String serviceName = service['name']?.toString() ?? 'Service';
    final String gender = service['gender']?.toString() ?? '';
    final String age = service['age']?.toString() ?? '';
    final double price = (service['price'] as num?)?.toDouble() ?? 0.0;
    final int duration = service['duration'] ?? 30;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
                color: _primaryColor,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$gender $age • $duration min',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Rs. ${price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedServices.removeAt(index);
                _updateTotalAndDiscount();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close,
                size: 16,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceSelectionStep() {
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
          color: Colors.white,
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  image: (_selectedSalon?['logo_url'] as String?) != null && (_selectedSalon!['logo_url'] as String).isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_selectedSalon!['logo_url']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (_selectedSalon?['logo_url'] == null || (_selectedSalon!['logo_url'] as String).isEmpty)
                    ? Center(
                        child: Text(
                          (_selectedSalon?['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'S',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
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

        if (_selectedServices.isNotEmpty)
          GestureDetector(
            onTap: () => _showSelectedServicesSheet(),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.3),
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
                        color: _primaryColor,
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
                          _selectedServices.map((s) => s['name']?.toString() ?? '').take(2).join(', '),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Rs. ${_calculateTotalPrice().toStringAsFixed(0)}',
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

        _buildOfferBanner(),

        SizedBox(
          height: 45,
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
                      _buildServiceCard(servicesToShow[index], index, isMobile),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedServices.isEmpty
                        ? 'Select a Service'
                        : 'Continue to Barber',
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

  Widget _buildServiceCard(Map<String, dynamic> service, int index, bool isMobile) {
    final variants = service['variants'] as List? ?? [];
    final isAnyVariantSelected = _selectedServices.any((s) => s['id'] == service['id']);
    final int serviceId = service['id'] as int; // ✅ FIXED: Cast to int
    final isExpanded = _expandedServiceId == serviceId; // ✅ FIXED: Compare int? == int

    final String serviceName = service['name']?.toString() ?? 'Service';
    final String categoryName = service['category_name']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isAnyVariantSelected ? _primaryColor : Colors.transparent,
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
            InkWell(
              onTap: () {
                if (isMobile && variants.isNotEmpty) {
                  setState(() {
                    if (isExpanded) {
                      _expandedServiceId = null;
                    } else {
                      _expandedServiceId = serviceId; // ✅ FIXED: Assign int, not String
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getServiceIcon(serviceName),
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
                            serviceName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            categoryName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
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
                                color: _primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedServices.where((s) => s['id'] == service['id']).length} selected',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isMobile && variants.isNotEmpty)
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[500],
                        size: 24,
                      ),
                  ],
                ),
              ),
            ),

            if (variants.isNotEmpty && (!isMobile || isExpanded))
              Column(
                children: [
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

            if (variants.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _selectServiceWithoutVariant(service),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: BorderSide(color: _primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Select Service'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _selectServiceWithoutVariant(Map<String, dynamic> service) {
    final variants = service['variants'] as List? ?? [];
    if (variants.isNotEmpty) {
      _toggleVariant(service, variants.first);
    } else {
      final String serviceName = service['name']?.toString() ?? 'Service';
      final int serviceId = service['id'] as int;

      setState(() {
        _selectedServices.add({
          'id': serviceId,
          'name': serviceName,
          'variant_id': null,
          'gender': '',
          'age': '',
          'price': 0.0,
          'duration': 30,
        });
        _updateTotalAndDiscount();
      });
    }
  }

  Widget _buildVariantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final isSelected = _selectedServices.any(
      (s) => s['id'] == service['id'] && s['variant_id'] == variant['id'],
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
    final double discountedPrice = _getDiscountedPrice(price);
    final int duration = variant['duration'] ?? 30;

    final String displayText = '$gender $age'.trim();

    return GestureDetector(
      onTap: () => _toggleVariant(service, variant),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(isMobile ? 10 : 12),
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
            Container(
              width: isMobile ? 40 : 44,
              height: isMobile ? 40 : 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? _primaryColor.withValues(alpha: 0.2)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                genderIcon,
                size: isMobile ? 22 : 24,
                color: isSelected ? _primaryColor : Colors.grey[600],
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
                      color: isSelected ? _primaryColor : _textDark,
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
                          Icon(Icons.currency_rupee, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 2),
                          if (_discountAmount > 0 && isSelected)
                            Text(
                              price.toStringAsFixed(0),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          if (_discountAmount > 0 && isSelected)
                            const SizedBox(width: 4),
                          Text(
                            discountedPrice.toStringAsFixed(0),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: _discountAmount > 0 && isSelected
                                  ? Colors.green.shade700
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 2),
                          Text(
                            '$duration min',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
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
                color: isSelected ? _primaryColor : Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected ? Icons.check : Icons.add,
                    size: isMobile ? 14 : 16,
                    color: isSelected ? Colors.white : _primaryColor,
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 4),
                    Text(
                      isSelected ? 'Selected' : 'Select',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : _primaryColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            child: Icon(Icons.local_offer, color: Colors.green.shade700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎉 Offer Applied!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  _appliedOffer!['title']?.toString() ?? '',
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
            style: TextButton.styleFrom(
              foregroundColor: Colors.green.shade700,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  double _getDiscountedPrice(double originalPrice) {
    if (_appliedOffer == null) return originalPrice;
    final discountType = _appliedOffer!['discount_type']?.toString() ?? '';
    final discountValue = _appliedOffer!['discount_value'] ?? 0;
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
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  image: (_selectedSalon?['logo_url'] as String?) != null && (_selectedSalon!['logo_url'] as String).isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_selectedSalon!['logo_url']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (_selectedSalon?['logo_url'] == null || (_selectedSalon!['logo_url'] as String).isEmpty)
                    ? Center(
                        child: Text(
                          (_selectedSalon?['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'S',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
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
                    ? _primaryColor
                    : Colors.grey[400],
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
    final isSelected = _selectedBarber?['id'] == barber['id'];
    final availability = _barberAvailability[barber['id']];
    final isAvailable = availability?['is_available'] ?? true;
    final hasSpecialSchedule = availability?['has_special_schedule'] ?? false;
    final hasSpecialBreak = availability?['has_special_break'] ?? false;

    final String barberName = barber['full_name']?.toString() ?? 'Barber';
    final String avatarUrl = barber['avatar_url']?.toString() ?? '';
    final double avgRating = (barber['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final int todayAppointments = barber['today_appointments'] ?? 0;

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
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          barberName.substring(0, 1).toUpperCase(),
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
                              barberName,
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
                            avgRating > 0 ? avgRating.toStringAsFixed(1) : 'New',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.work, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '$todayAppointments today',
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
          'full_name': profile['full_name']?.toString() ?? 'Barber',
          'avatar_url': profile['avatar_url']?.toString(),
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
        user?.userMetadata?['full_name']?.toString() ??
        user?.email?.split('@').first ??
        'Customer';

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
                  _selectedBarber?['full_name']?.toString().substring(0, 1).toUpperCase() ?? 'B',
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
                      _selectedBarber?['full_name']?.toString() ?? 'Barber',
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
        ),
        if (_selectedDate != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Who is this appointment for?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Select who will receive the service',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                          'Each person can only have one booking per day.',
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Continue to Time Slot',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
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
            ? '⚠️ You already have a booking for ${childName.isEmpty ? "yourself" : childName} on ${DateFormat('MMM dd').format(_selectedDate!)}.'
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

  // ==================== STEP 6: TIME SLOT SELECTION ====================

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

  Widget _buildTravelTimeSelector() {
    if (!_showTravelTimeSelector) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.15),
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
                  color: _primaryColor,
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
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Select travel time:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
                      ? _primaryColor
                      : Colors.grey[100],
                  foregroundColor: isSelected ? Colors.white : Colors.grey[700],
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedTravelTime > 0
                        ? '✓ Travel time $_selectedTravelTime min added to your appointment'
                        : 'Select travel time to add to your appointment start time',
                    style: TextStyle(
                      fontSize: 12,
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
    );
  }

  Future<void> _loadAvailableSlots() async {
    setState(() {
      _isLoadingSlots = true;
      _availableSlots = [];
      _selectedSlot = null;
      _showTravelTimeSelector = false;
      _slotErrorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingSlots = false);
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
          .timeout(const Duration(seconds: 10));

      if (result == null) throw Exception('No response');
      final data = result is List && result.isNotEmpty ? result[0] : result;

      final conflictType = data['conflict_type']?.toString() ?? '';
      final extensionMinutes = data['extension_minutes'] ?? 0;

      if (isToday &&
          (conflictType == 'OVERFLOW' || conflictType == 'MOVE_TO_NEXT_DAY')) {
        String message =
            'No appointments available on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\n'
            'Your requested time would exceed salon closing time by $extensionMinutes minutes.\n\n'
            'Please select another date or try tomorrow.';

        setState(() {
          _slotErrorMessage = message;
          _isLoadingSlots = false;
        });
        return;
      }

      if (conflictType == 'SALON_CLOSED') {
        setState(() {
          _slotErrorMessage =
              'Salon is closed on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\nPlease select another date.';
          _isLoadingSlots = false;
        });
        return;
      }

      if (conflictType == 'BARBER_UNAVAILABLE') {
        setState(() {
          _slotErrorMessage =
              '${_selectedBarber!['full_name']} is not working on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\nPlease select another barber or date.';
          _isLoadingSlots = false;
        });
        return;
      }

      if (conflictType == 'NO_SLOTS_REMAINING') {
        setState(() {
          _slotErrorMessage =
              'No appointments available on ${DateFormat('EEEE, MMM dd').format(_selectedDate!)}.\n\nAll time slots are fully booked. Please select another date.';
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

      String localStart = TimezoneService.utcToLocalTimeForDate(utcStart, _selectedDate!);
      String localEnd = TimezoneService.utcToLocalTimeForDate(utcEnd, _selectedDate!);

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
        _showTravelTimeSelector = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSlots = false;
        _slotErrorMessage = 'Failed to load time slots. Please try again.';
        _availableSlots = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTimeSlotStep() {
    final isMobile = MediaQuery.of(context).size.width < 600;

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
                  _selectedBarber?['full_name']?.toString().substring(0, 1).toUpperCase() ?? 'B',
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
                      _selectedBarber?['full_name']?.toString() ?? 'Barber',
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
        ),
        if (_selectedDate != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          'No Appointments Available',
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
                                  _showTravelTimeSelector = false;
                                  _selectedTravelTime = 0;
                                  _availableSlots = [];
                                  _isLoadingSlots = true;
                                  _slotErrorMessage = null;
                                });
                                await _checkDateAvailability(tomorrow);
                                await _loadAvailableSlots();
                              },
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: Text(
                                'Try ${DateFormat('MMM dd').format(_selectedDate != null ? _selectedDate!.add(const Duration(days: 1)) : DateTime.now())}',
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
                        const SizedBox(height: 16),
                        if (_selectedBarber != null)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedBarber = null;
                                _currentStep = 3;
                                _slotErrorMessage = null;
                              });
                            },
                            icon: Icon(
                              Icons.person,
                              size: 18,
                              color: _primaryColor,
                            ),
                            label: Text(
                              'Try Another Barber',
                              style: TextStyle(color: _primaryColor),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(bottom: isMobile ? 100 : 16),
                  child: Column(
                    children: [
                      if (_availableSlots.isNotEmpty)
                        _buildTimeSlotCard(_availableSlots.first),
                      if (_showTravelTimeSelector) _buildTravelTimeSelector(),
                    ],
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
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
                    ? _primaryColor
                    : Colors.grey[400],
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
                  const Text(
                    'Continue to Confirmation',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlotCard(Map<String, dynamic> slot) {
    final isSelected = _selectedSlot?['start_time'] == slot['start_time'];
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
      color: isSelected ? _primaryColor.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSelected ? _primaryColor : Colors.grey[200]!,
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
                  color: Colors.grey[600],
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
                    Icon(Icons.access_time, size: 22, color: _primaryColor),
                    const SizedBox(width: 10),
                    Text(
                      '$startTime - $endTime',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _textDark,
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
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '⏱️ ~ $waitMinutes min wait time',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade700,
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
                      color: _primaryColor,
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
                      color: Colors.green.shade700,
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
                      color: Colors.red.shade700,
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
                foregroundColor: Colors.white,
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
    final adjustedFor = _selectedSlot!['adjusted_for']?.toString() ?? '';
    final barberName = _selectedBarber!['full_name']?.toString() ?? 'Barber';
    final barberRating =
        (_selectedBarber!['avg_rating'] as num?)?.toStringAsFixed(1) ?? 'New';
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
                      const Icon(Icons.access_time, size: 20, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '⏰ Times shown in your local timezone: ${_getTimezoneDisplay()}',
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
                      ..._selectedServices
                          .map(
                            (s) => Text(
                              '• ${s['name']?.toString() ?? 'Service'}',
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
                if (_appliedOffer != null && _discountAmount > 0) ...[
                  const SizedBox(height: 12),
                  _buildConfirmationTile(
                    Icons.local_offer,
                    'Discount Applied',
                    '- Rs. ${_discountAmount.toStringAsFixed(2)}',
                    _appliedOffer!['title']?.toString() ?? '',
                  ),
                ],
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

      final result = await supabase.rpc(
        'create_new_appointment_advanced',
        params: {
          'p_customer_id': user.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': _selectedBarber!['id'],
          'p_service_id': _selectedServices.first['id'],
          'p_variant_id': _selectedServices.first['variant_id'],
          'p_appointment_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
          'p_utc_start_time': _selectedSlot!['utc_start_time'],
          'p_utc_end_time': _selectedSlot!['utc_end_time'],
          'p_child_name': _getChildNameForBooking(),
          'p_travel_time_minutes': _selectedSlot!['travel_time_used'] ?? 0,
          'p_notes': _selectedServices.length > 1
              ? 'Combined: ${_selectedServices.map((s) => s['name']?.toString() ?? '').join(", ")}'
              : null,
          'p_is_vip': false,
          'p_vip_booking_id': null,
          'p_confirm_overflow': true,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
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

        if (!mounted) return;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Booking Confirmed! Queue ${result['display_queue'] ?? result['regular_queue_number']}',
              ),
              backgroundColor: _secondaryColor,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(result['message'] ?? 'Booking failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBooking = false;
          _slotErrorMessage =
              'Booking failed: ${e.toString().replaceFirst('Exception: ', '')}';
          _currentStep = 5;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBooking = false);
      }
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
          title: const Text('Book Appointment'),
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
          'Book Appointment',
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