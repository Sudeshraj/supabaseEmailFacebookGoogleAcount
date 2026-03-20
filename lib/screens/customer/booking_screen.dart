// screens/customer/booking_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  
  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  // Step tracking
  int _currentStep = 0;
  
  // Search
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  
  // Selected salon
  Map<String, dynamic>? _selectedSalon;
  
  // Categories and services
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _services = [];
  Map<int, List<Map<String, dynamic>>> _serviceVariants = {};
  
  // Selected services and variants (multiple)
  List<Map<String, dynamic>> _selectedItems = [];
  
  // Available barbers for selected variants
  List<Map<String, dynamic>> _availableBarbers = [];
  Map<String, dynamic>? _selectedBarber;
  
  // Date and time selection
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  List<DateTime> _availableDates = [];
  List<TimeOfDay> _availableTimeSlots = [];
  bool _isLoadingAvailability = false;
  
  // Booking confirmation
  int? _queueNumber;
  String? _confirmNumber;
  Map<String, dynamic>? _confirmedBooking;
  String? _errorMessage;
  
  // Loading states
  bool _isLoading = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    
    _loadCategories();
    _searchController.addListener(_onSearchChanged);
    _generateAvailableDates();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ==================== SEARCH SALONS ====================
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    if (query.length >= 2) {
      if (!_isSearching) {
        setState(() => _isSearching = true);
      }

      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _searchSalons(query);
      });
    }
  }

  Future<void> _searchSalons(String query) async {
    try {
      final response = await supabase
          .from('salons')
          .select('id, name, address, phone, email, open_time, close_time, logo_url, cover_url, description')
          .ilike('name', '%$query%')
          .eq('is_active', true)
          .order('name')
          .limit(10);

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(response);
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error searching salons: $e');
      setState(() => _isSearching = false);
    }
  }

  // ==================== LOAD CATEGORIES ====================
  Future<void> _loadCategories() async {
    try {
      final response = await supabase
          .from('categories')
          .select('id, name, icon_name, display_order, description')
          .eq('is_active', true)
          .order('display_order');

      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
    }
  }

  // ==================== LOAD SERVICES BY CATEGORY ====================
  Future<void> _loadServicesByCategory(int categoryId) async {
    setState(() => _isLoading = true);

    try {
      // Load services
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, category_id, image_url')
          .eq('category_id', categoryId)
          .eq('is_active', true)
          .order('name');

      final serviceIds = servicesResponse.map((s) => s['id'] as int).toList();
      
      if (serviceIds.isEmpty) {
        setState(() {
          _services = [];
          _serviceVariants = {};
          _isLoading = false;
        });
        return;
      }

      // Load variants for these services
      final variantsResponse = await supabase
          .from('service_variants')
          .select('''
            id,
            service_id,
            price,
            duration,
            genders (display_name, name),
            age_categories (display_name, name, min_age, max_age)
          ''')
          .inFilter('service_id', serviceIds)
          .eq('is_active', true);

      // Group variants by service
      final Map<int, List<Map<String, dynamic>>> variantsMap = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsMap.containsKey(serviceId)) {
          variantsMap[serviceId] = [];
        }
        
        final gender = variant['genders'] as Map<String, dynamic>;
        final age = variant['age_categories'] as Map<String, dynamic>;

        variantsMap[serviceId]!.add({
          'id': variant['id'],
          'price': (variant['price'] as num).toDouble(),
          'duration': variant['duration'],
          'gender': gender['display_name'],
          'genderName': gender['name'],
          'age': age['display_name'],
          'ageName': age['name'],
          'display': '${gender['display_name']} • ${age['display_name']}',
        });
      }

      setState(() {
        _services = List<Map<String, dynamic>>.from(servicesResponse);
        _serviceVariants = variantsMap;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      setState(() => _isLoading = false);
    }
  }

  // ==================== CHECK BARBER AVAILABILITY FOR VARIANTS ====================
  Future<void> _checkBarberAvailabilityForVariants() async {
    if (_selectedSalon == null || _selectedItems.isEmpty) return;

    setState(() {
      _isLoadingAvailability = true;
      _errorMessage = null;
    });

    try {
      // Get all barbers in this salon
      final salonBarbers = await supabase
          .from('salon_barbers')
          .select('''
            barber_id,
            profiles!inner (
              full_name,
              avatar_url,
              bio
            )
          ''')
          .eq('salon_id', _selectedSalon!['id'])
          .eq('is_active', true);

      if (salonBarbers.isEmpty) {
        setState(() {
          _errorMessage = 'No barbers available in this salon';
          _isLoadingAvailability = false;
        });
        return;
      }

      // For each barber, check if they can perform ALL selected variants
      List<Map<String, dynamic>> qualifiedBarbers = [];

      for (var sb in salonBarbers) {
        final barberId = sb['barber_id'] as String;
        final profile = sb['profiles'] as Map<String, dynamic>;
        
        bool canPerformAll = true;
        List<String> missingServices = [];

        // Check each selected variant
        for (var item in _selectedItems) {
          final serviceId = item['serviceId'];
          final variantId = item['variantId'];
          
          // Check if barber offers this service/variant
          final barberService = await supabase
              .from('barber_services')
              .select()
              .eq('barber_id', barberId)
              .eq('service_id', serviceId)
              .eq('variant_id', variantId)
              .eq('is_active', true)
              .maybeSingle();

          if (barberService == null) {
            canPerformAll = false;
            missingServices.add(item['serviceName']);
          }
        }

        if (canPerformAll) {
          // Get specialties and rating
          final specialties = await _getBarberSpecialties(barberId);
          
          qualifiedBarbers.add({
            'id': barberId,
            'name': profile['full_name'] ?? 'Unknown Barber',
            'avatar': profile['avatar_url'],
            'bio': profile['bio'] ?? 'Professional barber',
            'specialties': specialties,
            'rating': _getRandomRating(),
            'experience': _getRandomExperience(),
            'missingServices': missingServices,
          });
        }
      }

      setState(() {
        _availableBarbers = qualifiedBarbers;
        if (qualifiedBarbers.isEmpty) {
          _errorMessage = 'No barber can perform all selected services. Try different variants.';
        }
        _isLoadingAvailability = false;
      });

    } catch (e) {
      debugPrint('❌ Error checking barber availability: $e');
      setState(() {
        _errorMessage = 'Error checking availability';
        _isLoadingAvailability = false;
      });
    }
  }

  // ==================== LOAD AVAILABLE DATES FOR SELECTED BARBER ====================
  Future<void> _loadAvailableDatesForBarber() async {
    if (_selectedBarber == null || _selectedSalon == null) return;

    setState(() => _isLoadingAvailability = true);

    try {
      final today = DateTime.now();
      List<DateTime> availableDates = [];

      // Check next 14 days
      for (int i = 0; i < 14; i++) {
        final date = today.add(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final dayOfWeek = date.weekday;

        // Check if barber has schedule for this day
        final schedule = await supabase
            .from('barber_schedules')
            .select()
            .eq('barber_id', _selectedBarber!['id'])
            .eq('salon_id', _selectedSalon!['id'])
            .eq('day_of_week', dayOfWeek)
            .eq('is_working', true)
            .maybeSingle();

        if (schedule == null) continue;

        // Check if barber has leave on this day
        final leave = await supabase
            .from('barber_leaves')
            .select()
            .eq('barber_id', _selectedBarber!['id'])
            .eq('leave_date', dateStr)
            .eq('status', 'approved')
            .maybeSingle();

        if (leave != null) continue;

        availableDates.add(date);
      }

      setState(() {
        _availableDates = availableDates;
        _isLoadingAvailability = false;
      });

    } catch (e) {
      debugPrint('❌ Error loading available dates: $e');
      setState(() => _isLoadingAvailability = false);
    }
  }

  // ==================== LOAD AVAILABLE TIME SLOTS ====================
  Future<void> _loadAvailableTimeSlots() async {
 if (_selectedBarber == null || 
      _selectedSalon == null || 
      _selectedDate == null ||
      _selectedItems.isEmpty) return;

  setState(() => _isLoadingAvailability = true);

  try {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final dayOfWeek = _selectedDate!.weekday;

    // Calculate total duration from all selected variants - FIXED
    int totalDuration = 0;
    for (var item in _selectedItems) {
      totalDuration += (item['duration'] as num).toInt();  // Convert to int
    }

    // Get salon working hours
    final openTime = _selectedSalon!['open_time'] ?? '09:00:00';
    final closeTime = _selectedSalon!['close_time'] ?? '18:00:00';

    // Parse times
    final openParts = openTime.split(':');
    final closeParts = closeTime.split(':');
    
    final openHour = int.parse(openParts[0]);
    final openMinute = int.parse(openParts[1]);
    final closeHour = int.parse(closeParts[0]);
    final closeMinute = int.parse(closeParts[1]);

      // Check barber's schedule
      final schedule = await supabase
          .from('barber_schedules')
          .select()
          .eq('barber_id', _selectedBarber!['id'])
          .eq('salon_id', _selectedSalon!['id'])
          .eq('day_of_week', dayOfWeek)
          .eq('is_working', true)
          .single();

      final scheduleStart = schedule['start_time'] as String;
      final scheduleEnd = schedule['end_time'] as String;

      final scheduleStartParts = scheduleStart.split(':');
      final scheduleEndParts = scheduleEnd.split(':');
      
      final scheduleStartHour = int.parse(scheduleStartParts[0]);
      final scheduleStartMinute = int.parse(scheduleStartParts[1]);
      final scheduleEndHour = int.parse(scheduleEndParts[0]);
      final scheduleEndMinute = int.parse(scheduleEndParts[1]);

      // Use the more restrictive times (later start, earlier end)
      final actualStartHour = scheduleStartHour > openHour ? scheduleStartHour : openHour;
      final actualStartMinute = scheduleStartHour > openHour ? scheduleStartMinute : openMinute;
      final actualEndHour = scheduleEndHour < closeHour ? scheduleEndHour : closeHour;
      final actualEndMinute = scheduleEndHour < closeHour ? scheduleEndMinute : closeMinute;

      // Check lunch break
      final lunchBreak = await supabase
          .from('barber_lunch_breaks')
          .select()
          .eq('barber_id', _selectedBarber!['id'])
          .eq('salon_id', _selectedSalon!['id'])
          .or('break_date.is.null,break_date.eq.$dateStr')
          .maybeSingle();

      int lunchStartMinutes = -1;
      int lunchEndMinutes = -1;
      
      if (lunchBreak != null) {
        final lunchStart = lunchBreak['start_time'] as String;
        final lunchEnd = lunchBreak['end_time'] as String;
        
        final lunchStartParts = lunchStart.split(':');
        final lunchEndParts = lunchEnd.split(':');
        
        lunchStartMinutes = int.parse(lunchStartParts[0]) * 60 + int.parse(lunchStartParts[1]);
        lunchEndMinutes = int.parse(lunchEndParts[0]) * 60 + int.parse(lunchEndParts[1]);
      }

      // Check VIP bookings for this date
      final vipBookings = await supabase
          .from('vip_bookings')
          .select('preferred_start_time, scheduled_start_time, scheduled_end_time')
          .eq('barber_id', _selectedBarber!['id'])
          .eq('event_date', dateStr)
          .eq('status', 'approved');

      // Generate time slots
      List<TimeOfDay> slots = [];
      int currentMinutes = actualStartHour * 60 + actualStartMinute;
      int endMinutes = actualEndHour * 60 + actualEndMinute;

      while (currentMinutes + totalDuration <= endMinutes) {
        final slotStart = currentMinutes;
        final slotEnd = currentMinutes + totalDuration;

        // Check if slot overlaps with lunch break
        if (lunchStartMinutes != -1 && 
            !(slotEnd <= lunchStartMinutes || slotStart >= lunchEndMinutes)) {
          currentMinutes += 30;
          continue;
        }

        // Check if slot overlaps with VIP bookings
        bool vipConflict = false;
        for (var vip in vipBookings) {
          final vipStart = vip['scheduled_start_time'] ?? vip['preferred_start_time'];
          final vipEnd = vip['scheduled_end_time'];
          
          if (vipStart != null && vipEnd != null) {
            final vipStartParts = vipStart.split(':');
            final vipEndParts = vipEnd.split(':');
            
            final vipStartMinutes = int.parse(vipStartParts[0]) * 60 + int.parse(vipStartParts[1]);
            final vipEndMinutes = int.parse(vipEndParts[0]) * 60 + int.parse(vipEndParts[1]);
            
            if (!(slotEnd <= vipStartMinutes || slotStart >= vipEndMinutes)) {
              vipConflict = true;
              break;
            }
          }
        }

        if (vipConflict) {
          currentMinutes += 30;
          continue;
        }

        // Check existing appointments
        final timeStr = '${(slotStart ~/ 60).toString().padLeft(2, '0')}:${(slotStart % 60).toString().padLeft(2, '0')}:00';
        final endTimeStr = '${(slotEnd ~/ 60).toString().padLeft(2, '0')}:${(slotEnd % 60).toString().padLeft(2, '0')}:00';

        final conflict = await supabase
            .from('appointments')
            .select()
            .eq('barber_id', _selectedBarber!['id'])
            .eq('appointment_date', dateStr)
            .inFilter('status', ['confirmed', 'in_progress'])
            .or('start_time.lte.$endTimeStr,end_time.gte.$timeStr')
            .maybeSingle();

        if (conflict == null) {
          final hour = slotStart ~/ 60;
          final minute = slotStart % 60;
          slots.add(TimeOfDay(hour: hour, minute: minute));
        }

        currentMinutes += 30;
      }

      setState(() {
        _availableTimeSlots = slots;
        _isLoadingAvailability = false;
      });

    } catch (e) {
      debugPrint('❌ Error loading time slots: $e');
      setState(() => _isLoadingAvailability = false);
    }
  }

  // ==================== CONFIRM BOOKING ====================
  Future<void> _confirmBooking() async {
     if (_selectedSalon == null ||
      _selectedBarber == null ||
      _selectedItems.isEmpty ||
      _selectedDate == null ||
      _selectedTime == null) {
    return;
  }

  setState(() => _isLoading = true);

  try {
    final user = supabase.auth.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final timeStr = _formatTimeOfDay(_selectedTime!);
    
    // Calculate total duration - FIXED
    int totalDuration = 0;
    for (var item in _selectedItems) {
      totalDuration += (item['duration'] as num).toInt();  // Convert to int
    }
    
    final endTime = _calculateEndTime(timeStr, totalDuration);

    // Get next queue number
    final queueResponse = await supabase
        .rpc('get_next_queue_number', params: {
          'p_barber_id': _selectedBarber!['id'],
          'p_queue_date': dateStr,
        });

    final queueNumber = queueResponse as int;

    // Generate confirm token
    final confirmNumber = await _generateConfirmToken();

    // Create appointments for each selected service
    List<Map<String, dynamic>> createdAppointments = [];
    
    // Calculate individual service times
    int currentStartMinutes = _timeToMinutes(timeStr);
    
    for (int i = 0; i < _selectedItems.length; i++) {
      final item = _selectedItems[i];
      final itemDuration = (item['duration'] as num).toInt();  // FIXED - convert to int
      final itemStartMinutes = currentStartMinutes;
      final itemEndMinutes = currentStartMinutes + itemDuration;
      
      final itemStartTime = '${(itemStartMinutes ~/ 60).toString().padLeft(2, '0')}:${(itemStartMinutes % 60).toString().padLeft(2, '0')}:00';
      final itemEndTime = '${(itemEndMinutes ~/ 60).toString().padLeft(2, '0')}:${(itemEndMinutes % 60).toString().padLeft(2, '0')}:00';

      // Create appointment
      final response = await supabase
          .from('appointments')
          .insert({
            'customer_id': user.id,
            'barber_id': _selectedBarber!['id'],
            'salon_id': _selectedSalon!['id'],
            'service_id': item['serviceId'],
            'variant_id': item['variantId'],
            'appointment_date': dateStr,
            'start_time': itemStartTime,
            'end_time': itemEndTime,
            'queue_number': queueNumber,
            'queue_token': confirmNumber,
            'price': (item['price'] as num).toDouble(),  // Also fix price if needed
            'status': 'confirmed',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      createdAppointments.add(response);
      currentStartMinutes = itemEndMinutes;
    }

      // Send notification
      await _sendBookingNotification(
        user.id,
        queueNumber,
        confirmNumber,
        dateStr,
        timeStr,
      );

      setState(() {
        _queueNumber = queueNumber;
        _confirmNumber = confirmNumber;
        _confirmedBooking = {
          'appointments': createdAppointments,
          'salon_name': _selectedSalon!['name'],
          'barber_name': _selectedBarber!['name'],
          'selected_items': _selectedItems,
          'date': dateStr,
          'time': timeStr,
        };
        _isLoading = false;
        _currentStep = 4; // Move to confirmation step
      });

      _fadeController.reset();
      _fadeController.forward();

    } catch (e) {
      debugPrint('❌ Error confirming booking: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  String _calculateEndTime(String startTime, int durationMinutes) {
    try {
      final parts = startTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      
      final totalMinutes = hour * 60 + minute + durationMinutes;
      final newHour = (totalMinutes ~/ 60) % 24;
      final newMinute = totalMinutes % 60;
      
      return '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      return startTime;
    }
  }

  Future<String> _generateConfirmToken() async {
    try {
      final response = await supabase.rpc('generate_queue_token');
      return response as String;
    } catch (e) {
      debugPrint('❌ Error generating token: $e');
      return 'C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
  }

  Future<void> _sendBookingNotification(
    String userId,
    int queueNumber,
    String token,
    String date,
    String time,
  ) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': '🎉 Booking Confirmed!',
        'body': 'Your booking #$queueNumber at ${_selectedSalon!['name']} is confirmed for $date at $time. Token: $token',
        'type': 'booking_confirmed',
        'data': {
          'queue_number': queueNumber,
          'token': token,
          'date': date,
          'time': time,
          'salon_name': _selectedSalon!['name'],
        },
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
    }
  }

  // ==================== HELPER FUNCTIONS ====================
  void _generateAvailableDates() {
    List<DateTime> dates = [];
    DateTime today = DateTime.now();
    
    for (int i = 0; i < 14; i++) {
      dates.add(today.add(Duration(days: i)));
    }
    
    setState(() {
      _availableDates = dates;
    });
  }

  Future<List<String>> _getBarberSpecialties(String barberId) async {
    try {
      final response = await supabase
          .from('barber_services')
          .select('''
            services (
              name
            )
          ''')
          .eq('barber_id', barberId)
          .eq('is_specialized', true)
          .limit(3);

      return response.map<String>((item) {
        final service = item['services'] as Map<String, dynamic>;
        return service['name'] as String;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  double _getRandomRating() {
    return (4.0 + (DateTime.now().millisecondsSinceEpoch % 10) / 10).clamp(4.0, 5.0);
  }

  String _getRandomExperience() {
    final experiences = ['2+ years', '3+ years', '5+ years', '7+ years', '10+ years'];
    return experiences[DateTime.now().millisecond % experiences.length];
  }

  IconData _getCategoryIcon(String? categoryName) {
    switch (categoryName?.toLowerCase()) {
      case 'hair':
        return Icons.content_cut;
      case 'skin':
        return Icons.face;
      case 'grooming':
        return Icons.face_retouching_natural;
      case 'wellness':
        return Icons.spa;
      case 'nails':
        return Icons.handshake;
      default:
        return Icons.build_circle_outlined;
    }
  }

  // ==================== UI BUILDERS ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Book Appointment',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedSalon != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _showSalonInfo,
            ),
        ],
      ),
      body: Container(
        color: Colors.grey[50],
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildStepContent(),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildProgressIndicator() {
    final steps = ['Salon', 'Services', 'Barber', 'Time', 'Confirm'];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      color: Colors.white,
      child: Row(
        children: List.generate(steps.length, (index) {
          return Expanded(
            child: _buildProgressStep(
              index + 1,
              steps[index],
              _currentStep > index,
              _currentStep == index,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildProgressStep(int step, String label, bool isCompleted, bool isCurrent) {
    Color backgroundColor;
    Color textColor;
    Color labelColor;

    if (isCompleted) {
      backgroundColor = const Color(0xFFFF6B8B);
      textColor = Colors.white;
      labelColor = const Color(0xFFFF6B8B);
    } else if (isCurrent) {
      backgroundColor = const Color(0xFFFF6B8B).withValues(alpha: 0.2);
      textColor = const Color(0xFFFF6B8B);
      labelColor = const Color(0xFFFF6B8B);
    } else {
      backgroundColor = Colors.grey.shade200;
      textColor = Colors.grey.shade600;
      labelColor = Colors.grey.shade600;
    }

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
            border: isCurrent
                ? Border.all(color: const Color(0xFFFF6B8B), width: 2)
                : null,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    step.toString(),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    if (_currentStep == 4) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _handleBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B8B),
                  side: const BorderSide(color: Color(0xFFFF6B8B)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Back'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _canProceed() ? _handleNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(_getNextButtonText()),
            ),
          ),
        ],
      ),
    );
  }

  String _getNextButtonText() {
    if (_currentStep == 0) return 'Select Salon';
    if (_currentStep == 1) return 'Find Barbers';
    if (_currentStep == 2) return 'Select Date';
    if (_currentStep == 3) return 'Confirm Booking';
    return 'Next';
  }

  bool _canProceed() {
    if (_currentStep == 0) return _selectedSalon != null;
    if (_currentStep == 1) return _selectedItems.isNotEmpty;
    if (_currentStep == 2) return _selectedBarber != null;
    if (_currentStep == 3) return _selectedDate != null && _selectedTime != null;
    return true;
  }

  void _handleNext() {
    if (_currentStep == 0 && _selectedSalon != null) {
      setState(() {
        _currentStep = 1;
        _fadeController.reset();
        _fadeController.forward();
      });
    } else if (_currentStep == 1 && _selectedItems.isNotEmpty) {
      _checkBarberAvailabilityForVariants();
      setState(() {
        _currentStep = 2;
        _fadeController.reset();
        _fadeController.forward();
      });
    } else if (_currentStep == 2 && _selectedBarber != null) {
      _loadAvailableDatesForBarber();
      setState(() {
        _currentStep = 3;
        _fadeController.reset();
        _fadeController.forward();
      });
    } else if (_currentStep == 3 && _selectedDate != null && _selectedTime != null) {
      _confirmBooking();
    }
  }

  void _handleBack() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _fadeController.reset();
        _fadeController.forward();
      });
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildSalonSearchStep();
      case 1:
        return _buildServiceSelectionStep();
      case 2:
        return _buildBarberSelectionStep();
      case 3:
        return _buildDateTimeStep();
      case 4:
        return _buildConfirmationStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ==================== STEP 1: SALON SEARCH ====================
  Widget _buildSalonSearchStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Find a Salon',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Search for your preferred salon',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        
        // Search field
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Enter salon name...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFFFF6B8B)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                          _selectedSalon = null;
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Search results
        Expanded(
          child: _isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                )
              : _searchResults.isEmpty && _searchController.text.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No salons found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'Search for a salon',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enter at least 2 characters',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final salon = _searchResults[index];
                            final isSelected = _selectedSalon != null && 
                                _selectedSalon!['id'] == salon['id'];
                            
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedSalon = salon;
                                  _selectedItems.clear();
                                  _selectedBarber = null;
                                  _selectedDate = null;
                                  _selectedTime = null;
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected 
                                        ? const Color(0xFFFF6B8B) 
                                        : Colors.grey[200]!,
                                    width: isSelected ? 2 : 1,
                                  ),
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
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        image: salon['logo_url'] != null
                                            ? DecorationImage(
                                                image: NetworkImage(salon['logo_url']),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: salon['logo_url'] == null
                                          ? const Icon(
                                              Icons.store,
                                              color: Color(0xFFFF6B8B),
                                              size: 30,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            salon['name'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (salon['address'] != null)
                                            Text(
                                              salon['address'],
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.access_time,
                                                size: 12,
                                                color: Colors.grey[500],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${salon['open_time']?.substring(0, 5) ?? '09:00'} - ${salon['close_time']?.substring(0, 5) ?? '18:00'}',
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
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFFFF6B8B)
                                              : Colors.grey[400]!,
                                          width: 2,
                                        ),
                                        color: isSelected
                                            ? const Color(0xFFFF6B8B)
                                            : Colors.transparent,
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 16,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  // ==================== STEP 2: SERVICE SELECTION (MULTIPLE) ====================
  Widget _buildServiceSelectionStep() {
    if (_selectedSalon == null) {
      return const Center(
        child: Text('Please select a salon first'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected salon info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                backgroundImage: _selectedSalon!['logo_url'] != null
                    ? NetworkImage(_selectedSalon!['logo_url'])
                    : null,
                child: _selectedSalon!['logo_url'] == null
                    ? const Icon(Icons.store, color: Color(0xFFFF6B8B))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedSalon!['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (_selectedSalon!['address'] != null)
                      Text(
                        _selectedSalon!['address'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Selected items summary
        if (_selectedItems.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shopping_cart, color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Selected Services (${_selectedItems.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._selectedItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item['serviceName']} - ${item['variantDisplay']}',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                        ),
                      ),
                      Text(
                        'Rs. ${item['price']}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Category chips
        const Text(
          'Select Category',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _loadServicesByCategory(category['id']);
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.grey[300]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade100,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getCategoryIcon(category['name']),
                        size: 18,
                        color: const Color(0xFFFF6B8B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        category['name'],
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Services
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                )
              : _services.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No services available',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _services.length,
                      itemBuilder: (context, index) {
                        final service = _services[index];
                        final variants = _serviceVariants[service['id']] ?? [];
                        
                        if (variants.isEmpty) return const SizedBox.shrink();
                        
                        return _buildServiceCard(service, variants);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, List<Map<String, dynamic>> variants) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getCategoryIcon(service['name']),
              color: const Color(0xFFFF6B8B),
              size: 28,
            ),
          ),
          title: Text(
            service['name'],
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Text(
            '${variants.length} options available',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          children: variants.map((variant) {
            final isSelected = _selectedItems.any((item) => 
                item['serviceId'] == service['id'] && 
                item['variantId'] == variant['id']);
            
            return Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.green.shade50
                    : null,
              ),
              child: ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedItems.add({
                          'serviceId': service['id'],
                          'serviceName': service['name'],
                          'variantId': variant['id'],
                          'variantDisplay': variant['display'],
                          'price': variant['price'],
                          'duration': variant['duration'],
                        });
                      } else {
                        _selectedItems.removeWhere((item) => 
                            item['serviceId'] == service['id'] && 
                            item['variantId'] == variant['id']);
                      }
                    });
                  },
                  activeColor: const Color(0xFFFF6B8B),
                  checkColor: Colors.white,
                ),
                title: Text(
                  variant['display'],
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  '${variant['duration']} min',
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Rs. ${variant['price']}',
                    style: const TextStyle(
                      color: Color(0xFFFF6B8B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ==================== STEP 3: BARBER SELECTION ====================
  Widget _buildBarberSelectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected services summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selected Services',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ..._selectedItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Color(0xFFFF6B8B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item['serviceName']} - ${item['variantDisplay']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                    Text(
                      '${item['duration']} min',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )).toList(),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        const Text(
          'Available Barbers',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          'Barbers who can perform all selected services',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        
        Expanded(
          child: _isLoadingAvailability
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.red.shade700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _currentStep = 1;
                                _errorMessage = null;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B8B),
                            ),
                            child: const Text('Choose Different Services'),
                          ),
                        ],
                      ),
                    )
                  : _availableBarbers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No barbers available',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try different service combinations',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _availableBarbers.length,
                          itemBuilder: (context, index) {
                            final barber = _availableBarbers[index];
                            final isSelected = _selectedBarber != null && 
                                _selectedBarber!['id'] == barber['id'];
                            
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedBarber = barber;
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFFF6B8B).withValues(alpha: 0.05)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFFF6B8B)
                                        : Colors.grey[200]!,
                                    width: isSelected ? 2 : 1,
                                  ),
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
                                    CircleAvatar(
                                      radius: 32,
                                      backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                                      backgroundImage: barber['avatar'] != null
                                          ? NetworkImage(barber['avatar'])
                                          : null,
                                      child: barber['avatar'] == null
                                          ? Text(
                                              barber['name'][0].toUpperCase(),
                                              style: const TextStyle(
                                                color: Color(0xFFFF6B8B),
                                                fontSize: 24,
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
                                          Text(
                                            barber['name'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.star,
                                                size: 14,
                                                color: Colors.amber.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                barber['rating'].toStringAsFixed(1),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.work_outline,
                                                size: 14,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                barber['experience'],
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (barber['specialties'].isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: (barber['specialties'] as List<String>).map((specialty) {
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    specialty,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Color(0xFFFF6B8B),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFFFF6B8B)
                                              : Colors.grey[400]!,
                                          width: 2,
                                        ),
                                        color: isSelected
                                            ? const Color(0xFFFF6B8B)
                                            : Colors.transparent,
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 16,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  // ==================== STEP 4: DATE & TIME SELECTION ====================
  Widget _buildDateTimeStep() {
    if (_selectedBarber == null) {
      return const Center(
        child: Text('Please select a barber first'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected barber info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                backgroundImage: _selectedBarber!['avatar'] != null
                    ? NetworkImage(_selectedBarber!['avatar'])
                    : null,
                child: _selectedBarber!['avatar'] == null
                    ? Text(
                        _selectedBarber!['name'][0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFFFF6B8B)),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedBarber!['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _selectedBarber!['bio'] ?? 'Professional barber',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Date selection
        const Text(
          'Select Date',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        
        if (_isLoadingAvailability)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            ),
          )
        else if (_availableDates.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.date_range, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'No available dates',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _availableDates.length,
              itemBuilder: (context, index) {
                final date = _availableDates[index];
                final isSelected = _selectedDate != null &&
                    _selectedDate!.year == date.year &&
                    _selectedDate!.month == date.month &&
                    _selectedDate!.day == date.day;
                
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedTime = null;
                      _loadAvailableTimeSlots();
                    });
                  },
                  child: Container(
                    width: 85,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF6B8B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFF6B8B)
                            : isToday
                                ? const Color(0xFFFF6B8B).withValues(alpha: 0.5)
                                : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade100,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(date),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[600],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('MMM').format(date),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                fontSize: 7,
                                color: isSelected ? Colors.white : const Color(0xFFFF6B8B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        
        const SizedBox(height: 20),
        
        // Time selection
        if (_selectedDate != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Time',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                DateFormat('MMMM d, yyyy').format(_selectedDate!),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (_isLoadingAvailability)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
              ),
            )
          else if (_availableTimeSlots.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.access_time, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No available time slots',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try selecting another date',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _availableTimeSlots.length,
                itemBuilder: (context, index) {
                  final time = _availableTimeSlots[index];
                  final isSelected = _selectedTime != null &&
                      _selectedTime!.hour == time.hour &&
                      _selectedTime!.minute == time.minute;
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedTime = time);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFF6B8B) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected 
                              ? const Color(0xFFFF6B8B) 
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          time.format(context),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  // ==================== STEP 5: CONFIRMATION ====================
  Widget _buildConfirmationStep() {
    if (_confirmedBooking == null) {
      return const Center(
        child: Text('No booking confirmed'),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Success animation
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 72,
            ),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            'Booking Confirmed!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            _selectedSalon!['name'],
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Queue number card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B8B), Color(0xFFFF8A9F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Your Queue Number',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '#${_queueNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.qr_code,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Token: $_confirmNumber',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Appointment details card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.grey[200]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildConfirmationDetailRow(
                    Icons.store,
                    'Salon',
                    _selectedSalon!['name'],
                  ),
                  const Divider(height: 24),
                  _buildConfirmationDetailRow(
                    Icons.person,
                    'Barber',
                    _selectedBarber!['name'],
                  ),
                  const Divider(height: 24),
                  ..._selectedItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Column(
                      children: [
                        if (index > 0) const Divider(height: 24),
                        _buildConfirmationDetailRow(
                          Icons.build,
                          'Service ${index + 1}',
                          '${item['serviceName']} - ${item['variantDisplay']}',
                        ),
                      ],
                    );
                  }).toList(),
                  const Divider(height: 24),
                  _buildConfirmationDetailRow(
                    Icons.calendar_today,
                    'Date',
                    DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!),
                  ),
                  const Divider(height: 24),
                  _buildConfirmationDetailRow(
                    Icons.access_time,
                    'Time',
                    _selectedTime!.format(context),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Please show this confirmation to your barber. Your queue number is #$_queueNumber',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    context.go('/customer/home');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B8B),
                    side: const BorderSide(color: Color(0xFFFF6B8B)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Home'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    context.push('/customer/my-bookings');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B8B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('My Bookings'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFFFF6B8B)),
        ),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  void _showSalonInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  backgroundImage: _selectedSalon!['logo_url'] != null
                      ? NetworkImage(_selectedSalon!['logo_url'])
                      : null,
                  child: _selectedSalon!['logo_url'] == null
                      ? const Icon(Icons.store, color: Color(0xFFFF6B8B))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedSalon!['name'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_selectedSalon!['address'] != null)
                        Text(
                          _selectedSalon!['address'],
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoRow(Icons.access_time, 'Hours',
                '${_selectedSalon!['open_time']?.substring(0, 5) ?? '09:00'} - ${_selectedSalon!['close_time']?.substring(0, 5) ?? '18:00'}'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.phone, 'Phone', _selectedSalon!['phone'] ?? 'Not available'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.email, 'Email', _selectedSalon!['email'] ?? 'Not available'),
            if (_selectedSalon!['description'] != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(Icons.description, 'About', _selectedSalon!['description']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}