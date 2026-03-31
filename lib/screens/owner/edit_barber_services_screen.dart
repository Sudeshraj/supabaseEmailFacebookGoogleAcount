// screens/owner/edit_barber_services_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditBarberServicesScreen extends StatefulWidget {
  final String barberId;
  final String salonId;

  const EditBarberServicesScreen({
    super.key,
    required this.barberId,
    required this.salonId,
  });

  @override
  State<EditBarberServicesScreen> createState() => _EditBarberServicesScreenState();
}

class _EditBarberServicesScreenState extends State<EditBarberServicesScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isDeleting = false;
  bool _isSelectMode = false;
  final Set<int> _selectedForDelete = {};

  // Barber details
  Map<String, dynamic> _barber = {};

  // Services with their variants
  List<Map<String, dynamic>> _services = [];

  // Salon barber ID
  int? _salonBarberId;

  // Gender and Age Category maps
  Map<int, String> _genderMap = {};
  Map<int, Map<String, dynamic>> _ageCategoryMap = {};
  
  // Categories list
  List<Map<String, dynamic>> _categories = [];

  // Expanded services for mobile view
  final Set<int> _expandedServices = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId);
      
      // Step 1: Get salon_barber_id
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('barber_id', widget.barberId)
          .eq('salon_id', salonIdInt)
          .maybeSingle();

      if (salonBarberResponse == null) {
        throw Exception('Barber not found in this salon');
      }

      _salonBarberId = salonBarberResponse['id'] as int;

      // Step 2: Load barber profile
      final profile = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .eq('id', widget.barberId)
          .maybeSingle();

      if (profile != null) {
        _barber = profile;
      }

      // Step 3: Load categories
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');
      
      _categories = List<Map<String, dynamic>>.from(categoriesResponse);

      // Step 4: Load genders
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);
      
      for (var g in gendersResponse) {
        _genderMap[g['id']] = g['display_name'];
      }

      // Step 5: Load age categories
      final ageCategoriesResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);
      
      for (var a in ageCategoriesResponse) {
        _ageCategoryMap[a['id']] = {
          'display_name': a['display_name'],
          'min_age': a['min_age'],
          'max_age': a['max_age'],
        };
      }

      // Step 6: Get barber's current active services
      final currentServices = await supabase
          .from('barber_services')
          .select('id, variant_id, service_id, status')
          .eq('salon_barber_id', _salonBarberId!)
          .eq('status', 'active');

      if (currentServices.isEmpty) {
        setState(() {
          _services = [];
          _isLoading = false;
        });
        return;
      }

      // Step 7: Get unique service IDs
      final allServiceIds = currentServices
          .map((s) => s['service_id'] as int)
          .toSet()
          .toList();

      // Step 8: Load service details
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, category_id, icon_name')
          .inFilter('id', allServiceIds)
          .eq('is_active', true);

      final Map<int, Map<String, dynamic>> serviceInfoMap = {};
      for (var service in servicesResponse) {
        final category = _categories.firstWhere(
          (c) => c['id'] == service['category_id'],
          orElse: () => {'display_name': 'Other', 'icon_name': 'build', 'color': '#FF6B8B'},
        );
        serviceInfoMap[service['id']] = {
          'id': service['id'],
          'name': service['name'],
          'description': service['description'] ?? '',
          'category_id': service['category_id'],
          'category_name': category['display_name'],
          'category_icon': category['icon_name'],
          'category_color': category['color'],
          'icon_name': service['icon_name'] ?? category['icon_name'],
        };
      }

      // Step 9: Process services
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      final Map<int, bool> hasFullService = {};

      for (var item in currentServices) {
        final serviceId = item['service_id'] as int;
        final variantId = item['variant_id'] as int?;
        
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
          hasFullService[serviceId] = false;
        }
        
        if (variantId == null) {
          hasFullService[serviceId] = true;
        } else {
          final variant = await supabase
              .from('service_variants')
              .select('id, price, duration, salon_gender_id, salon_age_category_id')
              .eq('id', variantId)
              .maybeSingle();
          
          if (variant != null) {
            final genderName = _genderMap[variant['salon_gender_id']] ?? 'Unknown';
            final ageData = _ageCategoryMap[variant['salon_age_category_id']] ?? 
                {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
            final ageName = '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';
            
            variantsByService[serviceId]!.add({
              'id': variant['id'],
              'price': variant['price'],
              'duration': variant['duration'],
              'gender_name': genderName,
              'age_name': ageName,
              'display_text': '$genderName • $ageName',
            });
          }
        }
      }

      // Step 10: Build services list
      final List<Map<String, dynamic>> processedServices = [];
      for (var serviceId in allServiceIds) {
        final serviceInfo = serviceInfoMap[serviceId];
        if (serviceInfo == null) continue;
        
        final variants = variantsByService[serviceId] ?? [];
        final hasFullServiceValue = hasFullService[serviceId] ?? false;
        
        processedServices.add({
          'id': serviceId,
          'name': serviceInfo['name'],
          'description': serviceInfo['description'],
          'category_name': serviceInfo['category_name'],
          'category_icon': serviceInfo['category_icon'],
          'category_color': serviceInfo['category_color'],
          'icon_name': serviceInfo['icon_name'],
          'has_full_service': hasFullServiceValue,
          'variants': variants,
          'variant_count': variants.length,
        });
      }

      // Sort by category then name
      processedServices.sort((a, b) {
        final categoryCompare = (a['category_name'] as String).compareTo(b['category_name'] as String);
        if (categoryCompare != 0) return categoryCompare;
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      setState(() {
        _services = processedServices;
      });

    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        _showSnackBar('Error loading data: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ADD VARIANT DIALOG (Same as ServiceManagementScreen)
  // ============================================================
  
  void _showAddVariantDialog(Map<String, dynamic> service) {
    int? selectedGenderId;
    int? selectedAgeCategoryId;
    final priceController = TextEditingController();
    final durationController = TextEditingController();
    String? priceError;
    String? durationError;
    
    void validatePrice() {
      final price = double.tryParse(priceController.text.trim());
      if (priceController.text.trim().isEmpty) {
        priceError = null;
      } else if (price == null) {
        priceError = 'Please enter a valid number';
      } else if (price <= 0) {
        priceError = 'Price must be greater than 0';
      } else {
        priceError = null;
      }
    }
    
    void validateDuration() {
      final duration = int.tryParse(durationController.text.trim());
      if (durationController.text.trim().isEmpty) {
        durationError = null;
      } else if (duration == null) {
        durationError = 'Please enter a valid number';
      } else if (duration <= 0) {
        durationError = 'Duration must be greater than 0';
      } else {
        durationError = null;
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getIconForName(service['icon_name']),
                    color: const Color(0xFFFF6B8B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add New Option - ${service['name']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gender Dropdown
                  const Text(
                    'Gender *',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedGenderId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.wc, color: Colors.grey, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    hint: const Text('Select gender'),
                    items: _genderMap.entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedGenderId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Age Category Dropdown
                  const Text(
                    'Age Category *',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedAgeCategoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.timeline, color: Colors.grey, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    hint: const Text('Select age category'),
                    items: _ageCategoryMap.entries.map((entry) {
                      final ageData = entry.value;
                      String displayName = ageData['display_name'];
                      if (ageData['min_age'] != null && ageData['max_age'] != null) {
                        displayName = '$displayName (${ageData['min_age']}-${ageData['max_age']} yrs)';
                      }
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedAgeCategoryId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Price and Duration Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Price (Rs.) *',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: priceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'e.g., 1500',
                                prefixIcon: const Icon(Icons.currency_rupee, color: Colors.grey, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                errorText: priceError,
                                errorMaxLines: 2,
                              ),
                              onChanged: (value) {
                                validatePrice();
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Duration (mins) *',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: durationController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'e.g., 30',
                                prefixIcon: const Icon(Icons.timer, color: Colors.grey, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                errorText: durationError,
                                errorMaxLines: 2,
                              ),
                              onChanged: (value) {
                                validateDuration();
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  priceController.dispose();
                  durationController.dispose();
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  validatePrice();
                  validateDuration();
                  
                  if (selectedGenderId == null) {
                    _showSnackBar('Please select a gender', Colors.orange);
                    return;
                  }
                  if (selectedAgeCategoryId == null) {
                    _showSnackBar('Please select an age category', Colors.orange);
                    return;
                  }
                  
                  final price = double.tryParse(priceController.text.trim());
                  final duration = int.tryParse(durationController.text.trim());
                  
                  if (price == null || price <= 0) {
                    _showSnackBar('Please enter a valid price', Colors.orange);
                    return;
                  }
                  if (duration == null || duration <= 0) {
                    _showSnackBar('Please enter a valid duration', Colors.orange);
                    return;
                  }
                  
                  // Check for duplicate variant
                  final bool isDuplicate = service['variants'].any((variant) {
                    return variant['gender_id'] == selectedGenderId &&
                           variant['age_category_id'] == selectedAgeCategoryId;
                  });
                  
                  if (isDuplicate) {
                    _showSnackBar('This option already exists!', Colors.orange);
                    return;
                  }
                  
                  setState(() => _isDeleting = true);
                  
                  try {
                    // First, check if the variant already exists in service_variants
                    final existingVariant = await supabase
                        .from('service_variants')
                        .select('id')
                        .eq('service_id', service['id'])
                        .eq('salon_gender_id', selectedGenderId!)
                        .eq('salon_age_category_id', selectedAgeCategoryId!)
                        .maybeSingle();
                    
                    int variantId;
                    
                    if (existingVariant != null) {
                      variantId = existingVariant['id'];
                    } else {
                      // Create new variant
                      final newVariant = await supabase
                          .from('service_variants')
                          .insert({
                            'service_id': service['id'],
                            'salon_gender_id': selectedGenderId,
                            'salon_age_category_id': selectedAgeCategoryId,
                            'price': price,
                            'duration': duration,
                            'is_active': true,
                          })
                          .select()
                          .single();
                      variantId = newVariant['id'];
                    }
                    
                    // Assign variant to barber
                    await supabase
                        .from('barber_services')
                        .insert({
                          'salon_barber_id': _salonBarberId!,
                          'service_id': service['id'],
                          'variant_id': variantId,
                          'status': 'active',
                        });
                    
                    priceController.dispose();
                    durationController.dispose();
                    Navigator.pop(context);
                    await _loadData();
                    
                    if (mounted) {
                      _showSnackBar('Option added successfully!', Colors.green);
                    }
                  } catch (e) {
                    if (mounted) {
                      _showSnackBar('Error adding option: $e', Colors.red);
                    }
                  } finally {
                    if (mounted) setState(() => _isDeleting = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Add Option', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // DELETE FUNCTIONS
  // ============================================================

  Future<void> _deleteService(Map<String, dynamic> service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Service'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to delete '${service['name']}'?"),
            const SizedBox(height: 12),
            const Text(
              'This will also remove this service from the barber.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      if (_salonBarberId == null) {
        throw Exception('Salon barber ID not found');
      }
      
      final int salonBarberId = _salonBarberId!;

      if (service['has_full_service'] == true) {
        // Delete full service entry
        await supabase
            .from('barber_services')
            .update({'status': 'inactive'})
            .eq('salon_barber_id', salonBarberId)
            .eq('service_id', service['id'])
            .filter('variant_id', 'is', 'null');
      }

      // Delete all variants
      for (var variant in service['variants']) {
        await supabase
            .from('barber_services')
            .update({'status': 'inactive'})
            .eq('salon_barber_id', salonBarberId)
            .eq('variant_id', variant['id']);
      }

      await _loadData();
      
      if (mounted) {
        _showSnackBar('Service deleted successfully', Colors.green);
      }

    } catch (e) {
      _showSnackBar('Error deleting: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _deleteVariant(Map<String, dynamic> service, Map<String, dynamic> variant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Option'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to delete this option from '${service['name']}'?"),
            const SizedBox(height: 12),
            Text(
              '${variant['display_text']}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone!',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      if (_salonBarberId == null) {
        throw Exception('Salon barber ID not found');
      }
      
      final int salonBarberId = _salonBarberId!;

      await supabase
          .from('barber_services')
          .update({'status': 'inactive'})
          .eq('salon_barber_id', salonBarberId)
          .eq('variant_id', variant['id']);

      await _loadData();
      
      if (mounted) {
        _showSnackBar('Option deleted successfully', Colors.green);
      }

    } catch (e) {
      _showSnackBar('Error deleting: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ============================================================
  // ADD SERVICE (Icon only)
  // ============================================================

  Future<void> _addService() async {
    if (_salonBarberId == null) {
      _showSnackBar('Salon barber ID not found', Colors.red);
      return;
    }
    
    final result = await context.push(
      '/owner/salon/${widget.salonId}/barber/${widget.barberId}/add-service',
      extra: {
        'salonBarberId': _salonBarberId,
        'barberName': _barber['full_name'],
      },
    );
    
    if (result == true) {
      await _loadData();
      if (mounted) {
        _showSnackBar('Services added successfully!', Colors.green);
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleExpand(int serviceId) {
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
      }
    });
  }

  IconData _getIconForName(String? iconName) {
    switch (iconName) {
      case 'content_cut': return Icons.content_cut;
      case 'face': return Icons.face;
      case 'face_retouching_natural': return Icons.face_retouching_natural;
      case 'spa': return Icons.spa;
      case 'handshake': return Icons.handshake;
      case 'build': return Icons.build;
      case 'brush': return Icons.brush;
      case 'cut': return Icons.cut;
      default: return Icons.build;
    }
  }

  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null) return const Color(0xFFFF6B8B);
    try {
      return Color(int.parse('0xFF${hexColor.replaceFirst('#', '')}'));
    } catch (e) {
      return const Color(0xFFFF6B8B);
    }
  }

  // ============================================================
  // UI BUILDERS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barber Services'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        actions: [
          // Add Service Button - Icon only
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _addService,
            tooltip: 'Add Service',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : _services.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildBarberInfoCard(),
                    Expanded(
                      child: isWeb
                          ? _buildWebView()
                          : _buildMobileView(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: isWeb ? 80 : 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No services found',
            style: TextStyle(
              fontSize: isWeb ? 18 : 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add services for this barber',
            style: TextStyle(
              fontSize: isWeb ? 14 : 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addService,
            icon: const Icon(Icons.add),
            label: const Text('Add Services'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isWeb ? 32 : 24,
                vertical: isWeb ? 14 : 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarberInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            backgroundImage: _barber['avatar_url'] != null
                ? NetworkImage(_barber['avatar_url'])
                : null,
            child: _barber['avatar_url'] == null
                ? Text(
                    _barber['full_name']?[0]?.toUpperCase() ?? '?',
                    style: const TextStyle(
                      color: Color(0xFFFF6B8B),
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
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
                  _barber['full_name'] ?? 'Unknown Barber',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _barber['email'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Add Service Button removed from here (moved to app bar)
        ],
      ),
    );
  }

  Widget _buildWebView() {
    // Group services by category
    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    final sortedCategories = groupedServices.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final services = groupedServices[category]!;
        return _buildCategorySection(category, services, true);
      },
    );
  }

  Widget _buildMobileView() {
    // Group services by category
    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    final sortedCategories = groupedServices.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final services = groupedServices[category]!;
        return _buildCategorySection(category, services, false);
      },
    );
  }

  Widget _buildCategorySection(String category, List<Map<String, dynamic>> services, bool isWeb) {
    final categoryColor = _getColorFromHex(services.first['category_color']);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconForName(services.first['category_icon']),
                  color: categoryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                category,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${services.length} service${services.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Services Grid/List
        isWeb
            ? GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: services.length,
                itemBuilder: (context, index) => _buildServiceCard(services[index], true),
              )
            : Column(
                children: services.map((service) => _buildServiceCard(service, false)).toList(),
              ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, bool isWeb) {
    final hasFullService = service['has_full_service'] == true;
    final variants = service['variants'] as List;
    final categoryColor = _getColorFromHex(service['category_color']);
    final isExpanded = _expandedServices.contains(service['id']);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getIconForName(service['icon_name']),
                    color: const Color(0xFFFF6B8B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (service['description'].isNotEmpty)
                        Text(
                          service['description'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (variants.isNotEmpty && !isWeb)
                        Text(
                          '${variants.length} options',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
                // Delete Service Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                  onPressed: _isDeleting ? null : () => _deleteService(service),
                  tooltip: 'Delete Service',
                ),
                // Expand/Collapse for mobile
                if (!isWeb && variants.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey,
                    ),
                    onPressed: () => _toggleExpand(service['id']),
                  ),
              ],
            ),
          ),
          
          // Full Service Badge (if no variants)
          if (variants.isEmpty && hasFullService)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Full Service - No variants',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Variants Section
          if (variants.isNotEmpty && (isWeb || isExpanded)) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Service Options',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      // Add Variant Button - Opens Dialog
                      TextButton.icon(
                        onPressed: () => _showAddVariantDialog(service),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Option'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B8B),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${variants.length} option${variants.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...variants.map((variant) => _buildVariantCard(service, variant)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantCard(Map<String, dynamic> service, Map<String, dynamic> variant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.local_offer,
                color: Colors.orange,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant['display_text'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rs. ${variant['price']} • ${variant['duration']} min',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Delete Variant Button
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: _isDeleting ? null : () => _deleteVariant(service, variant),
              tooltip: 'Delete Option',
            ),
          ],
        ),
      ),
    );
  }
}