import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/owner/add_services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceManagementScreen extends StatefulWidget {
  final int salonId;
  final String salonName;

  const ServiceManagementScreen({
    super.key,
    required this.salonId,
    required this.salonName,
  });

  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  // Search and filter
  String _searchQuery = '';
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];

  // Gender and age categories for variant form
  List<Map<String, dynamic>> _genders = [];
  List<Map<String, dynamic>> _ageCategories = [];

  // For expansion state - track expanded services
  final Set<int> _expandedServices = {};

  // Alternating card colors
  final List<Color> _cardColors = [
    const Color(0xFFE3F2FD), // Light Blue
    const Color(0xFFFCE4EC), // Light Pink
    const Color(0xFFE8F5E9), // Light Green
    const Color(0xFFFFF3E0), // Light Orange
    const Color(0xFFF3E5F5), // Light Purple
    const Color(0xFFE0F7FA), // Light Cyan
    const Color(0xFFFFEBEE), // Light Red
    const Color(0xFFE8EAF6), // Light Indigo
  ];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load categories
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Load genders for variant form
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Load age categories for variant form
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _genders = List<Map<String, dynamic>>.from(gendersResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
      });

      await _loadServices();
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        _showSnackBar('Error loading data: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServices() async {
    try {
      // Load services
      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            icon_name,
            category_id,
            is_active,
            created_at,
            updated_at
          ''')
          .eq('salon_id', widget.salonId)
          .order('name');

      final services = List<Map<String, dynamic>>.from(servicesResponse);

      // Load variants for each service
      for (var service in services) {
        final variantsResponse = await supabase
            .from('service_variants')
            .select('''
              id,
              price,
              duration,
              is_active,
              salon_gender_id,
              salon_age_category_id,
              salon_genders!inner (display_name),
              salon_age_categories!inner (display_name, min_age, max_age)
            ''')
            .eq('service_id', service['id'])
            .eq('is_active', true);

        final variants = List<Map<String, dynamic>>.from(variantsResponse);

        // Format variants for display
        final formattedVariants = variants.map((variant) {
          final genderName =
              variant['salon_genders']?['display_name'] ?? 'Unknown';
          final ageCat = variant['salon_age_categories'];
          String ageName = ageCat?['display_name'] ?? 'Unknown';
          if (ageCat?['min_age'] != null && ageCat?['max_age'] != null) {
            ageName =
                '$ageName (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
          }
          return {
            'id': variant['id'],
            'gender_name': genderName,
            'age_name': ageName,
            'price': variant['price'],
            'duration': variant['duration'],
            'is_active': variant['is_active'],
            'gender_id': variant['salon_gender_id'],
            'age_category_id': variant['salon_age_category_id'],
          };
        }).toList();

        service['variants'] = formattedVariants;
        service['variant_count'] = formattedVariants.length;
        service['has_variants'] = formattedVariants.isNotEmpty;

        // Get category name
        final category = _categories.firstWhere(
          (c) => c['id'] == service['category_id'],
          orElse: () => {'display_name': 'Uncategorized'},
        );
        service['category_name'] = category['display_name'];
      }

      setState(() {
        _services = services;

        // Auto-expand all services that have variants
        _expandedServices.clear();
        for (var service in services) {
          if (service['has_variants'] == true) {
            _expandedServices.add(service['id'] as int);
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading services: $e');
      rethrow;
    }
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

  void _expandAllServices() {
    setState(() {
      _expandedServices.clear();
      for (var service in _services) {
        if (service['has_variants'] == true) {
          _expandedServices.add(service['id'] as int);
        }
      }
    });
  }

  void _collapseAllServices() {
    setState(() {
      _expandedServices.clear();
    });
  }

  // ============================================
  // ADD VARIANT DIALOG
  // ============================================

  void _showAddVariantDialog(Map<String, dynamic> service) async {
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

    await showDialog(
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
                    'Add New Option',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.room_service,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            service['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Gender Dropdown
                  const Text(
                    'Gender',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedGenderId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.wc,
                        color: Colors.grey,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    hint: const Text('Select gender'),
                    items: _genders.map((gender) {
                      return DropdownMenuItem<int>(
                        value: gender['id'] as int,
                        child: Text(
                          gender['display_name'],
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    'Age Category',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedAgeCategoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.timeline,
                        color: Colors.grey,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    hint: const Text('Select age category'),
                    items: _ageCategories.map((ageCat) {
                      String displayName = ageCat['display_name'];
                      if (ageCat['min_age'] != null &&
                          ageCat['max_age'] != null) {
                        displayName =
                            '$displayName (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
                      }
                      return DropdownMenuItem<int>(
                        value: ageCat['id'] as int,
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                              'Price (Rs.)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: priceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'e.g., 1500',
                                prefixIcon: const Icon(
                                  Icons.currency_rupee,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
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
                              'Duration (mins)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: durationController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'e.g., 30',
                                prefixIcon: const Icon(
                                  Icons.timer,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
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
                    _showSnackBar(
                      'Please select an age category',
                      Colors.orange,
                    );
                    return;
                  }

                  final price = double.tryParse(priceController.text.trim());
                  final duration = int.tryParse(durationController.text.trim());

                  if (price == null || price <= 0) {
                    _showSnackBar('Please enter a valid price', Colors.orange);
                    return;
                  }
                  if (duration == null || duration <= 0) {
                    _showSnackBar(
                      'Please enter a valid duration',
                      Colors.orange,
                    );
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

                  setState(() => _isProcessing = true);

                  try {
                    await supabase.from('service_variants').insert({
                      'service_id': service['id'],
                      'salon_gender_id': selectedGenderId,
                      'salon_age_category_id': selectedAgeCategoryId,
                      'price': price,
                      'duration': duration,
                      'is_active': true,
                    });
                  } catch (e) {
                    if (mounted) {
                      _showSnackBar('Error adding option: $e', Colors.red);
                    }
                  } finally {
                    if (mounted) setState(() => _isProcessing = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Add Option',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================
  // EDIT VARIANT DIALOG
  // ============================================

  void _showEditVariantDialog(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final priceController = TextEditingController(
      text: variant['price'].toString(),
    );
    final durationController = TextEditingController(
      text: variant['duration'].toString(),
    );
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
                const Text(
                  'Edit Option',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.room_service,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              service['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.wc, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(variant['gender_name']),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(variant['age_name']),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Price & Duration',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: priceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Price (Rs.)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(
                              Icons.currency_rupee,
                              size: 20,
                            ),
                            errorText: priceError,
                          ),
                          onChanged: (value) {
                            validatePrice();
                            setDialogState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: durationController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Duration (mins)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.timer, size: 20),
                            errorText: durationError,
                          ),
                          onChanged: (value) {
                            validateDuration();
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  validatePrice();
                  validateDuration();

                  final price = double.tryParse(priceController.text.trim());
                  final duration = int.tryParse(durationController.text.trim());

                  if (price == null || price <= 0) {
                    _showSnackBar('Please enter a valid price', Colors.orange);
                    return;
                  }
                  if (duration == null || duration <= 0) {
                    _showSnackBar(
                      'Please enter a valid duration',
                      Colors.orange,
                    );
                    return;
                  }

                  setState(() => _isProcessing = true);

                  try {
                    await supabase
                        .from('service_variants')
                        .update({
                          'price': price,
                          'duration': duration,
                          'updated_at': DateTime.now().toIso8601String(),
                        })
                        .eq('id', variant['id']);
                  } catch (e) {
                    if (mounted) {
                      _showSnackBar('Error updating option: $e', Colors.red);
                    }
                  } finally {
                    if (mounted) setState(() => _isProcessing = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================
  // DELETE VARIANT
  // ============================================

  Future<void> _deleteVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              'Delete Option',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete this option?",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service: ${service['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${variant['gender_name']} - ${variant['age_name']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rs. ${variant['price']} | ${variant['duration']} mins',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone!',
              style: TextStyle(fontSize: 12, color: Colors.red),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);

      try {
        await supabase
            .from('service_variants')
            .delete()
            .eq('id', variant['id']);

        await _loadServices();

        if (mounted) {
          _showSnackBar('Option deleted successfully', Colors.green);
        }
      } catch (e) {
        if (mounted) {
          _showSnackBar('Error deleting option: $e', Colors.red);
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  // ============================================
  // SERVICE MANAGEMENT FUNCTIONS
  // ============================================

  // Edit Service
  Future<void> _editService(Map<String, dynamic> service) async {
    final nameController = TextEditingController(text: service['name']);
    final descriptionController = TextEditingController(
      text: service['description'] ?? '',
    );
    int? selectedCategoryId = service['category_id'];

    await showDialog(
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
                const Text(
                  'Edit Service',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Service Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedCategoryId,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem<int>(
                        value: category['id'] as int,
                        child: Text(category['display_name']),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedCategoryId = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() => _isProcessing = true);

                  try {
                    await supabase
                        .from('services')
                        .update({
                          'name': nameController.text.trim(),
                          'description':
                              descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim(),
                          'category_id': selectedCategoryId,
                          'updated_at': DateTime.now().toIso8601String(),
                        })
                        .eq('id', service['id']);
                  } catch (e) {
                    if (mounted) {
                      _showSnackBar('Error updating service: $e', Colors.red);
                    }
                  } finally {
                    if (mounted) setState(() => _isProcessing = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Delete Service
  Future<void> _deleteService(Map<String, dynamic> service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              'Delete Service',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete '${service['name']}'?",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠️ This will also delete:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• ${service['variant_count']} option${service['variant_count'] != 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Text(
                    '• All barber assignments',
                    style: TextStyle(fontSize: 13),
                  ),
                  const Text(
                    '• All appointments with this service',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.red,
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);

      try {
        await supabase.from('services').delete().eq('id', service['id']);

        await _loadServices();

        if (mounted) {
          _showSnackBar('Service deleted successfully', Colors.green);
        }
      } catch (e) {
        debugPrint('Error deleting service: $e');
        if (mounted) {
          _showSnackBar('Error deleting service: $e', Colors.red);
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

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

  // Filter services based on search and category
  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((service) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          service['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (service['description']?.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ??
              false);

      final matchesCategory =
          _selectedCategoryId == null ||
          service['category_id'] == _selectedCategoryId;

      return matchesSearch && matchesCategory;
    }).toList();
  }

  // ============================================
  // ADD SERVICE CARD (WEB)
  // ============================================

  Widget _buildAddServiceCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: InkWell(
        onTap: _isProcessing
            ? null
            : () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddServiceScreen(salonId: widget.salonId),
                  ),
                );
                if (result == true) {
                  await _loadServices();
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // colors: [
              //   Color(0xFFFF6B8B),
              //   Color(0xFFFF9E6B),
              // ],
              colors: [
                Color.fromARGB(255, 248, 174, 190),
                Color.fromARGB(255, 245, 164, 211),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  size: 40, // Reduced from 48 to 40
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12), // Reduced from 16 to 12
              const Text(
                'Add New Service',
                style: TextStyle(
                  fontSize: 15, // Reduced from 16 to 15
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4), // Reduced from 8 to 4
              Text(
                'Create a new service\nfor your salon',
                style: TextStyle(
                  fontSize: 11, // Reduced from 12 to 11
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // ADD SERVICE CARD (MOBILE)
  // ============================================

  Widget _buildAddServiceCardMobile() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: InkWell(
        onTap: _isProcessing
            ? null
            : () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddServiceScreen(salonId: widget.salonId),
                  ),
                );
                if (result == true) {
                  await _loadServices();
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16), // Reduced from 24 to 16
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 248, 174, 190),
                Color.fromARGB(255, 245, 164, 211),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10), // Reduced from 12 to 10
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  size: 28, // Reduced from 32 to 28
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12), // Reduced from 16 to 12
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add New Service',
                      style: TextStyle(
                        fontSize: 15, // Reduced from 16 to 15
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    // const SizedBox(height: 2), // Reduced from 4 to 2
                    // Text(
                    //   'Create a new service for your salon',
                    //   style: TextStyle(
                    //     fontSize: 11, // Reduced from 12 to 11
                    //     color: Colors.white70,
                    //   ),
                    // ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14, // Reduced from 16 to 14
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // SERVICE CARD (WEB) - WITH ALTERNATING COLORS
  // ============================================

  Widget _buildServiceCardWeb(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isExpanded = _expandedServices.contains(service['id']);
    final accentColor = const Color(0xFFFF6B8B);
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cardColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
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
                      color: accentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.grey[800],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service['category_name'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Service Action Buttons
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.blue,
                          size: 20,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _editService(service),
                        tooltip: 'Edit Service',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _deleteService(service),
                        tooltip: 'Delete Service',
                      ),
                      if (hasVariants)
                        IconButton(
                          icon: AnimatedRotation(
                            duration: const Duration(milliseconds: 300),
                            turns: isExpanded ? 0.5 : 0.0,
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.grey,
                            ),
                          ),
                          onPressed: () => _toggleExpand(service['id']),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Description
            if (service['description'] != null &&
                service['description'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service['description'],
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Variants Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Options',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _showAddVariantDialog(service),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Option'),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (hasVariants && isExpanded) ...[
                    ...variants.map((variant) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.local_offer,
                                color: Colors.orange,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${variant['gender_name']} • ${variant['age_name']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rs. ${variant['price']} | ${variant['duration']} mins',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _showEditVariantDialog(
                                          service,
                                          variant,
                                        ),
                                  tooltip: 'Edit Option',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _deleteVariant(service, variant),
                                  tooltip: 'Delete Option',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else if (!hasVariants) ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No options added yet',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Click "Add Option" to add gender and age-based pricing',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
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

  // ============================================
  // SERVICE CARD (MOBILE) - WITH ALTERNATING COLORS
  // ============================================

  Widget _buildServiceCardMobile(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isExpanded = _expandedServices.contains(service['id']);
    final accentColor = const Color(0xFFFF6B8B);
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cardColor,
        ),
        child: Column(
          children: [
            // Service Header
            InkWell(
              onTap: hasVariants ? () => _toggleExpand(service['id']) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForName(service['icon_name']),
                        color: accentColor,
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
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                service['category_name'],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (hasVariants) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${variants.length} options',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.blue,
                            size: 20,
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _editService(service),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _deleteService(service),
                        ),
                        if (hasVariants)
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Description
            if (service['description'] != null &&
                service['description'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  service['description'],
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),

            // Variants Section
            if (hasVariants && isExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Options',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _showAddVariantDialog(service),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Option'),
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...variants.map((variant) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.local_offer,
                                color: Colors.orange,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${variant['gender_name']} • ${variant['age_name']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${variant['price']} | ${variant['duration']} mins',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _showEditVariantDialog(
                                          service,
                                          variant,
                                        ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _deleteVariant(service, variant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // WEB VIEW
  // ============================================

  Widget _buildWebView() {
    final filteredServices = _filteredServices;

    if (filteredServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No services added yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddServiceScreen(salonId: widget.salonId),
                        ),
                      );
                      if (result == true) {
                        await _loadServices();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add Your First Service'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: filteredServices.length + 1,
      itemBuilder: (context, index) {
        if (index == filteredServices.length) {
          return _buildAddServiceCard();
        }
        final service = filteredServices[index];
        return _buildServiceCardWeb(service, index);
      },
    );
  }

  // ============================================
  // MOBILE VIEW
  // ============================================

  Widget _buildMobileView() {
    final filteredServices = _filteredServices;

    if (filteredServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No services added yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddServiceScreen(salonId: widget.salonId),
                        ),
                      );
                      if (result == true) {
                        await _loadServices();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add Your First Service'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredServices.length + 1,
      itemBuilder: (context, index) {
        if (index == filteredServices.length) {
          return _buildAddServiceCardMobile();
        }
        final service = filteredServices[index];
        return _buildServiceCardMobile(service, index);
      },
    );
  }

  IconData _getIconForName(String? iconName) {
    switch (iconName) {
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
      case 'cut':
        return Icons.cut;
      default:
        return Icons.build;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final hasVariants = _services.any((s) => s['has_variants'] == true);

    return Scaffold(
      appBar: AppBar(
        title: Text('Services - ${widget.salonName}'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        actions: [
          if (hasVariants)
            IconButton(
              icon: const Icon(Icons.expand),
              onPressed: _expandAllServices,
              tooltip: 'Expand All',
            ),
          if (hasVariants)
            IconButton(
              icon: const Icon(Icons.compress),
              onPressed: _collapseAllServices,
              tooltip: 'Collapse All',
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _isProcessing
                ? null
                : () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            AddServiceScreen(salonId: widget.salonId),
                      ),
                    );
                    if (result == true) {
                      await _loadServices();
                    }
                  },
            tooltip: 'Add New Service',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : Column(
              children: [
                // Search and Filter Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search services...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFFF6B8B),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Category filter chips
                      SizedBox(
                        height: 45,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            FilterChip(
                              label: const Text('All'),
                              selected: _selectedCategoryId == null,
                              onSelected: (_) =>
                                  setState(() => _selectedCategoryId = null),
                              selectedColor: const Color(
                                0xFFFF6B8B,
                              ).withValues(alpha: 0.2),
                              checkmarkColor: const Color(0xFFFF6B8B),
                            ),
                            const SizedBox(width: 8),
                            ..._categories.map((category) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category['display_name']),
                                  selected:
                                      _selectedCategoryId == category['id'],
                                  onSelected: (_) => setState(() {
                                    _selectedCategoryId = category['id'] as int;
                                  }),
                                  selectedColor: const Color(
                                    0xFFFF6B8B,
                                  ).withValues(alpha: 0.2),
                                  checkmarkColor: const Color(0xFFFF6B8B),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Services List
                Expanded(child: isWeb ? _buildWebView() : _buildMobileView()),
              ],
            ),
    );
  }
}
