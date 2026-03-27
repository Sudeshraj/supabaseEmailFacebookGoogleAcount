import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/owner/add_services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';

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

      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
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

        // Get category name
        final category = _categories.firstWhere(
          (c) => c['id'] == service['category_id'],
          orElse: () => {'display_name': 'Uncategorized'},
        );
        service['category_name'] = category['display_name'];
      }

      setState(() {
        _services = services;
      });
    } catch (e) {
      debugPrint('Error loading services: $e');
      rethrow;
    }
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
  // VARIANT MANAGEMENT FUNCTIONS
  // ============================================

  // Show Edit Variant Dialog
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
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
                    'Edit Variant - ${service['name']}',
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
                            const Icon(Icons.wc, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              'Gender: ${variant['gender_name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Age: ${variant['age_name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                          decoration: const InputDecoration(
                            labelText: 'Price (Rs.)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.currency_rupee, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: durationController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duration (mins)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.timer, size: 20),
                          ),
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

                    if (mounted) {
                      Navigator.pop(context);
                      await _loadServices();
                      _showSnackBar(
                        'Variant updated successfully',
                        Colors.green,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      _showSnackBar('Error updating variant: $e', Colors.red);
                    }
                  } finally {
                    if (mounted) setState(() => _isProcessing = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Delete Variant
  Future<void> _deleteVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              'Delete Variant',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete this variant?",
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
                    'Variant: ${variant['gender_name']} - ${variant['age_name']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Price: Rs. ${variant['price']} | Duration: ${variant['duration']} mins',
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
          _showSnackBar('Variant deleted successfully', Colors.green);
        }
      } catch (e) {
        if (mounted) {
          _showSnackBar('Error deleting variant: $e', Colors.red);
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
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
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
                    decoration: const InputDecoration(
                      labelText: 'Service Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
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

                    if (mounted) {
                      Navigator.pop(context);
                      await _loadServices();
                      _showSnackBar(
                        'Service updated successfully',
                        Colors.green,
                      );
                    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                borderRadius: BorderRadius.circular(8),
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
                    '• ${service['variant_count']} variant${service['variant_count'] != 1 ? 's' : ''}',
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
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: Text('Services - ${widget.salonName}'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isDesktop,
        elevation: 0,
        actions: [
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
                  padding: EdgeInsets.all(isDesktop ? 16 : 12),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: DropdownButtonFormField<int>(
                          value: _selectedCategoryId,
                          decoration: InputDecoration(
                            hintText: 'All Categories',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<int>(
                              value: null,
                              child: Text('All Categories'),
                            ),
                            ..._categories.map((category) {
                              return DropdownMenuItem<int>(
                                value: category['id'] as int,
                                child: Text(category['display_name']),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedCategoryId = value;
                            });
                          },
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
                              Icon(
                                Icons.inbox,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty ||
                                        _selectedCategoryId != null
                                    ? 'No services match your filters'
                                    : 'No services added yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_searchQuery.isNotEmpty ||
                                  _selectedCategoryId != null)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _searchQuery = '';
                                      _selectedCategoryId = null;
                                    });
                                  },
                                  child: const Text('Clear Filters'),
                                )
                              else
                                ElevatedButton(
                                  onPressed: _isProcessing
                                      ? null
                                      : () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  AddServiceScreen(
                                                    salonId: widget.salonId,
                                                  ),
                                            ),
                                          );
                                          if (result == true) {
                                            await _loadServices();
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B8B),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Add Your First Service'),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.all(isDesktop ? 16 : 12),
                          itemCount: _filteredServices.length,
                          itemBuilder: (context, index) {
                            final service = _filteredServices[index];
                            return _buildServiceCard(service, isDesktop);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, bool isDesktop) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getIconForName(service['icon_name']),
            color: const Color(0xFFFF6B8B),
            size: 28,
          ),
        ),
        title: Text(
          service['name'],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service['category_name'],
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              '${service['variant_count']} variant${service['variant_count'] != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: _isProcessing ? null : () => _editService(service),
              tooltip: 'Edit Service',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _isProcessing ? null : () => _deleteService(service),
              tooltip: 'Delete Service',
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (service['description'] != null &&
                    service['description'].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      service['description'],
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),

                // Variants Section Header with Add Button
                Row(
                  children: [
                    const Text(
                      'Variants',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddServiceScreen(
                                    salonId: widget.salonId,
                                    // Pass service ID to add variant to existing service
                                  ),
                                ),
                              );
                              if (result == true) {
                                await _loadServices();
                              }
                            },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Variant'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B8B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Variants List
                if (service['variants'].isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'No variants added yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: service['variants'].length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final variant = service['variants'][index];
                      return _buildVariantTile(service, variant);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantTile(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
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
                  '${variant['gender_name']} - ${variant['age_name']}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rs. ${variant['price']} | ${variant['duration']} mins',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                onPressed: _isProcessing
                    ? null
                    : () => _showEditVariantDialog(service, variant),
                tooltip: 'Edit Variant',
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: _isProcessing
                    ? null
                    : () => _deleteVariant(service, variant),
                tooltip: 'Delete Variant',
              ),
            ],
          ),
        ],
      ),
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
}
