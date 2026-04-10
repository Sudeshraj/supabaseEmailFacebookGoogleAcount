// lib/screens/customer/booking_flow_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _slotsLoaded = false;
  
  // Category tab state
  String? _selectedCategoryTab;
  
  // Colors
  final Color _primaryColor = const Color(0xFFFF6B8B);
  final Color _secondaryColor = const Color(0xFF4CAF50);
  final Color _textDark = const Color(0xFF333333);
  final Color _textLight = const Color(0xFF666666);
  final Color _bgLight = const Color(0xFFF8F9FA);
  
  // Alternating card colors
  final List<Color> _cardColors = [
    const Color(0xFFFCE4EC), // Light Pink
    const Color(0xFFE3F2FD), // Light Blue
    const Color(0xFFE8F5E9), // Light Green
    const Color(0xFFFFF3E0), // Light Orange
    const Color(0xFFF3E5F5), // Light Purple
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
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _selectedSalon = null;
                  _selectedDate = null;
                  _selectedServices = [];
                  _selectedBarber = null;
                  _selectedSlot = null;
                  _searchController.clear();
                  _searchResults = [];
                  _isInitialized = false;
                  _servicesLoaded = false;
                  _barbersLoaded = false;
                  _slotsLoaded = false;
                  _availableBarbers = [];
                  _availableSlots = [];
                  _selectedCategoryTab = null;
                  _salonServices = [];
                });
              },
              child: Text(
                'Reset',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
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
                Expanded(child: Container(height: 2, color: _currentStep > 0 ? _primaryColor : Colors.grey[300])),
                _buildStepIndicator(1, 'Date', Icons.calendar_today),
                Expanded(child: Container(height: 2, color: _currentStep > 1 ? _primaryColor : Colors.grey[300])),
                _buildStepIndicator(2, 'Service', Icons.content_cut),
                Expanded(child: Container(height: 2, color: _currentStep > 2 ? _primaryColor : Colors.grey[300])),
                _buildStepIndicator(3, 'Barber', Icons.person),
                Expanded(child: Container(height: 2, color: _currentStep > 3 ? _primaryColor : Colors.grey[300])),
                _buildStepIndicator(4, 'Time', Icons.access_time),
                Expanded(child: Container(height: 2, color: _currentStep > 4 ? _primaryColor : Colors.grey[300])),
                _buildStepIndicator(5, 'Confirm', Icons.check_circle),
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
                _buildTimeSlotStep(),
                _buildConfirmationStep(),
              ],
            ),
          ),
        ],
      ),
    );
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
            color: isCompleted ? _primaryColor : (isActive ? _primaryColor.withValues(alpha: 0.1) : Colors.grey[200]),
            border: Border.all(
              color: isActive ? _primaryColor : Colors.grey[300]!,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : Icon(icon, size: 20, color: isActive ? _primaryColor : Colors.grey[500]),
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
    final isWeb = MediaQuery.of(context).size.width > 800;
    
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
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
          child: _searchResults.isEmpty && !_isSearching && _searchController.text.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('Search for a salon', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : _searchResults.isEmpty && !_isSearching && _searchController.text.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('No salons found', style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) => _buildSalonCard(_searchResults[index]),
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
                  color: _primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    (salon['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'S',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _primaryColor),
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (salon['address'] != null)
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(child: Text(salon['address'], style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatTime(salon['open_time'])} - ${_formatTime(salon['close_time'])}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
    return timeStr.length >= 5 ? timeStr.substring(0, 5) : timeStr;
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
  }

  // ==================== STEP 2: DATE SELECTION ====================
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
                    Text('Selected Salon', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(_selectedSalon?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CalendarDatePicker(
                      initialDate: today,
                      firstDate: today,
                      lastDate: maxDate,
                      onDateChanged: (date) {
                        setState(() {
                          _selectedDate = date;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedDate == null
                        ? null
                        : () async {
                            setState(() => _currentStep = 2);
                            await _loadSalonServices();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedDate != null ? _primaryColor : Colors.grey[300],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _selectedDate == null 
                          ? 'Select Date' 
                          : 'Continue →',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                    Text('Selected Salon', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(_selectedSalon?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              color: _primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selected:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedServices.map((service) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _primaryColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      service['name'] ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Total: ${_calculateTotalDuration()} min | Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _primaryColor),
                ),
              ],
            ),
          ),
        // Category chips
        Container(
          height: 45,
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildCategoryChip('All', _selectedCategoryTab == null),
              ...categories.map((category) => _buildCategoryChip(category, _selectedCategoryTab == category)),
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
                          Icon(Icons.content_cut, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('No services available', style: TextStyle(color: Colors.grey[600])),
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
                          itemBuilder: (context, index) => _buildServiceCard(servicesToShow[index], index),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: servicesToShow.length,
                          itemBuilder: (context, index) => _buildServiceCard(servicesToShow[index], index),
                        ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedServices.isEmpty ? null : () {
                setState(() {
                  _currentStep = 3;
                  _barbersLoaded = false;
                  _availableBarbers = [];
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedServices.isNotEmpty ? _primaryColor : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _selectedServices.isEmpty ? 'Select a service' : 'Continue →',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
        onSelected: (_) => setState(() => _selectedCategoryTab = isSelected ? null : label),
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
    final hasVariants = service['variants'] != null && (service['variants'] as List).isNotEmpty;
    final variants = service['variants'] as List? ?? [];
    final selectedVariantCount = _selectedServices.where((s) => s['id'] == serviceId).length;
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSelected ? _primaryColor : Colors.transparent, width: 2),
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
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (selectedVariantCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$selectedVariantCount',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                  children: variants.map((variant) => _buildVariantCard(service, variant)).toList(),
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
                      foregroundColor: isSelected ? _secondaryColor : _primaryColor,
                      side: BorderSide(color: isSelected ? _secondaryColor : _primaryColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildVariantCard(Map<String, dynamic> service, Map<String, dynamic> variant) {
    final serviceId = service['id'] as int;
    final isSelected = _selectedServices.any((s) => 
        s['id'] == serviceId && s['variant_id'] == variant['id']);

    return GestureDetector(
      onTap: () => _toggleVariant(service, variant),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? _primaryColor : Colors.grey[200]!),
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
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
                border: Border.all(color: isSelected ? _primaryColor : Colors.grey[400]!),
              ),
              child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
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
            'category_name': categoryMap[service['salon_category_id']] ?? 'Other',
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

  void _toggleVariant(Map<String, dynamic> service, Map<String, dynamic> variant) {
    final serviceId = service['id'] as int;
    final variantId = variant['id'] as int;
    
    if (_selectedServices.any((s) => s['id'] == serviceId && s['variant_id'] == variantId)) {
      setState(() {
        _selectedServices.removeWhere((s) => s['id'] == serviceId && s['variant_id'] == variantId);
      });
    } else {
      _addServiceVariant(service, variant);
    }
  }

  void _addServiceVariant(Map<String, dynamic> service, Map<String, dynamic> variant) {
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

  void _removeService(Map<String, dynamic> service) {
    setState(() {
      _selectedServices.removeWhere((s) => s['id'] == service['id']);
    });
  }

  int _calculateTotalDuration() {
    return _selectedServices.fold(0, (sum, s) => sum + (s['duration'] as int));
  }

  double _calculateTotalPrice() {
    return _selectedServices.fold(0.0, (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0));
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
  Widget _buildBarberSelectionStep() {
    if (!_barbersLoaded && !_isLoadingBarbers && _selectedSalon != null) {
      _barbersLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAvailableBarbers());
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
                    Text('Services: ${_selectedServices.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${_calculateTotalDuration()} min total', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                          Text('No barbers available', style: TextStyle(color: Colors.grey[600])),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _barbersLoaded = false;
                              _loadAvailableBarbers();
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _availableBarbers.length,
                      itemBuilder: (context, index) => _buildBarberCard(_availableBarbers[index]),
                    ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedBarber == null ? null : () {
                setState(() {
                  _currentStep = 4;
                  _slotsLoaded = false;
                  _availableSlots = [];
                });
                _loadAvailableSlots();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedBarber != null ? _primaryColor : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _selectedBarber == null ? 'Select a barber' : 'Continue →',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final isSelected = _selectedBarber?['id'] == barber['id'];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSelected ? _primaryColor : Colors.transparent, width: 2),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedBarber = barber),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _primaryColor.withValues(alpha: 0.1),
                backgroundImage: barber['avatar_url'] != null ? NetworkImage(barber['avatar_url']) : null,
                child: barber['avatar_url'] == null
                    ? Text(barber['full_name']?.substring(0, 1).toUpperCase() ?? 'B', 
                        style: TextStyle(fontSize: 22, color: _primaryColor, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(barber['full_name'] ?? 'Barber', 
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star, size: 14, color: Colors.amber[700]),
                        const SizedBox(width: 4),
                        Text((barber['avg_rating'] as num?)?.toStringAsFixed(1) ?? '4.5',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 12),
                        Icon(Icons.work, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('${barber['today_appointments'] ?? 0} today',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: _primaryColor, size: 24),
            ],
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
      
      final List<String> barberIds = salonBarbers.map<String>((b) => b['barber_id'].toString()).toList();
      
      final profiles = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', barberIds);
      
      final List<Map<String, dynamic>> barberList = [];
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      for (var profile in profiles) {
        final barberId = profile['id'];
        
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
        });
      }
      
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

  // ==================== STEP 5: TIME SLOT SELECTION ====================
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
                backgroundColor: _primaryColor.withValues(alpha: 0.1),
                child: Text(_selectedBarber?['full_name']?.substring(0, 1).toUpperCase() ?? 'B',
                    style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedBarber?['full_name'] ?? 'Barber',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${_calculateTotalDuration()} min service',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
          child: _isLoadingSlots
              ? const Center(child: CircularProgressIndicator())
              : _availableSlots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.access_time, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('No slots available', style: TextStyle(color: Colors.grey[600])),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              _slotsLoaded = false;
                              _loadAvailableSlots();
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _availableSlots.length,
                      itemBuilder: (context, index) => _buildTimeSlotCard(_availableSlots[index]),
                    ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedSlot == null ? null : () => setState(() => _currentStep = 5),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedSlot != null ? _primaryColor : Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _selectedSlot == null ? 'Select a time' : 'Continue →',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlotCard(Map<String, dynamic> slot) {
    final isSelected = _selectedSlot?['start_time'] == slot['start_time'];
    final isAvailable = slot['is_available'] == true;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? _primaryColor.withValues(alpha: 0.05) : Colors.white,
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isSelected ? _primaryColor.withValues(alpha: 0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatTime(slot['start_time']),
                style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? _primaryColor : _textDark),
              ),
              Text(
                _formatTime(slot['end_time']),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        title: Text(
          slot['queue_number'] != null ? 'Queue #${slot['queue_number']}' : 'Slot',
          style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? _primaryColor : _textDark),
        ),
        subtitle: Text('${slot['duration']} minutes'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isAvailable ? _secondaryColor.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isAvailable ? 'Available' : 'Booked',
            style: TextStyle(color: isAvailable ? _secondaryColor : Colors.red, fontSize: 12),
          ),
        ),
        onTap: isAvailable ? () => setState(() => _selectedSlot = slot) : null,
      ),
    );
  }

  Future<void> _loadAvailableSlots() async {
    if (_isLoadingSlots) return;
    
    setState(() => _isLoadingSlots = true);
    
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final targetDate = _selectedDate ?? today;
      
      final dayOfWeek = targetDate.weekday;
      
      final schedule = await supabase
          .from('barber_schedules')
          .select()
          .eq('barber_id', _selectedBarber!['id'])
          .eq('salon_id', _selectedSalon!['id'])
          .eq('day_of_week', dayOfWeek)
          .eq('is_working', true)
          .maybeSingle();
      
      if (schedule == null) {
        setState(() {
          _availableSlots = [];
          _isLoadingSlots = false;
        });
        return;
      }
      
      // Reset queue for this date
      await supabase.rpc('reset_daily_queue', params: {
        'p_barber_id': _selectedBarber!['id'],
        'p_queue_date': DateFormat('yyyy-MM-dd').format(targetDate),
      });
      
      final existingAppointments = await supabase
          .from('appointments')
          .select('start_time, end_time')
          .eq('barber_id', _selectedBarber!['id'])
          .eq('appointment_date', DateFormat('yyyy-MM-dd').format(targetDate))
          .inFilter('status', ['confirmed', 'pending', 'in_progress']);
      
      final startTimeStr = schedule['start_time'].toString();
      final endTimeStr = schedule['end_time'].toString();
      
      final startHour = int.parse(startTimeStr.substring(0, 2));
      final startMinute = int.parse(startTimeStr.substring(3, 5));
      final endHour = int.parse(endTimeStr.substring(0, 2));
      final endMinute = int.parse(endTimeStr.substring(3, 5));
      
      final serviceDuration = _calculateTotalDuration();
      
      List<Map<String, dynamic>> slots = [];
      int queueNumber = 1;
      
      DateTime currentSlot = DateTime(
        targetDate.year, targetDate.month, targetDate.day,
        startHour, startMinute,
      );
      
      final endDateTime = DateTime(
        targetDate.year, targetDate.month, targetDate.day,
        endHour, endMinute,
      );
      
      final bookedSlots = existingAppointments.map((a) => a['start_time'].toString()).toSet();
      
      while (currentSlot.add(Duration(minutes: serviceDuration)).isBefore(endDateTime) || 
             currentSlot.add(Duration(minutes: serviceDuration)).isAtSameMomentAs(endDateTime)) {
        
        final slotStartStr = DateFormat('HH:mm:ss').format(currentSlot);
        
        bool isFutureSlot = true;
        if (targetDate.isAtSameMomentAs(today)) {
          isFutureSlot = currentSlot.isAfter(now);
        }
        
        bool isBooked = bookedSlots.contains(slotStartStr);
        
        slots.add({
          'start_time': slotStartStr,
          'end_time': DateFormat('HH:mm:ss').format(currentSlot.add(Duration(minutes: serviceDuration))),
          'queue_number': isBooked ? null : queueNumber,
          'is_available': !isBooked && isFutureSlot,
          'duration': serviceDuration,
        });
        
        if (!isBooked && isFutureSlot) queueNumber++;
        currentSlot = currentSlot.add(Duration(minutes: serviceDuration));
      }
      
      setState(() {
        _availableSlots = slots;
        _isLoadingSlots = false;
      });
    } catch (e) {
      debugPrint('Error loading slots: $e');
      setState(() => _isLoadingSlots = false);
    }
  }

  // ==================== STEP 6: CONFIRMATION ====================
  Widget _buildConfirmationStep() {
    if (_selectedSalon == null || _selectedServices.isEmpty || _selectedBarber == null || _selectedSlot == null || _selectedDate == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Missing information', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _currentStep = 0),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text('Start Over'),
            ),
          ],
        ),
      );
    }

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
                  value: DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate!),
                  subtitle: '${_formatTime(_selectedSlot!['start_time'])} - ${_formatTime(_selectedSlot!['end_time'])} • Queue #${_selectedSlot!['queue_number']}',
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  icon: Icons.content_cut,
                  title: 'Services (${_selectedServices.length})',
                  value: '${_calculateTotalDuration()} min • Rs. ${_calculateTotalPrice().toStringAsFixed(2)}',
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedServices.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${s['name']} ${s['gender'] != null ? '(${s['gender']} ${s['age']})' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildConfirmationTile(
                  icon: Icons.person,
                  title: 'Barber',
                  value: _selectedBarber!['full_name'] ?? '',
                  subtitle: '⭐ ${(_selectedBarber!['avg_rating'] as num?)?.toStringAsFixed(1) ?? '4.5'} rating',
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isBooking
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm Booking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              color: _primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  if (subtitle is String)
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]))
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

  Future<void> _confirmBooking() async {
    setState(() => _isBooking = true);
    
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please login');
      
      final nextQueue = await supabase
          .rpc('get_next_queue_number', params: {
            'p_barber_id': _selectedBarber!['id'],
            'p_queue_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
          });
      
      final appointmentData = {
        'customer_id': user.id,
        'barber_id': _selectedBarber!['id'],
        'salon_id': _selectedSalon!['id'],
        'service_id': _selectedServices.first['id'],
        'variant_id': _selectedServices.first['variant_id'],
        'appointment_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'start_time': _selectedSlot!['start_time'],
        'end_time': _selectedSlot!['end_time'],
        'queue_number': nextQueue,
        'queue_token': 'Q${nextQueue.toString().padLeft(3, '0')}',
        'status': 'confirmed',
        'price': _calculateTotalPrice(),
        'notes': _selectedServices.map((s) => s['name']).join(', '),
      };
      
      await supabase.from('appointments').insert(appointmentData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Booking confirmed! Queue #$nextQueue'), backgroundColor: _secondaryColor),
        );
        Navigator.pop(context);
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