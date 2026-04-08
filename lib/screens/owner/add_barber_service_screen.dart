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

  // Maps for lookups
  Map<int, String> _genderMap = {};
  Map<int, Map<String, dynamic>> _ageCategoryMap = {};
  Map<int, Map<String, dynamic>> _categoryMap = {};

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

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId);

      // Step 1: Get salon_barber_id if not provided
      if (widget.salonBarberId == null) {
        final salonBarberResponse = await supabase
            .from('salon_barbers')
            .select('id')
            .eq('barber_id', widget.barberId)
            .eq('salon_id', salonIdInt)
            .maybeSingle();

        if (salonBarberResponse != null) {
          _salonBarberId = salonBarberResponse['id'] as int;
        } else {
          throw Exception('Barber not found in this salon');
        }
      } else {
        _salonBarberId = widget.salonBarberId;
      }

      // Step 2: Load genders
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _genderMap = {};
      for (var g in gendersResponse) {
        _genderMap[g['id']] = g['display_name'];
      }

      // Step 3: Load age categories
      final ageCategoriesResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _ageCategoryMap = {};
      for (var a in ageCategoriesResponse) {
        _ageCategoryMap[a['id']] = {
          'display_name': a['display_name'],
          'min_age': a['min_age'],
          'max_age': a['max_age'],
        };
      }

      // Step 4: Load categories
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _categoryMap = {};
      for (var c in categoriesResponse) {
        _categoryMap[c['id']] = {
          'display_name': c['display_name'],
          'icon_name': c['icon_name'] ?? 'build',
          'color': c['color'] ?? '#FF6B8B',
        };
      }

      // Step 5: Get already assigned services
      final existingServices = await supabase
          .from('barber_services')
          .select('service_id, variant_id')
          .eq('salon_barber_id', _salonBarberId!);

      final Set<String> assignedServiceKeys = {};
      for (var item in existingServices) {
        if (item['variant_id'] == null) {
          assignedServiceKeys.add('service_${item['service_id']}');
        } else {
          assignedServiceKeys.add('variant_${item['variant_id']}');
        }
      }

      // Step 6: Load services
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, category_id, icon_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('name');

      // Step 7: Load variants
      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, service_id, price, duration, salon_gender_id, salon_age_category_id',
          )
          .eq('is_active', true);

      // Group variants by service
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }

        final genderId = variant['salon_gender_id'];
        final genderName = _genderMap[genderId] ?? 'Unknown';

        final ageId = variant['salon_age_category_id'];
        final ageData =
            _ageCategoryMap[ageId] ??
            {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
        final ageName =
            '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';

        final variantId = variant['id'] as int;

        variantsByService[serviceId]!.add({
          'id': variantId,
          'price': variant['price'],
          'duration': variant['duration'],
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_name': ageName,
          'display_text': '$genderName • $ageName',
          'isAssigned': assignedServiceKeys.contains('variant_$variantId'),
        });
      }

      // Step 8: Build services list
      final List<Map<String, dynamic>> processedServices = [];
      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final variants = variantsByService[serviceId] ?? [];
        final categoryId = service['category_id'];
        final category =
            _categoryMap[categoryId] ??
            {'display_name': 'Other', 'icon_name': 'build', 'color': '#FF6B8B'};
        final categoryName = category['display_name'];

        variants.sort((a, b) {
          if (a['gender_name'] != b['gender_name']) {
            return a['gender_name'].compareTo(b['gender_name']);
          }
          return a['age_name'].compareTo(b['age_name']);
        });

        final isFullServiceAssigned = assignedServiceKeys.contains(
          'service_$serviceId',
        );
        final allVariantsAssigned =
            variants.isNotEmpty &&
            variants.every((v) => v['isAssigned'] == true);

        processedServices.add({
          'id': serviceId,
          'id_str': serviceId.toString(),
          'name': service['name'] ?? 'Unknown',
          'category_id': categoryId,
          'category_name': categoryName,
          'category_icon': category['icon_name'],
          'category_color': category['color'],
          'description': service['description'] ?? '',
          'icon_name': service['icon_name'] ?? category['icon_name'],
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variantCount': variants.length,
          'isFullServiceAssigned': isFullServiceAssigned,
          'allVariantsAssigned': allVariantsAssigned,
          'minPrice': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a < b ? a : b)
              : 0,
          'maxPrice': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a > b ? a : b)
              : 0,
        });
      }

      setState(() {
        _services = processedServices;
      });

      debugPrint('✅ Loaded ${processedServices.length} services');
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
    return _selectedVariants.containsKey(serviceId) &&
        _selectedVariants[serviceId]!.isEmpty;
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
          });
          addedCount++;
        } else {
          for (int variantId in variantIds) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': _salonBarberId!,
              'service_id': serviceId,
              'variant_id': variantId,
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
    final categories = _services
        .map((s) => s['category_name'] as String)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((service) {
      if (_selectedCategory != 'all' &&
          service['category_name'] != _selectedCategory) {
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
    switch (categoryName.toLowerCase()) {
      case 'hair':
        return Colors.blue;
      case 'skin':
        return Colors.pink;
      case 'grooming':
        return Colors.orange;
      case 'wellness':
        return Colors.green;
      case 'nails':
        return Colors.purple;
      default:
        return const Color(0xFFFF6B8B);
    }
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
        return Icons.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final int selectedCount = _getSelectedCount();
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Services', style: TextStyle(fontSize: isWeb ? 20 : 18)),
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
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : Column(
              children: [
                _buildSearchAndFilterBar(isWeb, padding),
                Expanded(
                  child: _filteredServices.isEmpty
                      ? _buildEmptyState(isWeb)
                      : isWeb
                      ? _buildWebView(padding, selectedCount)
                      : _buildMobileView(padding, selectedCount),
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
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
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
                borderSide: const BorderSide(
                  color: Color(0xFFFF6B8B),
                  width: 2,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isWeb ? 16 : 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                      onSelected: (_) =>
                          setState(() => _selectedCategory = category),
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

  Widget _buildWebView(double padding, int selectedCount) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              return _buildServiceCardWeb(service, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCardWeb(Map<String, dynamic> service, int index) {
    final serviceId = service['id_str'];
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
    final allVariantsAssigned = service['allVariantsAssigned'] == true;
    final isFullServiceSelected = _isFullServiceSelected(serviceId);
    final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
    final categoryColor = _getCategoryColor(service['category_name']);
    final cardColor = _cardColors[index % _cardColors.length];
    final accentColor = const Color(0xFFFF6B8B);

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
                ? accentColor
                : Colors.grey[300]!,
            width: isFullServiceSelected || selectedVariantCount > 0 ? 2 : 1,
          ),
        ),
        elevation: isFullServiceSelected || selectedVariantCount > 0 ? 4 : 2,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cardColor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
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
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Icon(
                          _getIconForName(service['icon_name']),
                          color: accentColor,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
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
                              if (hasVariants) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${variants.length} variants',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!hasVariants)
                      Checkbox(
                        value: _selectedVariants.containsKey(serviceId),
                        onChanged: isCompletelyAssigned
                            ? null
                            : (_) => _toggleFullService(serviceId),
                        activeColor: accentColor,
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
                      if (hasVariants && !isCompletelyAssigned) ...[
                        Text(
                          'Rs. ${service['minPrice']} - ${service['maxPrice']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

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
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Already assigned',
                                style: TextStyle(
                                  fontSize: 10,
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
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],

                      if (hasVariants) ...[
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: variants.length,
                            itemBuilder: (context, vIndex) {
                              final variant = variants[vIndex];
                              final variantId = variant['id'] as int;
                              final isAssigned = variant['isAssigned'] == true;
                              final isSelected = _isVariantSelected(
                                serviceId,
                                variantId,
                              );

                              return GestureDetector(
                                onTap: isAssigned || isCompletelyAssigned
                                    ? null
                                    : () =>
                                          _toggleVariant(serviceId, variantId),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? accentColor.withValues(alpha: 0.1)
                                        : Colors.white.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? accentColor
                                          : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        size: 14,
                                        color: isSelected
                                            ? accentColor
                                            : Colors.grey[400],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              variant['display_text'],
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: isSelected
                                                    ? accentColor
                                                    : Colors.grey[800],
                                              ),
                                            ),
                                            Text(
                                              'Rs. ${variant['price']} • ${variant['duration']} min',
                                              style: TextStyle(
                                                fontSize: 9,
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
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
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
                            style: TextStyle(
                              fontSize: 10,
                              color: accentColor,
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
      ),
    );
  }

  Widget _buildMobileView(double padding, int selectedCount) {
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        final serviceId = service['id_str'];
        final variants = service['variants'] as List;
        final hasVariants = variants.isNotEmpty;
        final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
        final allVariantsAssigned = service['allVariantsAssigned'] == true;
        final isFullServiceSelected = _isFullServiceSelected(serviceId);
        final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
        final isExpanded = _expandedServices.contains(serviceId);
        final categoryColor = _getCategoryColor(service['category_name']);
        final cardColor = _cardColors[index % _cardColors.length];
        final accentColor = const Color(0xFFFF6B8B);

        final isCompletelyAssigned = !hasVariants
            ? isFullServiceAssigned
            : allVariantsAssigned;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isFullServiceSelected || selectedVariantCount > 0
                  ? accentColor
                  : Colors.grey[300]!,
              width: isFullServiceSelected || selectedVariantCount > 0 ? 2 : 1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cardColor,
            ),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  // Service header
                  InkWell(
                    onTap: hasVariants ? () => _toggleExpand(serviceId) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Icon(
                                _getIconForName(service['icon_name']),
                                color: accentColor,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service['name'],
                                  style: TextStyle(
                                    fontWeight:
                                        isFullServiceSelected ||
                                            selectedVariantCount > 0
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    fontSize: 14,
                                    color: isCompletelyAssigned
                                        ? Colors.grey
                                        : Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: categoryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        service['category_name'],
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: categoryColor,
                                        ),
                                      ),
                                    ),
                                    if (hasVariants) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '${variants.length} variants',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!hasVariants)
                            Checkbox(
                              value: _selectedVariants.containsKey(serviceId),
                              onChanged: isCompletelyAssigned
                                  ? null
                                  : (_) => _toggleFullService(serviceId),
                              activeColor: accentColor,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (hasVariants)
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                              color: selectedVariantCount > 0
                                  ? accentColor
                                  : Colors.grey,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Variants list (if expanded)
                  if (isExpanded && hasVariants)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        children: variants.map((variant) {
                          final variantId = variant['id'] as int;
                          final isAssigned = variant['isAssigned'] == true;
                          final isSelected = _isVariantSelected(
                            serviceId,
                            variantId,
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accentColor.withValues(alpha: 0.05)
                                  : Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? accentColor
                                    : Colors.grey[200]!,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 0,
                              ),
                              leading: Checkbox(
                                value: isSelected,
                                onChanged: isAssigned || isCompletelyAssigned
                                    ? null
                                    : (_) =>
                                          _toggleVariant(serviceId, variantId),
                                activeColor: accentColor,
                                visualDensity: VisualDensity.compact,
                              ),
                              title: Text(
                                variant['display_text'],
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Rs. ${variant['price']} • ${variant['duration']} min',
                                style: TextStyle(fontSize: 10),
                              ),
                              trailing: isAssigned
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Assigned',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.green[700],
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
          ),
        );
      },
    );
  }
}
