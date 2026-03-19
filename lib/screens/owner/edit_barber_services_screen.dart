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

  // Store variant details
  Map<int, Map<String, dynamic>> _variantDetailsMap = {};

 
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
      // Get salon_barber_id
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('barber_id', widget.barberId)
          .eq('salon_id', int.parse(widget.salonId))
          .maybeSingle();

      if (salonBarberResponse == null) {
        throw Exception('Barber not found in this salon');
      }

      final int salonBarberId = salonBarberResponse['id'] as int;
      _salonBarberId = salonBarberId;

      // Load barber profile
      final profile = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .eq('id', widget.barberId)
          .maybeSingle();

      if (profile != null) {
        _barber = profile;
      }

      // Load categories
      // await supabase
      //     .from('categories')
      //     .select('id, name, icon_name')
      //     .eq('is_active', true)
      //     .order('display_order');


      // Get barber's current active services
      final currentServices = await supabase
          .from('barber_services')
          .select('''
            id,
            variant_id,
            service_id,
            is_active
          ''')
          .eq('salon_barber_id', salonBarberId)
          .eq('is_active', true);

      debugPrint('📋 Current services from DB: $currentServices');

      if (currentServices.isEmpty) {
        setState(() {
          _services = [];
          _isLoading = false;
        });
        return;
      }

      // Separate services with and without variants
      final servicesWithVariants = currentServices
          .where((s) => s['variant_id'] != null)
          .toList();
      
      final servicesWithoutVariants = currentServices
          .where((s) => s['variant_id'] == null)
          .toList();

      // Get unique service IDs
      final allServiceIds = currentServices
          .map((s) => s['service_id'] as int)
          .toSet()
          .toList();

      // Load service details
      Map<int, Map<String, dynamic>> serviceInfoMap = {};
      for (int serviceId in allServiceIds) {
        final service = await supabase
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
            .eq('id', serviceId)
            .eq('is_active', true)
            .maybeSingle();

        if (service != null) {
          final categoryName = service['categories']?['name'] ?? 'other';
          serviceInfoMap[serviceId] = {
            'id': serviceId,
            'name': service['name'],
            'category_name': categoryName,
          };
        }
      }

      // Process services with variants
      final variantIds = servicesWithVariants
          .map((s) => s['variant_id'] as int?)
          .whereType<int>()
          .toList();

      Map<int, Map<String, dynamic>> variantDetailsMap = {};

      for (int variantId in variantIds) {
        final variant = await supabase
            .from('service_variants')
            .select('''
              id,
              service_id,
              price,
              duration,
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
            .eq('id', variantId)
            .eq('is_active', true)
            .maybeSingle();

        if (variant != null) {
          final serviceId = variant['service_id'] as int;
          final serviceInfo = serviceInfoMap[serviceId] ?? {};
          final gender = variant['genders'] as Map<String, dynamic>;
          final age = variant['age_categories'] as Map<String, dynamic>;

          variantDetailsMap[variantId] = {
            'id': variantId,
            'service_id': serviceId,
            'service_name': serviceInfo['name'] ?? 'Unknown',
            'category_name': serviceInfo['category_name'] ?? 'other',
            'price': variant['price'],
            'duration': variant['duration'],
            'gender_name': gender['display_name'],
            'age_name': age['display_name'],
            'display_text': '${gender['display_name']} • ${age['display_name']}',
            'has_variant': true,
          };
        }
      }

      // Process services without variants
      for (var service in servicesWithoutVariants) {
        final serviceId = service['service_id'] as int;
        final serviceInfo = serviceInfoMap[serviceId] ?? {};
        
        // Create entry for service without variant
        final fakeId = -serviceId; // Negative ID to avoid conflict
        variantDetailsMap[fakeId] = {
          'id': fakeId,
          'service_id': serviceId,
          'service_name': serviceInfo['name'] ?? 'Unknown',
          'category_name': serviceInfo['category_name'] ?? 'other',
          'price': 0,
          'duration': 0,
          'has_variant': false,
          'is_simple_service': true,
        };
      }

      _variantDetailsMap = variantDetailsMap;

      // Group by service for display
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantDetailsMap.values) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }
        variantsByService[serviceId]!.add(variant);
      }

      // Build services list
      final List<Map<String, dynamic>> processedServices = [];
      for (int serviceId in allServiceIds) {
        final variants = variantsByService[serviceId] ?? [];
        if (variants.isNotEmpty) {
          processedServices.add({
            'id': serviceId,
            'name': serviceInfoMap[serviceId]?['name'] ?? 'Unknown',
            'category_name': serviceInfoMap[serviceId]?['category_name'] ?? 'other',
            'variants': variants,
            'variantCount': variants.length,
            'hasVariants': variants.any((v) => v['has_variant'] == true),
          });
        }
      }

      // Sort services by name within each category (will be done in UI)
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

  Future<void> _deleteSelectedVariants() async {
    if (_selectedForDelete.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Delete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete ${_selectedForDelete.length} selected item(s)?'),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
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
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      final int? salonBarberId = _salonBarberId;
      if (salonBarberId == null) throw Exception('Salon barber ID not found');

      // Separate real variants from service entries
      final realVariantIds = _selectedForDelete.where((id) => id > 0).toList();
      final serviceEntryIds = _selectedForDelete.where((id) => id < 0).toList();

      // Delete real variants
      if (realVariantIds.isNotEmpty) {
        for (int variantId in realVariantIds) {
          await supabase
              .from('barber_services')
              .update({'is_active': false})
              .eq('salon_barber_id', salonBarberId)
              .eq('variant_id', variantId);
        }
      }

      // Delete service entries (without variants)
      if (serviceEntryIds.isNotEmpty) {
        for (int fakeId in serviceEntryIds) {
          final serviceId = -fakeId; // Convert back to positive
          await supabase
              .from('barber_services')
              .update({'is_active': false})
              .eq('salon_barber_id', salonBarberId)
              .eq('service_id', serviceId)
              .filter('variant_id', 'is', null);
        }
      }

      // Remove from local state
      setState(() {
        for (int id in _selectedForDelete) {
          _variantDetailsMap.remove(id);
        }

        // Update services list
        final updatedServices = <Map<String, dynamic>>[];
        for (var service in _services) {
          final remainingVariants = service['variants']
              .where((v) => !_selectedForDelete.contains(v['id']))
              .toList();

          if (remainingVariants.isNotEmpty) {
            updatedServices.add({
              ...service,
              'variants': remainingVariants,
              'variantCount': remainingVariants.length,
              'hasVariants': remainingVariants.any((v) => v['has_variant'] == true),
            });
          }
        }

        _services = updatedServices;
        _selectedForDelete.clear();
        _isSelectMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedForDelete.length} item(s) deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      debugPrint('❌ Error deleting items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // Add service method
  Future<void> _addService() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Service'),
        content: const Text('Choose how you want to add a service:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
              _navigateToAddServiceWithVariants();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Add with Variants'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _loadData();
    }
  }

  // Navigate to add service with variants
  void _navigateToAddServiceWithVariants() {
    context.push(
      '/owner/salon/${widget.salonId}/barber/${widget.barberId}/add-service',
      extra: {
        'salonBarberId': _salonBarberId,
        'barberName': _barber['full_name'],
      },
    ).then((result) {
      if (result == true) {
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Services added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedForDelete.clear();
      }
    });
  }

  void _toggleSelection(int variantId) {
    setState(() {
      if (_selectedForDelete.contains(variantId)) {
        _selectedForDelete.remove(variantId);
      } else {
        _selectedForDelete.add(variantId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedForDelete.clear();
      for (var service in _services) {
        for (var variant in service['variants']) {
          _selectedForDelete.add(variant['id']);
        }
      }
    });
  }

  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName) {
      case 'hair': return Icons.content_cut;
      case 'skin': return Icons.face;
      case 'grooming': return Icons.face_retouching_natural;
      case 'wellness': return Icons.spa;
      case 'nails': return Icons.handshake;
      default: return Icons.category;
    }
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
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Barber Services'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        actions: [
          if (!_isLoading && _services.isNotEmpty)
            IconButton(
              icon: Icon(_isSelectMode ? Icons.close : Icons.edit),
              onPressed: _toggleSelectMode,
              tooltip: _isSelectMode ? 'Cancel' : 'Select Items',
            ),
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
              tooltip: 'Select All',
            ),
          if (_isSelectMode && _selectedForDelete.isNotEmpty)
            IconButton(
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete, color: Colors.red),
              onPressed: _isDeleting ? null : _deleteSelectedVariants,
              tooltip: 'Delete Selected',
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addService,
            tooltip: 'Add New Service',
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
                    _buildBarberInfoCard(padding),
                    Expanded(
                      child: _buildServicesList(padding),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No services found for this barber',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addService,
            icon: const Icon(Icons.add),
            label: const Text('Add New Service'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarberInfoCard(double padding) {
    return Container(
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
                if (_isSelectMode) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedForDelete.length} selected',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF6B8B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_isSelectMode)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Color(0xFFFF6B8B),
                ),
                onPressed: _addService,
                tooltip: 'Add New Service',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServicesList(double padding) {
    // Group services by category and sort
    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    
    // Sort services by name first
    final sortedServices = List<Map<String, dynamic>>.from(_services);
    sortedServices.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    
    for (var service in sortedServices) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    // Sort categories by name
    final sortedCategories = groupedServices.keys.toList()..sort();

    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
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
                child: Icon(
                  categoryIcon,
                  color: categoryColor,
                  size: 20,
                ),
              ),
              title: Text(
                category[0].toUpperCase() + category.substring(1),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text('${services.length} service${services.length > 1 ? 's' : ''}'),
              children: services.map((service) {
                final variants = service['variants'] as List;
                final simpleServices = variants.where((v) => !v['has_variant']).toList();
                final variantServices = variants.where((v) => v['has_variant']).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Simple services (without variants) - show as simple tiles
                    if (simpleServices.isNotEmpty)
                      ...simpleServices.map((variant) => 
                        _buildSimpleServiceTile(service, variant)
                      ),
                    
                    // Services with variants - show expandable section
                    if (variantServices.isNotEmpty)
                      _buildVariantServiceTile(service, variantServices),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSimpleServiceTile(Map<String, dynamic> service, Map<String, dynamic> variant) {
    final isSelected = _selectedForDelete.contains(variant['id']);
    
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.red : Colors.grey[300]!,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: _isSelectMode ? () => _toggleSelection(variant['id']) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              if (_isSelectMode) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.red : Colors.grey[400]!,
                      width: 2,
                    ),
                    color: isSelected ? Colors.red : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Full Service',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.circle, size: 4, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text(
                          'No variants',
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariantServiceTile(Map<String, dynamic> service, List variants) {
    final serviceSelectedCount = variants
        .where((v) => _selectedForDelete.contains(v['id']))
        .length;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  service['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (_isSelectMode && serviceSelectedCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$serviceSelectedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (!_isSelectMode)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${variants.length} variant${variants.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Click to view variants',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: variants.map((variant) {
                  final isSelected = _selectedForDelete.contains(variant['id']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.red.withValues(alpha: 0.05) : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.red : Colors.grey[300]!,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: _isSelectMode
                          ? () => _toggleSelection(variant['id'])
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            if (_isSelectMode) ...[
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.red : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                  color: isSelected ? Colors.red : Colors.transparent,
                                ),
                                child: isSelected
                                    ? const Center(
                                        child: Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                            ],
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                variant['gender_name'] == 'Male' ? Icons.male :
                                variant['gender_name'] == 'Female' ? Icons.female : Icons.people,
                                color: Colors.grey[600],
                                size: 16,
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
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
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
  }
}