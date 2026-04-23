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

  // Services with their variants
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

  // ==================== CATEGORY TAB STATE ====================
  String? _selectedCategoryTab;

  // ==================== TIMERS ====================
  Timer? _debounceTimer;

  // ==================== SUPABASE CLIENT ====================
  final supabase = Supabase.instance.client;

  // ==================== RESPONSIVE HELPERS ====================
  bool get _isWeb => MediaQuery.of(context).size.width > 800;

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

    if (mounted) setState(() => _isLoadingIp = true);

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
    if (mounted) setState(() => _isLoading = true);

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

    if (mounted) setState(() => _isLoading = true);

    try {
      await Future.wait([_loadOwnerSalons(), _loadIpAddress()]);
      if (_selectedSalonId != null) {
        await _loadSalonSpecificData();
      }
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
    if (mounted) setState(() => _isLoadingSalons = true);

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
  // Helper: Check if barber is already in salon
  // ============================================================
  Future<bool> _isBarberAlreadyInSalon(String barberId, int salonId) async {
    try {
      final response = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('barber_id', barberId)
          .eq('salon_id', salonId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('❌ Error checking barber in salon: $e');
      return false;
    }
  }

  // ============================================================
  // Search users using PostgreSQL function
  // ============================================================

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    debugPrint('🔍 _onSearchChanged called with query: "$query"');

    _debounceTimer?.cancel();

    if (query.isEmpty) {
      debugPrint('🔍 Query empty, clearing results');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _selectedBarberId = null;
        });
      }
      return;
    }

    if (_selectedSalonId == null) {
      debugPrint('⚠️ No salon selected, cannot search');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        _showSnackBar('Please select a salon first', Colors.orange);
      }
      return;
    }

    if (query.length >= 2) {
      debugPrint('🔍 Query length >= 2, starting search timer');
      if (mounted) setState(() => _isSearching = true);

      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        debugPrint('🔍 Debounce timer executed, calling _searchUsers');
        if (mounted) {
          _searchUsers(query);
        }
      });
    } else {
      debugPrint(
        '🔍 Query too short (${query.length}), waiting for more characters',
      );
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _searchUsers(String query) async {
    debugPrint('🔍🔍🔍 _searchUsers STARTED with query: "$query"');

    if (query.length < 2) return;

    if (_selectedSalonId == null) {
      debugPrint('⚠️ No salon selected');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }

    try {
      if (mounted) setState(() => _isSearching = true);

      final response = await supabase.rpc(
        'get_all_barbers',
        params: {'search_query': query},
      );

      debugPrint('📊 Function response length: ${response.length}');

      if (response.isEmpty) {
        debugPrint('⚠️ No barbers found from function');
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
          _showSnackBar('No barbers found matching "$query"', Colors.orange);
        }
        return;
      }

      final List<Map<String, dynamic>> results = [];

      for (var barber in response) {
        final alreadyInSalon = await _isBarberAlreadyInSalon(
          barber['user_id'],
          int.parse(_selectedSalonId!),
        );

        results.add({
          'id': barber['user_id'],
          'full_name': barber['full_name'] ?? 'Unknown',
          'email': barber['email'] ?? '',
          'avatar_url': barber['avatar_url'],
          'already_in_salon': alreadyInSalon,
        });
      }

      results.sort((a, b) {
        if (a['already_in_salon'] == b['already_in_salon']) return 0;
        return a['already_in_salon'] ? 1 : -1;
      });

      debugPrint(
        '✅ Search complete - Found ${results.length} matching barbers',
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }

      if (results.isEmpty && mounted) {
        _showSnackBar('No barbers found matching "$query"', Colors.orange);
      }
    } catch (e) {
      debugPrint('❌ Search error: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        _showSnackBar('Error searching barbers: ${e.toString()}', Colors.red);
      }
    }
  }

  // ============================================================
  // Load salon-specific data
  // ============================================================

  Future<void> _loadSalonSpecificData() async {
    if (_selectedSalonId == null) return;

    if (mounted) setState(() => _isLoadingSalonData = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

      final categoriesResponse = await supabase
          .from('salon_categories')
          .select(
            'id, display_name, description, icon_name, color, display_order, is_active',
          )
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');

      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name, display_order, is_active')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');

      final ageCategoriesResponse = await supabase
          .from('salon_age_categories')
          .select(
            'id, display_name, min_age, max_age, display_order, is_active',
          )
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('display_order');

      debugPrint(
        '✅ Salon data loaded - Categories: ${categoriesResponse.length}, Genders: ${gendersResponse.length}, Age Cats: ${ageCategoriesResponse.length}',
      );

      if (mounted) {
        setState(() {
          _isLoadingSalonData = false;
        });
      }

      await _loadServicesWithVariants();

      _searchController.clear();
      if (mounted) {
        setState(() {
          _searchResults = [];
          _selectedBarberId = null;
          _isSearching = false;
          _selectedCategoryTab = null;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salon data: $e');
      if (mounted) setState(() => _isLoadingSalonData = false);
    }
  }

  // ============================================================
  // Load services and variants - WITH DEFAULT EXPAND ALL
  // ============================================================

  Future<void> _loadServicesWithVariants() async {
    if (_selectedSalonId == null) {
      if (mounted) setState(() => _isLoadingServices = false);
      return;
    }

    if (mounted) setState(() => _isLoadingServices = true);

    try {
      final salonIdInt = int.parse(_selectedSalonId!);

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

      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      final Map<int, Map<String, dynamic>> categoryMap = {};
      for (var cat in categoriesResponse) {
        categoryMap[cat['id']] = cat;
      }

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

          _expandedServices.clear();
          for (var service in processedServices) {
            final serviceId = service['id'] as String;
            if (service['hasVariants'] == true) {
              _expandedServices.add(serviceId);
            }
          }
          debugPrint(
            '✅ Expanded ${_expandedServices.length} services by default',
          );
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

  void _expandAllServices() {
    setState(() {
      _expandedServices.clear();
      for (var service in _services) {
        final serviceId = service['id'] as String;
        if (service['hasVariants'] == true) {
          _expandedServices.add(serviceId);
        }
      }
    });
  }

  void _collapseAllServices() {
    setState(() {
      _expandedServices.clear();
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
      for (var s in _services) {
        if (s['id'].toString() == serviceId) {
          for (var v in s['variants']) {
            if (v['id'] == variantId) return v;
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
        if (s['id'].toString() == serviceId) {
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
                    service['name'] ?? 'Service',
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
                    service['name'] ?? 'Service',
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
    if (mounted) _showSnackBar('Please select a barber', Colors.red);
    return;
  }
  if (_selectedSalonId == null) {
    if (mounted) _showSnackBar('Please select a salon', Colors.red);
    return;
  }
  if (_totalSelectedItems == 0) {
    if (mounted) {
      _showSnackBar('Please select at least one service', Colors.red);
    }
    return;
  }

  final alreadyExists = await _isBarberAlreadyInSalon(
    _selectedBarberId!,
    int.parse(_selectedSalonId!),
  );

  if (alreadyExists) {
    if (mounted) {
      _showSnackBar(
        'This barber is already added to the salon',
        Colors.orange,
      );
    }
    return;
  }
  if (!mounted) return;
  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFFF6B8B),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_add,
              color: Colors.white,
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.restaurant, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lunch Break',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Lunch break will be set from 12:00 PM to 1:00 PM',
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
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text(
            'Cancel',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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

  if (mounted) setState(() => _isLoading = true);

  try {
    final salonIdInt = int.parse(_selectedSalonId!);

    final salonResponse = await supabase
        .from('salons')
        .select('open_time, close_time')
        .eq('id', salonIdInt)
        .single();

    final openTime = salonResponse['open_time'] as String? ?? '09:00:00';
    final closeTime = salonResponse['close_time'] as String? ?? '18:00:00';

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
    } else {
      salonBarberId = salonBarberResponse['id'];
      await supabase
          .from('salon_barbers')
          .update({'status': 'active'})
          .eq('id', salonBarberId);
    }

    // ==================== CREATE WORK SCHEDULES ====================
    int createdCount = 0, updatedCount = 0, errorCount = 0;
    List<String> errorDays = [];

    for (int dayOfWeek in weekDays) {
      try {
        final existingSchedule = await supabase
            .from('barber_schedules')
            .select('id')
            .eq('barber_id', _selectedBarberId!)
            .eq('salon_id', salonIdInt)
            .eq('day_of_week', dayOfWeek)
            .maybeSingle();

        if (existingSchedule == null) {
          await supabase.from('barber_schedules').insert({
            'barber_id': _selectedBarberId!,
            'salon_id': salonIdInt,
            'day_of_week': dayOfWeek,
            'start_time': openTime,
            'end_time': closeTime,
            'is_working': true,
          });
          createdCount++;
        } else {
          await supabase
              .from('barber_schedules')
              .update({
                'is_working': true,
                'start_time': openTime,
                'end_time': closeTime,
              })
              .eq('id', existingSchedule['id']);
          updatedCount++;
        }
      } catch (e) {
        errorCount++;
        errorDays.add(dayNames[dayOfWeek] ?? 'Day $dayOfWeek');
      }
    }

    // ==================== CREATE LUNCH BREAKS ====================
    // Lunch break: 12:00 to 13:00 for all days (Monday to Sunday)
    int lunchBreakCreatedCount = 0;
    int lunchBreakUpdatedCount = 0;
    List<String> lunchBreakErrorDays = [];

    for (int dayOfWeek in weekDays) {
      try {
        // Check if lunch break already exists for this day
        final existingBreak = await supabase
            .from('barber_breaks')
            .select('id')
            .eq('barber_id', _selectedBarberId!)
            .eq('salon_id', salonIdInt)
            .eq('day_of_week', dayOfWeek)
            .eq('break_type', 'lunch')
            .maybeSingle();

        if (existingBreak == null) {
          // Insert new lunch break
          await supabase.from('barber_breaks').insert({
            'barber_id': _selectedBarberId!,
            'salon_id': salonIdInt,
            'day_of_week': dayOfWeek,
            'start_time': '12:00:00',
            'end_time': '13:00:00',
            'break_type': 'lunch',
          });
          lunchBreakCreatedCount++;
        } else {
          // Update existing lunch break
          await supabase
              .from('barber_breaks')
              .update({
                'start_time': '12:00:00',
                'end_time': '13:00:00',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', existingBreak['id']);
          lunchBreakUpdatedCount++;
        }
      } catch (e) {
        lunchBreakErrorDays.add(dayNames[dayOfWeek] ?? 'Day $dayOfWeek');
        debugPrint('❌ Error creating lunch break for ${dayNames[dayOfWeek]}: $e');
      }
    }

    // ==================== ENSURE BARBER ROLE ====================
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
      }
    }

    // ==================== ADD SELECTED SERVICES ====================
    final selectedServicesList = [];
    int servicesAddedCount = 0, variantsAddedCount = 0;

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
          });
          servicesAddedCount++;
        }
      } else {
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
            });
            variantsAddedCount++;
          }
        }
      }
    }

    // ==================== LOG ACTIVITY ====================
    await _logOwnerActivity(
      actionType: 'add_barber',
      targetType: 'barber',
      targetId: _selectedBarberId,
      details: {
        'barber_name': _getBarberName(),
        'barber_id': _selectedBarberId,
        'salon_id': salonIdInt,
        'salon_name': _selectedSalonDetails?['name'],
        'selected_services_count': _totalSelectedItems,
        'selected_services': selectedServicesList,
        'schedules_created': createdCount,
        'schedules_updated': updatedCount,
        'lunch_breaks_created': lunchBreakCreatedCount,
        'lunch_breaks_updated': lunchBreakUpdatedCount,
        'services_added': servicesAddedCount,
        'variants_added': variantsAddedCount,
      },
    );

    if (mounted) {
      String message = 
          'Barber added successfully!\n'
          '• $createdCount schedules created\n'
          '• $lunchBreakCreatedCount lunch breaks added (12:00-13:00)\n'
          '• $servicesAddedCount services, $variantsAddedCount variants added';
      
      if (lunchBreakErrorDays.isNotEmpty) {
        message += '\n⚠️ Lunch break failed for: ${lunchBreakErrorDays.join(', ')}';
      }
      
      _showSnackBar(message, errorCount > 0 || lunchBreakErrorDays.isNotEmpty ? Colors.orange : Colors.green);

      setState(() {
        _selectedBarberId = null;
        _selectedItems.clear();
        _expandedServices.clear();
        _searchController.clear();
        _searchResults = [];
        _isSearching = false;
        _selectedCategoryTab = null;
      });
    }
  } catch (e) {
    debugPrint('❌ Error adding barber: $e');
    if (mounted) _showSnackBar('Error: ${e.toString()}', Colors.red);
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

  Widget _buildCategoryChip(String label, bool isSelected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFFFF6B8B),
      backgroundColor: Colors.grey[100],
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected ? const Color(0xFFFF6B8B) : Colors.transparent,
          width: 1,
        ),
      ),
    );
  }

  // ============================================================
  // UPDATED SERVICE CARD WITH ALTERNATING COLORS
  // ============================================================

  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final serviceId = service['id'] as String;
    final hasVariants = service['hasVariants'] as bool;
    final variants = service['variants'] as List;
    final selectedCount = _getSelectedCount(serviceId);
    final isExpanded = _expandedServices.contains(serviceId);
    final accentColor = const Color(0xFFFF6B8B);
    final cardColor = _cardColors[index % _cardColors.length];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selectedCount > 0 ? accentColor : Colors.grey[200]!,
          width: selectedCount > 0 ? 2 : 1,
        ),
      ),
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
                      service['icon'] ?? Icons.build,
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
                          service['name'] ?? 'Service',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  if (selectedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
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
                      onPressed: () => _toggleExpand(serviceId),
                    ),
                ],
              ),
            ),
            if (service['description'] != null &&
                service['description'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service['description'],
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasVariants) ...[
                    if (isExpanded) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Select Options:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...variants.map(
                        (variant) => _buildVariantCard(serviceId, variant),
                      ),
                    ] else if (selectedCount > 0) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$selectedCount option${selectedCount > 1 ? 's' : ''} selected',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    const Divider(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _toggleSelection(serviceId),
                        icon: Icon(
                          _isSelected(serviceId)
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          size: 18,
                        ),
                        label: Text(
                          _isSelected(serviceId) ? 'Selected' : 'Select Service',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSelected(serviceId)
                              ? Colors.green
                              : accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
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

  Widget _buildVariantCard(String serviceId, Map<String, dynamic> variant) {
    final isSelected = _isSelected(serviceId, variant['id']);

    return GestureDetector(
      onTap: () => _toggleSelection(serviceId, variant['id']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFF6B8B).withValues(alpha: 0.2)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                variant['gender_name'].toLowerCase().contains('male')
                    ? Icons.male
                    : variant['gender_name'].toLowerCase().contains('female')
                    ? Icons.female
                    : Icons.people,
                color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant['display_text'] ??
                        '${variant['gender_name']} • ${variant['age_category_name']}',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 13,
                      color: isSelected
                          ? const Color(0xFFFF6B8B)
                          : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.currency_rupee,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${variant['price']}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.timer, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 2),
                      Text(
                        '${variant['duration']} min',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? const Color(0xFFFF6B8B)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFF6B8B)
                      : Colors.grey[400]!,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesSection() {
    if (_services.isEmpty) {
      return Card(
        elevation: _isWeb ? 4 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(40),
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
              const SizedBox(height: 8),
              Text(
                'Please add services to this salon first',
                style: TextStyle(
                  fontSize: _isWeb ? 14 : 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
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

    final List<String> categories = groupedServices.keys.toList();
    if (_selectedCategoryTab == null && categories.isNotEmpty) {
      _selectedCategoryTab = categories.first;
    }

    List<Map<String, dynamic>> servicesToShow = [];
    if (_selectedCategoryTab == null) {
      for (var services in groupedServices.values) {
        servicesToShow.addAll(services);
      }
    } else {
      servicesToShow = groupedServices[_selectedCategoryTab] ?? [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 45,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildCategoryChip('All', _selectedCategoryTab == null, () {
                if (mounted) setState(() => _selectedCategoryTab = null);
              }),
              const SizedBox(width: 8),
              ...categories.map(
                (category) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildCategoryChip(
                    category,
                    _selectedCategoryTab == category,
                    () {
                      if (mounted) {
                        setState(() => _selectedCategoryTab = category);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isWeb)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: servicesToShow.length,
            itemBuilder: (context, index) =>
                _buildServiceCard(servicesToShow[index], index),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: servicesToShow.length,
            itemBuilder: (context, index) =>
                _buildServiceCard(servicesToShow[index], index),
          ),
      ],
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
        if (mounted) {
          setState(() {
            _selectedSalonId = salon['id'].toString();
            _selectedSalonDetails = salon;
            _selectedBarberId = null;
            _selectedItems.clear();
            _searchController.clear();
            _searchResults = [];
            _isSearching = false;
            _selectedCategoryTab = null;
          });
        }
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
              enabled: _selectedSalonId != null,
              decoration: InputDecoration(
                hintText: _selectedSalonId != null
                    ? 'Type name or email to search...'
                    : 'Select a salon first',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) {
                            setState(() {
                              _searchResults = [];
                              _isSearching = false;
                              _selectedBarberId = null;
                            });
                          }
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
                fillColor: _selectedSalonId != null
                    ? Colors.grey[50]
                    : Colors.grey[100],
              ),
            ),
            if (_selectedSalonId == null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Text(
                  '⚠️ Please select a salon first to search barbers',
                  style: TextStyle(
                    fontSize: _isWeb ? 13 : 12,
                    color: Colors.orange[700],
                    fontStyle: FontStyle.italic,
                  ),
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
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                      SizedBox(height: 12),
                      Text('Searching for barbers...'),
                    ],
                  ),
                ),
              ),
            ] else if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 16),
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
            ] else if (_searchController.text.isNotEmpty &&
                _searchController.text.length >= 2 &&
                !_isSearching) ...[
              const SizedBox(height: 16),
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
                      Text(
                        'Try a different name or email',
                        style: TextStyle(
                          fontSize: _isWeb ? 12 : 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBarberTile(Map<String, dynamic> barber, bool isSelected) {
    final alreadyInSalon = barber['already_in_salon'] == true;
    final isDisabled = alreadyInSalon && !isSelected;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isSelected
            ? const Color(0xFFFF6B8B)
            : alreadyInSalon
            ? Colors.grey[400]
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              barber['full_name'] ?? 'Unknown',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: _isWeb ? 16 : 14,
                color: alreadyInSalon && !isSelected ? Colors.grey : null,
              ),
            ),
          ),
          if (alreadyInSalon && !isSelected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 0.5),
              ),
              child: const Text(
                'Already Added',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        barber['email'] ?? '',
        style: TextStyle(
          fontSize: _isWeb ? 14 : 12,
          color: alreadyInSalon && !isSelected ? Colors.grey[500] : null,
        ),
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
          : alreadyInSalon
          ? const Icon(Icons.check_circle, color: Colors.grey, size: 20)
          : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
      onTap: isDisabled
          ? null
          : () {
              if (mounted) setState(() => _selectedBarberId = barber['id']);
            },
      enabled: !isDisabled,
    );
  }

  Widget _buildSelectedBarber() {
    final barber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
      orElse: () => {},
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
          if (_services.any((s) => s['hasVariants'] == true))
            IconButton(
              icon: const Icon(Icons.unfold_more),
              onPressed: _expandAllServices,
              tooltip: 'Expand All',
            ),
          if (_services.any((s) => s['hasVariants'] == true))
            IconButton(
              icon: const Icon(Icons.compress),
              onPressed: _collapseAllServices,
              tooltip: 'Collapse All',
            ),
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