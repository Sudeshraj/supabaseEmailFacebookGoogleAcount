import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';

class AddServiceScreen extends StatefulWidget {
  final int salonId;
  final int? salonBarberId;
  final String? barberName;
  final bool isEditing;
  final int? serviceId;
  
  const AddServiceScreen({
    super.key,
    required this.salonId,
    this.salonBarberId,
    this.barberName,
    this.isEditing = false,
    this.serviceId,
  });

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  // Controllers
  final TextEditingController _serviceNameController = TextEditingController();
  final TextEditingController _serviceDescriptionController = TextEditingController();
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
  
  // Mode
  String _mode = 'new_service';
  
  // Loading states
  bool _isLoadingData = true;
  bool _isLoading = false;

  // Validation errors
  String? _priceError;
  String? _durationError;
  String? _serviceNameError;

  // Icon suggestions
  final List<Map<String, dynamic>> _iconSuggestions = [
    {'icon': Icons.content_cut, 'name': 'content_cut', 'label': 'Hair Cut', 'color': 0xFFFF6B8B},
    {'icon': Icons.face, 'name': 'face', 'label': 'Face', 'color': 0xFF4CAF50},
    {'icon': Icons.face_retouching_natural, 'name': 'face_retouching_natural', 'label': 'Grooming', 'color': 0xFF2196F3},
    {'icon': Icons.spa, 'name': 'spa', 'label': 'Spa', 'color': 0xFF9C27B0},
    {'icon': Icons.handshake, 'name': 'handshake', 'label': 'Nails', 'color': 0xFFFF9800},
    {'icon': Icons.build, 'name': 'build', 'label': 'Service', 'color': 0xFF795548},
    {'icon': Icons.brush, 'name': 'brush', 'label': 'Makeup', 'color': 0xFFE91E63},
    {'icon': Icons.cut, 'name': 'cut', 'label': 'Hair Cut', 'color': 0xFFFF6B8B},
    {'icon': Icons.shower, 'name': 'shower', 'label': 'Shower', 'color': 0xFF00BCD4},
    {'icon': Icons.masks, 'name': 'masks', 'label': 'Masks', 'color': 0xFF607D8B},
    {'icon': Icons.palette, 'name': 'palette', 'label': 'Makeup', 'color': 0xFFE91E63},
    {'icon': Icons.spa_outlined, 'name': 'spa_outlined', 'label': 'Wellness', 'color': 0xFF9C27B0},
  ];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadData();
    _selectedIcon = _iconSuggestions.first['name'];
    
    if (widget.isEditing && widget.serviceId != null) {
      _loadServiceDataForEdit();
    }
    
    // Add listeners for real-time validation
    _variantPriceController.addListener(_validatePrice);
    _variantDurationController.addListener(_validateDuration);
    _serviceNameController.addListener(_validateServiceName);
  }

  @override
  void dispose() {
    _serviceNameController.dispose();
    _serviceDescriptionController.dispose();
    _variantPriceController.dispose();
    _variantDurationController.dispose();
    super.dispose();
  }

  // ============================================
  // VALIDATION METHODS
  // ============================================
  
  void _validateServiceName() {
    final String name = _serviceNameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _serviceNameError = null;
      });
      return;
    }
    
    // Check if service name already exists (only for new services, not for editing)
    if (!widget.isEditing && _mode == 'new_service') {
      final bool exists = _existingServices.any((service) => 
        service['name'].toString().toLowerCase() == name.toLowerCase()
      );
      
      if (exists) {
        setState(() {
          _serviceNameError = 'A service with this name already exists';
        });
      } else {
        setState(() {
          _serviceNameError = null;
        });
      }
    } else if (widget.isEditing) {
      // For editing, check if name exists for other services
      final bool exists = _existingServices.any((service) => 
        service['id'] != widget.serviceId && 
        service['name'].toString().toLowerCase() == name.toLowerCase()
      );
      
      if (exists) {
        setState(() {
          _serviceNameError = 'A service with this name already exists';
        });
      } else {
        setState(() {
          _serviceNameError = null;
        });
      }
    }
  }
  
  void _validatePrice() {
    final String priceText = _variantPriceController.text.trim();
    if (priceText.isEmpty) {
      setState(() {
        _priceError = null;
      });
      return;
    }
    
    final double? price = double.tryParse(priceText);
    if (price == null) {
      setState(() {
        _priceError = 'Please enter a valid number';
      });
    } else if (price <= 0) {
      setState(() {
        _priceError = 'Price must be greater than 0';
      });
    } else {
      setState(() {
        _priceError = null;
      });
    }
  }
  
  void _validateDuration() {
    final String durationText = _variantDurationController.text.trim();
    if (durationText.isEmpty) {
      setState(() {
        _durationError = null;
      });
      return;
    }
    
    final int? duration = int.tryParse(durationText);
    if (duration == null) {
      setState(() {
        _durationError = 'Please enter a valid number';
      });
    } else if (duration <= 0) {
      setState(() {
        _durationError = 'Duration must be greater than 0';
      });
    } else {
      setState(() {
        _durationError = null;
      });
    }
  }

  // ============================================
  // DATA LOADING
  // ============================================
  
  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    
    try {
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, description, icon_name, color, display_order, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');
      
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name, display_order, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');
      
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age, display_order, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');
      
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('name');
      
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _genders = List<Map<String, dynamic>>.from(gendersResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
        _existingServices = List<Map<String, dynamic>>.from(servicesResponse);
        
        if (_categories.isNotEmpty && _selectedCategoryId == null) {
          _selectedCategoryId = _categories.first['id'] as int;
        }
        
        _isLoadingData = false;
      });
      
      debugPrint('✅ Data loaded');
      
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() => _isLoadingData = false);
      if (mounted) {
        _showSnackBar('Error loading data: $e', Colors.red);
      }
    }
  }
  
  Future<void> _loadServiceDataForEdit() async {
    try {
      if (widget.serviceId == null) return;
      
      final serviceResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id')
          .eq('id', widget.serviceId!)
          .single();
      
      setState(() {
        _serviceNameController.text = serviceResponse['name'] ?? '';
        _serviceDescriptionController.text = serviceResponse['description'] ?? '';
        _selectedIcon = serviceResponse['icon_name'] ?? _iconSuggestions.first['name'];
        _selectedCategoryId = serviceResponse['category_id'];
      });
      
      final variantsResponse = await supabase
          .from('service_variants')
          .select('id, price, duration, salon_gender_id, salon_age_category_id')
          .eq('service_id', widget.serviceId!)
          .eq('is_active', true);
      
      for (var variant in variantsResponse) {
        final gender = _genders.firstWhere(
          (g) => g['id'] == variant['salon_gender_id'],
          orElse: () => {'display_name': 'Unknown'},
        );
        final ageCat = _ageCategories.firstWhere(
          (a) => a['id'] == variant['salon_age_category_id'],
          orElse: () => {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0},
        );
        
        _variants.add({
          'gender_id': variant['salon_gender_id'],
          'gender_name': _getGenderDisplayName(gender),
          'age_category_id': variant['salon_age_category_id'],
          'age_category_name': _getAgeCategoryDisplayName(ageCat),
          'price': variant['price'],
          'duration': variant['duration'],
          'variant_id': variant['id'],
        });
      }
      
      setState(() {});
      debugPrint('✅ Loaded service data for edit');
      
    } catch (e) {
      debugPrint('Error loading service data: $e');
    }
  }

  // ============================================
  // HELPER METHODS
  // ============================================
  
  String _getCategoryDisplayName(Map<String, dynamic> category) {
    return category['display_name'] ?? 'Unknown';
  }

  String _getGenderDisplayName(Map<String, dynamic> gender) {
    return gender['display_name'] ?? 'Unknown';
  }

  String _getAgeCategoryDisplayName(Map<String, dynamic> ageCat) {
    String name = ageCat['display_name'] ?? 'Unknown';
    if (ageCat['min_age'] != null && ageCat['max_age'] != null) {
      name = '$name (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
    }
    return name;
  }

  String _getServiceName(int serviceId) {
    final service = _existingServices.firstWhere(
      (s) => s['id'] == serviceId,
      orElse: () => {'name': 'Unknown'},
    );
    return service['name'];
  }

  bool _isVariantDuplicate() {
    return _variants.any((variant) {
      return variant['gender_id'] == _selectedGenderId &&
             variant['age_category_id'] == _selectedAgeCategoryId &&
             _variants.indexOf(variant) != _editingVariantIndex;
    });
  }

  // ============================================
  // VARIANT MANAGEMENT
  // ============================================
  
  void _saveVariant() {
    // Clear previous errors
    _validatePrice();
    _validateDuration();
    
    if (_selectedGenderId == null) {
      _showSnackBar('Please select a gender', Colors.orange);
      return;
    }
    if (_selectedAgeCategoryId == null) {
      _showSnackBar('Please select an age category', Colors.orange);
      return;
    }
    
    final price = double.tryParse(_variantPriceController.text.trim());
    final duration = int.tryParse(_variantDurationController.text.trim());
    
    if (price == null || price <= 0) {
      _showSnackBar('Please enter a valid price', Colors.orange);
      return;
    }
    if (duration == null || duration <= 0) {
      _showSnackBar('Please enter a valid duration', Colors.orange);
      return;
    }
    
    if (_isVariantDuplicate()) {
      _showSnackBar('This variant combination already exists!', Colors.orange);
      return;
    }
    
    final gender = _genders.firstWhere((g) => g['id'] == _selectedGenderId);
    final ageCat = _ageCategories.firstWhere((a) => a['id'] == _selectedAgeCategoryId);
    
    final newVariant = {
      'gender_id': _selectedGenderId,
      'gender_name': _getGenderDisplayName(gender),
      'age_category_id': _selectedAgeCategoryId,
      'age_category_name': _getAgeCategoryDisplayName(ageCat),
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
      
      _selectedGenderId = null;
      _selectedAgeCategoryId = null;
      _variantPriceController.clear();
      _variantDurationController.clear();
      _priceError = null;
      _durationError = null;
    });
    
    _showSnackBar('Variant added', Colors.green);
  }

  void _editVariant(int index) {
    final variant = _variants[index];
    setState(() {
      _editingVariantIndex = index;
      _selectedGenderId = variant['gender_id'];
      _selectedAgeCategoryId = variant['age_category_id'];
      _variantPriceController.text = variant['price'].toString();
      _variantDurationController.text = variant['duration'].toString();
      _validatePrice();
      _validateDuration();
    });
  }

  void _removeVariant(int index) {
    setState(() {
      _variants.removeAt(index);
      if (_editingVariantIndex == index) {
        _editingVariantIndex = -1;
        _selectedGenderId = null;
        _selectedAgeCategoryId = null;
        _variantPriceController.clear();
        _variantDurationController.clear();
        _priceError = null;
        _durationError = null;
      }
    });
    _showSnackBar('Variant removed', Colors.red);
  }

  // ============================================
  // CREATE/UPDATE SERVICE
  // ============================================
  
  Future<void> _createAndAddService() async {
    // Validation
    if (_mode == 'new_service' || widget.isEditing) {
      final serviceName = _serviceNameController.text.trim();
      if (serviceName.isEmpty) {
        _showSnackBar('Service name is required', Colors.orange);
        return;
      }
      
      // Check for duplicate service name
      if (_serviceNameError != null) {
        _showSnackBar(_serviceNameError!, Colors.orange);
        return;
      }
    } else {
      if (_selectedExistingServiceId == null) {
        _showSnackBar('Please select a service', Colors.orange);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      int serviceId;
      
      if (_mode == 'new_service' || widget.isEditing) {
        if (widget.isEditing && widget.serviceId != null) {
          serviceId = widget.serviceId!;
          
          final updateData = {
            'name': _serviceNameController.text.trim(),
            'description': _serviceDescriptionController.text.trim().isNotEmpty 
                ? _serviceDescriptionController.text.trim() : null,
            'category_id': _selectedCategoryId,
            'icon_name': _selectedIcon,
            'updated_at': DateTime.now().toIso8601String(),
          };
          
          await supabase
              .from('services')
              .update(updateData)
              .eq('id', serviceId);
          
          debugPrint('✅ Updated service: $serviceId');
          
          // Delete existing variants if any
          if (_variants.isNotEmpty) {
            await supabase
                .from('service_variants')
                .delete()
                .eq('service_id', serviceId);
          }
        } else {
          // Check again for duplicate before inserting
          final exists = _existingServices.any((service) => 
            service['name'].toString().toLowerCase() == _serviceNameController.text.trim().toLowerCase()
          );
          
          if (exists) {
            setState(() {
              _serviceNameError = 'A service with this name already exists';
              _isLoading = false;
            });
            _showSnackBar('A service with this name already exists', Colors.orange);
            return;
          }
          
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
          debugPrint('✅ Created new service: $serviceId');
        }
      } else {
        serviceId = _selectedExistingServiceId!;
        debugPrint('✅ Using existing service: $serviceId');
        
        // Delete existing variants for this service
        if (_variants.isNotEmpty) {
          await supabase
              .from('service_variants')
              .delete()
              .eq('service_id', serviceId);
        }
      }

      // Create variants if any
      if (_variants.isNotEmpty) {
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
          debugPrint('✅ Created variant: $variantId');
          
          if (widget.salonBarberId != null) {
            final existingBarberService = await supabase
                .from('barber_services')
                .select()
                .eq('salon_barber_id', widget.salonBarberId!)
                .eq('service_id', serviceId)
                .eq('variant_id', variantId)
                .maybeSingle();
            
            if (existingBarberService == null) {
              await supabase
                  .from('barber_services')
                  .insert({
                    'salon_barber_id': widget.salonBarberId!,
                    'service_id': serviceId,
                    'variant_id': variantId,
                    'custom_price': variant['price'],
                    'status': 'active',
                  });
              debugPrint('✅ Added to barber services');
            }
          }
        }
      } else if (widget.salonBarberId != null) {
        // For services without variants, add to barber_services without variant_id
        final existingBarberService = await supabase
            .from('barber_services')
            .select()
            .eq('salon_barber_id', widget.salonBarberId!)
            .eq('service_id', serviceId)
            .maybeSingle();
        
        if (existingBarberService == null) {
          final Map<String, dynamic> barberServiceData = {
            'salon_barber_id': widget.salonBarberId!,
            'service_id': serviceId,
            'status': 'active',
          };
          
          await supabase
              .from('barber_services')
              .insert(barberServiceData);
          debugPrint('✅ Added to barber services (no variants)');
        }
      }

      if (!mounted) return;

      String successMessage;
      if (_mode == 'new_service' || widget.isEditing) {
        if (_variants.isNotEmpty) {
          successMessage = "${_serviceNameController.text.trim()} has been ${widget.isEditing ? 'updated' : 'added'} successfully.\n\n✅ ${_variants.length} variant${_variants.length > 1 ? 's' : ''} ${widget.isEditing ? 'updated' : 'added'}";
        } else {
          successMessage = "${_serviceNameController.text.trim()} has been ${widget.isEditing ? 'updated' : 'added'} successfully.";
        }
      } else {
        if (_variants.isNotEmpty) {
          successMessage = "${_getServiceName(serviceId)} variants added successfully.\n\n✅ ${_variants.length} variant${_variants.length > 1 ? 's' : ''} added";
        } else {
          successMessage = "${_getServiceName(serviceId)} has been added successfully.";
        }
      }

      await showCustomAlert(
        context: context,
        title: widget.isEditing ? "✅ Service Updated!" : "🎉 Service Added!",
        message: successMessage,
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        // Handle duplicate key error specifically
        if (e.toString().contains('duplicate key value violates unique constraint')) {
          _showSnackBar('A service with this name already exists. Please use a different name.', Colors.orange);
          setState(() {
            _serviceNameError = 'A service with this name already exists';
          });
        } else {
          _showSnackBar('Error: $e', Colors.red);
        }
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
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================
  // UI BUILDERS
  // ============================================
  
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
            child: Icon(
              widget.isEditing ? Icons.edit : Icons.build,
              color: const Color(0xFFFF6B8B),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isEditing ? 'Edit Service' : 'Add Service',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            widget.barberName != null 
                ? '${widget.isEditing ? 'Edit' : 'Add'} service for ${widget.barberName}' 
                : widget.isEditing 
                    ? 'Update service details' 
                    : 'Create a new service',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    if (widget.salonBarberId == null) return const SizedBox();
    if (widget.isEditing) return const SizedBox();
    
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
                        _serviceNameError = null;
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
              initialValue: _selectedExistingServiceId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Select Service',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: _existingServices.map((service) {
                return DropdownMenuItem<int>(
                  value: service['id'] as int,
                  child: Text(
                    service['name'],
                    overflow: TextOverflow.ellipsis,
                  ),
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
    if (_categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: const Center(
          child: Text('No categories available. Please add categories first.'),
        ),
      );
    }
    
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
              final displayName = _getCategoryDisplayName(category);
              return FilterChip(
                label: Text(displayName),
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
            'Service Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
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
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              errorText: _serviceNameError,
              errorMaxLines: 2,
            ),
            onChanged: (value) {
              _validateServiceName();
              setState(() {});
            },
          ),
          const SizedBox(height: 16),

          const Text(
            'Description',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _serviceDescriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Describe what this service includes...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Service Icon',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: _iconSuggestions.map((iconData) {
                final isSelected = _selectedIcon == iconData['name'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIcon = iconData['name'];
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? Color(iconData['color']).withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected 
                            ? Color(iconData['color'])
                            : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          iconData['icon'],
                          size: 24,
                          color: isSelected 
                              ? Color(iconData['color'])
                              : Colors.grey[600],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          iconData['label'],
                          style: TextStyle(
                            fontSize: 9,
                            color: isSelected 
                                ? Color(iconData['color'])
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantForm() {
    if (_genders.isEmpty || _ageCategories.isEmpty) {
      return const SizedBox();
    }
    
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
                'Add Variants (Optional)',
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
                      _priceError = null;
                      _durationError = null;
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
                      'Gender',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedGenderId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.wc, color: Colors.grey, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      hint: const Text('Select gender'),
                      items: _genders.map((gender) {
                        return DropdownMenuItem<int>(
                          value: gender['id'] as int,
                          child: Text(
                            _getGenderDisplayName(gender),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                      'Age Category',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedAgeCategoryId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.timeline, color: Colors.grey, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      hint: const Text('Select age'),
                      items: _ageCategories.map((ageCat) {
                        return DropdownMenuItem<int>(
                          value: ageCat['id'] as int,
                          child: Text(
                            _getAgeCategoryDisplayName(ageCat),
                            overflow: TextOverflow.ellipsis,
                          ),
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

          // Price and Duration Row with Validation
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
                        prefixIcon: const Icon(Icons.currency_rupee, color: Colors.grey, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        errorText: _priceError,
                        errorMaxLines: 2,
                      ),
                      onChanged: (value) {
                        _validatePrice();
                        setState(() {});
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
                      controller: _variantDurationController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g., 30',
                        prefixIcon: const Icon(Icons.timer, color: Colors.grey, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        errorText: _durationError,
                        errorMaxLines: 2,
                      ),
                      onChanged: (value) {
                        _validateDuration();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
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
      return const SizedBox();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
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
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  child: Text('${index + 1}', style: const TextStyle(color: Color(0xFFFF6B8B))),
                ),
                title: Text(
                  '${variant['gender_name']} - ${variant['age_category_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Rs. ${variant['price']} | ${variant['duration']} mins',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                      onPressed: () => _editVariant(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
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
    bool isEnabled = false;
    
    if (_mode == 'new_service' || widget.isEditing) {
      // For new service or edit mode - need service name and no error
      isEnabled = _serviceNameController.text.trim().isNotEmpty && _serviceNameError == null;
    } else {
      // For add to existing mode - need to select a service
      isEnabled = _selectedExistingServiceId != null;
    }
    
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || !isEnabled) ? null : _createAndAddService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.isEditing ? Icons.save : Icons.add, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    widget.isEditing ? 'Update Service' : 'Add Service',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.barberName != null 
            ? '${widget.isEditing ? 'Edit' : 'Add'} Service - ${widget.barberName}' 
            : widget.isEditing ? 'Edit Service' : 'Add New Service'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : Container(
              color: Colors.grey[50],
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 24),
                              if (widget.salonBarberId != null && !widget.isEditing) 
                                _buildModeSelector(),
                              if (widget.salonBarberId != null && !widget.isEditing) 
                                const SizedBox(height: 24),
                              _buildCategorySection(),
                              const SizedBox(height: 24),
                              if (_mode == 'new_service' || widget.isEditing) ...[
                                _buildServiceInfoForm(),
                                const SizedBox(height: 24),
                              ],
                              _buildVariantForm(),
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
}