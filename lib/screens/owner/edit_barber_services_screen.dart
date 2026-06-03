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
  State<EditBarberServicesScreen> createState() =>
      _EditBarberServicesScreenState();
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
          orElse: () => {
            'display_name': 'Other',
            'icon_name': 'build',
            'color': '#FF6B8B',
          },
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
              .select(
                'id, price, duration, salon_gender_id, salon_age_category_id',
              )
              .eq('id', variantId)
              .maybeSingle();

          if (variant != null) {
            final genderName =
                _genderMap[variant['salon_gender_id']] ?? 'Unknown';
            final ageData =
                _ageCategoryMap[variant['salon_age_category_id']] ??
                {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
            final ageName =
                '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';

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
        final categoryCompare = (a['category_name'] as String).compareTo(
          b['category_name'] as String,
        );
        if (categoryCompare != 0) return categoryCompare;
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      if (mounted) {
        setState(() {
          _services = processedServices;
          _expandedServices.clear();
          for (var service in processedServices) {
            if (service['has_variants'] == true) {
              _expandedServices.add(service['id'] as int);
            }
          }
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
  // ASSIGN VARIANTS DIALOG
  // ============================================================

  Future<void> _showAssignVariantsDialog(Map<String, dynamic> service) async {
    if (!mounted) return;

    final allVariants = await supabase
        .from('service_variants')
        .select('id, price, duration, salon_gender_id, salon_age_category_id')
        .eq('service_id', service['id'])
        .eq('is_active', true);

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

    final List<Map<String, dynamic>> variantList = [];
    for (var variant in allVariants) {
      if (assignedVariantIds.contains(variant['id'])) continue;

      final genderName = _genderMap[variant['salon_gender_id']] ?? 'Unknown';
      final ageData =
          _ageCategoryMap[variant['salon_age_category_id']] ??
          {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
      final ageName =
          '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';

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

    if (variantList.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No Options Available',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'All options for this service are already assigned to this barber.',
              ),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

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
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getIconForName(service['icon_name']),
                    color: const Color(0xFFFF6B8B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Assign Options',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Container(
              width: isMobile ? screenWidth * 0.85 : 450,
              constraints: BoxConstraints(
                maxWidth: isMobile ? screenWidth * 0.85 : 450,
                maxHeight: 450,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${variantList.length} option(s) available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Available Options',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: toggleSelectAll,
                        icon: Icon(
                          selectAll ? Icons.deselect : Icons.select_all,
                          size: 16,
                        ),
                        label: Text(
                          selectAll ? 'Deselect All' : 'Select All',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B8B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: variantList.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final variant = variantList[index];
                        final isSelected = selectedVariantIds.contains(
                          variant['id'],
                        );

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
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Rs. ${variant['price']} • ${variant['duration']} min',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
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
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedVariantIds.isEmpty) {
                    if (mounted) {
                      _showSnackBar(
                        'Please select at least one option',
                        Colors.orange,
                      );
                    }
                    return;
                  }

                  if (!mounted) return;
                  setState(() => _isProcessing = true);

                  try {
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

                    for (int variantId in selectedVariantIds) {
                      await supabase.from('barber_services').insert({
                        'salon_barber_id': _salonBarberId!,
                        'service_id': service['id'],
                        'variant_id': variantId,
                      });
                    }

                    if (mounted) {
                      setState(() {
                        for (int i = 0; i < _services.length; i++) {
                          if (_services[i]['id'] == service['id']) {
                            _services[i]['has_full_service'] = false;

                            for (int variantId in selectedVariantIds) {
                              final variantData = variantList.firstWhere(
                                (v) => v['id'] == variantId,
                              );
                              final isAlreadyInList = _services[i]['variants']
                                  .any((v) => v['id'] == variantId);

                              if (!isAlreadyInList) {
                                _services[i]['variants'].add({
                                  'id': variantData['id'],
                                  'price': variantData['price'],
                                  'duration': variantData['duration'],
                                  'gender_id': variantData['gender_id'],
                                  'age_category_id':
                                      variantData['age_category_id'],
                                  'gender_name': variantData['gender_name'],
                                  'age_name': variantData['age_name'],
                                  'display_text': variantData['display_text'],
                                });
                              }
                            }
                            _services[i]['variant_count'] =
                                _services[i]['variants'].length;
                            _services[i]['has_variants'] =
                                _services[i]['variants'].isNotEmpty;
                            break;
                          }
                        }
                      });
                    }

                    // if (mounted) {
                    //   Navigator.pop(context);
                    //   _showSnackBar('${selectedVariantIds.length} option(s) assigned successfully!', Colors.green);
                    // }
                  } catch (e) {
                    if (mounted) {
                      if (e.toString().contains('23505') ||
                          e.toString().contains('duplicate key')) {
                        _showSnackBar(
                          'This option is already assigned!',
                          Colors.orange,
                        );
                      } else {
                        _showSnackBar(
                          'Error assigning options: $e',
                          Colors.red,
                        );
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text(
                  'Assign Selected',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // REMOVE SERVICE
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
            Expanded(
              child: Text('Remove Service', overflow: TextOverflow.ellipsis),
            ),
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
      final barberServiceEntries = await supabase
          .from('barber_services')
          .select('id')
          .eq('salon_barber_id', _salonBarberId!)
          .eq('service_id', service['id']);

      for (var entry in barberServiceEntries) {
        await supabase.from('barber_services').delete().eq('id', entry['id']);
      }

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
  // REMOVE VARIANT
  // ============================================================

  Future<void> _removeVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text('Remove Option', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to remove '${variant['display_text']}' from '${service['name']}'?",
            ),
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
      final barberServiceEntry = await supabase
          .from('barber_services')
          .select('id')
          .eq('salon_barber_id', _salonBarberId!)
          .eq('service_id', service['id'])
          .eq('variant_id', variant['id'])
          .maybeSingle();

      if (barberServiceEntry != null) {
        await supabase
            .from('barber_services')
            .delete()
            .eq('id', barberServiceEntry['id']);
      }

      if (mounted) {
        setState(() {
          for (int i = 0; i < _services.length; i++) {
            if (_services[i]['id'] == service['id']) {
              _services[i]['variants'].removeWhere(
                (v) => v['id'] == variant['id'],
              );
              _services[i]['variant_count'] = _services[i]['variants'].length;
              _services[i]['has_variants'] =
                  _services[i]['variants'].isNotEmpty;
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
  // EXPAND/COLLAPSE FUNCTIONS
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

  void _expandAllServices() {
    setState(() {
      _expandedServices.clear();
      for (var service in _services) {
        if (service['has_variants'] == true) {
          _expandedServices.add(service['id'] as int);
        }
      }
    });
  }

  void _collapseAllServices() {
    setState(() {
      _expandedServices.clear();
    });
  }

  // ============================================================
  // HELPERS
  // ============================================================

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

  // ============================================================
  // ASSIGN NEW SERVICE CARD (WEB)
  // ============================================================

  Widget _buildAssignNewServiceCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: InkWell(
        onTap: _isProcessing ? null : _addService,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 248, 174, 190),
                Color.fromARGB(255, 245, 164, 211),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                'Assign New Service',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a new service\nfor this barber',
                style: TextStyle(fontSize: 11, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ASSIGN NEW SERVICE CARD (MOBILE)
  // ============================================================

  Widget _buildAssignNewServiceCardMobile() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: InkWell(
        onTap: _isProcessing ? null : _addService,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 248, 174, 190),
                Color.fromARGB(255, 245, 164, 211),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Assign New Service',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add a new service for this barber',
                      style: TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 12,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SERVICE CARD (WEB)
  // ============================================================

  Widget _buildServiceCardWeb(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final hasFullService = service['has_full_service'] == true;
    final isExpanded = _expandedServices.contains(service['id']);
    final accentColor = const Color(0xFFFF6B8B);
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cardColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
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
                      color: accentColor,
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.grey[800],
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
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _removeService(service),
                        tooltip: 'Remove Service',
                      ),
                      if (hasVariants)
                        IconButton(
                          icon: AnimatedRotation(
                            duration: const Duration(milliseconds: 300),
                            turns: isExpanded ? 0.5 : 0.0,
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.grey,
                            ),
                          ),
                          onPressed: () => _toggleExpand(service['id']),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            if (service['description'] != null &&
                service['description'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service['description'],
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            if (hasFullService && !hasVariants)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Full Service Assigned',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        hasVariants ? 'Assigned Options' : 'Service Options',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _showAssignVariantsDialog(service),
                        icon: const Icon(Icons.playlist_add, size: 16),
                        label: const Text('Assign Options'),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (hasVariants && isExpanded) ...[
                    ...variants.map((variant) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
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
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: _isProcessing
                                  ? null
                                  : () => _removeVariant(service, variant),
                              tooltip: 'Remove Option',
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else if (!hasVariants) ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48,
                            color: Colors.blue[300],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'This service has no variants',
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
                  ] else if (hasVariants && !isExpanded) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${variants.length} option(s) assigned',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
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
      ),
    );
  }

  // ============================================================
  // SERVICE CARD (MOBILE) - FIXED
  // ============================================================

  Widget _buildServiceCardMobile(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final hasFullService = service['has_full_service'] == true;
    final isExpanded = _expandedServices.contains(service['id']);
    final accentColor = const Color(0xFFFF6B8B);
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cardColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service Header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon
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
                  // Service Info - Expanded
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          service['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              service['category_name'],
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (hasVariants) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${variants.length}',
                                  style: TextStyle(
                                    fontSize: 8,
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
                  // Action Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 16,
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _removeService(service),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      if (hasVariants)
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: IconButton(
                            icon: Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Colors.grey[600],
                              size: 16,
                            ),
                            onPressed: () => _toggleExpand(service['id']),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Description
            if (service['description'] != null &&
                service['description'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  service['description'],
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Full Service Badge
            if (hasFullService && !hasVariants)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 10,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Full Service',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Variants Section
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        hasVariants ? 'Options' : 'No Variants',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 28,
                        child: TextButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _showAssignVariantsDialog(service),
                          icon: const Icon(Icons.playlist_add, size: 12),
                          label: const Text(
                            'Assign',
                            style: TextStyle(fontSize: 11),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (hasVariants && isExpanded) ...[
                    ...variants.map((variant) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.local_offer,
                                color: Colors.orange,
                                size: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    variant['display_text'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Rs. ${variant['price']} | ${variant['duration']} min',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                                size: 14,
                              ),
                              onPressed: _isProcessing
                                  ? null
                                  : () => _removeVariant(service, variant),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 14,
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else if (hasVariants && !isExpanded) ...[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Colors.green[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${variants.length} option(s) assigned',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (!hasVariants) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Center(
                        child: Text(
                          'No variants available',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WEB VIEW
  // ============================================================

  Widget _buildWebView() {
    final filteredServices = _filteredServices;

    if (filteredServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No services assigned yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addService,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Assign New Service'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: filteredServices.length + 1,
      itemBuilder: (context, index) {
        if (index == filteredServices.length) {
          return _buildAssignNewServiceCard();
        }
        final service = filteredServices[index];
        return _buildServiceCardWeb(service, index);
      },
    );
  }

  // ============================================================
  // MOBILE VIEW
  // ============================================================

  Widget _buildMobileView() {
    final filteredServices = _filteredServices;
    final screenWidth = MediaQuery.of(context).size.width;

    if (filteredServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No services assigned yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addService,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Assign New Service'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth < 400 ? 8 : 12,
        vertical: 12,
      ),
      itemCount: filteredServices.length + 1,
      itemBuilder: (context, index) {
        if (index == filteredServices.length) {
          return _buildAssignNewServiceCardMobile();
        }
        final service = filteredServices[index];
        return _buildServiceCardMobile(service, index);
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final hasVariants = _services.any((s) => s['has_variants'] == true);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_barber['full_name'] ?? 'Barber'} - Services'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        actions: [
          if (hasVariants)
            IconButton(
              icon: const Icon(Icons.expand),
              onPressed: _expandAllServices,
              tooltip: 'Expand All',
            ),
          if (hasVariants)
            IconButton(
              icon: const Icon(Icons.compress),
              onPressed: _collapseAllServices,
              tooltip: 'Collapse All',
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addService,
            tooltip: 'Assign Service',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : Column(
              children: [
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
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
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
                              label: const Text('All'),
                              selected: _selectedCategoryId == null,
                              onSelected: (_) =>
                                  setState(() => _selectedCategoryId = null),
                              selectedColor: const Color(
                                0xFFFF6B8B,
                              ).withValues(alpha: 0.2),
                              checkmarkColor: const Color(0xFFFF6B8B),
                            ),
                            const SizedBox(width: 8),
                            ..._categories.map((category) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category['display_name']),
                                  selected:
                                      _selectedCategoryId == category['id'],
                                  onSelected: (_) => setState(() {
                                    _selectedCategoryId = category['id'] as int;
                                  }),
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
                ),
                Expanded(child: isWeb ? _buildWebView() : _buildMobileView()),
              ],
            ),
    );
  }
}
