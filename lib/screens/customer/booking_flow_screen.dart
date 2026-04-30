// lib/screens/customer/booking_flow_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/customer/my_bookings_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Search state
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();

  // Selected data
  Map<String, dynamic>? _selectedSalon;
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _salonServices = [];
  List<Map<String, dynamic>> _selectedServices = [];

  // Available barbers
  List<Map<String, dynamic>> _availableBarbers = [];
  Map<String, dynamic>? _selectedBarber;

  // Travel time
  int _selectedTravelTime = 0;
  bool _showTravelTimeSelector = false;
  final List<int> _travelTimeOptions = [5, 10, 15, 20, 25, 30, 45, 60];

  // Appointment slots
  List<Map<String, dynamic>> _availableSlots = [];
  Map<String, dynamic>? _selectedSlot;

  // Loading states
  bool _isLoadingServices = false;
  bool _isLoadingBarbers = false;
  bool _isLoadingSlots = false;
  bool _isBooking = false;
  bool _isInitialized = false;

  // Prevent multiple calls
  bool _servicesLoaded = false;
  bool _barbersLoaded = false;

  // Category tab state
  String? _selectedCategoryTab;

  // Holiday check
  Set<DateTime> _holidays = {};
  Map<DateTime, String> _holidayNames = {};
  bool _isDateUnavailable = false;
  String? _unavailableReason;

  // Barber availability status
  Map<String, Map<String, dynamic>> _barberAvailability = {};

  // Person selection
  final TextEditingController _childNameController = TextEditingController();
  String? _selectedChildName;
  bool _isSameAsCustomer = true;
  bool _isCheckingDuplicate = false;
  String? _duplicateError;

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
    _initializeScreen();
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: Text(
          'Book Appointment',
          style: TextStyle(
            fontSize: isWeb ? 22 : 18,
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
          if (_currentStep > 0)
            TextButton(
              onPressed: () => _resetBooking(),
              child: Text(
                'Reset',
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Step indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                _buildStepIndicator(0, 'Salon', Icons.store),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 0 ? _primaryColor : Colors.grey[300],
                  ),
                ),
                _buildStepIndicator(1, 'Date', Icons.calendar_today),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 1 ? _primaryColor : Colors.grey[300],
                  ),
                ),
                _buildStepIndicator(2, 'Service', Icons.content_cut),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 2 ? _primaryColor : Colors.grey[300],
                  ),
                ),
                _buildStepIndicator(3, 'Barber', Icons.person),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 3 ? _primaryColor : Colors.grey[300],
                  ),
                ),
                _buildStepIndicator(4, 'Person', Icons.badge),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 4 ? _primaryColor : Colors.grey[300],
                  ),
                ),
                _buildStepIndicator(5, 'Time', Icons.access_time),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > 5 ? _primaryColor : Colors.grey[300],
                  ),
                ),
                _buildStepIndicator(6, 'Confirm', Icons.check_circle),
              ],
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
    );
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
    });
  }

  Widget _buildStepIndicator(int step, String label, IconData icon) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? _primaryColor
                : (isActive
                      ? _primaryColor.withOpacity(0.1)
                      : Colors.grey[200]),
            border: Border.all(
              color: isActive ? _primaryColor : Colors.grey[300]!,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : Icon(
                    icon,
                    size: 20,
                    color: isActive ? _primaryColor : Colors.grey[500],
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? _primaryColor : Colors.grey[500],
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ==================== STEP 1: SALON SEARCH ====================
  Widget _buildSalonSearchStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _searchSalons,
            decoration: InputDecoration(
              hintText: 'Search salon by name...',
              prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
              suffixIcon: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey[50],
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
                      Icon(Icons.search, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Search for a salon',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : _searchResults.isEmpty &&
                    !_isSearching &&
                    _searchController.text.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.store, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No salons found',
                        style: TextStyle(color: Colors.grey[500]),
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
  }

  Widget _buildSalonCard(Map<String, dynamic> salon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _selectSalon(salon),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    (salon['name'] as String?)?.substring(0, 1).toUpperCase() ??
                        'S',
                    style: TextStyle(
                      fontSize: 24,
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatTime(salon['open_time'])} - ${_formatTime(salon['close_time'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(dynamic time) {
    if (time == null) return '09:00';
    final timeStr = time.toString();
    if (timeStr.isEmpty) return '09:00';
    if (timeStr.length >= 5) {
      return timeStr.substring(0, 5);
    }
    return timeStr;
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
      debugPrint('Search error: $e');
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

  Widget _buildDateSelectionStep() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
                      'Selected Salon',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      _selectedSalon?['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: Text('Change', style: TextStyle(color: _primaryColor)),
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
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CalendarDatePicker(
                      initialDate: today,
                      firstDate: today,
                      lastDate: maxDate,
                      selectableDayPredicate: (date) {
                        final isHoliday = _holidays.contains(date);
                        return !isHoliday;
                      },
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
                if (_selectedDate != null && _holidays.contains(_selectedDate))
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_busy, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Holiday: ${_holidayNames[_selectedDate]}',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isDateUnavailable &&
                    !_holidays.contains(_selectedDate)) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _unavailableReason ??
                                'No barbers available on this date',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
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
                          : Colors.grey[300],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _selectedDate == null
                          ? 'Select Date'
                          : (_holidays.contains(_selectedDate)
                                ? 'Holiday - Not Available'
                                : (_isDateUnavailable
                                      ? 'No Barbers Available'
                                      : 'Continue →')),
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

  Future<void> _checkDateAvailability(DateTime date) async {
    if (_selectedSalon == null) return;

    final dayOfWeek = date.weekday;

    try {
      final schedules = await supabase
          .from('barber_schedules')
          .select('barber_id')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('day_of_week', dayOfWeek)
          .eq('is_working', true);

      if (schedules.isEmpty) {
        setState(() {
          _isDateUnavailable = true;
          _unavailableReason =
              'No barbers working on ${DateFormat('EEEE').format(date)}';
        });
        return;
      }

      setState(() {
        _isDateUnavailable = false;
        _unavailableReason = null;
      });
    } catch (e) {
      debugPrint('Error checking date availability: $e');
    }
  }

  // ==================== STEP 3: SERVICE SELECTION ====================
  Widget _buildServiceSelectionStep() {
    final isWeb = MediaQuery.of(context).size.width > 800;

    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    for (var service in _salonServices) {
      final category = service['category_name'] ?? 'Other';
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    final List<String> categories = groupedServices.keys.toList();
    if (_selectedCategoryTab == null && categories.isNotEmpty) {
      _selectedCategoryTab = categories.first;
    }

    List<Map<String, dynamic>> servicesToShow = [];
    if (_selectedCategoryTab == null) {
      for (var services in groupedServices.values) {
        servicesToShow.addAll(services);
      }
    } else {
      servicesToShow = groupedServices[_selectedCategoryTab] ?? [];
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
                      'Selected Salon',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      _selectedSalon?['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: Text('Change', style: TextStyle(color: _primaryColor)),
              ),
            ],
          ),
        ),
        if (_selectedDate != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: _secondaryColor),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: Text('Change', style: TextStyle(color: _primaryColor)),
                ),
              ],
            ),
          ),
        if (_selectedServices.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedServices
                      .map(
                        (service) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            service['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Total: ${_calculateTotalDuration()} min | Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: 45,
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildCategoryChip('All', _selectedCategoryTab == null),
              ...categories.map(
                (category) => _buildCategoryChip(
                  category,
                  _selectedCategoryTab == category,
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
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No services available',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : isWeb
              ? GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: servicesToShow.length,
                  itemBuilder: (context, index) =>
                      _buildServiceCard(servicesToShow[index], index),
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
                      });
                      _loadAvailableBarbers();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedServices.isNotEmpty
                    ? _primaryColor
                    : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _selectedServices.isEmpty ? 'Select a service' : 'Continue →',
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

  Widget _buildCategoryChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) =>
            setState(() => _selectedCategoryTab = isSelected ? null : label),
        backgroundColor: Colors.white,
        selectedColor: _primaryColor,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : _textDark,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        side: BorderSide(color: isSelected ? _primaryColor : Colors.grey[300]!),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final serviceId = service['id'] as int;
    final isSelected = _selectedServices.any((s) => s['id'] == serviceId);
    final hasVariants =
        service['variants'] != null && (service['variants'] as List).isNotEmpty;
    final variants = service['variants'] as List? ?? [];
    final selectedVariantCount = _selectedServices
        .where((s) => s['id'] == serviceId)
        .length;
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? _primaryColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cardColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getServiceIcon(service['name']),
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
                          service['name'] ?? 'Service',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: _textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          service['category_name'] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selectedVariantCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$selectedVariantCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hasVariants) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: variants
                      .map((variant) => _buildVariantCard(service, variant))
                      .toList(),
                ),
              ),
            ] else ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _toggleService(service),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isSelected
                          ? _secondaryColor
                          : _primaryColor,
                      side: BorderSide(
                        color: isSelected ? _secondaryColor : _primaryColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(isSelected ? 'Selected ✓' : 'Select'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantCard(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final serviceId = service['id'] as int;
    final isSelected = _selectedServices.any(
      (s) => s['id'] == serviceId && s['variant_id'] == variant['id'],
    );

    return GestureDetector(
      onTap: () => _toggleVariant(service, variant),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _primaryColor : Colors.grey[200]!,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _getGenderIcon(variant['gender'] ?? ''),
              size: 20,
              color: isSelected ? _primaryColor : Colors.grey[600],
            ),
            const SizedBox(width: 10),
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
                      fontSize: 13,
                      color: isSelected ? _primaryColor : _textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs. ${variant['price']} • ${variant['duration']} min',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? _primaryColor : Colors.grey[400]!,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getGenderIcon(String gender) {
    final genderLower = gender.toLowerCase();
    if (genderLower.contains('male')) return Icons.male;
    if (genderLower.contains('female')) return Icons.female;
    return Icons.people;
  }

  Future<void> _loadSalonServices() async {
    if (_servicesLoaded) return;

    setState(() => _isLoadingServices = true);

    try {
      final response = await supabase
          .from('salon_services_with_details')
          .select()
          .eq('salon_id', _selectedSalon!['id'])
          .eq('service_active', true);

      final List<dynamic> services = response;

      final categories = await supabase
          .from('salon_categories')
          .select('id, display_name')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('is_active', true);

      final Map<int, String> categoryMap = {};
      for (var cat in categories) {
        categoryMap[cat['id']] = cat['display_name'];
      }

      final Map<int, Map<String, dynamic>> groupedServices = {};

      for (var service in services) {
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
      debugPrint('Error loading services: $e');
      setState(() => _isLoadingServices = false);
    }
  }

  void _toggleService(Map<String, dynamic> service) {
    final serviceId = service['id'] as int;
    if (_selectedServices.any((s) => s['id'] == serviceId)) {
      setState(() {
        _selectedServices.removeWhere((s) => s['id'] == serviceId);
      });
    } else if (service['variants'].isNotEmpty) {
      final firstVariant = service['variants'].first;
      _addServiceVariant(service, firstVariant);
    }
  }

  void _toggleVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final serviceId = service['id'] as int;
    final variantId = variant['id'] as int;

    if (_selectedServices.any(
      (s) => s['id'] == serviceId && s['variant_id'] == variantId,
    )) {
      setState(() {
        _selectedServices.removeWhere(
          (s) => s['id'] == serviceId && s['variant_id'] == variantId,
        );
      });
    } else {
      _addServiceVariant(service, variant);
    }
  }

  void _addServiceVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    setState(() {
      _selectedServices.add({
        'id': service['id'],
        'name': service['name'],
        'variant_id': variant['id'],
        'gender': variant['gender'],
        'age': variant['age'],
        'price': variant['price'],
        'duration': variant['duration'],
      });
    });
  }

  int _calculateTotalDuration() {
    return _selectedServices.fold(0, (sum, s) => sum + (s['duration'] as int));
  }

  double _calculateTotalPrice() {
    return _selectedServices.fold(
      0.0,
      (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0),
    );
  }

  IconData _getServiceIcon(String? serviceName) {
    if (serviceName == null) return Icons.content_cut;
    final name = serviceName.toLowerCase();
    if (name.contains('hair')) return Icons.content_cut;
    if (name.contains('face') || name.contains('skin')) return Icons.face;
    if (name.contains('shave')) return Icons.face_retouching_natural;
    if (name.contains('massage')) return Icons.spa;
    return Icons.build;
  }

  // ==================== STEP 4: BARBER SELECTION ====================
  String _safeToString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  Future<Map<String, dynamic>> _checkBarberFullAvailability(
    String barberId,
    DateTime date,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    Map<String, dynamic> result = {
      'is_available': true,
      'reason': null,
      'available_from': null,
      'available_to': null,
      'has_special_schedule': false,
      'has_special_break': false,
      'work_start': null,
      'work_end': null,
      'break_start': null,
      'break_end': null,
      'salon_close_time': null,
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
        result['work_start'] = _safeToString(schedule['work_start']);
        result['work_end'] = _safeToString(schedule['work_end']);
        result['break_start'] = _safeToString(schedule['lunch_break_start']);
        result['break_end'] = _safeToString(schedule['lunch_break_end']);
        result['salon_close_time'] = _safeToString(
          schedule['salon_close_time'],
        );

        result['has_special_schedule'] =
            schedule['has_special_schedule'] == true;
        result['has_special_break'] = schedule['has_special_break'] == true;

        final leaveType = schedule['leave_type'] as String?;
        if (leaveType == 'full_day') {
          result['is_available'] = false;
          result['reason'] = 'On full day leave';
          return result;
        }
        if (leaveType == 'half_day') {
          result['is_available'] = true;
          result['reason'] = 'Half day - limited availability';
        }
      }

      final now = DateTime.now();
      final isToday = date.isAtSameMomentAs(
        DateTime(now.year, now.month, now.day),
      );

      if (isToday &&
          result['work_start'] != null &&
          result['work_start'].toString().isNotEmpty) {
        final workStartStr = result['work_start'].toString();
        final workStartParts = workStartStr.split(':');
        if (workStartParts.length >= 2) {
          final workStartHour = int.tryParse(workStartParts[0]) ?? 9;
          final workStartMinute = int.tryParse(workStartParts[1]) ?? 0;

          final workStartDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            workStartHour,
            workStartMinute,
          );

          if (now.isAfter(workStartDateTime.add(const Duration(minutes: 30)))) {
            final newTime = now.add(const Duration(minutes: 15));
            result['available_from'] =
                '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking barber availability: $e');
      result['is_available'] = true;
    }

    return result;
  }

  Widget _buildBarberSelectionStep() {
    if (!_barbersLoaded && !_isLoadingBarbers && _selectedSalon != null) {
      _barbersLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadAvailableBarbers(),
      );
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
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_calculateTotalDuration()} min total',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 2),
                child: Text('Change', style: TextStyle(color: _primaryColor)),
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
                Icon(Icons.calendar_today, size: 16, color: _secondaryColor),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: Text('Change', style: TextStyle(color: _primaryColor)),
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
                      Icon(Icons.person_off, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No barbers available',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _barbersLoaded = false;
                          _loadAvailableBarbers();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
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
                    : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _selectedBarber == null ? 'Select a barber' : 'Continue →',
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
    final unavailableReason = availability?['reason'];
    final availableFrom = availability?['available_from'];
    final hasSpecialSchedule = availability?['has_special_schedule'] ?? false;
    final hasSpecialBreak = availability?['has_special_break'] ?? false;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _primaryColor.withOpacity(0.1),
                  backgroundImage: barber['avatar_url'] != null
                      ? NetworkImage(barber['avatar_url'])
                      : null,
                  child: barber['avatar_url'] == null
                      ? Text(
                          barber['full_name']?.substring(0, 1).toUpperCase() ??
                              'B',
                          style: TextStyle(
                            fontSize: 22,
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
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!isAvailable)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Unavailable',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: Colors.amber[700]),
                          const SizedBox(width: 4),
                          Text(
                            (barber['avg_rating'] as num?)?.toStringAsFixed(
                                  1,
                                ) ??
                                '4.5',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.work, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '${barber['today_appointments'] ?? 0} today',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      if (hasSpecialSchedule)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.amber.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Special schedule today',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasSpecialBreak)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.free_breakfast,
                                size: 12,
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Special break today',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!isAvailable && unavailableReason != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 12,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                unavailableReason,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                              if (availableFrom != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(Available from ${_formatTime(availableFrom)})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isAvailable)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? _primaryColor : Colors.grey[400]!,
                        width: 2,
                      ),
                      color: isSelected ? _primaryColor : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                if (!isAvailable)
                  const Icon(Icons.block, color: Colors.red, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadAvailableBarbers() async {
    if (_isLoadingBarbers) return;

    setState(() => _isLoadingBarbers = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _availableBarbers = [];
          _isLoadingBarbers = false;
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
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
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
            .eq('appointment_date', todayStr)
            .inFilter('status', ['confirmed', 'pending']);

        final ratings = await supabase
            .from('reviews')
            .select('overall_rating')
            .eq('barber_id', barberId);

        double avgRating = 4.5;
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
          'available_from': availability['available_from'],
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
      });
    } catch (e) {
      debugPrint('Error loading barbers: $e');
      setState(() => _isLoadingBarbers = false);
      _barbersLoaded = false;
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
                    radius: 20,
                    backgroundColor: _primaryColor.withOpacity(0.1),
                    child: Text(
                      _selectedBarber?['full_name']
                              ?.substring(0, 1)
                              .toUpperCase() ??
                          'B',
                      style: TextStyle(
                        color: _primaryColor,
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
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_calculateTotalDuration()} min service',
                          style: TextStyle(
                            fontSize: 12,
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
                      style: TextStyle(color: _primaryColor),
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
                        size: 16,
                        color: _secondaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 1),
                        child: Text(
                          'Change',
                          style: TextStyle(color: _primaryColor),
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
                  'Who is this appointment for?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select who will receive the service',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),

                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _isSameAsCustomer
                          ? _primaryColor
                          : Colors.grey[300]!,
                      width: _isSameAsCustomer ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isSameAsCustomer = true;
                        _selectedChildName = null;
                        _childNameController.clear();
                        _duplicateError = null;
                      });
                      _checkDuplicateBooking();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Icon(
                              Icons.person,
                              size: 28,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Myself',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  customerName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  'Booking for yourself',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isSameAsCustomer
                                  ? _primaryColor
                                  : Colors.transparent,
                              border: Border.all(
                                color: _isSameAsCustomer
                                    ? _primaryColor
                                    : Colors.grey[400]!,
                              ),
                            ),
                            child: _isSameAsCustomer
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
                ),

                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: !_isSameAsCustomer
                          ? _primaryColor
                          : Colors.grey[300]!,
                      width: !_isSameAsCustomer ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isSameAsCustomer = false;
                        _duplicateError = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Icon(
                              Icons.group,
                              size: 28,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Someone else',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Family member, friend, or child',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (!_isSameAsCustomer &&
                                    _selectedChildName != null &&
                                    _selectedChildName!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Will book for: $_selectedChildName',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _primaryColor,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: !_isSameAsCustomer
                                  ? _primaryColor
                                  : Colors.transparent,
                              border: Border.all(
                                color: !_isSameAsCustomer
                                    ? _primaryColor
                                    : Colors.grey[400]!,
                              ),
                            ),
                            child: !_isSameAsCustomer
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
                ),

                if (!_isSameAsCustomer) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.badge, size: 20, color: _primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Person\'s Name',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _childNameController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Enter full name (e.g., Kamal Perera)',
                            prefixIcon: Icon(
                              Icons.person_outline,
                              color: _primaryColor,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _primaryColor,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedChildName = value.trim();
                              _duplicateError = null;
                            });
                            _checkDuplicateBooking();
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 12,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Use the person\'s real name as it will appear on their booking',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                if ((_isSameAsCustomer) ||
                    (_selectedChildName != null &&
                        _selectedChildName!.isNotEmpty))
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _primaryColor.withOpacity(0.1),
                          _primaryColor.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _primaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _isSameAsCustomer ? Icons.person : Icons.badge,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Booking for',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _primaryColor,
                                ),
                              ),
                              Text(
                                _isSameAsCustomer
                                    ? customerName
                                    : _selectedChildName!,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_isSameAsCustomer)
                          IconButton(
                            icon: Icon(
                              Icons.edit,
                              size: 18,
                              color: _primaryColor,
                            ),
                            onPressed: () {
                              _childNameController.clear();
                              setState(() {
                                _selectedChildName = null;
                              });
                            },
                          ),
                      ],
                    ),
                  ),

                if (_duplicateError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red.shade700),
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
                ],

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Each person can only have one booking per day. You can book for multiple different people on the same day.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
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
                          _showTravelTimeSelector = false;
                          _selectedTravelTime = 0;
                          _availableSlots = [];
                          _selectedSlot = null;
                        });
                        await _loadAvailableSlots();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canProceedToTimeSlot()
                    ? _primaryColor
                    : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  bool _canProceedToTimeSlot() {
    if (_isCheckingDuplicate) return false;
    if (_duplicateError != null) return false;
    if (_isSameAsCustomer) return true;
    return _selectedChildName != null && _selectedChildName!.trim().isNotEmpty;
  }

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

      final existingBookings = await supabase
          .from('appointments')
          .select('id, child_name, status')
          .eq('customer_id', user.id)
          .eq('appointment_date', dateStr)
          .eq('child_name', childName)
          .not('status', 'in', '("cancelled","no_show")');

      if (existingBookings.isNotEmpty) {
        setState(() {
          _duplicateError =
              '⚠️ You already have a booking for ${childName.isEmpty ? "yourself" : childName} on ${DateFormat('MMM dd').format(_selectedDate!)}.\n\nEach person can only have one booking per day.';
        });
      } else {
        setState(() {
          _duplicateError = null;
        });
      }
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

  String _getChildNameForBooking() {
    if (_isSameAsCustomer) return '';
    return _selectedChildName?.trim() ?? '';
  }

  // ==================== STEP 6: TIME SLOT SELECTION ====================

  Widget _buildTimezoneIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TimezoneService.getTimezoneFlag(),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          Text(
            TimezoneService.getTimezoneDisplayName(),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(width: 4),
          Text(
            '(${TimezoneService.getUtcOffsetString()})',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelTimeSelector() {
    if (!_showTravelTimeSelector) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.directions_car,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Travel Time Required',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'How long will it take to reach the salon?',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Select travel time:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _travelTimeOptions.map((time) {
              final isSelected = _selectedTravelTime == time;
              return ElevatedButton(
                onPressed: () async {
                  print('Travel time selected: $time min');
                  setState(() {
                    _selectedTravelTime = time;
                    _showTravelTimeSelector = false;
                    _availableSlots = [];
                    _isLoadingSlots = false;
                  });
                  await _loadAvailableSlots();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? _primaryColor
                      : Colors.grey[200],
                  foregroundColor: isSelected ? Colors.white : Colors.grey[700],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text('${time} min'),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selecting travel time helps us schedule your appointment accurately',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
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
    if (_isLoadingSlots) return;

    setState(() => _isLoadingSlots = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingSlots = false);
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final totalDuration = _calculateTotalDuration();

      // Get existing appointments
      final existingAppointments = await supabase
          .from('appointments')
          .select('id, end_time')
          .eq('barber_id', _selectedBarber!['id'])
          .eq('appointment_date', dateStr)
          .inFilter('status', ['confirmed', 'pending', 'in_progress']);

      final appointmentCount = existingAppointments.length;
      final isFirstBooking = appointmentCount == 0;

      // Calculate wait time if not first booking
      int waitMinutes = 0;
      if (!isFirstBooking) {
        DateTime? lastEndTime;
        for (var apt in existingAppointments) {
          final endTimeStr = apt['end_time'].toString();
          final endParts = endTimeStr.split(':');
          final aptEndTime = DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
            int.parse(endParts[0]),
            int.parse(endParts[1]),
          );
          if (lastEndTime == null || aptEndTime.isAfter(lastEndTime)) {
            lastEndTime = aptEndTime;
          }
        }

        if (lastEndTime != null) {
          final now = DateTime.now();
          waitMinutes = lastEndTime.difference(now).inMinutes;
        }
      }

      // Show travel time selector if needed
      if (_selectedTravelTime == 0 && (isFirstBooking || waitMinutes <= 30)) {
        print(
          'Showing travel time selector (firstBooking=$isFirstBooking, wait=$waitMinutes)',
        );
        setState(() {
          _showTravelTimeSelector = true;
          _isLoadingSlots = false;
        });
        return;
      }

      setState(() => _showTravelTimeSelector = false);

      print('Calling RPC with travel time: $_selectedTravelTime');

      final result = await supabase.rpc(
        'calculate_next_queue_start_advanced',
        params: {
          'p_barber_id': _selectedBarber!['id'],
          'p_appointment_date': dateStr,
          'p_service_duration': totalDuration,
          'p_travel_time_minutes': _selectedTravelTime,
          'p_salon_id': _selectedSalon!['id'],
        },
      );

      print('RPC Result: $result');

      if (result == null) {
        throw Exception('Failed to calculate time slot');
      }

      final data = result is List && result.isNotEmpty ? result[0] : result;

      if (data['needs_travel_selector'] == true && _selectedTravelTime == 0) {
        print('RPC says need travel selector');
        setState(() {
          _showTravelTimeSelector = true;
          _isLoadingSlots = false;
        });
        return;
      }

      // Get UTC times from database
      String utcStartTime = data['new_start_time']?.toString() ?? '--:--';
      String utcEndTime = data['new_end_time']?.toString() ?? '--:--';

      // Convert UTC to Local using TimezoneService
      String localStartTime = TimezoneService.utcToLocalTime(
        utcStartTime,
        _selectedDate!,
      );
      String localEndTime = TimezoneService.utcToLocalTime(
        utcEndTime,
        _selectedDate!,
      );

      print(
        'UTC: $utcStartTime -> Local: $localStartTime (${TimezoneService.getCurrentTimezone()})',
      );

      final queueNumRaw = data['new_queue_number'];
      int queueNumber = 1;
      if (queueNumRaw is int) {
        queueNumber = queueNumRaw;
      } else if (queueNumRaw is String) {
        queueNumber = int.tryParse(queueNumRaw) ?? 1;
      }

      final waitRaw = data['estimated_wait_minutes'];
      int estimatedWait = 0;
      if (waitRaw is int) {
        estimatedWait = waitRaw;
      } else if (waitRaw is String) {
        estimatedWait = int.tryParse(waitRaw) ?? 0;
      }

      final extRaw = data['extension_minutes'];
      int extensionMinutes = 0;
      if (extRaw is int) {
        extensionMinutes = extRaw;
      } else if (extRaw is String) {
        extensionMinutes = int.tryParse(extRaw) ?? 0;
      }

      final salonWillExtend = data['salon_will_extend'] == true;
      final adjustedFor = data['adjusted_for']?.toString() ?? '';

      String message = 'Queue #$queueNumber • ';
      if (_selectedTravelTime > 0) {
        message += 'Travel: $_selectedTravelTime min • ';
      }

      if (estimatedWait > 200) {
        message += "Please select another date or barber";
      } else if (estimatedWait > 0) {
        message += "Wait: $estimatedWait min";
      } else {
        message += "Available now";
      }

      if (salonWillExtend) {
        message += '\n⏰ Salon will close $extensionMinutes minutes late';
      }

      print('Final start time: $localStartTime');
      print('Queue number: $queueNumber');

      setState(() {
        _availableSlots = [
          {
            'start_time': localStartTime,
            'end_time': localEndTime,
            'utc_start_time': utcStartTime,
            'utc_end_time': utcEndTime,
            'queue_number': queueNumber,
            'is_available': true,
            'duration': totalDuration,
            'estimated_wait_minutes': estimatedWait,
            'travel_time_used': _selectedTravelTime,
            'salon_will_extend': salonWillExtend,
            'extension_minutes': extensionMinutes,
            'adjusted_for': adjustedFor,
            'message': message,
          },
        ];
        _isLoadingSlots = false;
      });
    } catch (e) {
      print('Error loading slots: $e');
      setState(() => _isLoadingSlots = false);

      setState(() {
        _showTravelTimeSelector = true;
        _availableSlots = [
          {
            'start_time': '--:--',
            'end_time': '--:--',
            'queue_number': 0,
            'is_available': false,
            'duration': _calculateTotalDuration(),
            'message': 'Please select travel time to continue',
          },
        ];
      });
    }
  }

  Widget _buildTimeSlotStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _primaryColor.withOpacity(0.1),
                child: Text(
                  _selectedBarber?['full_name']
                          ?.substring(0, 1)
                          .toUpperCase() ??
                      'B',
                  style: TextStyle(
                    color: _primaryColor,
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
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_calculateTotalDuration()} min service',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = 3),
                child: Text('Change', style: TextStyle(color: _primaryColor)),
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
                Icon(Icons.calendar_today, size: 16, color: _secondaryColor),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: Text('Change', style: TextStyle(color: _primaryColor)),
                ),
              ],
            ),
          ),

        _buildTimezoneIndicator(),
        _buildTravelTimeSelector(),

        Expanded(
          child: _isLoadingSlots
              ? const Center(child: CircularProgressIndicator())
              : _availableSlots.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No slots available',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _loadAvailableSlots();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                        ),
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _availableSlots.length,
                  itemBuilder: (context, index) =>
                      _buildTimeSlotCard(_availableSlots[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_selectedSlot == null ||
                      (_availableSlots.isNotEmpty &&
                          _availableSlots[0]['is_available'] == false))
                  ? null
                  : () => setState(() => _currentStep = 6),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    (_selectedSlot != null &&
                        _availableSlots.isNotEmpty &&
                        _availableSlots[0]['is_available'] == true)
                    ? _primaryColor
                    : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlotCard(Map<String, dynamic> slot) {
    final isSelected = _selectedSlot?['start_time'] == slot['start_time'];
    final isAvailable = slot['is_available'] ?? true;
    final queueNumber = slot['queue_number'] ?? 0;
    final message = slot['message'];
    final waitMinutes = slot['estimated_wait_minutes'] ?? 0;
    final travelTimeUsed = slot['travel_time_used'] ?? 0;
    final salonWillExtend = slot['salon_will_extend'] ?? false;
    final extensionMinutes = slot['extension_minutes'] ?? 0;

    final startTime = slot['start_time'];
    final endTime = slot['end_time'];

    String displayMessage = message ?? '';
    if (waitMinutes > 200 && isAvailable) {
      displayMessage =
          '⚠️ Long wait time. Consider selecting another date or barber.';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? _primaryColor.withOpacity(0.05) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? _primaryColor : _primaryColor.withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: isAvailable ? () => setState(() => _selectedSlot = slot) : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isAvailable
                        ? [_primaryColor, _primaryColor.withOpacity(0.8)]
                        : [Colors.grey, Colors.grey.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Your Queue Number',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#$queueNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (waitMinutes > 0 && waitMinutes <= 200)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '≈ $waitMinutes min wait',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                    if (waitMinutes > 200)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '⚠️ Long wait',
                          style: TextStyle(
                            color: Colors.orange.shade300,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    if (travelTimeUsed > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '🚗 $travelTimeUsed min travel time',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                    if (salonWillExtend)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '⏰ +$extensionMinutes min extended',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.access_time,
                      color: isAvailable ? _primaryColor : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$startTime - $endTime',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isAvailable ? _textDark : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${slot['duration']} minutes',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              if (displayMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? (waitMinutes > 200
                              ? Colors.orange.shade50
                              : Colors.green.shade50)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isAvailable
                            ? (waitMinutes > 200
                                  ? Icons.warning_amber
                                  : Icons.check_circle)
                            : Icons.warning_amber,
                        size: 14,
                        color: isAvailable
                            ? (waitMinutes > 200
                                  ? Colors.orange.shade700
                                  : Colors.green.shade700)
                            : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          displayMessage,
                          style: TextStyle(
                            fontSize: 11,
                            color: isAvailable
                                ? (waitMinutes > 200
                                      ? Colors.orange.shade700
                                      : Colors.green.shade700)
                                : Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isAvailable
                      ? () => setState(() => _selectedSlot = slot)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected
                        ? _secondaryColor
                        : (isAvailable ? _primaryColor : Colors.grey),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isSelected
                        ? 'Selected ✓'
                        : (isAvailable ? 'Select This Time' : 'Not Available'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
    final user = supabase.auth.currentUser;
    final customerName =
        user?.userMetadata?['full_name'] ??
        user?.email?.split('@').first ??
        'Customer';
    final displayName = _isSameAsCustomer
        ? customerName
        : _getChildNameForBooking();

    if (_selectedSalon == null ||
        _selectedServices.isEmpty ||
        _selectedBarber == null ||
        _selectedSlot == null ||
        _selectedDate == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Missing information',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _resetBooking(),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text('Start Over'),
            ),
          ],
        ),
      );
    }

    final waitMinutes = _selectedSlot!['estimated_wait_minutes'] ?? 0;
    final willExtend = _selectedSlot!['salon_will_extend'] ?? false;
    final extensionMin = _selectedSlot!['extension_minutes'] ?? 0;
    final travelTimeUsed = _selectedSlot!['travel_time_used'] ?? 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildConfirmationTile(
                  icon: Icons.store,
                  title: 'Salon',
                  value: _selectedSalon!['name'] ?? '',
                  subtitle: _selectedSalon!['address'],
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  icon: Icons.calendar_today,
                  title: 'Date & Time',
                  value: DateFormat(
                    'EEEE, MMM dd, yyyy',
                  ).format(_selectedDate!),
                  subtitle:
                      '${_selectedSlot!['start_time']} - ${_selectedSlot!['end_time']} • Queue #${_selectedSlot!['queue_number']}',
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  icon: Icons.badge,
                  title: 'Booking For',
                  value: displayName,
                  subtitle: _isSameAsCustomer
                      ? 'Self booking'
                      : 'Booking for family/friend',
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  icon: Icons.content_cut,
                  title: 'Services (${_selectedServices.length})',
                  value:
                      '${_calculateTotalDuration()} min • Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedServices
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '• ${s['name']} ${s['gender'] != null ? '(${s['gender']} ${s['age']})' : ''}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  icon: Icons.person,
                  title: 'Barber',
                  value: _selectedBarber!['full_name'] ?? '',
                  subtitle:
                      '⭐ ${(_selectedBarber!['avg_rating'] as num?)?.toStringAsFixed(1) ?? '4.5'} rating',
                ),
                if (travelTimeUsed > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildConfirmationTile(
                      icon: Icons.directions_car,
                      title: 'Travel Time',
                      value: '$travelTimeUsed minutes',
                      subtitle:
                          'Arrive $travelTimeUsed minutes before appointment',
                    ),
                  ),
                if (willExtend)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildConfirmationTile(
                      icon: Icons.access_time,
                      title: 'Salon Hours',
                      value: 'Extended by $extensionMin minutes',
                      subtitle:
                          'Salon will stay open later for this appointment',
                    ),
                  ),
                if (waitMinutes > 30)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildConfirmationTile(
                      icon: Icons.timer,
                      title: 'Wait Time',
                      value: '$waitMinutes minutes',
                      subtitle: 'You may need to wait. Please arrive on time.',
                    ),
                  ),
                const SizedBox(height: 8),
                _buildTimezoneIndicator(),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationTile({
    required IconData icon,
    required String title,
    required String value,
    dynamic subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  if (subtitle is String)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    )
                  else
                    subtitle,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CONFIRM BOOKING WITH DUPLICATE CHECK ====================

  Future<void> _confirmBooking() async {
    print('📌 CONFIRM BOOKING STARTED');

    // Check mounted before any state change
    if (!mounted) return;
    setState(() => _isBooking = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please login');

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final childName = _getChildNameForBooking();
      final travelTime = _selectedSlot?['travel_time_used'] ?? 0;

      // Get UTC times from selected slot
      final String utcStartTime = _selectedSlot!['utc_start_time'];
      final String utcEndTime = _selectedSlot!['utc_end_time'];

      print('📅 Date: $dateStr');
      print('👤 Child: ${childName.isEmpty ? "Myself" : childName}');
      print('⏰ UTC Times: $utcStartTime - $utcEndTime');

      if (_selectedServices.isEmpty) {
        throw Exception('No service selected');
      }

      final firstService = _selectedServices.first;

      print('📝 Creating appointment with params...');

      final result = await supabase.rpc(
        'create_new_appointment_advanced',
        params: {
          'p_customer_id': user.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': _selectedBarber!['id'],
          'p_service_id': firstService['id'],
          'p_variant_id': firstService['variant_id'],
          'p_appointment_date': dateStr,
          'p_utc_start_time': utcStartTime,
          'p_utc_end_time': utcEndTime,
          'p_child_name': childName.isEmpty ? null : childName,
          'p_travel_time_minutes': travelTime,
          'p_notes': _selectedServices.length > 1
              ? 'Combined booking with ${_selectedServices.length} services: ${_selectedServices.map((s) => s['name']).join(', ')}'
              : null,
          'p_is_vip': false,
          'p_vip_booking_id': null,
          'p_confirm_overflow': true,
        },
      );

      print('📨 RPC Response: $result');

      // =====================================================
      // CHECK FOR DUPLICATE ERROR FROM RPC
      // =====================================================
      if (result != null && result['success'] == false) {
        final errorMessage = result['message'] ?? 'Booking failed';
        print('❌ RPC returned error: $errorMessage');

        // Check if it's a duplicate error
        if (errorMessage.contains('already have a booking') ||
            errorMessage.contains('duplicate') ||
            errorMessage.contains('already a booking')) {
          print('⚠️ DUPLICATE ERROR DETECTED! Showing dialog...');

          // Get existing booking details for better dialog
          final existingCheck = await supabase
              .from('appointments')
              .select(
                'id, child_name, start_time, end_time, status, booking_number',
              )
              .eq('customer_id', user.id)
              .eq('appointment_date', dateStr)
              .eq('child_name', childName)
              .not('status', 'in', '("cancelled","no_show")');

          String existingStartLocal = '';
          String existingEndLocal = '';

          if (existingCheck.isNotEmpty) {
            final existing = existingCheck.first;
            final existingStartUtc = existing['start_time'] as String;
            final existingEndUtc = existing['end_time'] as String;
            existingStartLocal = TimezoneService.utcToLocalTime(
              existingStartUtc,
              _selectedDate!,
            );
            existingEndLocal = TimezoneService.utcToLocalTime(
              existingEndUtc,
              _selectedDate!,
            );
          }

          // Check mounted before showing dialog
          if (!mounted) {
            if (mounted) setState(() => _isBooking = false);
            return;
          }

          // Close any existing dialogs first
          Navigator.of(
            context,
            rootNavigator: true,
          ).popUntil((route) => route.isFirst);

          if (!mounted) {
            if (mounted) setState(() => _isBooking = false);
            return;
          }

          // Duplicate Dialog - Ultra Simple
          // Duplicate Dialog - Simple version
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Duplicate Booking',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Booking for: ${childName.isEmpty ? "Yourself" : childName}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat(
                                'EEEE, MMMM dd, yyyy',
                              ).format(_selectedDate!),
                              style: TextStyle(color: Colors.orange.shade800),
                            ),
                          ],
                        ),
                        if (existingStartLocal.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$existingStartLocal - $existingEndLocal',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '⚠️ You already have a booking on this date.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Each person can only have ONE booking per day.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please select a different date.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    // Just close the dialog, stay on current screen
                    Navigator.of(dialogContext).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    minimumSize: const Size(double.infinity, 45),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (mounted) setState(() => _isBooking = false);
          return;
        }

        // Not a duplicate error, show generic error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: $errorMessage'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (mounted) setState(() => _isBooking = false);
        return;
      }

      // =====================================================
      // SUCCESS OR NEEDS CONFIRMATION
      // =====================================================
      if (result != null && result['success'] == true) {
        print('🎉 BOOKING SUCCESSFUL!');

        if (!mounted) {
          if (mounted) setState(() => _isBooking = false);
          return;
        }

        final localStartTime = _selectedSlot!['start_time'];
        final queueNumber = result['queue_number'];
        final barberName = _selectedBarber!['full_name'];

        // Success Dialog - Complete Working Version
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Booking Confirmed!'),
            content: Text(
              'Queue #$queueNumber\nTime: $localStartTime\nBarber: $barberName',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Reset to date selection
                  setState(() {
                    _currentStep = 1;
                    _selectedDate = null;
                  });
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (mounted) setState(() => _isBooking = false);
      } else if (result != null && result['needs_confirmation'] == true) {
        print('⚠️ Needs confirmation for overflow');
        if (mounted) {
          _showMoveConfirmationDialog(result);
        }
      } else {
        throw Exception(result?['message'] ?? 'Booking failed');
      }
    } catch (e) {
      print('❌ ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  // Helper methods
  Color _getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.purple;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'confirmed':
        return 'Confirmed';
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  void _showMoveConfirmationDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Appointment Needs to be Moved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result['message'] ?? 'Appointment exceeds salon hours.'),
            const SizedBox(height: 12),
            Text(
              'Would you like to move it to ${DateFormat('MMM dd, yyyy').format(DateTime.parse(result['new_date']))}?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Estimated time: ${result['estimated_start']}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetBooking();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _confirmBookingWithMove(result),
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text('Move to Next Day'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBookingWithMove(Map<String, dynamic> moveData) async {
    setState(() => _isBooking = true);

    try {
      final user = supabase.auth.currentUser;
      final childName = _getChildNameForBooking();
      final firstService = _selectedServices.first;
      final travelTime = _selectedSlot?['travel_time_used'] ?? 0;
      final utcStartTime = _selectedSlot!['utc_start_time'];
      final utcEndTime = _selectedSlot!['utc_end_time'];

      final result = await supabase.rpc(
        'create_new_appointment_advanced',
        params: {
          'p_customer_id': user?.id,
          'p_salon_id': _selectedSalon!['id'],
          'p_barber_id': _selectedBarber!['id'],
          'p_service_id': firstService['id'],
          'p_variant_id': firstService['variant_id'],
          'p_appointment_date': moveData['new_date'],
          'p_utc_start_time': utcStartTime,
          'p_utc_end_time': utcEndTime,
          'p_child_name': childName.isEmpty ? null : childName,
          'p_travel_time_minutes': travelTime,
          'p_notes':
              'Moved from ${DateFormat('yyyy-MM-dd').format(_selectedDate!)} due to schedule overflow',
          'p_is_vip': false,
          'p_vip_booking_id': null,
          'p_confirm_overflow': true,
        },
      );

      if (result != null && result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Appointment moved to ${DateFormat('MMM dd').format(DateTime.parse(moveData['new_date']))}',
              ),
              backgroundColor: _secondaryColor,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(result?['message'] ?? 'Move failed');
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
}
