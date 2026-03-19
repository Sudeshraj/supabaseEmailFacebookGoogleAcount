// screens/owner/add_barber_service_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddBarberServiceScreen extends StatefulWidget {
  final String salonId;
  final String barberId;
  final int? salonBarberId;
  final String? barberName;

  const AddBarberServiceScreen({
    super.key,
    required this.salonId,
    required this.barberId,
    this.salonBarberId,
    this.barberName,
  });

  @override
  State<AddBarberServiceScreen> createState() => _AddBarberServiceScreenState();
}

class _AddBarberServiceScreenState extends State<AddBarberServiceScreen> {
  final supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _services = [];
  Map<String, Set<int>> _selectedVariants = {}; // serviceId -> set of variantIds
  int? _salonBarberId;
  
  // For search/filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Get salon_barber_id if not provided
      if (widget.salonBarberId == null) {
        final salonBarberResponse = await supabase
            .from('salon_barbers')
            .select('id')
            .eq('barber_id', widget.barberId)
            .eq('salon_id', int.parse(widget.salonId))
            .maybeSingle();

        if (salonBarberResponse != null) {
          _salonBarberId = salonBarberResponse['id'] as int;
        } else {
          throw Exception('Barber not found in this salon');
        }
      } else {
        _salonBarberId = widget.salonBarberId;
      }

      // Get already assigned services to disable them
      final existingServices = await supabase
          .from('barber_services')
          .select('service_id, variant_id')
          .eq('salon_barber_id', _salonBarberId!)
          .eq('is_active', true);

      final Set<String> assignedServiceKeys = {};
      for (var item in existingServices) {
        if (item['variant_id'] == null) {
          assignedServiceKeys.add('service_${item['service_id']}');
        } else {
          assignedServiceKeys.add('variant_${item['variant_id']}');
        }
      }

      // Load services with variants
      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            category_id,
            categories!inner (
              id,
              name
            )
          ''')
          .eq('is_active', true)
          .order('name');

      final variantsResponse = await supabase
          .from('service_variants')
          .select('''
            id,
            service_id,
            price,
            duration,
            genders!inner (
              id,
              name,
              display_name
            ),
            age_categories!inner (
              id,
              name,
              display_name,
              min_age,
              max_age
            )
          ''')
          .eq('is_active', true);

      // Group variants by service
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }

        final gender = variant['genders'] as Map<String, dynamic>;
        final age = variant['age_categories'] as Map<String, dynamic>;
        final variantId = variant['id'] as int;

        variantsByService[serviceId]!.add({
          'id': variantId,
          'price': variant['price'],
          'duration': variant['duration'],
          'gender_name': gender['display_name'],
          'gender_original': gender['name'],
          'age_name': age['display_name'],
          'display_text': '${gender['display_name']} • ${age['display_name']}',
          'isAssigned': assignedServiceKeys.contains('variant_$variantId'),
        });
      }

      // Build services list
      final List<Map<String, dynamic>> processedServices = [];
      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final variants = variantsByService[serviceId] ?? [];
        final category = service['categories'] as Map<String, dynamic>?;
        final categoryName = category?['name'] ?? 'other';

        // Sort variants by gender and age
        variants.sort((a, b) {
          if (a['gender_original'] != b['gender_original']) {
            return a['gender_original'].compareTo(b['gender_original']);
          }
          return a['age_name'].compareTo(b['age_name']);
        });

        // Check if full service is assigned
        final isFullServiceAssigned = assignedServiceKeys.contains('service_$serviceId');

        processedServices.add({
          'id': serviceId,
          'name': service['name'] ?? 'Unknown',
          'category_name': categoryName,
          'description': service['description'] ?? '',
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variantCount': variants.length,
          'isFullServiceAssigned': isFullServiceAssigned,
          'allVariantsAssigned': variants.isNotEmpty && variants.every((v) => v['isAssigned'] == true),
        });
      }

      setState(() {
        _services = processedServices;
      });

    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleVariant(String serviceId, int variantId) {
    setState(() {
      if (!_selectedVariants.containsKey(serviceId)) {
        _selectedVariants[serviceId] = {};
      }

      if (_selectedVariants[serviceId]!.contains(variantId)) {
        _selectedVariants[serviceId]!.remove(variantId);
        if (_selectedVariants[serviceId]!.isEmpty) {
          _selectedVariants.remove(serviceId);
        }
      } else {
        _selectedVariants[serviceId]!.add(variantId);
      }
    });
  }

  void _toggleFullService(String serviceId) {
    setState(() {
      if (_selectedVariants.containsKey(serviceId)) {
        _selectedVariants.remove(serviceId);
      } else {
        _selectedVariants[serviceId] = {};
      }
    });
  }

  bool _isVariantSelected(String serviceId, int variantId) {
    return _selectedVariants[serviceId]?.contains(variantId) ?? false;
  }

  bool _isFullServiceSelected(String serviceId) {
    return _selectedVariants.containsKey(serviceId) && _selectedVariants[serviceId]!.isEmpty;
  }

  int _getSelectedCount() {
    int count = 0;
    _selectedVariants.forEach((serviceId, variants) {
      if (variants.isEmpty) {
        count += 1;
      } else {
        count += variants.length;
      }
    });
    return count;
  }

  Future<void> _saveServices() async {
    if (_selectedVariants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one service'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_salonBarberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barber not found in this salon'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      int addedCount = 0;

      for (var entry in _selectedVariants.entries) {
        final serviceId = int.parse(entry.key);
        final variantIds = entry.value;

        if (variantIds.isEmpty) {
          // Add full service (no variants)
          await supabase.from('barber_services').insert({
            'salon_barber_id': _salonBarberId!,
            'service_id': serviceId,
            'variant_id': null,
            'is_active': true,
          });
          addedCount++;
        } else {
          // Add variants
          for (int variantId in variantIds) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': _salonBarberId!,
              'service_id': serviceId,
              'variant_id': variantId,
              'is_active': true,
            });
            addedCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully added $addedCount service(s)'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Return true to indicate success and refresh previous screen
        Navigator.pop(context, true);
      }

    } catch (e) {
      debugPrint('❌ Error saving services: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Get unique categories for filter
  List<String> get _categories {
    final categories = _services.map((s) => s['category_name'] as String).toSet().toList();
    categories.sort();
    return categories;
  }

  // Filtered services based on search and category
  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((service) {
      // Category filter
      if (_selectedCategory != 'all' && service['category_name'] != _selectedCategory) {
        return false;
      }
      
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final name = (service['name'] as String).toLowerCase();
        if (!name.contains(_searchQuery)) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final selectedCount = _getSelectedCount();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Services'),
            if (widget.barberName != null)
              Text(
                'for ${widget.barberName}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        actions: [
          if (selectedCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$selectedCount selected',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          if (selectedCount > 0)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveServices,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(
                _isSaving ? 'Saving...' : 'Save',
                style: const TextStyle(color: Colors.white),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : Column(
              children: [
                // Search and Filter Bar
                Container(
                  padding: EdgeInsets.all(isWeb ? 16 : 12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      // Search field
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search services...',
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Category filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('All'),
                              selected: _selectedCategory == 'all',
                              onSelected: (_) {
                                setState(() {
                                  _selectedCategory = 'all';
                                });
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                              checkmarkColor: const Color(0xFFFF6B8B),
                            ),
                            const SizedBox(width: 8),
                            ..._categories.map((category) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category[0].toUpperCase() + category.substring(1)),
                                  selected: _selectedCategory == category,
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedCategory = category;
                                    });
                                  },
                                  selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
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
                Expanded(
                  child: _filteredServices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No services found',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.all(isWeb ? 24 : 16),
                          itemCount: _filteredServices.length,
                          itemBuilder: (context, index) {
                            final service = _filteredServices[index];
                            final serviceId = service['id'].toString();
                            final variants = service['variants'] as List;
                            final hasVariants = variants.isNotEmpty;
                            final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
                            final allVariantsAssigned = service['allVariantsAssigned'] == true;
                            final isFullServiceSelected = _isFullServiceSelected(serviceId);
                            
                            // If all variants are already assigned, disable the service
                            final isCompletelyAssigned = !hasVariants 
                                ? isFullServiceAssigned
                                : allVariantsAssigned;

                            return Opacity(
                              opacity: isCompletelyAssigned ? 0.5 : 1.0,
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isFullServiceSelected || _selectedVariants.containsKey(serviceId)
                                        ? const Color(0xFFFF6B8B)
                                        : Colors.grey[300]!,
                                    width: isFullServiceSelected || _selectedVariants.containsKey(serviceId) ? 2 : 1,
                                  ),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    leading: hasVariants
                                        ? Checkbox(
                                            value: isFullServiceSelected,
                                            onChanged: isCompletelyAssigned
                                                ? null
                                                : (_) => _toggleFullService(serviceId),
                                            activeColor: const Color(0xFFFF6B8B),
                                          )
                                        : Checkbox(
                                            value: _selectedVariants.containsKey(serviceId),
                                            onChanged: isCompletelyAssigned
                                                ? null
                                                : (_) => _toggleFullService(serviceId),
                                            activeColor: const Color(0xFFFF6B8B),
                                          ),
                                    title: Text(
                                      service['name'],
                                      style: TextStyle(
                                        fontWeight: (isFullServiceSelected || _selectedVariants.containsKey(serviceId))
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isCompletelyAssigned ? Colors.grey : Colors.black,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          service['category_name'][0].toUpperCase() + 
                                          service['category_name'].substring(1),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        if (isCompletelyAssigned)
                                          const Text(
                                            'Already assigned',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: hasVariants
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_selectedVariants.containsKey(serviceId) && 
                                                  _selectedVariants[serviceId]!.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFF6B8B),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    '${_selectedVariants[serviceId]!.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              const Icon(Icons.expand_more),
                                            ],
                                          )
                                        : null,
                                    children: hasVariants
                                        ? [
                                            Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(
                                                children: variants.map((variant) {
                                                  final variantId = variant['id'] as int;
                                                  final isAssigned = variant['isAssigned'] == true;
                                                  final isSelected = _isVariantSelected(serviceId, variantId);
                                                  
                                                  return Container(
                                                    margin: const EdgeInsets.only(bottom: 8),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: isSelected 
                                                            ? const Color(0xFFFF6B8B) 
                                                            : Colors.grey[300]!,
                                                      ),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: CheckboxListTile(
                                                      title: Text(variant['display_text']),
                                                      subtitle: Text(
                                                        'Rs. ${variant['price']} • ${variant['duration']} min',
                                                      ),
                                                      value: isSelected,
                                                      onChanged: isAssigned || isCompletelyAssigned
                                                          ? null
                                                          : (_) => _toggleVariant(serviceId, variantId),
                                                      activeColor: const Color(0xFFFF6B8B),
                                                      controlAffinity: ListTileControlAffinity.leading,
                                                      secondary: isAssigned
                                                          ? Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: Colors.green[100],
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: const Text(
                                                                'Assigned',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors.green,
                                                                ),
                                                              ),
                                                            )
                                                          : null,
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ]
                                        : [],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: selectedCount > 0
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveServices,
              backgroundColor: const Color(0xFFFF6B8B),
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save ($selectedCount)'),
            )
          : null,
    );
  }
}