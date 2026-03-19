// screens/owner/add_barber_service_screen.dart
import 'package:flutter/material.dart';
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
  final Map<String, Set<int>> _selectedVariants = {};
  int? _salonBarberId;
  
  // For search/filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';
  
  // For expansion state
  final Set<String> _expandedServices = {};

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

      // Get already assigned services
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

        // Sort variants
        variants.sort((a, b) {
          if (a['gender_original'] != b['gender_original']) {
            return a['gender_original'].compareTo(b['gender_original']);
          }
          return a['age_name'].compareTo(b['age_name']);
        });

        final isFullServiceAssigned = assignedServiceKeys.contains('service_$serviceId');
        final allVariantsAssigned = variants.isNotEmpty && variants.every((v) => v['isAssigned'] == true);

        processedServices.add({
          'id': serviceId,
          'name': service['name'] ?? 'Unknown',
          'category_name': categoryName,
          'description': service['description'] ?? '',
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variantCount': variants.length,
          'isFullServiceAssigned': isFullServiceAssigned,
          'allVariantsAssigned': allVariantsAssigned,
          'minPrice': variants.isNotEmpty 
              ? variants.map((v) => v['price'] as double).reduce((a, b) => a < b ? a : b)
              : 0,
          'maxPrice': variants.isNotEmpty
              ? variants.map((v) => v['price'] as double).reduce((a, b) => a > b ? a : b)
              : 0,
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

  void _toggleExpand(String serviceId) {
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
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
          await supabase.from('barber_services').insert({
            'salon_barber_id': _salonBarberId!,
            'service_id': serviceId,
            'variant_id': null,
            'is_active': true,
          });
          addedCount++;
        } else {
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

  List<String> get _categories {
    final categories = _services.map((s) => s['category_name'] as String).toSet().toList();
    categories.sort();
    return categories;
  }

  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((service) {
      if (_selectedCategory != 'all' && service['category_name'] != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final name = (service['name'] as String).toLowerCase();
        if (!name.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Color _getCategoryColor(String categoryName) {
    switch (categoryName) {
      case 'hair': return Colors.blue;
      case 'skin': return Colors.pink;
      case 'grooming': return Colors.orange;
      case 'wellness': return Colors.green;
      case 'nails': return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final int selectedCount = _getSelectedCount(); // FIXED: Changed from _selectedCount to selectedCount
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Services',
              style: TextStyle(fontSize: isWeb ? 20 : 18),
            ),
            if (widget.barberName != null)
              Text(
                'for ${widget.barberName}',
                style: TextStyle(
                  fontSize: isWeb ? 14 : 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        actions: [
          if (selectedCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '$selectedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.save, color: Colors.white),
                      onPressed: _saveServices,
                      tooltip: 'Save Services',
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : Column(
              children: [
                _buildSearchAndFilterBar(isWeb, padding),
                Expanded(
                  child: _filteredServices.isEmpty
                      ? _buildEmptyState(isWeb)
                      : isWeb
                          ? _buildWebView(padding, selectedCount) // FIXED: Pass selectedCount
                          : _buildMobileView(padding, selectedCount), // FIXED: Pass selectedCount
                ),
              ],
            ),
      floatingActionButton: selectedCount > 0 && !isWeb
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

  Widget _buildSearchAndFilterBar(bool isWeb, double padding) {
    return Container(
      padding: EdgeInsets.all(padding),
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
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isWeb ? 16 : 12,
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
                  label: Text(
                    'All',
                    style: TextStyle(fontSize: isWeb ? 14 : 12),
                  ),
                  selected: _selectedCategory == 'all',
                  onSelected: (_) => setState(() => _selectedCategory = 'all'),
                  selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFFFF6B8B),
                  padding: EdgeInsets.symmetric(
                    horizontal: isWeb ? 16 : 12,
                    vertical: isWeb ? 8 : 6,
                  ),
                ),
                const SizedBox(width: 8),
                ..._categories.map((category) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        category[0].toUpperCase() + category.substring(1),
                        style: TextStyle(fontSize: isWeb ? 14 : 12),
                      ),
                      selected: _selectedCategory == category,
                      onSelected: (_) => setState(() => _selectedCategory = category),
                      selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                      checkmarkColor: const Color(0xFFFF6B8B),
                      padding: EdgeInsets.symmetric(
                        horizontal: isWeb ? 16 : 12,
                        vertical: isWeb ? 8 : 6,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isWeb) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: isWeb ? 80 : 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No services found',
            style: TextStyle(
              fontSize: isWeb ? 20 : 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedCategory != 'all'
                ? 'Try adjusting your search or filters'
                : 'No services available',
            style: TextStyle(
              fontSize: isWeb ? 16 : 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView(double padding, int selectedCount) { // FIXED: Added selectedCount parameter
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          if (selectedCount > 0) ...[
            Card(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFFF6B8B)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFF6B8B)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$selectedCount service${selectedCount > 1 ? 's' : ''} selected',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFFF6B8B),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _saveServices,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B8B),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Services grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: _filteredServices.length,
            itemBuilder: (context, index) {
              final service = _filteredServices[index];
              return _buildServiceCard(service);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final serviceId = service['id'].toString();
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
    final allVariantsAssigned = service['allVariantsAssigned'] == true;
    final isFullServiceSelected = _isFullServiceSelected(serviceId);
    final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
    final categoryColor = _getCategoryColor(service['category_name']);
    
    // If all variants are already assigned, disable the service
    final isCompletelyAssigned = !hasVariants 
        ? isFullServiceAssigned
        : allVariantsAssigned;

    return Opacity(
      opacity: isCompletelyAssigned ? 0.6 : 1.0,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isFullServiceSelected || selectedVariantCount > 0
                ? const Color(0xFFFF6B8B)
                : Colors.grey[300]!,
            width: isFullServiceSelected || selectedVariantCount > 0 ? 2 : 1,
          ),
        ),
        elevation: isFullServiceSelected || selectedVariantCount > 0 ? 4 : 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      service['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!hasVariants)
                    Checkbox(
                      value: _selectedVariants.containsKey(serviceId),
                      onChanged: isCompletelyAssigned
                          ? null
                          : (_) => _toggleFullService(serviceId),
                      activeColor: const Color(0xFFFF6B8B),
                    ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category and price info
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            service['category_name'],
                            style: TextStyle(
                              fontSize: 11,
                              color: categoryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (hasVariants)
                          Text(
                            'Rs. ${service['minPrice']} - ${service['maxPrice']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Assigned badge
                    if (isCompletelyAssigned)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Already assigned',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    if (!hasVariants && !isCompletelyAssigned) ...[
                      const Spacer(),
                      Center(
                        child: Text(
                          'Full Service',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                    
                    if (hasVariants) ...[
                      const SizedBox(height: 8),
                      // Variants list
                      Expanded(
                        child: ListView.builder(
                          itemCount: variants.length,
                          itemBuilder: (context, vIndex) {
                            final variant = variants[vIndex];
                            final variantId = variant['id'] as int;
                            final isAssigned = variant['isAssigned'] == true;
                            final isSelected = _isVariantSelected(serviceId, variantId);
                            
                            return GestureDetector(
                              onTap: isAssigned || isCompletelyAssigned
                                  ? null
                                  : () => _toggleVariant(serviceId, variantId),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
                                      : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected 
                                        ? const Color(0xFFFF6B8B)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected 
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 16,
                                      color: isSelected
                                          ? const Color(0xFFFF6B8B)
                                          : Colors.grey[400],
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            variant['display_text'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: isSelected
                                                  ? const Color(0xFFFF6B8B)
                                                  : Colors.black87,
                                            ),
                                          ),
                                          Text(
                                            'Rs. ${variant['price']}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isAssigned)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green[100],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Assigned',
                                          style: TextStyle(
                                            fontSize: 8,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    
                    if (selectedVariantCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '$selectedVariantCount variant${selectedVariantCount > 1 ? 's' : ''} selected',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFF6B8B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileView(double padding, int selectedCount) { // FIXED: Added selectedCount parameter
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        final serviceId = service['id'].toString();
        final variants = service['variants'] as List;
        final hasVariants = variants.isNotEmpty;
        final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
        final allVariantsAssigned = service['allVariantsAssigned'] == true;
        final isFullServiceSelected = _isFullServiceSelected(serviceId);
        final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
        final isExpanded = _expandedServices.contains(serviceId);
        final categoryColor = _getCategoryColor(service['category_name']);
        
        final isCompletelyAssigned = !hasVariants 
            ? isFullServiceAssigned
            : allVariantsAssigned;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isFullServiceSelected || selectedVariantCount > 0
                  ? const Color(0xFFFF6B8B)
                  : Colors.grey[300]!,
              width: isFullServiceSelected || selectedVariantCount > 0 ? 2 : 1,
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Column(
              children: [
                // Service header
                InkWell(
                  onTap: hasVariants 
                      ? () => _toggleExpand(serviceId)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Selection checkbox for simple services
                        if (!hasVariants)
                          Checkbox(
                            value: _selectedVariants.containsKey(serviceId),
                            onChanged: isCompletelyAssigned
                                ? null
                                : (_) => _toggleFullService(serviceId),
                            activeColor: const Color(0xFFFF6B8B),
                          ),
                        
                        // Category color indicator
                        Container(
                          width: 4,
                          height: 40,
                          decoration: BoxDecoration(
                            color: categoryColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Service info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service['name'],
                                style: TextStyle(
                                  fontWeight: isFullServiceSelected || selectedVariantCount > 0
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 16,
                                  color: isCompletelyAssigned
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: categoryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      service['category_name'],
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: categoryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (hasVariants)
                                    Text(
                                      '${variants.length} variants',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Status badges
                        if (isCompletelyAssigned)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Assigned',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        else if (selectedVariantCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$selectedVariantCount',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFF6B8B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        
                        if (hasVariants)
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: selectedVariantCount > 0
                                ? const Color(0xFFFF6B8B)
                                : Colors.grey,
                          ),
                      ],
                    ),
                  ),
                ),
                
                // Variants list (if expanded)
                if (isExpanded && hasVariants)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: variants.map((variant) {
                        final variantId = variant['id'] as int;
                        final isAssigned = variant['isAssigned'] == true;
                        final isSelected = _isVariantSelected(serviceId, variantId);
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFFF6B8B).withValues(alpha: 0.05)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected 
                                  ? const Color(0xFFFF6B8B) 
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: ListTile(
                            leading: Checkbox(
                              value: isSelected,
                              onChanged: isAssigned || isCompletelyAssigned
                                  ? null
                                  : (_) => _toggleVariant(serviceId, variantId),
                              activeColor: const Color(0xFFFF6B8B),
                            ),
                            title: Text(
                              variant['display_text'],
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              'Rs. ${variant['price']} • ${variant['duration']} min',
                            ),
                            trailing: isAssigned
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[50],
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
              ],
            ),
          ),
        );
      },
    );
  }
}