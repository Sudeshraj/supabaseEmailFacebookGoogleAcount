import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/category_model.dart';

class AddBarberScreen extends StatefulWidget {
  const AddBarberScreen({super.key});

  @override
  State<AddBarberScreen> createState() => _AddBarberScreenState();
}

class _AddBarberScreenState extends State<AddBarberScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = false;
  String? _selectedBarberId;

  // Categories from database
  List<CategoryModel> _categories = [];

  // Services grouped by category
  Map<String, List<Map<String, dynamic>>> _servicesByCategory = {};

  // Available services list
  List<Map<String, dynamic>> _availableServices = [];

  // Selected services for the barber
  final List<Map<String, dynamic>> _selectedServices = [];

  bool _isLoadingServices = true;
  bool _isLoadingCategories = true;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadCategoriesAndServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🔥 Load categories and services from database
  Future<void> _loadCategoriesAndServices() async {
    setState(() {
      _isLoadingCategories = true;
      _isLoadingServices = true;
    });

    try {
      // 1. Load categories first
      await _loadCategories();

      // 2. Then load services with category info
      await _loadServicesFromDatabase();
    } catch (e) {
      print('❌ Error loading categories and services: $e');
    } finally {
      setState(() {
        _isLoadingCategories = false;
        _isLoadingServices = false;
      });
    }
  }

  // 🔥 Load categories from database
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

      print('📦 Categories loaded: $response');

      if (response.isNotEmpty) {
        setState(() {
          _categories = response
              .map((cat) => CategoryModel.fromJson(cat))
              .toList();
        });
      }
    } catch (e) {
      print('❌ Error loading categories: $e');
      rethrow;
    }
  }

  // 🔥 Load services from database with category info
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

      print('📦 Services loaded: $response');

      if (response.isNotEmpty) {
        // Process services
        final List<Map<String, dynamic>> services = [];
        final Map<String, List<Map<String, dynamic>>> grouped = {};

        for (var service in response) {
          // Get category info
          final categoryData = service['categories'] as Map<String, dynamic>;
          final categoryName = categoryData['name'] ?? 'other';
          final iconName = categoryData['icon_name'] ?? 'build_circle_outlined';

          // Create service map
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

          // Group by category
          if (!grouped.containsKey(categoryName)) {
            grouped[categoryName] = [];
          }
          grouped[categoryName]!.add(serviceMap);
        }

        setState(() {
          _availableServices = services;
          _servicesByCategory = grouped;
        });
      } else {
        setState(() {
          _availableServices = [];
          _servicesByCategory = {};
        });

        // Show message to add services first
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No services found. Please add services first.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error loading services: $e');
      setState(() {
        _availableServices = [];
        _servicesByCategory = {};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  // 🎨 Get icon from name string
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
        return Icons.category_outlined;
    }
  }

  // 🔍 Search users by email from Supabase auth.users
  Future<void> _searchUsers() async {
    String query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = true;
    });

    try {
      // Get the barber role ID (role_id = 2 for barbers)
      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'barber')
          .single();

      final barberRoleId = roleResponse['id'];

      // Search for existing barbers
      final response = await supabase
          .from('profiles')
          .select('''
            id,
            role_id,
            full_name,
            phone,
            avatar_url,
            extra_data,
            is_active
          ''')
          .eq('role_id', barberRoleId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (response.isNotEmpty) {
        setState(() {
          _searchResults = response.map((profile) {
            return {
              'id': profile['id'],
              'email': profile['extra_data']?['email'] ?? 'No email',
              'name':
                  profile['full_name'] ??
                  profile['extra_data']?['name'] ??
                  'Unknown Barber',
              'photo':
                  profile['avatar_url'] ?? profile['extra_data']?['avatar_url'],
              'role': 'barber',
              'services': profile['extra_data']?['services'] ?? [],
            };
          }).toList();
        });
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    } catch (e) {
      print('Error searching barbers: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching barbers: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ✅ Add barber to salon
  // ✅ Add barber to salon
  Future<void> _addBarberToSalon() async {
    if (_selectedBarberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a barber first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Find selected barber details
    final selectedBarber = _searchResults.firstWhere(
      (b) => b['id'] == _selectedBarberId,
    );

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Add Barber'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add ${selectedBarber['name']} as barber?'),
            const SizedBox(height: 16),
            const Text(
              'Services:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._selectedServices.map(
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

    setState(() {
      _isLoading = true;
    });

    try {
      // Get barber role ID
      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', 'barber')
          .single();

      final barberRoleId = roleResponse['id'];

      // Get current profile data
      final currentProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', _selectedBarberId!)
          .single();

      // Get current user's salon (assuming owner has a salon)
      final ownerSalon = await supabase
          .from('salons')
          .select('id')
          .eq('owner_id', supabase.auth.currentUser!.id)
          .maybeSingle();

      // If no salon exists, create one
      int salonId;
      if (ownerSalon == null) {
        final newSalon = await supabase
            .from('salons')
            .insert({
              'name': 'My Salon',
              'owner_id': supabase.auth.currentUser!.id,
              'is_active': true,
            })
            .select('id')
            .single();
        salonId = newSalon['id'];
      } else {
        salonId = ownerSalon['id'];
      }

      // Update the user's profile with barber role and services
      final updatedExtraData = {
        ...currentProfile['extra_data'] ?? {},
        'services': _selectedServices
            .map(
              (s) => {
                'id': int.parse(s['id']),
                'name': s['name'],
                'price': s['price'],
                'duration': s['duration'],
                'category_id': s['category_id'],
                'category_name': s['category_name'],
              },
            )
            .toList(),
        'added_by': supabase.auth.currentUser?.id,
        'added_at': DateTime.now().toIso8601String(),
        'previous_role': currentProfile['role_id'],
      };

      // Update profile role to barber
      await supabase
          .from('profiles')
          .update({
            'role_id': barberRoleId,
            'extra_data': updatedExtraData,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _selectedBarberId!);

      // Add to salon_barbers table (check if already exists)
      final existingSalonBarber = await supabase
          .from('salon_barbers')
          .select()
          .eq('salon_id', salonId)
          .eq('barber_id', _selectedBarberId!)
          .maybeSingle();

      if (existingSalonBarber == null) {
        await supabase.from('salon_barbers').insert({
          'salon_id': salonId,
          'barber_id': _selectedBarberId!,
          'is_active': true,
        });
      }

      // Add services to barber_services table (check if already exists)
      for (var service in _selectedServices) {
        final existingService = await supabase
            .from('barber_services')
            .select()
            .eq('barber_id', _selectedBarberId!)
            .eq('service_id', int.parse(service['id']))
            .maybeSingle();

        if (existingService == null) {
          await supabase.from('barber_services').insert({
            'barber_id': _selectedBarberId!,
            'service_id': int.parse(service['id']),
            'custom_price': service['price'],
            'is_active': true,
          });
        }
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${selectedBarber['name']} added as barber successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Clear selection and go back
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            context.pop();
          }
        });
      }
    } catch (e) {
      print('Error adding barber: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding barber: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoading || _isLoadingServices || _isLoadingCategories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Barber'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        actions: [
          // Refresh services button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCategoriesAndServices,
            tooltip: 'Refresh Services',
          ),

          // Save button
          if (_selectedBarberId != null &&
              _selectedServices.isNotEmpty &&
              !isLoading)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _addBarberToSalon,
              tooltip: 'Add Barber',
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔍 Search Section
                  _buildSearchSection(),

                  const SizedBox(height: 20),

                  // 💇 Selected Barber
                  if (_selectedBarberId != null) ...[
                    _buildSelectedBarber(),
                    const SizedBox(height: 20),
                  ],

                  // 🛠️ Services Section
                  _buildServicesSection(),

                  const SizedBox(height: 20),

                  // ✅ Add Button
                  if (_selectedBarberId != null &&
                      _selectedServices.isNotEmpty &&
                      _availableServices.isNotEmpty)
                    _buildAddButton(),
                ],
              ),
            ),
    );
  }

  // 🔍 Search Section Widget
  Widget _buildSearchSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search Barbers',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Enter barber name or email...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
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
            ),
            onChanged: (value) {
              if (value.length > 2) {
                _searchUsers();
              } else if (value.isEmpty) {
                setState(() {
                  _searchResults = [];
                  _isSearching = false;
                });
              }
            },
          ),

          // Search Results
          if (_isSearching) ...[
            const SizedBox(height: 16),
            const Text(
              'Search Results:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_searchResults.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No barbers found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try a different name',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final barber = _searchResults[index];
                  final isSelected = _selectedBarberId == barber['id'];
                  final serviceCount =
                      (barber['services'] as List?)?.length ?? 0;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? const Color(0xFFFF6B8B)
                          : Colors.grey[200],
                      backgroundImage: barber['photo'] != null
                          ? NetworkImage(barber['photo'])
                          : null,
                      child: barber['photo'] == null
                          ? Text(
                              barber['name'][0].toUpperCase(),
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[700],
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      barber['name'],
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(barber['email']),
                        if (serviceCount > 0)
                          Text(
                            '$serviceCount services',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                            ),
                          ),
                      ],
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFFFF6B8B),
                          )
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
                },
              ),
          ],
        ],
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
        border: Border.all(color: const Color(0xFFFF6B8B), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Color(0xFFFF6B8B), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected Barber:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  selectedBarber['name'],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  selectedBarber['email'],
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🛠️ Services Section Widget
  Widget _buildServicesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.build_circle_outlined,
                color: Color(0xFFFF6B8B),
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Select Services for Barber',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Show message if no services
          if (_availableServices.isEmpty) ...[
            _buildEmptyServices(),
          ] else ...[
            // Selected Services
            if (_selectedServices.isNotEmpty) ...[
              _buildSelectedServices(),
              const SizedBox(height: 16),
            ],

            // Services by Category
            ..._servicesByCategory.entries.map((entry) {
              return _buildCategorySection(entry.key, entry.value);
            }),
          ],
        ],
      ),
    );
  }

  // Empty Services Widget
  Widget _buildEmptyServices() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.build_circle_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'No services available',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Please add services first',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                // Navigate to add services screen
                context.push('/owner/services/add');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
              ),
              child: const Text('Add Services'),
            ),
          ],
        ),
      ),
    );
  }

  // Selected Services Widget
  Widget _buildSelectedServices() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
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
          ..._selectedServices.map(
            (service) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(service['icon'], size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${service['category_name']} • Rs. ${service['price']} • ${service['duration']} min',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedServices.removeWhere(
                          (s) => s['id'] == service['id'],
                        );
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Category Section Widget
  Widget _buildCategorySection(
    String categoryName,
    List<Map<String, dynamic>> services,
  ) {
    // Find category from list
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: services.length,
          itemBuilder: (context, index) {
            final service = services[index];
            final isSelected = _selectedServices.any(
              (s) => s['id'] == service['id'],
            );

            return GestureDetector(
              onTap: () {
                if (!isSelected) {
                  setState(() {
                    _selectedServices.add(service);
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${service['name']} added'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6B8B)
                        : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      service['icon'],
                      color: isSelected
                          ? const Color(0xFFFF6B8B)
                          : Colors.grey[600],
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service['name'],
                      style: TextStyle(
                        fontSize: 12,
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
                        fontSize: 10,
                        color: isSelected
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[600],
                      ),
                    ),
                    if (service['duration'] != null)
                      Text(
                        '${service['duration']} min',
                        style: TextStyle(
                          fontSize: 8,
                          color: isSelected
                              ? const Color(0xFFFF6B8B).withValues(alpha: 0.8)
                              : Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ✅ Add Button Widget
  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _addBarberToSalon,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Add Barber to Salon',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
