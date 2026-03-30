// screens/owner/add_barber_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/ip_helper.dart';

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

  // Services with their variants (salon-specific - updated for new schema)
  List<Map<String, dynamic>> _services = [];

  // Selected items: serviceId -> list of selected variantIds
  final Map<String, List<int>> _selectedItems = {};

  // ==================== SELECTED ITEMS ====================
  String? _selectedBarberId;
  String? _selectedSalonId;
  Map<String, dynamic>? _selectedSalonDetails;

  // ==================== UI STATES ====================
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isLoadingSalons = false;
  bool _isLoadingServices = true;
  bool _isLoadingSalonData = false;

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
    _loadIpAddress();
    _searchController.addListener(_onSearchChanged);

    if (widget.refresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshData();
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
      if (mounted) setState(() => _isLoadingIp = false);
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

      final ip = _currentIp ?? await IpHelper.getPublicIp();

      final logData = {
        'owner_id': ownerId,
        'action_type': actionType,
        'target_type': targetType,
        'target_id': targetId,
        'details': details ?? {},
        'ip_address': ip,
        'created_at': DateTime.now().toIso8601String(),
      };

      debugPrint('📝 Logging activity: $actionType');
      await supabase.from('owner_activity_log').insert(logData);
      debugPrint('✅ Activity logged: $actionType');
    } catch (e) {
      debugPrint('❌ Error logging activity: $e');
    }
  }

  // ==================== LOAD DATA METHODS ====================
  Future<void> _loadInitialData() async {
    debugPrint('📥 Loading initial data...');
    setState(() => _isLoading = true);

    try {
      await Future.wait([_loadOwnerSalons()]);
    } catch (e) {
      debugPrint('❌ Error loading initial data: $e');
      if (mounted) _showSnackBar('Error loading data: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    debugPrint('🔄 Refreshing data...');
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      await Future.wait([_loadOwnerSalons(), _loadIpAddress()]);
    } catch (e) {
      debugPrint('❌ Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Data refreshed!', Colors.green);
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
          .select('id, name, address, logo_url, is_active')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('name');

      debugPrint('📊 Owner salons loaded: ${response.length}');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          if (_ownerSalons.length == 1) {
            _selectedSalonId = _ownerSalons[0]['id'].toString();
            _selectedSalonDetails = _ownerSalons[0];
            _loadSalonSpecificData();
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

  // ============================================================
  // UPDATED: Load salon-specific data with new schema
  // ============================================================

  Future<void> _loadSalonSpecificData() async {
    if (_selectedSalonId == null) return;

    setState(() => _isLoadingSalonData = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

      // Load salon categories (new schema - direct fields)
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select(
            'id, display_name, description, icon_name, color, display_order, is_active',
          )
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');

      // Load salon genders (new schema - direct fields)
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name, display_order, is_active')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');

      // Load salon age categories (new schema - direct fields)
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select(
            'id, display_name, min_age, max_age, display_order, is_active',
          )
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');

      debugPrint(
        '✅ Salon data loaded - Categories: ${categoriesResponse.length}, Genders: ${gendersResponse.length}, Age Cats: ${ageResponse.length}',
      );

      setState(() {
        _isLoadingSalonData = false;
      });

      // Reload services with new salon context
      await _loadServicesWithVariants();
    } catch (e) {
      debugPrint('❌ Error loading salon data: $e');
      setState(() => _isLoadingSalonData = false);
    }
  }

  // ============================================================
  // UPDATED: Load services and variants with new schema
  // ============================================================

  Future<void> _loadServicesWithVariants() async {
    if (_selectedSalonId == null) {
      setState(() => _isLoadingServices = false);
      return;
    }

    setState(() => _isLoadingServices = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

      // Load services (new schema - direct category_id from salon_categories)
      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            category_id,
            icon_name,
            is_active
          ''')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('name');

      debugPrint('📊 Services loaded: ${servicesResponse.length}');

      // Load categories to map category_id to display_name
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final Map<int, Map<String, dynamic>> categoryMap = {};
      for (var cat in categoriesResponse) {
        categoryMap[cat['id']] = cat;
      }

      // Load variants for these services
      final serviceIds = servicesResponse.map((s) => s['id'] as int).toList();

      List<Map<String, dynamic>> variantsResponse = [];

      if (serviceIds.isNotEmpty) {
        variantsResponse = await supabase
            .from('service_variants')
            .select('''
              id,
              service_id,
              price,
              duration,
              is_active,
              salon_gender_id,
              salon_age_category_id
            ''')
            .inFilter('service_id', serviceIds)
            .eq('is_active', true);
      }

      debugPrint('📊 Variants loaded: ${variantsResponse.length}');

      // Load genders and age categories for variant names
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final ageCategoriesResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final Map<int, String> genderMap = {};
      for (var g in gendersResponse) {
        genderMap[g['id']] = g['display_name'];
      }

      final Map<int, Map<String, dynamic>> ageMap = {};
      for (var a in ageCategoriesResponse) {
        ageMap[a['id']] = {
          'display_name': a['display_name'],
          'min_age': a['min_age'],
          'max_age': a['max_age'],
        };
      }

      // Group variants by service
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }

        final genderId = variant['salon_gender_id'];
        final ageId = variant['salon_age_category_id'];

        final genderName = genderMap[genderId] ?? 'Unknown';
        final ageData =
            ageMap[ageId] ??
            {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
        final ageName =
            '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';

        variantsByService[serviceId]!.add({
          'id': variant['id'],
          'price': (variant['price'] as num?)?.toDouble() ?? 0.0,
          'duration': variant['duration'] ?? 0,
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_category_name': ageName,
          'display_text': '$genderName • $ageName',
        });
      }

      // Process services
      final List<Map<String, dynamic>> processedServices = [];

      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final categoryId = service['category_id'];

        final category =
            categoryMap[categoryId] ??
            {'display_name': 'Other', 'icon_name': 'build', 'color': '#FF6B8B'};

        final variants = variantsByService[serviceId] ?? [];

        variants.sort((a, b) {
          final genderCompare = a['gender_name'].compareTo(b['gender_name']);
          if (genderCompare != 0) return genderCompare;
          return a['age_category_name'].compareTo(b['age_category_name']);
        });

        double minPrice = 0;
        double maxPrice = 0;

        if (variants.isNotEmpty) {
          final prices = variants
              .map<double>((v) => v['price'] as double)
              .toList();
          minPrice = prices.reduce((a, b) => a < b ? a : b);
          maxPrice = prices.reduce((a, b) => a > b ? a : b);
        }

        processedServices.add({
          'id': serviceId.toString(),
          'name': service['name']?.toString() ?? 'Unknown Service',
          'description': service['description']?.toString() ?? '',
          'category_id': categoryId,
          'category_name': category['display_name'],
          'icon': _getIconFromName(
            service['icon_name']?.toString() ??
                category['icon_name'] ??
                'build',
          ),
          'icon_name':
              service['icon_name']?.toString() ??
              category['icon_name'] ??
              'build',
          'color': category['color'] ?? '#FF6B8B',
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variant_count': variants.length,
          'min_price': minPrice,
          'max_price': maxPrice,
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
      case 'build':
        return Icons.build;
      case 'brush':
        return Icons.brush;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'massage':
        return Icons.message;
      case 'health_and_safety':
        return Icons.health_and_safety;
      case 'cut':
        return Icons.cut;
      case 'shower':
        return Icons.shower;
      case 'masks':
        return Icons.masks;
      case 'palette':
        return Icons.palette;
      case 'spa_outlined':
        return Icons.spa_outlined;
      default:
        return Icons.category;
    }
  }

  // ==================== SEARCH METHODS ====================
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
      if (!_isSearching) setState(() => _isSearching = true);
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _searchUsers(query);
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

      if (roleResponse == null) return;

      final barberRoleId = roleResponse['id'];

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('user_id')
          .eq('role_id', barberRoleId);

      if (userRolesResponse.isEmpty) {
        if (mounted) setState(() => _searchResults = []);
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

      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      debugPrint('❌ Search error: $e');
      if (mounted) setState(() => _searchResults = []);
    }
  }

  // ==================== SELECTION METHODS ====================
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
      return _selectedItems.containsKey(serviceId) &&
          _selectedItems[serviceId]!.isEmpty;
    } else {
      return _selectedItems[serviceId]?.contains(variantId) ?? false;
    }
  }

  int _getSelectedCount(String serviceId) {
    return _selectedItems[serviceId]?.length ?? 0;
  }

  Map<String, dynamic>? _findVariantById(String serviceId, int variantId) {
    try {
      Map<String, dynamic>? service;
      for (var s in _services) {
        final id = s['id'];
        if (id != null && id.toString() == serviceId) {
          service = s;
          break;
        }
      }

      if (service == null) return null;

      final variants = service['variants'];
      if (variants == null || variants is! List) return null;

      for (var v in variants) {
        if (v is Map<String, dynamic>) {
          final id = v['id'];
          if (id != null && id == variantId) {
            return v;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error finding variant: $e');
      return null;
    }
  }

  String _getBarberName() {
    final barber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
      orElse: () => {},
    );
    return barber['full_name'] ?? barber['email'] ?? 'Barber';
  }

  List<Widget> _buildSelectedServicesList() {
    final List<Widget> widgets = [];

    for (var entry in _selectedItems.entries) {
      final serviceId = entry.key;
      final variantIds = entry.value;

      Map<String, dynamic>? service;
      for (var s in _services) {
        final id = s['id'];
        if (id != null && id.toString() == serviceId) {
          service = s;
          break;
        }
      }

      if (service == null) continue;

      if (variantIds.isEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service['name']?.toString() ?? 'Service',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final variantWidgets = <Widget>[];
        for (var variantId in variantIds) {
          final variant = _findVariantById(serviceId, variantId);
          if (variant != null) {
            variantWidgets.add(
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        variant['display_text']?.toString() ?? 'Variant',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        if (variantWidgets.isNotEmpty) {
          widgets.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    service['name']?.toString() ?? 'Service',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ...variantWidgets,
              ],
            ),
          );
        }
      }
    }

    return widgets;
  }

  // ==================== ADD BARBER ====================
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
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add,
                color: Color(0xFFFF6B8B),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Confirm Add Barber',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: _isWeb ? 450 : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person,
                      color: Color(0xFFFF6B8B),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add ${_getBarberName()} to ${_selectedSalonDetails?['name'] ?? 'salon'}?',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Auto Schedule',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'All days (Mon-Sun) will be set as working days with salon hours',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Selected Services:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildSelectedServicesList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Confirm Add',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

      // ============================================================
      // STEP 1: Get salon times
      // ============================================================
      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time')
          .eq('id', salonIdInt)
          .single();

      final openTime = salonResponse['open_time'] as String? ?? '09:00:00';
      final closeTime = salonResponse['close_time'] as String? ?? '18:00:00';

      debugPrint('📅 Salon times - Open: $openTime, Close: $closeTime');

      // ============================================================
      // STEP 2: Use days 1-7 (Monday=1 to Sunday=7)
      // This matches the database constraint
      // ============================================================
      final List<int> weekDays = [1, 2, 3, 4, 5, 6, 7];
      final Map<int, String> dayNames = {
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      };

      debugPrint('📅 Creating schedules for days: $weekDays');

      // ============================================================
      // STEP 3: Get or create salon_barber entry
      // ============================================================
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('barber_id', _selectedBarberId!)
          .maybeSingle();

      int salonBarberId;

      if (salonBarberResponse == null) {
        final newSalonBarber = await supabase
            .from('salon_barbers')
            .insert({
              'salon_id': salonIdInt,
              'barber_id': _selectedBarberId!,
              'status': 'active',
            })
            .select('id')
            .single();
        salonBarberId = newSalonBarber['id'];
        debugPrint('✅ Created new salon_barber entry with id: $salonBarberId');
      } else {
        salonBarberId = salonBarberResponse['id'];
        await supabase
            .from('salon_barbers')
            .update({'status': 'active'})
            .eq('id', salonBarberId);
        debugPrint(
          '✅ Updated existing salon_barber entry with id: $salonBarberId',
        );
      }

      // ============================================================
      // STEP 4: Auto-create schedules for all days (1-7)
      // ============================================================
      debugPrint('📅 Creating barber schedules for all days...');

      int createdCount = 0;
      int updatedCount = 0;
      int errorCount = 0;
      List<String> errorDays = [];

      for (int dayOfWeek in weekDays) {
        try {
          // Check if schedule already exists
          final existingSchedule = await supabase
              .from('barber_schedules')
              .select('id')
              .eq('barber_id', _selectedBarberId!)
              .eq('salon_id', salonIdInt)
              .eq('day_of_week', dayOfWeek)
              .maybeSingle();

          if (existingSchedule == null) {
            // Create new schedule
            await supabase.from('barber_schedules').insert({
              'barber_id': _selectedBarberId!,
              'salon_id': salonIdInt,
              'day_of_week': dayOfWeek,
              'start_time': openTime,
              'end_time': closeTime,
              'is_working': true,
            });
            createdCount++;
            debugPrint(
              '✅ Created schedule for ${dayNames[dayOfWeek]} (day: $dayOfWeek)',
            );
          } else {
            // Update existing schedule
            await supabase
                .from('barber_schedules')
                .update({
                  'is_working': true,
                  'start_time': openTime,
                  'end_time': closeTime,
                })
                .eq('id', existingSchedule['id']);
            updatedCount++;
            debugPrint(
              '✅ Updated schedule for ${dayNames[dayOfWeek]} (day: $dayOfWeek)',
            );
          }
        } catch (e) {
          errorCount++;
          errorDays.add(dayNames[dayOfWeek] ?? 'Day $dayOfWeek');
          debugPrint(
            '❌ Error with day $dayOfWeek (${dayNames[dayOfWeek]}): $e',
          );
        }
      }

      debugPrint(
        '✅ Schedule summary - Created: $createdCount, Updated: $updatedCount, Errors: $errorCount',
      );

      if (errorCount > 0) {
        _showSnackBar(
          '$errorCount schedule(s) failed: ${errorDays.join(", ")}',
          Colors.orange,
        );
      }

      // ============================================================
      // STEP 5: Assign barber role if not already
      // ============================================================
      final userRoleCheck = await supabase
          .from('user_roles')
          .select()
          .eq('user_id', _selectedBarberId!);

      if (userRoleCheck.isEmpty) {
        final roleResponse = await supabase
            .from('roles')
            .select('id')
            .eq('name', 'barber')
            .maybeSingle();
        if (roleResponse != null) {
          await supabase.from('user_roles').insert({
            'user_id': _selectedBarberId!,
            'role_id': roleResponse['id'],
          });
          debugPrint('✅ Assigned barber role to user');
        }
      }

      // ============================================================
      // STEP 6: Add selected services and variants
      // ============================================================
      final selectedServicesList = [];
      int servicesAddedCount = 0;
      int variantsAddedCount = 0;

      for (var entry in _selectedItems.entries) {
        final serviceId = int.parse(entry.key);
        final variantIds = entry.value;

        Map<String, dynamic>? service;
        for (var s in _services) {
          if (s['id'] == entry.key) {
            service = s;
            break;
          }
        }

        if (service == null) continue;

        if (variantIds.isEmpty) {
          // Full service (no variants)
          selectedServicesList.add({
            'service_id': serviceId,
            'service_name': service['name'] ?? 'Unknown',
            'type': 'full_service',
          });

          final existing = await supabase
              .from('barber_services')
              .select()
              .eq('salon_barber_id', salonBarberId)
              .eq('service_id', serviceId)
              .filter('variant_id', 'is', null);

          if (existing.isEmpty) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': salonBarberId,
              'service_id': serviceId,
              'variant_id': null,
              'status': 'active',
            });
            servicesAddedCount++;
            debugPrint('✅ Added full service: ${service['name']}');
          } else {
            await supabase
                .from('barber_services')
                .update({'status': 'active'})
                .eq('id', existing[0]['id']);
            debugPrint('✅ Updated full service: ${service['name']}');
          }
        } else {
          // Selected variants
          for (var variantId in variantIds) {
            final variant = _findVariantById(entry.key, variantId);
            selectedServicesList.add({
              'service_id': serviceId,
              'service_name': service['name'] ?? 'Unknown',
              'variant_id': variantId,
              'variant_details': variant != null
                  ? (variant['display_text'] ?? 'Variant')
                  : 'Variant',
              'type': 'variant',
            });

            final existing = await supabase
                .from('barber_services')
                .select()
                .eq('salon_barber_id', salonBarberId)
                .eq('variant_id', variantId);

            if (existing.isEmpty) {
              await supabase.from('barber_services').insert({
                'salon_barber_id': salonBarberId,
                'service_id': serviceId,
                'variant_id': variantId,
                'status': 'active',
              });
              variantsAddedCount++;
              debugPrint(
                '✅ Added variant for ${service['name']}: ${variant?['display_text']}',
              );
            } else {
              await supabase
                  .from('barber_services')
                  .update({'status': 'active'})
                  .eq('id', existing[0]['id']);
              debugPrint(
                '✅ Updated variant for ${service['name']}: ${variant?['display_text']}',
              );
            }
          }
        }
      }

      debugPrint(
        '✅ Services summary - Full services: $servicesAddedCount, Variants: $variantsAddedCount',
      );

      // ============================================================
      // STEP 7: Log owner activity
      // ============================================================
      await _logOwnerActivity(
        actionType: 'add_barber',
        targetType: 'barber',
        targetId: _selectedBarberId,
        details: {
          'barber_name': _getBarberName(),
          'barber_id': _selectedBarberId,
          'salon_id': salonIdInt,
          'salon_name': _selectedSalonDetails?['name'],
          'salon_open_time': openTime,
          'salon_close_time': closeTime,
          'selected_services_count': _totalSelectedItems,
          'selected_services': selectedServicesList,
          'schedules_created': createdCount,
          'schedules_updated': updatedCount,
          'schedules_errors': errorCount,
          'schedules_error_days': errorDays,
          'services_added': servicesAddedCount,
          'variants_added': variantsAddedCount,
          'total_selected_items': _totalSelectedItems,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // ============================================================
      // STEP 8: Show success message and reset form
      // ============================================================
      if (mounted) {
        String message = 'Barber added successfully!\n';
        message += '• $createdCount schedules created, $updatedCount updated\n';
        if (errorCount > 0) message += '• ⚠️ $errorCount schedules failed\n';
        message +=
            '• $servicesAddedCount services, $variantsAddedCount variants added';

        _showSnackBar(message, errorCount > 0 ? Colors.orange : Colors.green);

        // Reset all selections
        setState(() {
          _selectedBarberId = null;
          _selectedItems.clear();
          _expandedServices.clear();
          _searchController.clear();
          _searchResults = [];
          _isSearching = false;
        });

        // Optional: Navigate back or refresh parent screen
        // context.pop(true); // Uncomment if you want to go back
      }
    } catch (e) {
      debugPrint('❌ Error adding barber: $e');
      _showSnackBar('Error: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==================== UI BUILDERS ====================

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
                separatorBuilder: (_, __) => const SizedBox(height: 8),
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
        border: Border.all(color: Colors.orange[200]!),
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
            onPressed: () => context.push('/owner/salon/create'),
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
      onTap: () {
        setState(() {
          _selectedSalonId = salon['id'].toString();
          _selectedSalonDetails = salon;
        });
        _loadSalonSpecificData();
      },
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
            CircleAvatar(
              radius: 20,
              backgroundColor: isSelected
                  ? const Color(0xFFFF6B8B)
                  : Colors.grey[100],
              backgroundImage: salon['logo_url'] != null
                  ? NetworkImage(salon['logo_url'])
                  : null,
              child: salon['logo_url'] == null
                  ? Icon(
                      Icons.store,
                      color: isSelected ? Colors.white : Colors.grey[600],
                      size: 20,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon['name'] ?? 'Unnamed Salon',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 15,
                    ),
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
                  separatorBuilder: (_, __) => const Divider(height: 1),
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
              decoration: const BoxDecoration(
                color: Color(0xFFFF6B8B),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            )
          : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
      onTap: () => setState(() => _selectedBarberId = barber['id']),
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

    // Group services by category
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
            ...groupedServices.entries.map(
              (entry) => _buildCategorySection(entry.key, entry.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    String categoryName,
    List<Map<String, dynamic>> services,
  ) {
    final categorySelectedCount = services.fold<int>(
      0,
      (sum, service) => sum + _getSelectedCount(service['id'] as String),
    );
    final categoryColor = _getCategoryColor(categoryName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          child: Row(
            children: [
              Icon(
                _getCategoryIcon(categoryName),
                size: _isWeb ? 24 : 20,
                color: categoryColor,
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
        if (_isWeb)
          SizedBox(
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
              itemBuilder: (context, index) =>
                  _buildServiceCard(services[index]),
            ),
          )
        else
          Column(
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
          onTap: () => _toggleSelection(serviceId),
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
                variant['gender_name'].toLowerCase().contains('male')
                    ? Icons.male
                    : variant['gender_name'].toLowerCase().contains('female')
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

  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName.toLowerCase()) {
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
        return Icons.category;
    }
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final isLoading =
        _isLoading ||
        _isLoadingServices ||
        _isLoadingSalons ||
        _isLoadingSalonData;

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
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
