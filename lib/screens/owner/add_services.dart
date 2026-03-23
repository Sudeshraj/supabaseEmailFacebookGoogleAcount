import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';

class AddServiceScreen extends StatefulWidget {
  final int salonId;
  final int? salonBarberId;
  final String? barberName;
  
  const AddServiceScreen({
    super.key, 
    required this.salonId,
    this.salonBarberId,
    this.barberName,
  });

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  // Service Controllers
  final TextEditingController _serviceNameController = TextEditingController();
  final TextEditingController _serviceDescriptionController = TextEditingController();

  // Variant Controllers
  final TextEditingController _variantPriceController = TextEditingController();
  final TextEditingController _variantDurationController = TextEditingController();

  // Selected items
  int? _selectedCategoryId;
  int? _selectedGenderId;
  int? _selectedAgeCategoryId;
  int? _selectedExistingServiceId;
  String? _selectedIcon;
  
  // Available options
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _genders = [];
  List<Map<String, dynamic>> _ageCategories = [];
  List<Map<String, dynamic>> _existingServices = [];
  
  // Variants list
  final List<Map<String, dynamic>> _variants = [];
  int _editingVariantIndex = -1;
  
  // Mode: 'new_service' or 'add_to_existing'
  String _mode = 'new_service';
  
  bool _isLoadingData = true;
  bool _isLoading = false;

  // Icon suggestions
  final List<Map<String, dynamic>> _iconSuggestions = [
    {'icon': Icons.content_cut, 'name': 'content_cut', 'label': 'Hair Cut'},
    {'icon': Icons.face, 'name': 'face', 'label': 'Face'},
    {'icon': Icons.face_retouching_natural, 'name': 'face_retouching_natural', 'label': 'Grooming'},
    {'icon': Icons.spa, 'name': 'spa', 'label': 'Spa'},
    {'icon': Icons.handshake, 'name': 'handshake', 'label': 'Nails'},
    {'icon': Icons.build, 'name': 'build', 'label': 'Service'},
    {'icon': Icons.brush, 'name': 'brush', 'label': 'Makeup'},
    {'icon': Icons.cleaning_services, 'name': 'cleaning_services', 'label': 'Cleaning'},
    {'icon': Icons.message, 'name': 'massage', 'label': 'Massage'},
    {'icon': Icons.health_and_safety, 'name': 'health_and_safety', 'label': 'Wellness'},
    {'icon': Icons.accessibility_new, 'name': 'accessibility_new', 'label': 'Special'},
    {'icon': Icons.star, 'name': 'star', 'label': 'Premium'},
  ];

  // Form key
  final _formKey = GlobalKey<FormState>();

  // Responsive layout helpers
  bool get _isWeb => MediaQuery.of(context).size.width > 800;

  final supabase = Supabase.instance.client;

  @override
  void dispose() {
    _serviceNameController.dispose();
    _serviceDescriptionController.dispose();
    _variantPriceController.dispose();
    _variantDurationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _selectedIcon = _iconSuggestions.first['name'];
  }

  // Load salon-specific data
  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    
    try {
      // Load categories for this salon
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('''
            id,
            display_order,
            is_active,
            custom_name,
            category_id,
            categories!inner (
              id,
              name,
              description,
              icon_name,
              color
            )
          ''')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');
      
      // Load genders for this salon
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('''
            id,
            display_order,
            is_active,
            gender_id,
            genders!inner (
              id,
              name,
              display_name,
              icon_name
            )
          ''')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');
      
      // Load age categories for this salon
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('''
            id,
            display_order,
            is_active,
            min_age,
            max_age,
            age_category_id,
            age_categories!inner (
              id,
              name,
              display_name,
              icon_name
            )
          ''')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');
      
      // Load existing services for this salon
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, category_id, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('name');
      
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _genders = List<Map<String, dynamic>>.from(gendersResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
        _existingServices = List<Map<String, dynamic>>.from(servicesResponse);
        
        // Select first category by default
        if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first['id'] as int;
        }
        
        _isLoadingData = false;
      });
      
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() => _isLoadingData = false);
      if (mounted) {
        _showSnackBar('Error loading data', Colors.red);
      }
    }
  }

  // Get display name for category
  String _getCategoryDisplayName(Map<String, dynamic> category) {
    if (category['custom_name'] != null && category['custom_name'].toString().isNotEmpty) {
      return category['custom_name'];
    }
    final innerCat = category['categories'] as Map?;
    return innerCat?['name'] ?? 'Unknown';
  }

  // Get display name for gender
  String _getGenderDisplayName(Map<String, dynamic> gender) {
    final innerGender = gender['genders'] as Map?;
    return innerGender?['display_name'] ?? innerGender?['name'] ?? 'Unknown';
  }

  // Get display name for age category
  String _getAgeCategoryDisplayName(Map<String, dynamic> ageCat) {
    final innerAge = ageCat['age_categories'] as Map?;
    String name = innerAge?['display_name'] ?? innerAge?['name'] ?? 'Unknown';
    if (ageCat['min_age'] != null && ageCat['max_age'] != null) {
      name = '$name (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
    }
    return name;
  }

  // Get service name by ID
  String _getServiceName(int serviceId) {
    final service = _existingServices.firstWhere(
      (s) => s['id'] == serviceId,
      orElse: () => {'name': 'Unknown'},
    );
    return service['name'];
  }

  // Check if variant combination already exists
  bool _isVariantDuplicate() {
    return _variants.any((variant) {
      return variant['gender_id'] == _selectedGenderId &&
             variant['age_category_id'] == _selectedAgeCategoryId &&
             _variants.indexOf(variant) != _editingVariantIndex;
    });
  }

  // Add or update variant
  void _saveVariant() {
    if (_selectedGenderId == null) {
      _showSnackBar('Please select a gender', Colors.red);
      return;
    }
    if (_selectedAgeCategoryId == null) {
      _showSnackBar('Please select an age category', Colors.red);
      return;
    }
    
    final price = double.tryParse(_variantPriceController.text.trim());
    final duration = int.tryParse(_variantDurationController.text.trim());
    
    if (price == null) {
      _showSnackBar('Please enter a valid price', Colors.red);
      return;
    }
    if (duration == null || duration <= 0) {
      _showSnackBar('Please enter a valid duration', Colors.red);
      return;
    }
    
    // Check duplicate
    if (_isVariantDuplicate()) {
      _showSnackBar('This variant combination already exists!', Colors.red);
      return;
    }
    
    final newVariant = {
      'gender_id': _selectedGenderId,
      'gender_name': _getGenderDisplayName(
        _genders.firstWhere((g) => g['id'] == _selectedGenderId)
      ),
      'age_category_id': _selectedAgeCategoryId,
      'age_category_name': _getAgeCategoryDisplayName(
        _ageCategories.firstWhere((a) => a['id'] == _selectedAgeCategoryId)
      ),
      'price': price,
      'duration': duration,
    };
    
    setState(() {
      if (_editingVariantIndex >= 0) {
        _variants[_editingVariantIndex] = newVariant;
        _editingVariantIndex = -1;
      } else {
        _variants.add(newVariant);
      }
      
      // Clear form
      _selectedGenderId = null;
      _selectedAgeCategoryId = null;
      _variantPriceController.clear();
      _variantDurationController.clear();
    });
  }

  // Edit variant
  void _editVariant(int index) {
    final variant = _variants[index];
    setState(() {
      _editingVariantIndex = index;
      _selectedGenderId = variant['gender_id'];
      _selectedAgeCategoryId = variant['age_category_id'];
      _variantPriceController.text = variant['price'].toString();
      _variantDurationController.text = variant['duration'].toString();
    });
  }

  // Remove variant
  void _removeVariant(int index) {
    setState(() {
      _variants.removeAt(index);
      if (_editingVariantIndex == index) {
        _editingVariantIndex = -1;
        _selectedGenderId = null;
        _selectedAgeCategoryId = null;
        _variantPriceController.clear();
        _variantDurationController.clear();
      }
    });
  }

  // Create service and add to barber
  Future<void> _createAndAddService() async {
    if (_mode == 'new_service') {
      if (_serviceNameController.text.trim().isEmpty) {
        _showSnackBar('Service name is required', Colors.red);
        return;
      }
    }
    
    if (_variants.isEmpty) {
      _showSnackBar('Please add at least one variant', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      int serviceId;
      
      if (_mode == 'new_service') {
        // Create new service with icon
        final serviceData = {
          'salon_id': widget.salonId,
          'name': _serviceNameController.text.trim(),
          'description': _serviceDescriptionController.text.trim().isNotEmpty 
              ? _serviceDescriptionController.text.trim() : null,
          'category_id': _selectedCategoryId,
          'icon_name': _selectedIcon,
          'is_active': true,
          'created_by': supabase.auth.currentUser?.id,
        };

        final serviceResponse = await supabase
            .from('services')
            .insert(serviceData)
            .select()
            .single();

        serviceId = serviceResponse['id'];
      } else {
        // Use existing service
        serviceId = _selectedExistingServiceId!;
      }

      // Create variants
      for (var variant in _variants) {
        final variantData = {
          'service_id': serviceId,
          'salon_gender_id': variant['gender_id'],
          'salon_age_category_id': variant['age_category_id'],
          'price': variant['price'],
          'duration': variant['duration'],
          'is_active': true,
        };
        
        final variantResponse = await supabase
            .from('service_variants')
            .insert(variantData)
            .select()
            .single();
        
        final variantId = variantResponse['id'];
        
        // If this is for a barber, add to barber_services
        if (widget.salonBarberId != null) {
          await supabase
              .from('barber_services')
              .insert({
                'salon_barber_id': widget.salonBarberId,
                'service_id': serviceId,
                'variant_id': variantId,
                'custom_price': variant['price'],
                'status': 'active',
              });
        }
      }

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "🎉 Service Added!",
        message: _mode == 'new_service'
            ? "${_serviceNameController.text.trim()} has been added successfully.\n\n✅ ${_variants.length} variants added"
            : "${_getServiceName(serviceId)} variants added successfully.\n\n✅ ${_variants.length} variants added",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

    } catch (e) {
      debugPrint('❌ Error creating service: $e');
      if (mounted) {
        _showSnackBar('Error creating service: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.barberName != null 
            ? 'Add Service - ${widget.barberName}' 
            : 'Add New Service'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: _isWeb,
        elevation: 0,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : Container(
              color: Colors.grey[50],
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: _isWeb ? 900 : double.infinity),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(_isWeb ? 32 : 16),
                    child: Card(
                      elevation: _isWeb ? 4 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(_isWeb ? 32 : 20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 24),
                              _buildModeSelector(),
                              const SizedBox(height: 24),
                              _buildCategorySection(),
                              const SizedBox(height: 24),
                              if (_mode == 'new_service') ...[
                                _buildServiceInfoForm(),
                                const SizedBox(height: 24),
                              ],
                              _buildVariantForm(),
                              const SizedBox(height: 24),
                              _buildVariantsList(),
                              const SizedBox(height: 32),
                              _buildCreateButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.build,
              color: Color(0xFFFF6B8B),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add Service',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.barberName != null 
                ? 'Add service variants for ${widget.barberName}' 
                : 'Create a new service with multiple variants',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    if (widget.salonBarberId == null) return const SizedBox();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Type',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('New Service'),
                  selected: _mode == 'new_service',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _mode = 'new_service';
                        _selectedExistingServiceId = null;
                        _serviceNameController.clear();
                        _serviceDescriptionController.clear();
                      });
                    }
                  },
                  selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: _mode == 'new_service' ? const Color(0xFFFF6B8B) : Colors.grey[700],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Add to Existing'),
                  selected: _mode == 'add_to_existing',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _mode = 'add_to_existing';
                        _serviceNameController.clear();
                        _serviceDescriptionController.clear();
                      });
                    }
                  },
                  selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: _mode == 'add_to_existing' ? const Color(0xFFFF6B8B) : Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          if (_mode == 'add_to_existing') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedExistingServiceId,
              decoration: InputDecoration(
                labelText: 'Select Service',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _existingServices.map((service) {
                return DropdownMenuItem<int>(
                  value: service['id'] as int,
                  child: Text(service['name']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedExistingServiceId = value;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Category',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((category) {
              final isSelected = _selectedCategoryId == category['id'];
              return FilterChip(
                label: Text(_getCategoryDisplayName(category)),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedCategoryId = category['id'] as int;
                    }
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                checkmarkColor: const Color(0xFFFF6B8B),
                labelStyle: TextStyle(
                  color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceInfoForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // Service Name
          const Text(
            'Service Name *',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _serviceNameController,
            decoration: InputDecoration(
              hintText: 'e.g., Hair Cut, Facial, Massage',
              prefixIcon: const Icon(Icons.build, color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          const Text(
            'Description',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _serviceDescriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Describe what this service includes...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Icon Selection
          const Text(
            'Service Icon',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose an icon for your service',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _iconSuggestions.map((iconData) {
                    final isSelected = _selectedIcon == iconData['name'];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedIcon = iconData['name'];
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected 
                                ? const Color(0xFFFF6B8B)
                                : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              iconData['icon'],
                              size: 28,
                              color: isSelected 
                                  ? const Color(0xFFFF6B8B)
                                  : Colors.grey[600],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              iconData['label'],
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected 
                                    ? const Color(0xFFFF6B8B)
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Service Variants',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_editingVariantIndex >= 0)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _editingVariantIndex = -1;
                      _selectedGenderId = null;
                      _selectedAgeCategoryId = null;
                      _variantPriceController.clear();
                      _variantDurationController.clear();
                    });
                  },
                  child: const Text('Cancel Edit'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Add different pricing options for gender and age combinations',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Gender and Age Category Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gender *',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _selectedGenderId,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.wc, color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      hint: const Text('Select gender'),
                      items: _genders.map((gender) {
                        return DropdownMenuItem<int>(
                          value: gender['id'] as int,
                          child: Text(_getGenderDisplayName(gender)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedGenderId = value;
                        });
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
                      'Age Category *',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _selectedAgeCategoryId,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.timeline, color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      hint: const Text('Select age'),
                      items: _ageCategories.map((ageCat) {
                        return DropdownMenuItem<int>(
                          value: ageCat['id'] as int,
                          child: Text(_getAgeCategoryDisplayName(ageCat)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedAgeCategoryId = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

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
                      controller: _variantPriceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g., 1500',
                        prefixIcon: const Icon(Icons.currency_rupee, color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    const Text(
                      'Duration (mins) *',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _variantDurationController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g., 30',
                        prefixIcon: const Icon(Icons.timer, color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Add/Update Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveVariant,
              style: ElevatedButton.styleFrom(
                backgroundColor: _editingVariantIndex >= 0 ? Colors.orange : const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _editingVariantIndex >= 0 ? 'Update Variant' : 'Add Variant',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsList() {
    if (_variants.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.local_offer, size: 48, color: Colors.grey), // Changed from pricetag to local_offer
              SizedBox(height: 12),
              Text(
                'No variants added yet',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 4),
              Text(
                'Add variants to create different pricing options',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Added Variants',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _variants.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final variant = _variants[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  '${variant['gender_name']} - ${variant['age_category_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Rs. ${variant['price']} | ${variant['duration']} mins',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editVariant(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeVariant(index),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    final isDisabled = _isLoading || 
        (_mode == 'new_service' && _serviceNameController.text.trim().isEmpty) ||
        (_mode == 'add_to_existing' && _selectedExistingServiceId == null) ||
        _variants.isEmpty;
    
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _createAndAddService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Creating...'),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Add Service',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }
}