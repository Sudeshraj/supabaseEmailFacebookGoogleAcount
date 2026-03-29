// screens/customer/vip_booking_request_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class VIPBookingRequestScreen extends StatefulWidget {
  final String? salonId;
  
  const VIPBookingRequestScreen({super.key, this.salonId});

  @override
  State<VIPBookingRequestScreen> createState() => _VIPBookingRequestScreenState();
}

class _VIPBookingRequestScreenState extends State<VIPBookingRequestScreen> {
  final supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  
  // Form data
  int? _selectedVipTypeId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int? _numberOfGuests;
  final TextEditingController _specialRequestsController = TextEditingController();
  
  // Available services
  List<Map<String, dynamic>> _availableServices = [];
  Map<int, List<Map<String, dynamic>>> _serviceVariants = {};
  Set<int> _selectedVariantIds = {};
  
  // VIP types
  List<Map<String, dynamic>> _vipTypes = [];
  
  // Salon details
  String? _salonOpenTime;
  String? _salonCloseTime;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load VIP types
      final vipTypesResponse = await supabase
          .from('vip_booking_types')
          .select()
          .order('priority_level');

      _vipTypes = List<Map<String, dynamic>>.from(vipTypesResponse);

      // Load salon details
      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time')
          .eq('id', int.parse(widget.salonId!))
          .maybeSingle();

      if (salonResponse != null) {
        _salonOpenTime = salonResponse['open_time'];
        _salonCloseTime = salonResponse['close_time'];
      }

      // Load services with variants
      await _loadServices();

    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServices() async {
    try {
      // Get all services
      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            category_id,
            categories (
              name,
              icon_name
            )
          ''')
          .eq('is_active', true)
          .order('name');

      // Get all variants
      final variantsResponse = await supabase
          .from('service_variants')
          .select('''
            id,
            service_id,
            price,
            duration,
            genders (
              display_name
            ),
            age_categories (
              display_name
            )
          ''')
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
          'price': variant['price'],
          'duration': variant['duration'],
          'gender_name': gender['display_name'],
          'age_name': age['display_name'],
          'display_text': '${gender['display_name']} - ${age['display_name']}',
        });
      }

      _serviceVariants = variantsMap;
      _availableServices = List<Map<String, dynamic>>.from(servicesResponse);

    } catch (e) {
      debugPrint('❌ Error loading services: $e');
    }
  }

Future<void> _submitRequest() async {
  if (_selectedVipTypeId == null ||
      _selectedDate == null ||
      _selectedTime == null ||
      _numberOfGuests == null ||
      _selectedVariantIds.isEmpty) {
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please fill all required fields'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    // 🔥 FIXED: Calculate total duration
    int totalDuration = 0;
    for (int variantId in _selectedVariantIds) {
      bool found = false;
      for (var entry in _serviceVariants.entries) {
        for (var variant in entry.value) {
          if (variant['id'] == variantId) {
            totalDuration += variant['duration'] as int;
            found = true;
            break;
          }
        }
        if (found) break;
      }
    }

    // Format time
    final timeStr = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';
    final dateStr = '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';

    // Generate booking number
    final bookingNumber = 'VIP-${DateTime.now().millisecondsSinceEpoch}';

    // Create VIP booking
    final vipBookingResponse = await supabase
        .from('vip_bookings')
        .insert({
          'booking_number': bookingNumber,
          'vip_type_id': _selectedVipTypeId,
          'customer_id': user.id,
          'salon_id': int.parse(widget.salonId!),
          'event_date': dateStr,
          'preferred_start_time': timeStr,
          'total_duration_minutes': totalDuration,
          'number_of_guests': _numberOfGuests,
          'special_requirements': _specialRequestsController.text.trim(),
          'status': 'pending',
        })
        .select()
        .single();

    // Add selected services
    for (int variantId in _selectedVariantIds) {
      // Find service_id and duration for this variant
      int? serviceId;
      int? duration;
      
      for (var entry in _serviceVariants.entries) {
        for (var variant in entry.value) {
          if (variant['id'] == variantId) {
            serviceId = entry.key;
            duration = variant['duration'];
            break;
          }
        }
        if (serviceId != null) break;
      }

      if (serviceId != null && duration != null) {
        await supabase.from('vip_booking_services').insert({
          'vip_booking_id': vipBookingResponse['id'],
          'service_id': serviceId,
          'variant_id': variantId,
          'duration_minutes': duration,
          'status': 'pending',
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('VIP booking request submitted! Waiting for approval.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    }

  } catch (e) {
    debugPrint('❌ Error submitting VIP request: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}



  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VIP Booking Request'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        centerTitle: isWeb,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // VIP Info Card
                  Card(
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'VIP Booking',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Get priority service with special arrangements',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // VIP Type Selection
                  const Text('Event Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _vipTypes.map((type) {
                      final isSelected = _selectedVipTypeId == type['id'];
                      return FilterChip(
                        label: Text(type['name']),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() => _selectedVipTypeId = type['id']);
                        },
                        backgroundColor: Colors.grey[100],
                        selectedColor: Colors.amber.shade100,
                        checkmarkColor: Colors.amber.shade800,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Date and Time
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 90)),
                                );
                                if (date != null) {
                                  setState(() => _selectedDate = date);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      _selectedDate != null
                                          ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
                                          : 'Select date',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Time', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() => _selectedTime = time);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      _selectedTime != null
                                          ? _selectedTime!.format(context)
                                          : 'Select time',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Number of Guests
                  const Text('Number of Guests', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: (_numberOfGuests ?? 1).toDouble(),
                          min: 1,
                          max: 20,
                          divisions: 19,
                          label: '$_numberOfGuests',
                          onChanged: (value) {
                            setState(() => _numberOfGuests = value.round());
                          },
                          activeColor: Colors.amber,
                        ),
                      ),
                      Container(
                        width: 50,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_numberOfGuests ?? 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Services Selection
                  const Text('Select Services', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ..._availableServices.map((service) {
                    final serviceId = service['id'] as int;
                    final variants = _serviceVariants[serviceId] ?? [];
                    final categoryName = service['categories']?['name'] ?? 'other';

                    if (variants.isEmpty) return const SizedBox.shrink();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.build, color: Colors.amber, size: 20),
                          ),
                          title: Text(
                            service['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('${variants.length} variants'),
                          children: variants.map((variant) {
                            final isSelected = _selectedVariantIds.contains(variant['id']);
                            return CheckboxListTile(
                              title: Text(variant['display_text']),
                              subtitle: Text('Rs. ${variant['price']} • ${variant['duration']} min'),
                              value: isSelected,
                              onChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedVariantIds.add(variant['id']);
                                  } else {
                                    _selectedVariantIds.remove(variant['id']);
                                  }
                                });
                              },
                              secondary: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.amber : Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSelected ? Icons.check : Icons.circle_outlined,
                                  color: isSelected ? Colors.white : Colors.grey,
                                  size: 16,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Special Requests
                  const Text('Special Requests', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _specialRequestsController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Any special requirements?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : const Text(
                              'Submit VIP Request',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}