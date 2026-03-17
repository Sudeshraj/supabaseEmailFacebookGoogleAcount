// screens/owner/edit_barber_services_screen.dart
import 'package:flutter/material.dart';
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
  State<EditBarberServicesScreen> createState() =>
      _EditBarberServicesScreenState();
}

class _EditBarberServicesScreenState extends State<EditBarberServicesScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;

  // Barber details
  Map<String, dynamic> _barber = {};

  // Services and variants
  List<Map<String, dynamic>> _services = [];
  Map<int, List<Map<String, dynamic>>> _variantsByService = {};

  // Selected variant IDs
  Set<int> _selectedVariantIds = {};

  // Store variant to service mapping
  Map<int, int> _variantToServiceMap = {};

  // Categories

  // Salon barber ID
  int? _salonBarberId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 🔥 FIRST: Get salon_barber_id
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('barber_id', widget.barberId)
          .eq('salon_id', int.parse(widget.salonId))
          .maybeSingle();

      if (salonBarberResponse == null) {
        throw Exception('Barber not found in this salon');
      }

      // Store in both field and local variable for safety
      final int salonBarberId = salonBarberResponse['id'] as int;
      _salonBarberId = salonBarberId;

      // 1. Load barber profile
      final profile = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .eq('id', widget.barberId)
          .maybeSingle();

      if (profile != null) {
        _barber = profile;
      }

      // 2. Load categories
      final categoriesResponse = await supabase
          .from('categories')
          .select('id, name, icon_name')
          .eq('is_active', true)
          .order('display_order');

      // 3. Load all services with variants
      final servicesResponse = await supabase
          .from('services')
          .select('''
          id,
          name,
          category_id,
          categories (
            id,
            name
          )
        ''')
          .eq('is_active', true)
          .order('name');

      // 4. Load all variants
      final variantsResponse = await supabase
          .from('service_variants')
          .select('''
          id,
          service_id,
          price,
          duration,
          is_active,
          genders (
            id,
            name,
            display_name
          ),
          age_categories (
            id,
            name,
            display_name,
            min_age,
            max_age
          )
        ''')
          .eq('is_active', true);

      // 5. Load barber's current services using salon_barber_id
      final currentServices = await supabase
          .from('barber_services')
          .select('variant_id')
          .eq('salon_barber_id', salonBarberId)
          .eq('is_active', true);

      // Extract selected variant IDs - FIXED: handle null values
      _selectedVariantIds = currentServices
          .map((s) => s['variant_id'] as int?) // ✅ Step 1: Cast to nullable int
          .where((id) => id != null) // ✅ Step 2: Filter out nulls
          .map((id) => id!) // ✅ Step 3: Convert to non-nullable
          .toSet();

      debugPrint('📊 Selected variant IDs: $_selectedVariantIds');

      // Group variants by service and build mapping
      final Map<int, List<Map<String, dynamic>>> variantsMap = {};
      final Map<int, int> variantToServiceMap = {}; // Local mapping

      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        final variantId = variant['id'] as int;

        if (!variantsMap.containsKey(serviceId)) {
          variantsMap[serviceId] = [];
        }

        // Store variant to service mapping in local map
        variantToServiceMap[variantId] = serviceId;

        final gender = variant['genders'] as Map<String, dynamic>;
        final age = variant['age_categories'] as Map<String, dynamic>;

        variantsMap[serviceId]!.add({
          'id': variantId,
          'price': variant['price'],
          'duration': variant['duration'],
          'gender_name': gender['display_name'],
          'gender_original': gender['name'],
          'age_name': age['display_name'],
          'age_range': '${age['min_age']}-${age['max_age']}',
          'display_text': '${gender['display_name']} • ${age['display_name']}',
        });
      }

      // Assign to class fields
      _variantsByService = variantsMap;
      _variantToServiceMap = variantToServiceMap;

      // Process services
      final List<Map<String, dynamic>> processedServices = [];
      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final variants = variantsMap[serviceId] ?? [];
        final categoryData =
            service['categories'] as Map<String, dynamic>? ?? {};

        processedServices.add({
          'id': serviceId,
          'name': service['name'] ?? 'Unknown Service',
          'category_id': service['category_id'],
          'category_name': categoryData['name'] ?? 'other',
          'hasVariants': variants.isNotEmpty,
          'variantCount': variants.length,
          'minPrice': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a < b ? a : b)
              : 0,
        });
      }

      setState(() {
        _services = processedServices;
      });
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      // 🔥 FIX: Create a local variable
      final int? salonBarberId = _salonBarberId;

      if (salonBarberId == null) {
        throw Exception('Salon barber ID not found');
      }

      // First, deactivate all current services for this barber
      await supabase
          .from('barber_services')
          .update({'is_active': false})
          .eq('salon_barber_id', salonBarberId); // ✅ Use local variable

      // Then, insert selected variants
      if (_selectedVariantIds.isNotEmpty) {
        for (int variantId in _selectedVariantIds) {
          // Get service_id from mapping
          final serviceId = _variantToServiceMap[variantId];

          if (serviceId == null) {
            debugPrint('⚠️ No service found for variant $variantId, skipping');
            continue;
          }

          // Check if already exists
          final existing = await supabase
              .from('barber_services')
              .select('id')
              .eq('salon_barber_id', salonBarberId) // ✅ Use local variable
              .eq('variant_id', variantId)
              .maybeSingle();

          if (existing == null) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': salonBarberId, // ✅ Use local variable
              'service_id': serviceId,
              'variant_id': variantId,
              'is_active': true,
            });
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Services updated successfully'),
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
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleVariant(int variantId) {
    setState(() {
      if (_selectedVariantIds.contains(variantId)) {
        _selectedVariantIds.remove(variantId);
      } else {
        _selectedVariantIds.add(variantId);
      }
    });
  }

  void _selectAllForService(int serviceId) {
    setState(() {
      final variants = _variantsByService[serviceId] ?? [];
      for (var variant in variants) {
        _selectedVariantIds.add(variant['id']);
      }
    });
  }

  void _deselectAllForService(int serviceId) {
    setState(() {
      final variants = _variantsByService[serviceId] ?? [];
      for (var variant in variants) {
        _selectedVariantIds.remove(variant['id']);
      }
    });
  }

  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName) {
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

  Color _getCategoryColor(String categoryName) {
    switch (categoryName) {
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
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Barber Services'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        actions: [
          if (!_isLoading)
            IconButton(
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
              onPressed: _isSaving ? null : _saveChanges,
              tooltip: 'Save Changes',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : Column(
              children: [
                // Barber Info Card
                Container(
                  margin: EdgeInsets.all(padding),
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
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
                        backgroundColor: const Color(
                          0xFFFF6B8B,
                        ).withValues(alpha: 0.1),
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
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF6B8B,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedVariantIds.length} services selected',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFFF6B8B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Services List
                Expanded(child: _buildServicesList(padding, isWeb)),
              ],
            ),
    );
  }

  Widget _buildServicesList(double padding, bool isWeb) {
    // Group services by category
    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: groupedServices.length,
      itemBuilder: (context, index) {
        final category = groupedServices.keys.elementAt(index);
        final services = groupedServices[category]!;
        final categoryIcon = _getCategoryIcon(category);
        final categoryColor = _getCategoryColor(category);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(categoryIcon, color: categoryColor, size: 20),
              ),
              title: Text(
                category[0].toUpperCase() + category.substring(1),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text('${services.length} services'),
              children: services.map((service) {
                final serviceId = service['id'] as int;
                final variants = _variantsByService[serviceId] ?? [];
                final selectedInService = variants
                    .where((v) => _selectedVariantIds.contains(v['id']))
                    .length;

                if (!service['hasVariants']) {
                  return const SizedBox.shrink();
                }

                return Container(
                  margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              service['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (selectedInService > 0)
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
                                '$selectedInService',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('${variants.length} variants available'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selectedInService > 0)
                            IconButton(
                              icon: const Icon(
                                Icons.clear_all,
                                color: Colors.red,
                                size: 18,
                              ),
                              onPressed: () =>
                                  _deselectAllForService(serviceId),
                              tooltip: 'Deselect all',
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.select_all,
                              color: Colors.blue,
                              size: 18,
                            ),
                            onPressed: () => _selectAllForService(serviceId),
                            tooltip: 'Select all',
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: variants.map((variant) {
                              final isSelected = _selectedVariantIds.contains(
                                variant['id'],
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(
                                          0xFFFF6B8B,
                                        ).withValues(alpha: 0.05)
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFFF6B8B)
                                        : Colors.grey[300]!,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () => _toggleVariant(variant['id']),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(
                                                    0xFFFF6B8B,
                                                  ).withValues(alpha: 0.2)
                                                : Colors.grey[100],
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            variant['gender_original'] == 'male'
                                                ? Icons.male
                                                : variant['gender_original'] ==
                                                      'female'
                                                ? Icons.female
                                                : Icons.people,
                                            color: isSelected
                                                ? const Color(0xFFFF6B8B)
                                                : Colors.grey[600],
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                variant['display_text'],
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? const Color(0xFFFF6B8B)
                                                      : Colors.grey[800],
                                                ),
                                              ),
                                              Text(
                                                'Rs. ${variant['price']} • ${variant['duration']} min',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isSelected
                                                      ? const Color(
                                                          0xFFFF6B8B,
                                                        ).withValues(alpha: 0.8)
                                                      : Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_circle,
                                            color: Color(0xFFFF6B8B),
                                            size: 20,
                                          )
                                        else
                                          Icon(
                                            Icons.circle_outlined,
                                            color: Colors.grey[400],
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
