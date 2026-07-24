//Dashboard screen for customer to view their followed salons, search, filter, and unfollow salons

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FollowedSalonsScreen extends StatefulWidget {
  const FollowedSalonsScreen({super.key});

  @override
  State<FollowedSalonsScreen> createState() => _FollowedSalonsScreenState();
}

class _FollowedSalonsScreenState extends State<FollowedSalonsScreen> {
  final supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _followedSalons = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  
  // Filter options
  String _selectedFilter = 'All'; // All, Most Popular, Newest

  @override
  void initState() {
    super.initState();
    _loadFollowedSalons();
  }

  Future<void> _loadFollowedSalons() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view your followed salons';
          _isLoading = false;
        });
        return;
      }

      // Get followed salons with counts
      final response = await supabase.rpc(
        'get_followed_salons_with_counts',
        params: {'p_customer_id': currentUser.id},
      );

      if (response != null && response.isNotEmpty) {
        setState(() {
          _followedSalons = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
        debugPrint('✅ Loaded ${_followedSalons.length} followed salons');
      } else {
        setState(() {
          _followedSalons = [];
          _isLoading = false;
        });
        debugPrint('ℹ️ No followed salons found');
      }
    } catch (e) {
      debugPrint('❌ Error loading followed salons: $e');
      setState(() {
        _errorMessage = 'Error loading your followed salons: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // FILTER AND SEARCH
  // ============================================================
  List<Map<String, dynamic>> get _filteredSalons {
    var filtered = List<Map<String, dynamic>>.from(_followedSalons);

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((salon) {
        final name = (salon['name'] as String?)?.toLowerCase() ?? '';
        final address = (salon['address'] as String?)?.toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return name.contains(query) || address.contains(query);
      }).toList();
    }

    // Sort filter
    switch (_selectedFilter) {
      case 'Most Popular':
        filtered.sort((a, b) => (b['follower_count'] as int? ?? 0).compareTo(a['follower_count'] as int? ?? 0));
        break;
      case 'Newest':
        // Assuming salons have created_at or we use the order they were followed
        // For now, keep as is
        break;
      default: // 'All'
        break;
    }

    return filtered;
  }

  // ============================================================
  // UNFOLLOW SALON
  // ============================================================
  Future<void> _unfollowSalon(int salonId, String salonName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unfollow Salon'),
        content: Text(
          'Are you sure you want to unfollow "$salonName"?\n\n'
          'You will no longer receive updates from this salon.',
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
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      await supabase
          .from('salon_followers')
          .delete()
          .eq('customer_id', currentUser.id)
          .eq('salon_id', salonId);

      // Remove from list
      setState(() {
        _followedSalons.removeWhere((s) => s['id'] == salonId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unfollowed "$salonName"'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      debugPrint('❌ Error unfollowing salon: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error unfollowing salon: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // VIEW SALON DETAILS
  // ============================================================
  void _viewSalonDetails(Map<String, dynamic> salon) {
    context.push('/customer/salon-profile', extra: salon);
  }

  // ============================================================
  // BOOK APPOINTMENT
  // ============================================================
  void _bookAppointment(Map<String, dynamic> salon) {
    context.push('/customer/booking-flow', extra: salon);
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final filteredSalons = _filteredSalons;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Salons',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFollowedSalons,
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
                hintText: 'Search your followed salons...',
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
                  Text('Loading your salons...'),
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
                        onPressed: _loadFollowedSalons,
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
                    // Filter options
                    if (_followedSalons.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Sort:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: ['All', 'Most Popular', 'Newest'].map((filter) {
                                    final isSelected = _selectedFilter == filter;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: FilterChip(
                                        label: Text(
                                          filter,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isSelected ? Colors.white : Colors.grey[700],
                                          ),
                                        ),
                                        selected: isSelected,
                                        onSelected: (selected) {
                                          setState(() {
                                            _selectedFilter = selected ? filter : 'All';
                                          });
                                        },
                                        backgroundColor: Colors.grey[100],
                                        selectedColor: const Color(0xFFFF6B8B),
                                        checkmarkColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Salon count
                    if (filteredSalons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              '${filteredSalons.length} salon${filteredSalons.length > 1 ? 's' : ''}',
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
                    
                    // Salon list
                    Expanded(
                      child: filteredSalons.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.store_mall_directory,
                                    size: 80,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No salons found matching "$_searchQuery"'
                                        : 'You haven\'t followed any salons yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Follow salons to get updates and book appointments',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      // Navigate to salon search/find screen
                                      context.push('/customer/search-salons');
                                    },
                                    icon: const Icon(Icons.search),
                                    label: const Text('Find Salons to Follow'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF6B8B),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
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
                              itemCount: filteredSalons.length,
                              itemBuilder: (context, index) {
                                final salon = filteredSalons[index];
                                return _buildSalonCard(salon);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  // ============================================================
  // BUILD SALON CARD
  // ============================================================
  Widget _buildSalonCard(Map<String, dynamic> salon) {
    final name = salon['name']?.toString() ?? 'Salon';
    final address = salon['address']?.toString() ?? '';
    final logoUrl = salon['logo_url']?.toString();
    final openTime = salon['open_time']?.toString() ?? '09:00';
    final closeTime = salon['close_time']?.toString() ?? '18:00';
    final followerCount = salon['follower_count'] as int? ?? 0;
    final bookingCount = salon['booking_count'] as int? ?? 0;
    final salonId = salon['id'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        child: Column(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Logo
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      image: logoUrl != null && logoUrl.isNotEmpty
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(logoUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: logoUrl == null || logoUrl.isEmpty
                        ? Center(
                            child: Text(
                              name.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFFF6B8B),
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  
                  // Salon info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (address.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$openTime - $closeTime',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$followerCount followers',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.event_available,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$bookingCount bookings',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Actions
            Divider(
              height: 1,
              color: Colors.grey[200],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // View Details
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _viewSalonDetails(salon),
                      icon: const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Color(0xFFFF6B8B),
                      ),
                      label: const Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFFF6B8B),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 25,
                    color: Colors.grey[200],
                  ),
                  // Book
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _bookAppointment(salon),
                      icon: const Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: Colors.green,
                      ),
                      label: const Text(
                        'Book',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 25,
                    color: Colors.grey[200],
                  ),
                  // Unfollow
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _unfollowSalon(salonId, name),
                      icon: const Icon(
                        Icons.star_border,
                        size: 18,
                        color: Colors.orange,
                      ),
                      label: const Text(
                        'Unfollow',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
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