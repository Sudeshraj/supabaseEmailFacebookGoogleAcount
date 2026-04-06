// screens/owner/edit_barber_services_screen.dart - Fixed with proper mounted checks
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
  bool _isProcessing = false;
  
  // Barber details
  Map<String, dynamic> _barber = {};

  // Services with their variants
  List<Map<String, dynamic>> _services = [];

  // Salon barber ID
  int? _salonBarberId;

  // Gender and Age Category maps
  final Map<int, String> _genderMap = {};
  final Map<int, Map<String, dynamic>> _ageCategoryMap = {};
  
  // Categories list
  List<Map<String, dynamic>> _categories = [];

  // Search and filter
  String _searchQuery = '';
  int? _selectedCategoryId;
  
  // For expansion state - track expanded services
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
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId);
      
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

      final profile = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .eq('id', widget.barberId)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          _barber = profile;
        });
      }

      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');
      
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        });
      }

      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);
      
      for (var g in gendersResponse) {
        _genderMap[g['id']] = g['display_name'];
      }

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

      final currentServices = await supabase
          .from('barber_services')
          .select('id, variant_id, service_id')
          .eq('salon_barber_id', _salonBarberId!);        

      if (currentServices.isEmpty) {
        if (mounted) {
          setState(() {
            _services = [];
            _isLoading = false;
          });
        }
        return;
      }

      final allServiceIds = currentServices
          .map((s) => s['service_id'] as int)
          .toSet()
          .toList();

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
              'gender_id': variant['salon_gender_id'],
              'age_category_id': variant['salon_age_category_id'],
              'gender_name': genderName,
              'age_name': ageName,
              'display_text': '$genderName • $ageName',
            });
          }
        }
      }

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
          'category_id': serviceInfo['category_id'],
          'category_name': serviceInfo['category_name'],
          'category_icon': serviceInfo['category_icon'],
          'category_color': serviceInfo['category_color'],
          'icon_name': serviceInfo['icon_name'],
          'has_full_service': hasFullServiceValue,
          'variants': variants,
          'variant_count': variants.length,
          'has_variants': variants.isNotEmpty,
        });
      }

      processedServices.sort((a, b) {
        final categoryCompare = (a['category_name'] as String).compareTo(b['category_name'] as String);
        if (categoryCompare != 0) return categoryCompare;
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      if (mounted) {
        setState(() {
          _services = processedServices;
        });
      }

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
  // ASSIGN VARIANTS DIALOG (Only unassigned variants)
  // ============================================================
  
  Future<void> _showAssignVariantsDialog(Map<String, dynamic> service) async {
    if (!mounted) return;
    
    // Get all variants for this service from database
    final allVariants = await supabase
        .from('service_variants')
        .select('id, price, duration, salon_gender_id, salon_age_category_id')
        .eq('service_id', service['id'])
        .eq('is_active', true);
    
    // Get currently assigned variant IDs for this barber
    final assignedVariants = await supabase
        .from('barber_services')
        .select('variant_id')
        .eq('salon_barber_id', _salonBarberId!)
        .eq('service_id', service['id']);
    
    final Set<int> assignedVariantIds = {};
    for (var item in assignedVariants) {
      if (item['variant_id'] != null) {
        assignedVariantIds.add(item['variant_id'] as int);
      }
    }
    
    // Prepare variant list - ONLY UNASSIGNED variants
    final List<Map<String, dynamic>> variantList = [];
    for (var variant in allVariants) {
      if (assignedVariantIds.contains(variant['id'])) {
        continue;
      }
      
      final genderName = _genderMap[variant['salon_gender_id']] ?? 'Unknown';
      final ageData = _ageCategoryMap[variant['salon_age_category_id']] ?? 
          {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
      final ageName = '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';
      
      variantList.add({
        'id': variant['id'],
        'price': variant['price'],
        'duration': variant['duration'],
        'gender_id': variant['salon_gender_id'],
        'age_category_id': variant['salon_age_category_id'],
        'gender_name': genderName,
        'age_name': ageName,
        'display_text': '$genderName • $ageName',
      });
    }
    
    // If no variants available to assign
    if (variantList.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Text('No Options Available'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('All options for this service are already assigned to this barber.'),
              const SizedBox(height: 16),
              if (service['has_full_service'] == true)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Note: This service currently has "Full Service" assigned.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (mounted) Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    final Set<int> selectedVariantIds = {};
    bool selectAll = false;
    
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void toggleSelectAll() {
            setDialogState(() {
              selectAll = !selectAll;
              if (selectAll) {
                selectedVariantIds.clear();
                for (var variant in variantList) {
                  selectedVariantIds.add(variant['id']);
                }
              } else {
                selectedVariantIds.clear();
              }
            });
          }
          
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
                    'Assign Options - ${service['name']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 500,
                maxHeight: 500,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 20, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${variantList.length} option(s) available to assign',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Available Options',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: toggleSelectAll,
                        icon: Icon(
                          selectAll ? Icons.deselect : Icons.select_all,
                          size: 18,
                        ),
                        label: Text(selectAll ? 'Deselect All' : 'Select All'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B8B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: variantList.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final variant = variantList[index];
                        final isSelected = selectedVariantIds.contains(variant['id']);
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFFFF6B8B).withValues(alpha: 0.1) 
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedVariantIds.add(variant['id']);
                                } else {
                                  selectedVariantIds.remove(variant['id']);
                                }
                              });
                            },
                            title: Text(
                              variant['display_text'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'Rs. ${variant['price']} • ${variant['duration']} min',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedVariantIds.isEmpty) {
                    if (mounted) {
                      _showSnackBar('Please select at least one option', Colors.orange);
                    }
                    return;
                  }
                  
                  if (!mounted) return;
                  setState(() => _isProcessing = true);
                  
                  try {
                    // int addedCount = 0;
                    
                    // If service has full service, remove it first
                    if (service['has_full_service'] == true) {
                      final fullServiceEntry = await supabase
                          .from('barber_services')
                          .select('id')
                          .eq('salon_barber_id', _salonBarberId!)
                          .eq('service_id', service['id'])
                          .filter('variant_id', 'is', 'null')
                          .maybeSingle();
                      
                      if (fullServiceEntry != null) {
                        await supabase
                            .from('barber_services')
                            .delete()
                            .eq('id', fullServiceEntry['id']);
                      }
                    }
                    
                    // Assign selected variants
                    for (int variantId in selectedVariantIds) {
                      await supabase
                          .from('barber_services')
                          .insert({
                            'salon_barber_id': _salonBarberId!,
                            'service_id': service['id'],
                            'variant_id': variantId                           
                          });
                      // addedCount++;
                    }
                    
                    // Update local state
                    if (mounted) {
                      setState(() {
                        for (int i = 0; i < _services.length; i++) {
                          if (_services[i]['id'] == service['id']) {
                            // Remove full service flag
                            _services[i]['has_full_service'] = false;
                            
                            // Add newly assigned variants to local list
                            for (int variantId in selectedVariantIds) {
                              final variantData = variantList.firstWhere((v) => v['id'] == variantId);
                              final isAlreadyInList = _services[i]['variants'].any((v) => v['id'] == variantId);
                              
                              if (!isAlreadyInList) {
                                _services[i]['variants'].add({
                                  'id': variantData['id'],
                                  'price': variantData['price'],
                                  'duration': variantData['duration'],
                                  'gender_id': variantData['gender_id'],
                                  'age_category_id': variantData['age_category_id'],
                                  'gender_name': variantData['gender_name'],
                                  'age_name': variantData['age_name'],
                                  'display_text': variantData['display_text'],
                                });
                              }
                            }
                            _services[i]['variant_count'] = _services[i]['variants'].length;
                            _services[i]['has_variants'] = _services[i]['variants'].isNotEmpty;
                            break;
                          }
                        }
                      });
                    }
                    
                    // if (mounted) {
                    //   Navigator.pop(context);
                    //   _showSnackBar('$addedCount option(s) assigned successfully!', Colors.green);
                    // }
                  } catch (e) {
                    if (mounted) {
                      if (e.toString().contains('23505') || e.toString().contains('duplicate key')) {
                        _showSnackBar('This option is already assigned!', Colors.orange);
                      } else {
                        _showSnackBar('Error assigning options: $e', Colors.red);
                      }
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
                child: const Text('Assign Selected', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // REMOVE SERVICE - DELETE completely
  // ============================================================

  Future<void> _removeService(Map<String, dynamic> service) async {
    final hasVariants = service['variants'].isNotEmpty;
    final message = hasVariants 
        ? "Are you sure you want to remove '${service['name']}' and all its ${service['variants'].length} options?"
        : "Are you sure you want to remove '${service['name']}' from this barber?";
    
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Remove Service'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '⚠️ This action cannot be undone!',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      // Get all barber_service entries for this service
      final barberServiceEntries = await supabase
          .from('barber_services')
          .select('id')
          .eq('salon_barber_id', _salonBarberId!)
          .eq('service_id', service['id']);
      
      // Delete each entry completely
      for (var entry in barberServiceEntries) {
        await supabase
            .from('barber_services')
            .delete()
            .eq('id', entry['id']);
      }

      // Update local state
      if (mounted) {
        setState(() {
          _services.removeWhere((s) => s['id'] == service['id']);
        });
        _showSnackBar('Service removed successfully', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error removing service: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ============================================================
  // REMOVE VARIANT - DELETE completely
  // ============================================================

  Future<void> _removeVariant(Map<String, dynamic> service, Map<String, dynamic> variant) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Remove Option'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to remove '${variant['display_text']}' from '${service['name']}'?"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '⚠️ This action cannot be undone!',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      // Find the barber_service entry for this variant
      final barberServiceEntry = await supabase
          .from('barber_services')
          .select('id')
          .eq('salon_barber_id', _salonBarberId!)
          .eq('service_id', service['id'])
          .eq('variant_id', variant['id'])
          .maybeSingle();
      
      if (barberServiceEntry != null) {
        // COMPLETELY DELETE the record
        await supabase
            .from('barber_services')
            .delete()
            .eq('id', barberServiceEntry['id']);
      }

      // Update local state
      if (mounted) {
        setState(() {
          for (int i = 0; i < _services.length; i++) {
            if (_services[i]['id'] == service['id']) {
              _services[i]['variants'].removeWhere((v) => v['id'] == variant['id']);
              _services[i]['variant_count'] = _services[i]['variants'].length;
              _services[i]['has_variants'] = _services[i]['variants'].isNotEmpty;
              break;
            }
          }
        });
        _showSnackBar('Option removed successfully', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error removing option: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ============================================================
  // ADD SERVICE
  // ============================================================

  Future<void> _addService() async {
    if (_salonBarberId == null) {
      if (mounted) {
        _showSnackBar('Salon barber ID not found', Colors.red);
      }
      return;
    }
    
    if (!mounted) return;
    final result = await context.push(
      '/owner/salon/${widget.salonId}/barber/${widget.barberId}/add-service',
      extra: {
        'salonBarberId': _salonBarberId,
        'barberName': _barber['full_name'],
      },
    );
    
    if (result == true && mounted) {
      await _loadData();
      if (mounted) {
        _showSnackBar('Services added successfully!', Colors.green);
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _toggleExpand(int serviceId) {
    if (!mounted) return;
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
      }
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
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

  // ============================================================
  // UI BUILDERS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_barber['full_name'] ?? 'Barber'} - Services'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addService,
            tooltip: 'Add Service',
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
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
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
                              onSelected: (_) => setState(() => _selectedCategoryId = null),
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                              checkmarkColor: const Color(0xFFFF6B8B),
                            ),
                            const SizedBox(width: 8),
                            ..._categories.map((category) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category['display_name']),
                                  selected: _selectedCategoryId == category['id'],
                                  onSelected: (_) => setState(() {
                                    _selectedCategoryId = category['id'] as int;
                                  }),
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
                              Icon(
                                Icons.inbox,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty || _selectedCategoryId != null
                                    ? 'No services match your filters'
                                    : 'No services assigned yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_searchQuery.isNotEmpty || _selectedCategoryId != null)
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
                                  onPressed: _addService,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B8B),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Add Services for Barber'),
                                ),
                            ],
                          ),
                        )
                      : isWeb
                          ? _buildWebView()
                          : _buildMobileView(),
                ),
              ],
            ),
    );
  }

  Widget _buildWebView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        return _buildServiceCardWeb(service);
      },
    );
  }

  Widget _buildServiceCardWeb(Map<String, dynamic> service) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final hasFullService = service['has_full_service'] == true;
    final isExpanded = _expandedServices.contains(service['id']);
    
    return Card(
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
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.05),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                      onPressed: _isProcessing ? null : () => _removeService(service),
                      tooltip: 'Remove Service',
                    ),
                    if (hasVariants)
                      IconButton(
                        icon: AnimatedRotation(
                          duration: const Duration(milliseconds: 300),
                          turns: isExpanded ? 0.5 : 0.0,
                          child: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                        ),
                        onPressed: () => _toggleExpand(service['id']),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          // Description
          if (service['description'] != null && service['description'].isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                service['description'],
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          
          // Full Service Badge
          if (hasFullService && !hasVariants)
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
                      'Full Service Assigned',
                      style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
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
                    const Text(
                      'Assigned Options',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    // Assign Options Button
                    TextButton.icon(
                      onPressed: _isProcessing ? null : () => _showAssignVariantsDialog(service),
                      icon: const Icon(Icons.playlist_add, size: 16),
                      label: const Text('Assign Options'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B8B),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Variants List or Empty State
                if (hasVariants) ...[
                  ...variants.map((variant) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
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
                                  variant['display_text'],
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
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                            onPressed: _isProcessing
                                ? null
                                : () => _removeVariant(service, variant),
                            tooltip: 'Remove Option',
                          ),
                        ],
                      ),
                    );
                  }),
                ] else if (!hasFullService) ...[
                  // Empty state for services without variants
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.playlist_add,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No options assigned',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Assign Options" to add gender and age-based pricing',
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
    );
  }

  Widget _buildMobileView() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        final variants = service['variants'] as List;
        final hasVariants = variants.isNotEmpty;
        final hasFullService = service['has_full_service'] == true;
        final isExpanded = _expandedServices.contains(service['id']);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[200]!, width: 1),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
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
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: _isProcessing ? null : () => _removeService(service),
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
              if (service['description'] != null && service['description'].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    service['description'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              
              // Full Service Badge
              if (hasFullService && !hasVariants)
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
                          'Full Service Assigned',
                          style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // Variants Section
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Assigned Options',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _isProcessing ? null : () => _showAssignVariantsDialog(service),
                          icon: const Icon(Icons.playlist_add, size: 16),
                          label: const Text('Assign'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6B8B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    if (hasVariants) ...[
                      ...variants.map((variant) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
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
                                      variant['display_text'],
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
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 18),
                                onPressed: _isProcessing
                                    ? null
                                    : () => _removeVariant(service, variant),
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else if (!hasFullService) ...[
                      // Empty state for services without variants
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.playlist_add,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No options assigned',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap "Assign" to add gender and age-based pricing',
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
        );
      },
    );
  }
}