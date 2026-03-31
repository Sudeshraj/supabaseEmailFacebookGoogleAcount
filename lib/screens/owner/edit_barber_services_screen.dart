// screens/owner/edit_barber_services_screen.dart - Fully Updated
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
  Map<int, String> _genderMap = {};
  Map<int, Map<String, dynamic>> _ageCategoryMap = {};
  
  // Categories list
  List<Map<String, dynamic>> _categories = [];

  // Expanded services for mobile view
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

      if (profile != null) {
        _barber = profile;
      }

      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');
      
      _categories = List<Map<String, dynamic>>.from(categoriesResponse);

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
        setState(() {
          _services = [];
          _isLoading = false;
        });
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
          'category_name': serviceInfo['category_name'],
          'category_icon': serviceInfo['category_icon'],
          'category_color': serviceInfo['category_color'],
          'icon_name': serviceInfo['icon_name'],
          'has_full_service': hasFullServiceValue,
          'variants': variants,
          'variant_count': variants.length,
        });
      }

      processedServices.sort((a, b) {
        final categoryCompare = (a['category_name'] as String).compareTo(b['category_name'] as String);
        if (categoryCompare != 0) return categoryCompare;
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      setState(() {
        _services = processedServices;
      });

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
    
    // Prepare variant list - ONLY UNAssigned variants
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
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    final Set<int> selectedVariantIds = {};
    bool selectAll = false;
    
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedVariantIds.isEmpty) {
                    _showSnackBar('Please select at least one option', Colors.orange);
                    return;
                  }
                  
                  setState(() => _isProcessing = true);
                  
                  try {
                    int addedCount = 0;
                    
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
                      addedCount++;
                    }
                    
                    // Update local state
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
                          break;
                        }
                      }
                    });
                    
                    Navigator.pop(context);
                    
                    if (mounted) {
                      _showSnackBar('$addedCount option(s) assigned successfully!', Colors.green);
                    }
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
        content: Text(message),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
      setState(() {
        _services.removeWhere((s) => s['id'] == service['id']);
      });
      
      if (mounted) {
        _showSnackBar('Service removed successfully', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error removing service: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ============================================================
  // REMOVE VARIANT - DELETE completely
  // ============================================================

  Future<void> _removeVariant(Map<String, dynamic> service, Map<String, dynamic> variant) async {
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
        content: Text("Are you sure you want to remove '${variant['display_text']}' from '${service['name']}'?"),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
      setState(() {
        for (int i = 0; i < _services.length; i++) {
          if (_services[i]['id'] == service['id']) {
            _services[i]['variants'].removeWhere((v) => v['id'] == variant['id']);
            _services[i]['variant_count'] = _services[i]['variants'].length;
            break;
          }
        }
      });
      
      if (mounted) {
        _showSnackBar('Option removed successfully', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error removing option: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ============================================================
  // ADD SERVICE
  // ============================================================

  Future<void> _addService() async {
    if (_salonBarberId == null) {
      _showSnackBar('Salon barber ID not found', Colors.red);
      return;
    }
    
    final result = await context.push(
      '/owner/salon/${widget.salonId}/barber/${widget.barberId}/add-service',
      extra: {
        'salonBarberId': _salonBarberId,
        'barberName': _barber['full_name'],
      },
    );
    
    if (result == true) {
      await _loadData();
      if (mounted) {
        _showSnackBar('Services added successfully!', Colors.green);
      }
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

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

  void _toggleExpand(int serviceId) {
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
      }
    });
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

  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null) return const Color(0xFFFF6B8B);
    try {
      return Color(int.parse('0xFF${hexColor.replaceFirst('#', '')}'));
    } catch (e) {
      return const Color(0xFFFF6B8B);
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
        title: const Text('Barber Services'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _addService,
            tooltip: 'Add Service',
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
                    _buildBarberInfoCard(),
                    Expanded(
                      child: isWeb
                          ? _buildWebView()
                          : _buildMobileView(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: isWeb ? 80 : 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No services found',
            style: TextStyle(fontSize: isWeb ? 18 : 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add services for this barber',
            style: TextStyle(fontSize: isWeb ? 14 : 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addService,
            icon: const Icon(Icons.add),
            label: const Text('Add Services'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isWeb ? 32 : 24, vertical: isWeb ? 14 : 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarberInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            backgroundImage: _barber['avatar_url'] != null ? NetworkImage(_barber['avatar_url']) : null,
            child: _barber['avatar_url'] == null
                ? Text(_barber['full_name']?[0]?.toUpperCase() ?? '?',
                    style: const TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 24))
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_barber['full_name'] ?? 'Unknown Barber', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(_barber['email'] ?? '', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) groupedServices[category] = [];
      groupedServices[category]!.add(service);
    }
    final sortedCategories = groupedServices.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final services = groupedServices[category]!;
        return _buildCategorySection(category, services, true);
      },
    );
  }

  Widget _buildMobileView() {
    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) groupedServices[category] = [];
      groupedServices[category]!.add(service);
    }
    final sortedCategories = groupedServices.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final services = groupedServices[category]!;
        return _buildCategorySection(category, services, false);
      },
    );
  }

  Widget _buildCategorySection(String category, List<Map<String, dynamic>> services, bool isWeb) {
    final categoryColor = _getColorFromHex(services.first['category_color']);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(_getIconForName(services.first['category_icon']), color: categoryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(category, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
                child: Text('${services.length} service${services.length > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        isWeb
            ? GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
                itemCount: services.length,
                itemBuilder: (context, index) => _buildServiceCard(services[index], true),
              )
            : Column(children: services.map((service) => _buildServiceCard(service, false)).toList()),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service, bool isWeb) {
    final hasFullService = service['has_full_service'] == true;
    final variants = service['variants'] as List;
    final categoryColor = _getColorFromHex(service['category_color']);
    final isExpanded = _expandedServices.contains(service['id']);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!, width: 1)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Icon(_getIconForName(service['icon_name']), color: const Color(0xFFFF6B8B), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (service['description'].isNotEmpty)
                        Text(service['description'], style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (variants.isNotEmpty && !isWeb)
                        Text('${variants.length} options', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                ),
                // Remove Service Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                  onPressed: _isProcessing ? null : () => _removeService(service),
                  tooltip: 'Remove Service',
                ),
                // Assign Variants Button
                IconButton(
                  icon: const Icon(Icons.playlist_add, color: Color(0xFFFF6B8B), size: 22),
                  onPressed: _isProcessing ? null : () => _showAssignVariantsDialog(service),
                  tooltip: 'Assign Options',
                ),
                if (!isWeb && variants.isNotEmpty)
                  IconButton(
                    icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                    onPressed: () => _toggleExpand(service['id']),
                  ),
              ],
            ),
          ),
          
          // Full Service Badge
          if (hasFullService && variants.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text('Full Service Assigned', style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          
          // Assigned Variants List
          if (variants.isNotEmpty && (isWeb || isExpanded)) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Assigned Options', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                        child: Text('${variants.length} option${variants.length > 1 ? 's' : ''}',
                            style: TextStyle(fontSize: 11, color: Colors.blue[700], fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...variants.map((variant) => _buildVariantCard(service, variant)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantCard(Map<String, dynamic> service, Map<String, dynamic> variant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.local_offer, color: Colors.orange, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(variant['display_text'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Rs. ${variant['price']} • ${variant['duration']} min',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            // Remove Variant Button - DELETE completely
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
              onPressed: _isProcessing ? null : () => _removeVariant(service, variant),
              tooltip: 'Remove Option',
            ),
          ],
        ),
      ),
    );
  }
}