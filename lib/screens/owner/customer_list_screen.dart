// Dashboard screen for owners to view customers and followers of their salon

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CustomerListScreen extends StatefulWidget {
  final String? salonId;
  final String role; // 'owner', 'barber', 'customer'

  const CustomerListScreen({
    super.key,
    this.salonId,
    required this.role,
  });

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedSalonName;
  int _totalCustomers = 0;
  int _totalFollowers = 0;
  int _totalBookings = 0;

  // Filter options
  String _selectedFilter = 'All'; // All, Followers, Bookings, Newest
  bool _showFilterOptions = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view customers';
          _isLoading = false;
        });
        return;
      }

      // Get salon name if salonId is provided
      if (widget.salonId != null) {
        final salonResponse = await supabase
            .from('salons')
            .select('name')
            .eq('id', int.parse(widget.salonId!))
            .maybeSingle();

        if (salonResponse != null) {
          _selectedSalonName = salonResponse['name'];
        }
      }

      if (widget.role == 'customer') {
        await _loadCustomerData(currentUser.id);
      } else if (widget.role == 'barber') {
        await _loadBarberCustomers(currentUser.id);
      } else if (widget.role == 'owner') {
        if (widget.salonId != null) {
          await _loadSalonCustomers(widget.salonId!);
        } else {
          setState(() {
            _errorMessage = 'No salon selected';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading customers: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD CUSTOMER DATA (for customer role)
  // ============================================================
  Future<void> _loadCustomerData(String userId) async {
    try {
      final response = await supabase
          .from('profiles')
          .select('''
            id,
            full_name,
            email,
            phone,
            avatar_url,
            created_at,
            extra_data
          ''')
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        final bookingsResponse = await supabase
            .from('appointments')
            .select('id')
            .eq('customer_id', userId)
            .eq('status', 'completed');

        setState(() {
          _customers = [
            {
              'id': response['id'],
              'full_name': response['full_name'] ?? 'Unknown',
              'email': response['email'] ?? '',
              'phone': response['phone'] ?? '',
              'avatar_url': response['avatar_url'],
              'created_at': response['created_at'],
              'booking_count': bookingsResponse.length,
              'is_current_user': true,
              'is_follower': false,
              'followed_at': null,
            }
          ];
          _totalCustomers = 1;
          _totalBookings = bookingsResponse.length;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Profile not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading profile: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD BARBER CUSTOMERS
  // ============================================================
  Future<void> _loadBarberCustomers(String barberId) async {
    try {
      final response = await supabase
          .from('appointments')
          .select('''
            customer_id,
            profiles!appointments_customer_id_fkey (
              id,
              full_name,
              email,
              phone,
              avatar_url,
              created_at
            )
          ''')
          .eq('barber_id', barberId)
          .eq('status', 'completed')
          .order('appointment_date', ascending: false);

      final Map<String, Map<String, dynamic>> customerMap = {};

      for (var appointment in response) {
        final profile = appointment['profiles'] as Map?;
        if (profile == null) continue;

        final customerId = profile['id'] as String;

        if (!customerMap.containsKey(customerId)) {
          customerMap[customerId] = {
            'id': customerId,
            'full_name': profile['full_name'] ?? 'Unknown',
            'email': profile['email'] ?? '',
            'phone': profile['phone'] ?? '',
            'avatar_url': profile['avatar_url'],
            'created_at': profile['created_at'],
            'booking_count': 0,
            'is_follower': false,
            'followed_at': null,
          };
        }
        customerMap[customerId]!['booking_count'] =
            (customerMap[customerId]!['booking_count'] as int) + 1;
      }

      final customers = customerMap.values.toList()
        ..sort((a, b) => (b['booking_count'] as int).compareTo(a['booking_count'] as int));

      setState(() {
        _customers = customers;
        _totalCustomers = customers.length;
        _totalBookings = customers.fold(0, (sum, c) => sum + (c['booking_count'] as int));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading customers: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOAD SALON CUSTOMERS (for owner) - INCLUDES FOLLOWERS
  // ============================================================
  Future<void> _loadSalonCustomers(String salonId) async {
    try {
      final salonIdInt = int.parse(salonId);

      // STEP 1: Get customers who booked at this salon
      final appointmentsResponse = await supabase
          .from('appointments')
          .select('''
            customer_id,
            profiles!appointments_customer_id_fkey (
              id,
              full_name,
              email,
              phone,
              avatar_url,
              created_at
            )
          ''')
          .eq('salon_id', salonIdInt)
          .neq('status', 'cancelled')
          .order('appointment_date', ascending: false);

      // STEP 2: Get followers who haven't booked yet
      final followersResponse = await supabase
          .from('salon_followers')
          .select('''
            customer_id,
            created_at,
            profiles!salon_followers_customer_id_fkey (
              id,
              full_name,
              email,
              phone,
              avatar_url,
              created_at
            )
          ''')
          .eq('salon_id', salonIdInt)
          .order('created_at', ascending: false);

      // Group by customer
      final Map<String, Map<String, dynamic>> customerMap = {};

      // Add customers from appointments
      for (var appointment in appointmentsResponse) {
        final profile = appointment['profiles'] as Map?;
        if (profile == null) continue;

        final customerId = profile['id'] as String;

        if (!customerMap.containsKey(customerId)) {
          customerMap[customerId] = {
            'id': customerId,
            'full_name': profile['full_name'] ?? 'Unknown',
            'email': profile['email'] ?? '',
            'phone': profile['phone'] ?? '',
            'avatar_url': profile['avatar_url'],
            'created_at': profile['created_at'],
            'booking_count': 0,
            'is_follower': false,
            'followed_at': null,
          };
        }
        customerMap[customerId]!['booking_count'] =
            (customerMap[customerId]!['booking_count'] as int) + 1;
      }

      // Add followers (who haven't booked or already have bookings)
      int followerCount = 0;
      for (var follower in followersResponse) {
        final profile = follower['profiles'] as Map?;
        if (profile == null) continue;

        final customerId = profile['id'] as String;

        if (!customerMap.containsKey(customerId)) {
          customerMap[customerId] = {
            'id': customerId,
            'full_name': profile['full_name'] ?? 'Unknown',
            'email': profile['email'] ?? '',
            'phone': profile['phone'] ?? '',
            'avatar_url': profile['avatar_url'],
            'created_at': profile['created_at'],
            'booking_count': 0,
            'is_follower': true,
            'followed_at': follower['created_at'],
          };
          followerCount++;
        } else {
          // Already has bookings, mark as follower too
          customerMap[customerId]!['is_follower'] = true;
          if (customerMap[customerId]!['followed_at'] == null) {
            customerMap[customerId]!['followed_at'] = follower['created_at'];
          }
        }
      }

      final customers = customerMap.values.toList()
        ..sort((a, b) {
          // Sort by booking count first
          final bookingCompare = (b['booking_count'] as int).compareTo(
            a['booking_count'] as int,
          );
          if (bookingCompare != 0) return bookingCompare;
          // Then by follower status (followers first)
          if (a['is_follower'] == true && b['is_follower'] == false) return -1;
          if (a['is_follower'] == false && b['is_follower'] == true) return 1;
          return 0;
        });

      final totalBookings = customers.fold(
        0,
        (sum, c) => sum + (c['booking_count'] as int),
      );

      setState(() {
        _customers = customers;
        _totalCustomers = customers.length;
        _totalFollowers = followerCount;
        _totalBookings = totalBookings;
        _isLoading = false;
      });

      debugPrint('✅ Loaded ${customers.length} customers for salon $salonId');
      debugPrint('   - ${customers.where((c) => c['booking_count'] > 0).length} with bookings');
      debugPrint('   - $_totalFollowers followers');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading customers: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // FILTER AND SEARCH
  // ============================================================
  List<Map<String, dynamic>> get _filteredCustomers {
    var filtered = List<Map<String, dynamic>>.from(_customers);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((customer) {
        final name = (customer['full_name'] as String?)?.toLowerCase() ?? '';
        final email = (customer['email'] as String?)?.toLowerCase() ?? '';
        final phone = (customer['phone'] as String?)?.toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    // Sort filter
    switch (_selectedFilter) {
      case 'Followers':
        filtered = filtered.where((c) => c['is_follower'] == true).toList();
        filtered.sort((a, b) => (b['followed_at'] ?? '').compareTo(a['followed_at'] ?? ''));
        break;
      case 'Bookings':
        filtered = filtered.where((c) => c['booking_count'] > 0).toList();
        filtered.sort((a, b) => (b['booking_count'] as int).compareTo(a['booking_count'] as int));
        break;
      case 'Newest':
        filtered.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        break;
      default: // 'All'
        break;
    }

    return filtered;
  }

  // ============================================================
  // VIEW CUSTOMER DETAILS
  // ============================================================
  void _viewCustomerDetails(Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CustomerDetailsSheet(customer: customer),
    );
  }

  // ============================================================
  // BUILD STATS HEADER
  // ============================================================
  Widget _buildStatsHeader() {
    if (_customers.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.people,
            label: 'Total',
            value: '$_totalCustomers',
            color: Colors.blue,
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.grey[300],
          ),
          _buildStatItem(
            icon: Icons.star,
            label: 'Followers',
            value: '$_totalFollowers',
            color: Colors.orange,
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.grey[300],
          ),
          _buildStatItem(
            icon: Icons.event_available,
            label: 'Bookings',
            value: '$_totalBookings',
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = _filteredCustomers;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.role == 'customer' ? 'My Profile' : 'Customers',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_selectedSalonName != null)
              Text(
                _selectedSalonName!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.role != 'customer')
            IconButton(
              icon: Icon(
                _showFilterOptions ? Icons.filter_list : Icons.filter_list_outlined,
              ),
              onPressed: () {
                setState(() {
                  _showFilterOptions = !_showFilterOptions;
                });
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search customers...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading customers...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Stats header
                    if (widget.role == 'owner') _buildStatsHeader(),

                    // Filter options
                    if (_showFilterOptions && widget.role != 'customer')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('All'),
                              const SizedBox(width: 8),
                              _buildFilterChip('Followers'),
                              const SizedBox(width: 8),
                              _buildFilterChip('Bookings'),
                              const SizedBox(width: 8),
                              _buildFilterChip('Newest'),
                            ],
                          ),
                        ),
                      ),

                    // Customer count
                    if (filteredCustomers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${filteredCustomers.length} customer${filteredCustomers.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            const Spacer(),
                            if (_searchQuery.isNotEmpty)
                              Text(
                                'Showing results for "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),

                    // Customer list
                    Expanded(
                      child: filteredCustomers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No customers found matching "$_searchQuery"'
                                        : 'No customers yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                      },
                                      child: const Text('Clear Search'),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filteredCustomers.length,
                              itemBuilder: (context, index) {
                                final customer = filteredCustomers[index];
                                return _buildCustomerCard(customer);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  // ============================================================
  // BUILD FILTER CHIP
  // ============================================================
  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? label : 'All';
        });
      },
      backgroundColor: Colors.grey[100],
      selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      checkmarkColor: const Color(0xFFFF6B8B),
    );
  }

  // ============================================================
  // BUILD CUSTOMER CARD
  // ============================================================
  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    final name = customer['full_name']?.toString() ?? 'Unknown';
    final email = customer['email']?.toString() ?? '';
    final phone = customer['phone']?.toString() ?? '';
    final avatarUrl = customer['avatar_url']?.toString();
    final bookingCount = customer['booking_count'] as int? ?? 0;
    final isCurrentUser = customer['is_current_user'] == true;
    final isFollower = customer['is_follower'] == true;
    final hasBookings = bookingCount > 0;

    // Card border color based on type
    Color? borderColor;
    if (isFollower && !hasBookings) {
      borderColor = Colors.orange.shade300; // Follower only
    } else if (hasBookings && isFollower) {
      borderColor = Colors.green.shade300; // Both booking and follower
    } else if (hasBookings) {
      borderColor = Colors.blue.shade300; // Booking only
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: borderColor != null
            ? BorderSide(color: borderColor, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _viewCustomerDetails(customer),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                ),
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          width: 55,
                          height: 55,
                          placeholder: (context, url) =>
                              const CircularProgressIndicator(),
                          errorWidget: (context, url, error) => Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFFF6B8B),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFF6B8B),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),

              // Customer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentUser)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (email.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.email, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    if (phone.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        // Booking count
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hasBookings
                                ? Colors.blue.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_available,
                                size: 12,
                                color: hasBookings ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$bookingCount booking${bookingCount > 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hasBookings ? Colors.blue : Colors.grey,
                                  fontWeight: hasBookings
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Follower badge
                        if (isFollower)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 12,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasBookings ? 'Follower' : 'New Follower',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CUSTOMER DETAILS SHEET
// ============================================================
class CustomerDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailsSheet({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final name = customer['full_name']?.toString() ?? 'Unknown';
    final email = customer['email']?.toString() ?? '';
    final phone = customer['phone']?.toString() ?? '';
    final avatarUrl = customer['avatar_url']?.toString();
    final bookingCount = customer['booking_count'] as int? ?? 0;
    final isFollower = customer['is_follower'] == true;
    final followedAt = customer['followed_at']?.toString() ?? '';
    final isCurrentUser = customer['is_current_user'] == true;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Profile header
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    ),
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: avatarUrl,
                              fit: BoxFit.cover,
                              width: 80,
                              height: 80,
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF6B8B),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF6B8B),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isCurrentUser)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'You',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        if (phone.isNotEmpty)
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$bookingCount booking${bookingCount > 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isFollower)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star,
                                      size: 14,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Follower',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (followedAt.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Followed: ${_formatDate(followedAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(),

              // Actions - ✅ FIXED: Wrap each ListTile in Material
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (email.isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.email, color: Colors.blue),
                          ),
                          title: const Text('Send Email'),
                          subtitle: Text(email),
                          onTap: () {
                            // Implement email
                          },
                        ),
                      ),
                    if (phone.isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.phone, color: Colors.green),
                          ),
                          title: const Text('Call Customer'),
                          subtitle: Text(phone),
                          onTap: () {
                            // Implement call
                          },
                        ),
                      ),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.history, color: Colors.orange),
                        ),
                        title: const Text('Booking History'),
                        subtitle: const Text('View all bookings'),
                        onTap: () {
                          Navigator.pop(context);
                          // Navigate to booking history
                        },
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star, color: Colors.purple),
                        ),
                        title: const Text('Reviews'),
                        subtitle: const Text('View customer reviews'),
                        onTap: () {
                          Navigator.pop(context);
                          // Navigate to reviews
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return dateStr;
    }
  }

}