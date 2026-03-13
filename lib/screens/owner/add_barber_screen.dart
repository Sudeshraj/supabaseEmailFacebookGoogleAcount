import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/category_model.dart';

class AddBarberScreen extends StatefulWidget {
  final bool refresh;  // 🔥 New parameter for refresh trigger
  
  const AddBarberScreen({super.key, this.refresh = false});

  @override
  State<AddBarberScreen> createState() => _AddBarberScreenState();
}

class _AddBarberScreenState extends State<AddBarberScreen> with RouteAware {  // 🔥 RouteAware added
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = false;
  String? _selectedBarberId;
  
  // Salon selection
  List<Map<String, dynamic>> _ownerSalons = [];
  String? _selectedSalonId;
  bool _isLoadingSalons = false;
  
  // Debounce timer for search
  Timer? _debounceTimer;

  // Categories from database
  List<CategoryModel> _categories = [];

  // Services grouped by category
  Map<String, List<Map<String, dynamic>>> _servicesByCategory = {};

  // Available services list
  List<Map<String, dynamic>> _availableServices = [];

  // Selected services for the barber
  final Set<String> _selectedServiceIds = {};

  bool _isLoadingServices = true;
  bool _isLoadingCategories = true;

  final supabase = Supabase.instance.client;

  // Responsive layout helpers
  bool get _isWeb => MediaQuery.of(context).size.width > 800;
  bool get _isTablet => MediaQuery.of(context).size.width > 600 && MediaQuery.of(context).size.width <= 800;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_onSearchChanged);
    
    // 🔥 If widget.refresh is true, refresh data after build
    if (widget.refresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshData();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 🔥 Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    // 🔥 Unsubscribe from route changes
    routeObserver.unsubscribe(this);
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // 🔥 Called when this route is popped back to
  @override
  void didPopNext() {
    debugPrint('📍 AddBarberScreen came to foreground - refreshing data');
    _refreshData();
  }

  // 🔥 Load initial data
  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadCategoriesAndServices(),
      _loadOwnerSalons(),
    ]);
  }

  // 🔥 Refresh all data
  Future<void> _refreshData() async {
    debugPrint('🔄 Refreshing AddBarberScreen data...');
    setState(() {
      _isLoading = true;
    });
    
    await Future.wait([
      _loadCategoriesAndServices(),
      _loadOwnerSalons(),
    ]);
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Data refreshed successfully!', Colors.green);
    }
  }

  // Load owner's salons
  Future<void> _loadOwnerSalons() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingSalons = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('salons')
          .select('id, name, address, phone, is_active')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('name', ascending: true);

      debugPrint('📊 Owner salons loaded: ${response.length}');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          // Auto-select if only one salon
          if (_ownerSalons.length == 1) {
            _selectedSalonId = _ownerSalons[0]['id'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salons: $e');
      if (mounted) {
        _showSnackBar('Error loading salons: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSalons = false;
        });
      }
    }
  }

  // 🔥 Optimized search with faster response
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }
    
    if (query.length >= 2) {
      if (mounted) {
        setState(() {
          _isSearching = true;
        });
      }
      
      // 🔥 Faster debounce (150ms for instant feel)
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          _searchUsers(query);
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = true;
        });
      }
    }
  }

  // Load categories and services
  Future<void> _loadCategoriesAndServices() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingCategories = true;
      _isLoadingServices = true;
    });

    try {
      await _loadCategories();
      await _loadServicesFromDatabase();
    } catch (e) {
      debugPrint('❌ Error loading categories and services: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCategories = false;
          _isLoadingServices = false;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final response = await supabase
          .from('categories')
          .select('''
            id,
            name,
            description,
            icon_name,
            color,
            display_order,
            is_active
          ''')
          .eq('is_active', true)
          .order('display_order', ascending: true);

      if (response.isNotEmpty && mounted) {
        setState(() {
          _categories = response
              .map((cat) => CategoryModel.fromJson(cat))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
      rethrow;
    }
  }

  Future<void> _loadServicesFromDatabase() async {
    try {
      final response = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            price,
            duration,
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

      if (response.isNotEmpty && mounted) {
        final List<Map<String, dynamic>> services = [];
        final Map<String, List<Map<String, dynamic>>> grouped = {};

        for (var service in response) {
          final categoryData = service['categories'] as Map<String, dynamic>;
          final categoryName = categoryData['name'] ?? 'other';
          final iconName = categoryData['icon_name'] ?? 'build_circle_outlined';

          final serviceMap = {
            'id': service['id'].toString(),
            'name': service['name'] ?? 'Unknown Service',
            'price': (service['price'] as num?)?.toDouble() ?? 0.0,
            'duration': service['duration'] ?? 30,
            'description': service['description'] ?? '',
            'category_id': service['category_id'],
            'category_name': categoryName,
            'icon': _getIconFromName(iconName),
            'image_url': service['image_url'],
          };

          services.add(serviceMap);

          if (!grouped.containsKey(categoryName)) {
            grouped[categoryName] = [];
          }
          grouped[categoryName]!.add(serviceMap);
        }

        if (mounted) {
          setState(() {
            _availableServices = services;
            _servicesByCategory = grouped;
          });
        }
      } else if (mounted) {
        setState(() {
          _availableServices = [];
          _servicesByCategory = {};
        });

        _showSnackBar('No services found. Please add services first.', Colors.orange);
      }
    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      if (mounted) {
        setState(() {
          _availableServices = [];
          _servicesByCategory = {};
        });
      }
      rethrow;
    }
  }

  // 🎨 Get icon from name
  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'content_cut': return Icons.content_cut;
      case 'face': return Icons.face;
      case 'face_retouching_natural': return Icons.face_retouching_natural;
      case 'spa': return Icons.spa;
      case 'handshake': return Icons.handshake;
      case 'build_circle_outlined': return Icons.build_circle_outlined;
      case 'brush': return Icons.brush;
      case 'cleaning_services': return Icons.cleaning_services;
      case 'local_hospital': return Icons.local_hospital;
      case 'sports_kabaddi': return Icons.sports_kabaddi;
      default: return Icons.category_outlined;
    }
  }

  // 🔍 Search users - Optimized version
  Future<void> _searchUsers(String query) async {
    if (!mounted) return;
    
    // Don't show loading for empty results
    if (_searchResults.isEmpty) {
      setState(() {});
    }

    try {
      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'barber')
          .maybeSingle();

      if (roleResponse == null) {
        throw Exception('Barber role not found');
      }

      final barberRoleId = roleResponse['id'];
      final searchPattern = '%$query%';

      // 🔥 Optimized query with limit 10 for faster results
      final response = await supabase
          .from('profiles')
          .select('''
            id,
            role_id,
            full_name,
            email,
            phone,
            avatar_url,
            extra_data,
            is_active
          ''')
          .eq('role_id', barberRoleId)
          .eq('is_active', true)
          .or('full_name.ilike.$searchPattern,email.ilike.$searchPattern')
          .order('full_name', ascending: true)
          .limit(10);  // Limit to 10 for faster response

      if (mounted) {
        setState(() {
          if (response.isNotEmpty) {
            _searchResults = response.map((profile) {
              final extraData = profile['extra_data'] as Map<String, dynamic>? ?? {};
              
              String displayName = profile['full_name'] ?? '';
              if (displayName.isEmpty) {
                displayName = extraData['full_name'] ?? 
                             extraData['company_name'] ?? 
                             extraData['name'] ?? 
                             'Unknown Barber';
              }
              
              return {
                'id': profile['id'],
                'email': profile['email'] ?? extraData['email'] ?? 'No email',
                'name': displayName,
                'photo': profile['avatar_url'] ?? extraData['avatar_url'],
                'role': 'barber',
                'services': extraData['services'] ?? [],
              };
            }).toList();
          } else {
            _searchResults = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error searching barbers: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('Error searching barbers: $e', Colors.red);
      }
    }
  }

  // Check if barber already exists in selected salon
  Future<bool> _isBarberAlreadyInSalon(String barberId, int salonId) async {
    try {
      final existing = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', salonId)
          .eq('barber_id', barberId)
          .maybeSingle();
      
      return existing != null;
    } catch (e) {
      debugPrint('❌ Error checking existing barber: $e');
      return false;
    }
  }

  // ✅ Add barber to salon - COMPLETE FIXED VERSION WITH SALON_ID
  Future<void> _addBarberToSalon() async {
    if (!mounted) return;
    
    // Validation
    if (_selectedBarberId == null) {
      _showSnackBar('Please select a barber first', Colors.red);
      return;
    }

    if (_selectedSalonId == null) {
      _showSnackBar('Please select a salon', Colors.red);
      return;
    }

    if (_selectedServiceIds.isEmpty) {
      _showSnackBar('Please select at least one service', Colors.red);
      return;
    }

    final selectedBarber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
    );
    
    final selectedServices = _availableServices
        .where((s) => _selectedServiceIds.contains(s['id']))
        .toList();

    final selectedSalon = _ownerSalons.firstWhere(
      (s) => s['id'].toString() == _selectedSalonId,
    );

    // Check if barber already exists in this salon
    final salonIdInt = int.parse(_selectedSalonId!);
    final alreadyExists = await _isBarberAlreadyInSalon(_selectedBarberId!, salonIdInt);
    
    if (alreadyExists) {
      _showSnackBar('This barber is already added to this salon', Colors.orange);
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Add Barber'),
        content: Container(
          width: _isWeb ? 400 : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add ${selectedBarber['name']} to ${selectedSalon['name']}?'),
              const SizedBox(height: 8),
              Text('Salon: ${selectedSalon['name']}', 
                style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'Services:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...selectedServices.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Row(
                    children: [
                      Icon(s['icon'], size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s['name'], style: const TextStyle(fontSize: 13)),
                            Text(
                              '${s['category_name']} • Rs. ${s['price']} • ${s['duration']} min',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // STEP 1: Get barber role ID
      final roleList = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'barber');

      if (roleList.isEmpty) {
        throw Exception('Barber role not found in database');
      }
      final barberRoleId = roleList[0]['id'];
      debugPrint('✅ Barber role ID: $barberRoleId');

      // STEP 2: Get current profile - with role_id filter
      final profileList = await supabase
          .from('profiles')
          .select()
          .eq('id', _selectedBarberId!)
          .eq('role_id', barberRoleId);

      if (profileList.isEmpty) {
        throw Exception('Barber profile not found');
      }
      final currentProfile = profileList[0];
      debugPrint('✅ Current profile found');

      // STEP 3: Get salon
      final salonIdInt = int.parse(_selectedSalonId!);
      
      final salonList = await supabase
          .from('salons')
          .select('id, name')
          .eq('id', salonIdInt);

      if (salonList.isEmpty) {
        throw Exception('Salon not found');
      }

      final salonData = salonList[0];
      final salonId = salonData['id'];
      final salonName = salonData['name'];
      debugPrint('✅ Using salon: $salonName (ID: $salonId)');

      // Get existing services from extra_data
      final existingServices = currentProfile['extra_data']?['services'] ?? [];
      
      // Prepare extra_data - merge existing services with new ones
      final updatedExtraData = {
        ...currentProfile['extra_data'] ?? {},
        'services': [
          ...existingServices,
          ...selectedServices.map(
            (s) => {
              'id': int.parse(s['id']),
              'name': s['name'],
              'price': s['price'],
              'duration': s['duration'],
              'category_id': s['category_id'],
              'category_name': s['category_name'],
              'salon_id': salonId,  // 🔥 Add salon_id to extra_data
            },
          ),
        ],
        'added_by': supabase.auth.currentUser?.id,
        'added_at': DateTime.now().toIso8601String(),
        'salon_id': _selectedSalonId,
        'salon_name': salonName,
        'previous_role': currentProfile['role_id'],
      };

      // STEP 4: Update profile - WITH role_id filter
      await supabase
          .from('profiles')
          .update({
            'extra_data': updatedExtraData,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _selectedBarberId!)
          .eq('role_id', barberRoleId);

      debugPrint('✅ Profile updated');

      // STEP 5: Add to salon_barbers
      try {
        final salonBarberList = await supabase
            .from('salon_barbers')
            .select()
            .eq('salon_id', salonId)
            .eq('barber_id', _selectedBarberId!);

        if (salonBarberList.isEmpty) {
          debugPrint('📝 Attempting to insert into salon_barbers...');
          
          await supabase
              .from('salon_barbers')
              .insert({
                'salon_id': salonId,
                'barber_id': _selectedBarberId!,
                'is_active': true,
              });
          
          debugPrint('✅ Added to salon_barbers');
        } else {
          debugPrint('ℹ️ Already in salon_barbers');
        }
      } catch (e) {
        debugPrint('⚠️ Warning with salon_barbers: $e');
        // Don't throw - continue with service addition
      }

      // STEP 6: Add services to barber_services - WITH SALON_ID
      for (var service in selectedServices) {
        try {
          // Check if service already exists for this barber in this salon
          final serviceList = await supabase
              .from('barber_services')
              .select()
              .eq('barber_id', _selectedBarberId!)
              .eq('service_id', int.parse(service['id']))
              .eq('salon_id', salonId);  // 🔥 Check with salon_id

          if (serviceList.isEmpty) {
            // Insert with salon_id
            final insertData = {
              'barber_id': _selectedBarberId!,
              'service_id': int.parse(service['id']),
              'custom_price': service['price'],
              'salon_id': salonId,  // 🔥 Add salon_id
              'is_active': true,
            };
            
            debugPrint('📝 Inserting barber service: $insertData');
            
            await supabase
                .from('barber_services')
                .insert(insertData);
            
            debugPrint('✅ Service added: ${service['name']} for salon ID: $salonId');
          } else {
            debugPrint('ℹ️ Service already exists for this barber in this salon: ${service['name']}');
          }
        } catch (e) {
          debugPrint('⚠️ Error adding service ${service['name']}: $e');
        }
      }

      // Success!
      if (mounted) {
        _showSnackBar(
          '✅ ${selectedBarber['name']} added to $salonName successfully!',
          Colors.green,
        );

        // Clear selection and go back after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            context.pop();
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error adding barber: $e');
      if (mounted) {
        _showSnackBar('Error adding barber: ${e.toString()}', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      ),
    );
  }

  void _toggleService(Map<String, dynamic> service) {
    if (!mounted) return;
    setState(() {
      if (_selectedServiceIds.contains(service['id'])) {
        _selectedServiceIds.remove(service['id']);
        _showSnackBar('${service['name']} removed', Colors.orange);
      } else {
        _selectedServiceIds.add(service['id']);
        _showSnackBar('${service['name']} added', Colors.green);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoading || _isLoadingServices || _isLoadingCategories || _isLoadingSalons;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Barber'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: _isWeb,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
          if (_selectedBarberId != null && _selectedServiceIds.isNotEmpty && _selectedSalonId != null && !isLoading)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _addBarberToSalon,
              tooltip: 'Add Barber',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : RefreshIndicator(  // 🔥 Pull-to-refresh added
              onRefresh: _refreshData,
              color: const Color(0xFFFF6B8B),
              child: Container(
                color: Colors.grey[50],
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _isWeb ? 1200 : double.infinity,
                    ),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(), // 🔥 Important for RefreshIndicator
                      padding: EdgeInsets.all(_isWeb ? 24 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Salon Selection Section
                          _buildSalonSelectionSection(screenWidth),
                          
                          const SizedBox(height: 24),
                          
                          // Search Section
                          _buildSearchSection(screenWidth),
                          
                          const SizedBox(height: 24),
                          
                          // Selected Barber
                          if (_selectedBarberId != null) ...[
                            _buildSelectedBarber(),
                            const SizedBox(height: 24),
                          ],

                          // Services Section
                          _buildServicesSection(screenWidth),

                          const SizedBox(height: 24),

                          // Add Button
                          if (_selectedBarberId != null && _selectedServiceIds.isNotEmpty && _selectedSalonId != null && _availableServices.isNotEmpty)
                            _buildAddButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // Salon Selection Section
  Widget _buildSalonSelectionSection(double screenWidth) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.store, color: const Color(0xFFFF6B8B), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Select Salon',
                  style: TextStyle(
                    fontSize: _isWeb ? 18 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_ownerSalons.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.storefront, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No salons found',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Please create a salon first',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        // 🔥 Navigate to create salon and wait for result
                        final result = await context.push<bool>('/owner/salon/create');
                        
                        // If salon created successfully, refresh data
                        if (result == true) {
                          _refreshData();
                          _showSnackBar('Salon created successfully! Refreshing...', Colors.green);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B8B),
                      ),
                      child: const Text('Create Salon'),
                    ),
                  ],
                ),
              )
            else
              _isWeb
                  ? GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: screenWidth > 1000 ? 3 : 2,
                        childAspectRatio: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _ownerSalons.length,
                      itemBuilder: (context, index) {
                        final salon = _ownerSalons[index];
                        final isSelected = _selectedSalonId == salon['id'].toString();
                        return _buildSalonCard(salon, isSelected);
                      },
                    )
                  : ListView.separated(
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

  // 🏢 Salon Tile for mobile
  Widget _buildSalonTile(Map<String, dynamic> salon, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSalonId = salon['id'].toString();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF6B8B).withValues(alpha: 0.05) : Colors.white,
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
                children: [
                  Text(
                    salon['name'] ?? 'Unnamed Salon',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  if (salon['address'] != null)
                    Text(
                      salon['address'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFFFF6B8B), size: 24),
          ],
        ),
      ),
    );
  }

  // 🏢 Salon Card for web
  Widget _buildSalonCard(Map<String, dynamic> salon, bool isSelected) {
    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? const Color(0xFFFF6B8B) : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedSalonId = salon['id'].toString();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                  children: [
                    Text(
                      salon['name'] ?? 'Unnamed Salon',
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (salon['address'] != null)
                      Text(
                        salon['address'],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: Color(0xFFFF6B8B), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 🔍 Search Section
  Widget _buildSearchSection(double screenWidth) {
    final isSmallScreen = screenWidth < 600;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: const Color(0xFFFF6B8B), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Search Barbers',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 18 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
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
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            if (_searchController.text.isNotEmpty && _searchController.text.length < 2)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '🔍 Type at least 2 characters to search',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            if (_isSearching) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Search Results',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isLoading)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFF6B8B),
                      ),
                    ),
                  const Spacer(),
                  if (_searchResults.isNotEmpty)
                    Text(
                      '${_searchResults.length} found',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              if (_searchResults.isEmpty && !_isLoading)
                Container(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_search,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No barbers found',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try a different name or email',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              else if (_searchResults.isNotEmpty)
                _isWeb && !isSmallScreen
                    ? GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: screenWidth > 1000 ? 3 : 2,
                          childAspectRatio: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final barber = _searchResults[index];
                          final isSelected = _selectedBarberId == barber['id'];
                          return _buildBarberCard(barber, isSelected);
                        },
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _searchResults.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
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

  // 👤 Barber Tile for mobile
  Widget _buildBarberTile(Map<String, dynamic> barber, bool isSelected) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[200],
        backgroundImage: barber['photo'] != null ? NetworkImage(barber['photo']) : null,
        child: barber['photo'] == null
            ? Text(
                barber['name'][0].toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(
        barber['name'],
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(barber['email'], style: const TextStyle(fontSize: 12)),
        ],
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Color(0xFFFF6B8B))
          : Radio<String>(
              value: barber['id'],
              groupValue: _selectedBarberId,
              onChanged: (value) {
                setState(() {
                  _selectedBarberId = value;
                });
              },
              activeColor: const Color(0xFFFF6B8B),
            ),
      onTap: () {
        setState(() {
          _selectedBarberId = barber['id'];
        });
      },
    );
  }

  // 👤 Barber Card for web/tablet
  Widget _buildBarberCard(Map<String, dynamic> barber, bool isSelected) {
    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? const Color(0xFFFF6B8B) : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedBarberId = barber['id'];
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[200],
                backgroundImage: barber['photo'] != null ? NetworkImage(barber['photo']) : null,
                child: barber['photo'] == null
                    ? Text(
                        barber['name'][0].toUpperCase(),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      barber['name'],
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      barber['email'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: Color(0xFFFF6B8B), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 💇 Selected Barber Widget
  Widget _buildSelectedBarber() {
    final selectedBarber = _searchResults.firstWhere(
      (u) => u['id'] == _selectedBarberId,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B8B), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFFF6B8B),
            backgroundImage: selectedBarber['photo'] != null
                ? NetworkImage(selectedBarber['photo'])
                : null,
            child: selectedBarber['photo'] == null
                ? Text(
                    selectedBarber['name'][0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
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
                  selectedBarber['name'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  selectedBarber['email'],
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🛠️ Services Section
  Widget _buildServicesSection(double screenWidth) {
    final isSmallScreen = screenWidth < 600;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: Color(0xFFFF6B8B), size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select Services',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_selectedServiceIds.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_selectedServiceIds.length} selected',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF6B8B),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            if (_availableServices.isEmpty)
              _buildEmptyServices()
            else ...[
              if (_selectedServiceIds.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Services:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableServices
                            .where((s) => _selectedServiceIds.contains(s['id']))
                            .map((service) => Chip(
                                  label: Text(service['name']),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () => _toggleService(service),
                                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                                  labelStyle: const TextStyle(fontSize: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              ..._servicesByCategory.entries.map((entry) {
                return _buildCategorySection(entry.key, entry.value, screenWidth);
              }),
            ],
          ],
        ),
      ),
    );
  }

  // Empty Services Widget
  Widget _buildEmptyServices() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                color: Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please add services first',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.push('/owner/services/add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Add Services'),
            ),
          ],
        ),
      ),
    );
  }

  // Category Section
  Widget _buildCategorySection(String categoryName, List<Map<String, dynamic>> services, double screenWidth) {
    final isSmallScreen = screenWidth < 600;

    final category = _categories.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => CategoryModel(
        id: 0,
        name: categoryName,
        iconName: 'category_outlined',
        displayOrder: 999,
        isActive: true,
      ),
    );

    int crossAxisCount;
    if (_isWeb) {
      crossAxisCount = screenWidth > 1200 ? 6 : (screenWidth > 800 ? 4 : 3);
    } else if (_isTablet) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 2;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(category.icon, size: 20, color: const Color(0xFFFF6B8B)),
              const SizedBox(width: 8),
              Text(
                categoryName[0].toUpperCase() + categoryName.substring(1),
                style: const TextStyle(
                  fontSize: 16,
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: isSmallScreen ? 1.2 : 1.5,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: services.length,
          itemBuilder: (context, index) {
            final service = services[index];
            final isSelected = _selectedServiceIds.contains(service['id']);

            return InkWell(
              onTap: () => _toggleService(service),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF6B8B).withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6B8B)
                        : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            service['icon'],
                            color: isSelected
                                ? const Color(0xFFFF6B8B)
                                : Colors.grey[600],
                            size: isSmallScreen ? 24 : 28,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            service['name'],
                            style: TextStyle(
                              fontSize: isSmallScreen ? 11 : 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? const Color(0xFFFF6B8B)
                                  : Colors.grey[800],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Rs. ${service['price']}',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 10,
                              color: isSelected
                                  ? const Color(0xFFFF6B8B)
                                  : Colors.grey[600],
                            ),
                          ),
                          if (service['duration'] != null)
                            Text(
                              '${service['duration']} min',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 8 : 9,
                                color: isSelected
                                    ? const Color(0xFFFF6B8B).withValues(alpha: 0.8)
                                    : Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6B8B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ✅ Add Button Widget
  Widget _buildAddButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _isWeb ? 0 : 16,
        vertical: 8,
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _addBarberToSalon,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          minimumSize: Size(_isWeb ? 400 : double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
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

// 🔥 RouteObserver for route awareness
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();