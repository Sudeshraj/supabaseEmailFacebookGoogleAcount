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
  int? _expandedServiceId;

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

  // Offer related variables
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
  // CHECK FOR OFFER FROM NAVIGATION
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

    await _loadFollowedSalons();
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
      _expandedServiceId = null;
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

  String _getSalonLocalTime(Map<String, dynamic> salon) {
    final openTimeUTC = salon['open_time']?.toString() ?? '09:00:00';
    final closeTimeUTC = salon['close_time']?.toString() ?? '18:00:00';
    final referenceDate = _selectedDate ?? DateTime.now();

    final openLocal = TimezoneService.utcToLocalTimeForDate(
      openTimeUTC,
      referenceDate,
    );
    final closeLocal = TimezoneService.utcToLocalTimeForDate(
      closeTimeUTC,
      referenceDate,
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
  // STEP 1: SALON SEARCH
  // ============================================

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
                    Icon(
                      Icons.store_mall_directory,
                      size: 80,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No salons followed yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Follow salons to book VIP appointments',
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
            : _searchResults.isEmpty &&
                  !_isSearching &&
                  _followedSalons.isNotEmpty
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
                          (salon['name'] as String?)
                                  ?.substring(0, 1)
                                  .toUpperCase() ??
                              'S',
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '$followerCount followers',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
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
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
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

  // ============================================
  // STEP 2: DATE SELECTION
  // ============================================

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

      // Auto-select next available date if today is a holiday
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
                  image:
                      (_selectedSalon?['logo_url'] as String?) != null &&
                          (_selectedSalon!['logo_url'] as String).isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_selectedSalon!['logo_url']),
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
                if (_holidays.contains(today))
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_busy,
                          color: Colors.red.shade700,
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
                                  color: Colors.red.shade700,
                                ),
                              ),
                              Text(
                                _holidayNames[today] ?? 'Salon is closed today',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red.shade600,
                                ),
                              ),
                              Text(
                                'Auto-selected next available date: ${DateFormat('EEEE, MMM dd').format(_selectedDate ?? getFirstAvailableDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CalendarDatePicker(
                      initialDate: getFirstAvailableDate(),
                      firstDate: today,
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
                if (isSelectedDateHoliday)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.red.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.event_busy,
                            color: Colors.red.shade700,
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
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${selectedHolidayName ?? 'Salon is closed'} ${isSelectedToday ? 'today' : 'on this date'}',
                                style: TextStyle(
                                  color: Colors.red.shade600,
                                  fontSize: 14,
                                ),
                              ),
                              if (isSelectedToday)
                                Text(
                                  'Please select another date (tomorrow or later)',
                                  style: TextStyle(
                                    color: Colors.red.shade500,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
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
                            _unavailableReason ??
                                '⚠️ No barbers available on this day',
                            style: TextStyle(
                              color: Colors.orange.shade700,
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
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '✅ Selected: ${DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!)}',
                            style: TextStyle(
                              color: Colors.green.shade700,
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
                                    : 'Continue to Services')),
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
  // STEP 3: SERVICE SELECTION
  // ============================================

  Future<void> _loadSalonServices() async {
    if (_servicesLoaded) return;
    setState(() => _isLoadingServices = true);

    try {
      final salonId = _selectedSalon!['id'];

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
                  image:
                      (_selectedSalon?['logo_url'] as String?) != null &&
                          (_selectedSalon!['logo_url'] as String).isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_selectedSalon!['logo_url']),
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
        _buildOfferBanner(),
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

  Widget _buildServiceCard(
    Map<String, dynamic> service,
    int index,
    bool isMobile,
  ) {
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
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
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
                          Icon(
                            Icons.currency_rupee,
                            size: 12,
                            color: Colors.grey[500],
                          ),
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
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
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
                    border: Border.all(
                      color: _primaryColor.withValues(alpha: 0.2),
                    ),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
              child: const Icon(Icons.close, size: 16, color: Colors.red),
            ),
          ),
        ],
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

  // ============================================
  // STEP 4: BARBER SELECTION (UPDATED - FIXED)
  // ============================================

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
      // Check if barber has active role
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

      // Check profile is_active
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

      // Check salon barber status
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

      // Get effective schedule
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

  // ✅ UPDATED: Load available barbers with RPC function
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

      // ✅ Using RPC function - same as working code
      final result = await supabase.rpc(
        'get_active_barbers_for_salon',
        params: {
          'p_salon_id': _selectedSalon!['id'],
          'p_date': DateFormat(
            'yyyy-MM-dd',
          ).format(_selectedDate ?? DateTime.now()),
        },
      );

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

      // Check full availability for each barber
      final dateToCheck = _selectedDate ?? DateTime.now();

      for (var i = 0; i < barberList.length; i++) {
        final barber = barberList[i];
        final barberId = barber['barber_id']; // ✅ Use barber_id

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

      // Sort: available first, then by rating
      barberList.sort((a, b) {
        if (a['is_available'] && !b['is_available']) return -1;
        if (!a['is_available'] && b['is_available']) return 1;
        return (b['avg_rating'] as num).compareTo(a['avg_rating'] as num);
      });

      setState(() {
        _availableBarbers = barberList;
        _isLoadingBarbers = false;
        _barbersLoaded = true;
      });
    } catch (e) {
      debugPrint('❌ Error loading barbers: $e');
      setState(() {
        _isLoadingBarbers = false;
        _barbersLoaded = false;
        _availableBarbers = [];
      });
    }
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
                  image:
                      (_selectedSalon?['logo_url'] as String?) != null &&
                          (_selectedSalon!['logo_url'] as String).isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_selectedSalon!['logo_url']),
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

  // ✅ UPDATED: Build barber card with correct ID
  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final barberId = barber['barber_id'] ?? barber['id']; // ✅ Use barber_id
    final isSelected = (_selectedBarber?['barber_id'] ?? _selectedBarber?['id']) == barberId;
    final availability = _barberAvailability[barberId];
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
                            avgRating > 0
                                ? avgRating.toStringAsFixed(1)
                                : 'New',
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

  // ============================================
  // STEP 5: PERSON SELECTION
  // ============================================

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
                  _selectedBarber?['full_name']
                          ?.toString()
                          .substring(0, 1)
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
                      _selectedBarber?['full_name']?.toString() ?? 'Barber',
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
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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

  // ============================================
  // STEP 6: VIP TIME SLOT SELECTION (UPDATED - FIXED)
  // ============================================

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

  // ✅ FIXED: Load available slots with correct barber ID
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

      // ✅ FIXED: Get barber ID correctly
      final barberId = _selectedBarber!['barber_id'] ?? _selectedBarber!['id'];
      debugPrint('🔍 Loading slots for barber: $barberId');

      final scheduleResult = await supabase.rpc(
        'get_barber_effective_schedule',
        params: {
          'p_barber_id': barberId, // ✅ Use correct barber ID
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
          .eq('barber_id', barberId) // ✅ Use correct barber ID
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

        final localSlotStart = TimezoneService.utcToLocalDateTimeForDate(
          '${slotStartUTC.hour.toString().padLeft(2, '0')}:${slotStartUTC.minute.toString().padLeft(2, '0')}:00',
          _selectedDate!,
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

        final localStartDateTime = TimezoneService.utcToLocalDateTimeForDate(
          '${slotStartUTC.hour.toString().padLeft(2, '0')}:${slotStartUTC.minute.toString().padLeft(2, '0')}:00',
          _selectedDate!,
        );
        final localEndDateTime = TimezoneService.utcToLocalDateTimeForDate(
          '${slotEndUTC.hour.toString().padLeft(2, '0')}:${slotEndUTC.minute.toString().padLeft(2, '0')}:00',
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

  // ============================================
  // STEP 7: CONFIRMATION
  // ============================================

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

      final barberId = _selectedBarber!['barber_id'] ?? _selectedBarber!['id'];

      final utcStartTime = _selectedSlot!['utc_start_time'];
      final utcEndTime = _selectedSlot!['utc_end_time'];

      final result = await supabase.rpc(
        'create_vip_booking',
        params: {
          'p_customer_id': user.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': barberId,
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

  // ============================================
  // MAIN BUILD METHOD
  // ============================================

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
                  _buildSalonSearchStep(), // Step 0
                  _buildDateSelectionStep(), // Step 1
                  _buildServiceSelectionStep(), // Step 2
                  _buildBarberSelectionStep(), // Step 3
                  _buildPersonSelectionStep(), // Step 4
                  _buildTimeSlotStep(), // Step 5
                  _buildConfirmationStep(), // Step 6
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