// screens/owner/add_barber_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/category_model.dart';
import '../../utils/ip_helper.dart'; // Import IP helper

class AddBarberScreen extends StatefulWidget {
  final bool refresh;

  const AddBarberScreen({super.key, this.refresh = false});

  @override
  State<AddBarberScreen> createState() => _AddBarberScreenState();
}

class _AddBarberScreenState extends State<AddBarberScreen>
    with RouteAware, AutomaticKeepAliveClientMixin {
  // ==================== CONTROLLERS ====================
  final TextEditingController _searchController = TextEditingController();

  // ==================== DATA LISTS ====================
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _ownerSalons = [];
  List<CategoryModel> _categories = [];

  // Services with their variants
  List<Map<String, dynamic>> _services = [];

  // Selected items: serviceId -> list of selected variantIds (empty list means service itself selected)
  final Map<String, List<int>> _selectedItems = {};

  // ==================== SELECTED ITEMS ====================
  String? _selectedBarberId;
  String? _selectedSalonId;

  // ==================== UI STATES ====================
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isLoadingSalons = false;
  bool _isLoadingServices = true;

  // ==================== IP ADDRESS ====================
  String? _currentIp;
  bool _isLoadingIp = false;

  // ==================== EXPANSION STATE ====================
  final Set<String> _expandedServices = {};

  // ==================== TIMERS ====================
  Timer? _debounceTimer;

  // ==================== SUPABASE CLIENT ====================
  final supabase = Supabase.instance.client;

  // ==================== RESPONSIVE HELPERS ====================
  bool get _isWeb => MediaQuery.of(context).size.width > 800;

  // ==================== COMPUTED PROPERTIES ====================
  int get _totalSelectedItems {
    int total = 0;
    _selectedItems.forEach((serviceId, variantList) {
      if (variantList.isEmpty) {
        total += 1;
      } else {
        total += variantList.length;
      }
    });
    return total;
  }

  int get _totalSelectedServices {
    return _selectedItems.keys.length;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint('📍 AddBarberScreen initState');
    _loadInitialData();
    _loadIpAddress(); // Load IP address
    _searchController.addListener(_onSearchChanged);

    if (widget.refresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshData();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('📍 AddBarberScreen came to foreground - refreshing data');
    _refreshData();
  }

  // ==================== IP ADDRESS LOADING ====================
  Future<void> _loadIpAddress() async {
    if (_isLoadingIp) return;
    
    setState(() => _isLoadingIp = true);
    
    try {
      _currentIp = await IpHelper.getPublicIp();
      debugPrint('🌐 Current IP: $_currentIp');
    } catch (e) {
      debugPrint('❌ Error loading IP: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingIp = false);
      }
    }
  }

  // ==================== LOG OWNER ACTIVITY ====================
  Future<void> _logOwnerActivity({
    required String actionType,
    required String targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final ownerId = supabase.auth.currentUser?.id;
      if (ownerId == null) return;

      // Get IP (use cached or fetch if needed)
      final ip = _currentIp ?? await IpHelper.getPublicIp();

      final logData = {
        'owner_id': ownerId,
        'action_type': actionType,
        'target_type': targetType,
        'target_id': targetId, // String එකක් විදියට
        'details': details ?? {},
        'ip_address': ip, // IP address එක
        'created_at': DateTime.now().toIso8601String(),
      };

      debugPrint('📝 Logging activity: $actionType');
      
      await supabase.from('owner_activity_log').insert(logData);
      
      debugPrint('✅ Activity logged: $actionType');
    } catch (e) {
      debugPrint('❌ Error logging activity: $e');
      // Don't throw - logging failure shouldn't break the main flow
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final isLoading = _isLoading || _isLoadingServices || _isLoadingSalons;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add New Barber',
          style: TextStyle(
            fontSize: isWeb ? 20 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        automaticallyImplyLeading: true,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
          if (_totalSelectedItems > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    '$_totalSelectedItems',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          if (_selectedBarberId != null &&
              _selectedSalonId != null &&
              _totalSelectedItems > 0 &&
              !isLoading)
            IconButton(
              icon: const Icon(Icons.check, color: Colors.white),
              onPressed: _isLoading ? null : _addBarber,
              tooltip: 'Add Barber',
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Container(
              color: Colors.grey[50],
              child: isWeb ? _buildWebLayout() : _buildMobileLayout(),
            ),
    );
  }

  // ==================== ADD BARBER FUNCTION - WITH LOGGING ====================
  Future<void> _addBarber() async {
    if (_selectedBarberId == null) {
      _showSnackBar('Please select a barber', Colors.red);
      return;
    }

    if (_selectedSalonId == null) {
      _showSnackBar('Please select a salon', Colors.red);
      return;
    }

    if (_totalSelectedItems == 0) {
      _showSnackBar('Please select at least one service', Colors.red);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Add Barber'),
        content: SizedBox(
          width: _isWeb ? 400 : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add ${_getBarberName()} to selected salon?'),
              const SizedBox(height: 16),
              const Text(
                'Selected services:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._selectedItems.entries.map((entry) {
                final serviceId = entry.key;
                final variantIds = entry.value;
                final service = _services.firstWhere(
                  (s) => s['id'] == serviceId,
                  orElse: () => {},
                );

                if (service.isEmpty) return const SizedBox.shrink();

                if (variantIds.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            service['name'] ?? 'Service',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Text(
                          service['name'] ?? 'Service',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      ...variantIds.map((variantId) {
                        final variant = _findVariantById(serviceId, variantId);
                        if (variant == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(left: 24, bottom: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${variant['gender_name']} - ${variant['age_category_name']}',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                }
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', int.parse(_selectedSalonId!))
          .eq('barber_id', _selectedBarberId!)
          .maybeSingle();

      int salonBarberId;

      if (salonBarberResponse == null) {
        final newSalonBarber = await supabase
            .from('salon_barbers')
            .insert({
              'salon_id': int.parse(_selectedSalonId!),
              'barber_id': _selectedBarberId!,
              'is_active': true,
            })
            .select('id')
            .single();

        salonBarberId = newSalonBarber['id'];
      } else {
        salonBarberId = salonBarberResponse['id'];
      }

      final userRoleCheckResponse = await supabase
          .from('user_roles')
          .select()
          .eq('user_id', _selectedBarberId!);

      if (userRoleCheckResponse.isEmpty) {
        final roleResponse = await supabase
            .from('roles')
            .select('id')
            .eq('name', 'barber')
            .maybeSingle();

        if (roleResponse == null) throw Exception('Barber role not found');

        await supabase.from('user_roles').insert({
          'user_id': _selectedBarberId!,
          'role_id': roleResponse['id'],
        });
      }

      // Collect selected services for logging
      List<Map<String, dynamic>> selectedServicesList = [];

      for (var entry in _selectedItems.entries) {
        final serviceId = int.parse(entry.key);
        final variantIds = entry.value;
        final service = _services.firstWhere(
          (s) => s['id'] == entry.key,
          orElse: () => {},
        );

        if (variantIds.isEmpty) {
          // Service without variants
          selectedServicesList.add({
            'service_id': serviceId,
            'service_name': service['name'] ?? 'Unknown',
            'type': 'full_service',
          });

          final existingServiceResponse = await supabase
              .from('barber_services')
              .select()
              .eq('salon_barber_id', salonBarberId)
              .eq('service_id', serviceId)
              .filter('variant_id', 'is', null);

          if (existingServiceResponse.isEmpty) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': salonBarberId,
              'service_id': serviceId,
              'variant_id': null,
              'is_active': true,
            });
          }
        } else {
          // Service with variants
          for (var variantId in variantIds) {
            final variant = _findVariantById(entry.key, variantId);
            selectedServicesList.add({
              'service_id': serviceId,
              'service_name': service['name'] ?? 'Unknown',
              'variant_id': variantId,
              'variant_details': variant != null
                  ? '${variant['gender_name']} - ${variant['age_category_name']}'
                  : null,
              'type': 'variant',
            });

            final existingVariantResponse = await supabase
                .from('barber_services')
                .select()
                .eq('salon_barber_id', salonBarberId)
                .eq('variant_id', variantId);

            if (existingVariantResponse.isEmpty) {
              await supabase.from('barber_services').insert({
                'salon_barber_id': salonBarberId,
                'service_id': serviceId,
                'variant_id': variantId,
                'is_active': true,
              });
            }
          }
        }
      }

      // Log activity with IP address
      await _logOwnerActivity(
        actionType: 'add_barber',
        targetType: 'barber',
        targetId: _selectedBarberId!, // String එකක් විදියට
        details: {
          'barber_id': _selectedBarberId,
          'barber_name': _getBarberName(),
          'salon_id': int.parse(_selectedSalonId!),
          'salon_barber_id': salonBarberId,
          'selected_services_count': _totalSelectedItems,
          'selected_services': selectedServicesList,
        },
      );

      if (mounted) {
        _showSnackBar('Barber added successfully!', Colors.green);

        setState(() {
          _selectedBarberId = null;
          _selectedItems.clear();
          _expandedServices.clear();
          _searchController.clear();
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error adding barber: $e');
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== REST OF YOUR EXISTING METHODS ====================
  // (All your existing methods remain exactly the same)
  
  Future<void> _loadInitialData() async {
    debugPrint('📥 Loading initial data...');

    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadCategories(),
        _loadServicesWithVariants(),
        _loadOwnerSalons(),
      ]);
    } catch (e) {
      debugPrint('❌ Error loading initial data: $e');
      if (mounted) {
        _showSnackBar('Error loading data: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData() async {
    debugPrint('🔄 Refreshing data...');
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadCategories(),
        _loadServicesWithVariants(),
        _loadOwnerSalons(),
        _loadIpAddress(), // Refresh IP too
      ]);
    } catch (e) {
      debugPrint('❌ Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Data refreshed!', Colors.green);
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      debugPrint('📥 Loading categories...');

      final response = await supabase
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      debugPrint('📊 Categories loaded: ${response.length}');

      if (mounted) {
        setState(() {
          _categories = response
              .map((cat) => CategoryModel.fromJson(cat))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
    }
  }

  Future<void> _loadServicesWithVariants() async {
    if (!mounted) return;

    try {
      debugPrint('📥 Loading services...');

      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            category_id,
            image_url,
            is_active,
            categories!inner (
              id,
              name,
              icon_name,
              color
            )
          ''')
          .eq('is_active', true)
          .order('name', ascending: true);

      debugPrint('📊 Services loaded: ${servicesResponse.length}');

      final variantsResponse = await supabase
          .from('service_variants')
          .select('''
            id,
            service_id,
            price,
            duration,
            is_active,
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

      debugPrint('📊 Variants loaded: ${variantsResponse.length}');

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }

        final gender = variant['genders'] as Map<String, dynamic>;
        final age = variant['age_categories'] as Map<String, dynamic>;

        variantsByService[serviceId]!.add({
          'id': variant['id'],
          'price': variant['price'],
          'duration': variant['duration'],
          'gender_id': gender['id'],
          'gender_name': gender['display_name'],
          'gender_original': gender['name'],
          'age_category_id': age['id'],
          'age_category_name': age['display_name'],
          'age_category_original': age['name'],
          'age_range': '${age['min_age']}-${age['max_age']}',
          'display_text': '${gender['display_name']} • ${age['display_name']}',
        });
      }

      final List<Map<String, dynamic>> processedServices = [];

      for (var service in servicesResponse) {
        final categoryData = service['categories'] as Map<String, dynamic>;
        final categoryName = categoryData['name'] ?? 'other';
        final iconName = categoryData['icon_name'] ?? 'build_circle_outlined';

        final serviceId = service['id'] as int;
        final variants = variantsByService[serviceId] ?? [];

        variants.sort((a, b) {
          if (a['gender_original'] != b['gender_original']) {
            return a['gender_original'].compareTo(b['gender_original']);
          }
          return a['age_category_original'].compareTo(
            b['age_category_original'],
          );
        });

        processedServices.add({
          'id': serviceId.toString(),
          'name': service['name'] ?? 'Unknown Service',
          'description': service['description'] ?? '',
          'category_id': service['category_id'],
          'category_name': categoryName,
          'icon': _getIconFromName(iconName),
          'icon_name': iconName,
          'image_url': service['image_url'],
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variant_count': variants.length,
          'min_price': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a < b ? a : b)
              : 0,
          'max_price': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a > b ? a : b)
              : 0,
        });
      }

      if (mounted) {
        setState(() {
          _services = processedServices;
          _isLoadingServices = false;
        });
        debugPrint('✅ Services processed: ${processedServices.length}');
      }
    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      if (mounted) {
        setState(() => _isLoadingServices = false);
        _showSnackBar('Error loading services: $e', Colors.red);
      }
    }
  }

  Future<void> _loadOwnerSalons() async {
    setState(() => _isLoadingSalons = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('salons')
          .select('id, name, address, is_active')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('name');

      debugPrint('📊 Owner salons loaded: ${response.length}');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          if (_ownerSalons.length == 1) {
            _selectedSalonId = _ownerSalons[0]['id'].toString();
          }
          _isLoadingSalons = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salons: $e');
      if (mounted) {
        setState(() => _isLoadingSalons = false);
        _showSnackBar('Error loading salons: $e', Colors.red);
      }
    }
  }

  IconData _getIconFromName(String iconName) {
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
      case 'build_circle_outlined':
        return Icons.build_circle_outlined;
      case 'brush':
        return Icons.brush;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'sports_kabaddi':
        return Icons.sports_kabaddi;
      default:
        return Icons.category;
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    if (query.length >= 2) {
      if (!_isSearching) {
        setState(() => _isSearching = true);
      }

      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _searchUsers(query);
        }
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    try {
      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'barber')
          .maybeSingle();

      if (roleResponse == null) {
        debugPrint('❌ Barber role not found');
        return;
      }

      final barberRoleId = roleResponse['id'];

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('user_id')
          .eq('role_id', barberRoleId);

      if (userRolesResponse.isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
          });
        }
        return;
      }

      final barberUserIds = userRolesResponse
          .map((ur) => ur['user_id'] as String)
          .toList();

      final List<Map<String, dynamic>> results = [];
      final queryLower = query.toLowerCase();

      for (String userId in barberUserIds) {
        final profile = await supabase
            .from('profiles')
            .select('id, full_name, email, avatar_url')
            .eq('id', userId)
            .maybeSingle();

        if (profile != null) {
          final fullName = profile['full_name']?.toString().toLowerCase() ?? '';
          final email = profile['email']?.toString().toLowerCase() ?? '';

          if (fullName.contains(queryLower) || email.contains(queryLower)) {
            results.add({
              'id': profile['id'],
              'full_name': profile['full_name'],
              'email': profile['email'],
              'avatar_url': profile['avatar_url'],
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
        });
      }
    } catch (e) {
      debugPrint('❌ Search error: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
        });
      }
    }
  }

  void _toggleSelection(String serviceId, [int? variantId]) {
    setState(() {
      if (variantId == null) {
        if (_selectedItems.containsKey(serviceId)) {
          _selectedItems.remove(serviceId);
        } else {
          _selectedItems[serviceId] = [];
        }
      } else {
        if (!_selectedItems.containsKey(serviceId)) {
          _selectedItems[serviceId] = [];
        }

        if (_selectedItems[serviceId]!.contains(variantId)) {
          _selectedItems[serviceId]!.remove(variantId);
          if (_selectedItems[serviceId]!.isEmpty) {
            _selectedItems.remove(serviceId);
          }
        } else {
          _selectedItems[serviceId]!.add(variantId);
        }
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

  bool _isSelected(String serviceId, [int? variantId]) {
    if (variantId == null) {
      return _selectedItems.containsKey(serviceId) && _selectedItems[serviceId]!.isEmpty;
    } else {
      return _selectedItems[serviceId]?.contains(variantId) ?? false;
    }
  }

  int _getSelectedCount(String serviceId) {
    return _selectedItems[serviceId]?.length ?? 0;
  }

  Map<String, dynamic>? _findVariantById(String serviceId, int variantId) {
    final service = _services.firstWhere(
      (s) => s['id'] == serviceId,
      orElse: () => {},
    );
    if (service.isEmpty) return null;

    final variants = service['variants'] as List? ?? [];
    for (var variant in variants) {
      if (variant['id'] == variantId) {
        return {
          ...variant,
          'service_id': serviceId,
          'service_name': service['name'],
        };
      }
    }
    return null;
  }

  String _getBarberName() {
    final barber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
      orElse: () => {},
    );
    return barber['full_name'] ?? barber['email'] ?? 'Barber';
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ==================== UI BUILDERS ====================
  // (All your existing UI builder methods remain exactly the same)
  
  Widget _buildWebLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 380,
          margin: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildSalonSection(),
                const SizedBox(height: 16),
                _buildSearchSection(),
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          height: MediaQuery.of(context).size.height - 80,
          color: Colors.grey[300],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedBarberId != null) ...[
                  _buildSelectedBarber(),
                  const SizedBox(height: 24),
                ],
                _buildServicesSection(),
                const SizedBox(height: 24),
                if (_selectedBarberId != null &&
                    _selectedSalonId != null &&
                    _totalSelectedItems > 0)
                  _buildAddButton(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSalonSection(),
          const SizedBox(height: 24),
          _buildSearchSection(),
          const SizedBox(height: 24),
          if (_selectedBarberId != null) _buildSelectedBarber(),
          const SizedBox(height: 24),
          _buildServicesSection(),
          const SizedBox(height: 24),
          if (_selectedBarberId != null &&
              _selectedSalonId != null &&
              _totalSelectedItems > 0)
            _buildAddButton(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSalonSection() {
    return Card(
      elevation: _isWeb ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(_isWeb ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Color(0xFFFF6B8B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Select Salon',
                  style: TextStyle(
                    fontSize: _isWeb ? 20 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_ownerSalons.isEmpty)
              _buildNoSalonWarning()
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ownerSalons.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final salon = _ownerSalons[index];
                  final isSelected = _selectedSalonId == salon['id'].toString();
                  return _buildSalonTile(salon, isSelected);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSalonWarning() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Colors.orange[700],
          ),
          const SizedBox(height: 12),
          Text(
            'No Salons Found',
            style: TextStyle(
              fontSize: _isWeb ? 18 : 16,
              color: Colors.grey[800],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You need to create a salon first before adding barbers.',
            style: TextStyle(
              fontSize: _isWeb ? 14 : 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              context.push('/owner/salon/create');
            },
            icon: const Icon(Icons.add_business),
            label: const Text('Create Salon'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalonTile(Map<String, dynamic> salon, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedSalonId = salon['id'].toString()),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B8B).withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.store,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    salon['name'] ?? 'Unnamed Salon',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (salon['address'] != null)
                    Text(
                      salon['address'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFFFF6B8B),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    return Card(
      elevation: _isWeb ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(_isWeb ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.search,
                    color: Color(0xFFFF6B8B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Search Barbers',
                  style: TextStyle(
                    fontSize: _isWeb ? 20 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Type name or email...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _isSearching = false;
                            _selectedBarberId = null;
                          });
                        },
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
                  vertical: _isWeb ? 16 : 12,
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),

            if (_searchController.text.isNotEmpty &&
                _searchController.text.length < 2)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Text(
                  '🔍 Type at least 2 characters to search',
                  style: TextStyle(
                    fontSize: _isWeb ? 13 : 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            if (_isSearching) ...[
              const SizedBox(height: 16),
              if (_searchResults.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.person_search,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No barbers found',
                          style: TextStyle(
                            fontSize: _isWeb ? 16 : 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchResults.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final barber = _searchResults[index];
                    final isSelected = _selectedBarberId == barber['id'];
                    return _buildBarberTile(barber, isSelected);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBarberTile(Map<String, dynamic> barber, bool isSelected) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isSelected
            ? const Color(0xFFFF6B8B)
            : Colors.grey[200],
        backgroundImage: barber['avatar_url'] != null
            ? NetworkImage(barber['avatar_url'])
            : null,
        child: barber['avatar_url'] == null
            ? Text(
                barber['full_name']?[0]?.toUpperCase() ?? '?',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              )
            : null,
      ),
      title: Text(
        barber['full_name'] ?? 'Unknown',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: _isWeb ? 16 : 14,
        ),
      ),
      subtitle: Text(
        barber['email'] ?? '',
        style: TextStyle(fontSize: _isWeb ? 14 : 12),
      ),
      trailing: isSelected
          ? Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            )
          : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
      onTap: () {
        setState(() => _selectedBarberId = barber['id']);
      },
    );
  }

  Widget _buildSelectedBarber() {
    final barber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
    );

    return Container(
      padding: EdgeInsets.all(_isWeb ? 20 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B8B), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: _isWeb ? 32 : 28,
            backgroundColor: const Color(0xFFFF6B8B),
            backgroundImage: barber['avatar_url'] != null
                ? NetworkImage(barber['avatar_url'])
                : null,
            child: barber['avatar_url'] == null
                ? Text(
                    barber['full_name']?[0]?.toUpperCase() ?? '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: _isWeb ? 20 : 16,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected Barber',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  barber['full_name'] ?? 'Unknown',
                  style: TextStyle(
                    fontSize: _isWeb ? 20 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  barber['email'] ?? '',
                  style: TextStyle(
                    fontSize: _isWeb ? 14 : 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesSection() {
    if (_services.isEmpty) {
      return Card(
        elevation: _isWeb ? 4 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No services available',
                  style: TextStyle(
                    fontSize: _isWeb ? 18 : 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Map<String, List<Map<String, dynamic>>> groupedServices = {};
    for (var service in _services) {
      final category = service['category_name'] as String;
      if (!groupedServices.containsKey(category)) {
        groupedServices[category] = [];
      }
      groupedServices[category]!.add(service);
    }

    return Card(
      elevation: _isWeb ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(_isWeb ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.build_circle_outlined,
                    color: Color(0xFFFF6B8B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select Services',
                    style: TextStyle(
                      fontSize: _isWeb ? 22 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_totalSelectedServices > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_totalSelectedServices service${_totalSelectedServices > 1 ? 's' : ''} selected',
                      style: TextStyle(
                        fontSize: _isWeb ? 14 : 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFF6B8B),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Click on a service to select it, or expand to choose specific variants',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            ...groupedServices.entries.map((entry) {
              return _buildCategorySection(entry.key, entry.value);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    String categoryName,
    List<Map<String, dynamic>> services,
  ) {
    final category = _categories.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => CategoryModel(
        id: 0,
        name: categoryName,
        description: '',
        iconName: 'category',
        displayOrder: 999,
        isActive: true,
      ),
    );

    final categorySelectedCount = services.fold<int>(
      0,
      (sum, service) => sum + _getSelectedCount(service['id'] as String),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          child: Row(
            children: [
              Icon(
                category.icon,
                size: _isWeb ? 24 : 20,
                color: const Color(0xFFFF6B8B),
              ),
              const SizedBox(width: 8),
              Text(
                categoryName[0].toUpperCase() + categoryName.substring(1),
                style: TextStyle(
                  fontSize: _isWeb ? 20 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${services.length}',
                  style: TextStyle(
                    fontSize: _isWeb ? 14 : 12,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              if (categorySelectedCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$categorySelectedCount selected',
                    style: TextStyle(
                      fontSize: _isWeb ? 13 : 11,
                      color: const Color(0xFFFF6B8B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        _isWeb
            ? SizedBox(
                height: 350,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 1200
                        ? 3
                        : 2,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: services.length,
                  itemBuilder: (context, index) {
                    return _buildServiceCard(services[index]);
                  },
                ),
              )
            : Column(
                children: services
                    .map((service) => _buildServiceTile(service))
                    .toList(),
              ),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> service) {
    final serviceId = service['id'] as String;
    final hasVariants = service['hasVariants'] as bool;
    final variants = service['variants'] as List;
    final selectedCount = _getSelectedCount(serviceId);
    final isExpanded = _expandedServices.contains(serviceId);

    if (!hasVariants) {
      final isSelected = _isSelected(serviceId);

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        elevation: isSelected ? 4 : 1,
        child: InkWell(
          onTap: () {
            _toggleSelection(serviceId);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF6B8B).withValues(alpha: 0.2)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    service['icon'] ?? Icons.build,
                    color: isSelected
                        ? const Color(0xFFFF6B8B)
                        : Colors.grey[600],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['name'] ?? 'Service',
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 16,
                          color: isSelected
                              ? const Color(0xFFFF6B8B)
                              : Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'No variants',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6B8B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[400]!, width: 1.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selectedCount > 0
                ? const Color(0xFFFF6B8B)
                : Colors.grey[200]!,
            width: selectedCount > 0 ? 2 : 1,
          ),
        ),
        elevation: selectedCount > 0 ? 4 : 1,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => _toggleExpand(serviceId),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: selectedCount > 0
                              ? const Color(0xFFFF6B8B).withValues(alpha: 0.2)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          service['icon'] ?? Icons.build,
                          color: selectedCount > 0
                              ? const Color(0xFFFF6B8B)
                              : Colors.grey[600],
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service['name'] ?? 'Service',
                              style: TextStyle(
                                fontWeight: selectedCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 16,
                                color: selectedCount > 0
                                    ? const Color(0xFFFF6B8B)
                                    : Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${variants.length} variants • Rs. ${service['min_price']} - ${service['max_price']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selectedCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B8B),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$selectedCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: selectedCount > 0
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Select variants:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...variants.map(
                        (variant) => _buildVariantTile(serviceId, variant),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final serviceId = service['id'] as String;
    final hasVariants = service['hasVariants'] as bool;
    final variants = service['variants'] as List;
    final selectedCount = _getSelectedCount(serviceId);

    if (!hasVariants) {
      final isSelected = _isSelected(serviceId);

      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        elevation: isSelected ? 4 : 1,
        child: InkWell(
          onTap: () => _toggleSelection(serviceId),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 140),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF6B8B).withValues(alpha: 0.2)
                        : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    service['icon'] ?? Icons.build,
                    color: isSelected
                        ? const Color(0xFFFF6B8B)
                        : Colors.grey[600],
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  service['name'] ?? 'Service',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 14,
                    color: isSelected
                        ? const Color(0xFFFF6B8B)
                        : Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'No variants',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6B8B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selectedCount > 0
                ? const Color(0xFFFF6B8B)
                : Colors.grey[200]!,
            width: selectedCount > 0 ? 2 : 1,
          ),
        ),
        elevation: selectedCount > 0 ? 4 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selectedCount > 0
                          ? const Color(0xFFFF6B8B).withValues(alpha: 0.2)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      service['icon'] ?? Icons.build,
                      color: selectedCount > 0
                          ? const Color(0xFFFF6B8B)
                          : Colors.grey[600],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      service['name'] ?? 'Service',
                      style: TextStyle(
                        fontWeight: selectedCount > 0
                            ? FontWeight.bold
                            : FontWeight.w600,
                        fontSize: 14,
                        color: selectedCount > 0
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[800],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selectedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B8B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Rs. ${service['min_price']} - ${service['max_price']}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const Divider(height: 16),
              const Text(
                'Variants:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: variants
                        .map(
                          (variant) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GestureDetector(
                              onTap: () =>
                                  _toggleSelection(serviceId, variant['id']),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _isSelected(serviceId, variant['id'])
                                      ? const Color(
                                          0xFFFF6B8B,
                                        ).withValues(alpha: 0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _isSelected(serviceId, variant['id'])
                                        ? const Color(0xFFFF6B8B)
                                        : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _isSelected(serviceId, variant['id'])
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 14,
                                      color:
                                          _isSelected(serviceId, variant['id'])
                                          ? const Color(0xFFFF6B8B)
                                          : Colors.grey[400],
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        variant['display_text'] ?? 'Variant',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              _isSelected(
                                                serviceId,
                                                variant['id'],
                                              )
                                              ? const Color(0xFFFF6B8B)
                                              : Colors.grey[700],
                                          fontWeight:
                                              _isSelected(
                                                serviceId,
                                                variant['id'],
                                              )
                                              ? FontWeight.w500
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildVariantTile(String serviceId, Map<String, dynamic> variant) {
    final isSelected = _isSelected(serviceId, variant['id']);

    return GestureDetector(
      onTap: () => _toggleSelection(serviceId, variant['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFF6B8B).withValues(alpha: 0.2)
                    : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                variant['gender_original'] == 'male'
                    ? Icons.male
                    : variant['gender_original'] == 'female'
                    ? Icons.female
                    : Icons.people,
                color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
                size: 14,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant['display_text'] ??
                        '${variant['gender_name']} - ${variant['age_category_name']}',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 13,
                      color: isSelected
                          ? const Color(0xFFFF6B8B)
                          : Colors.grey[800],
                    ),
                  ),
                  Text(
                    'Rs. ${variant['price']} • ${variant['duration']} min',
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? const Color(0xFFFF6B8B).withValues(alpha: 0.8)
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFFFF6B8B), size: 18)
            else
              Icon(Icons.circle_outlined, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: _isWeb ? 0 : 16, vertical: 8),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _addBarber,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          minimumSize: Size(_isWeb ? 400 : double.infinity, _isWeb ? 60 : 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
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
                  const Icon(Icons.person_add, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isWeb ? 'Add Barber to Selected Salon' : 'Add Barber',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// RouteObserver for route awareness
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();