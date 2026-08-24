//Dashboard screen for customer to view their followed salons, search, filter, and unfollow salons

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // ✅ Focus Node for search
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadFollowedSalons();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
        filtered.sort(
          (a, b) => (b['follower_count'] as int? ?? 0).compareTo(
            a['follower_count'] as int? ?? 0,
          ),
        );
        break;
      case 'Newest':
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
    final isDark = context.isDarkMode;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Unfollow Salon',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Are you sure you want to unfollow "$salonName"?\n\n'
          'You will no longer receive updates from this salon.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black87),
            ),
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
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final filteredSalons = _filteredSalons;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FA),
      // ✅ App Bar - No Search Bar
      appBar: AppBar(
        title: Text(
          'My Salons',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadFollowedSalons,
          ),
        ],
      ),
      // ✅ EDGE-TO-EDGE: SafeArea with Web Layout
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading your salons...',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loadFollowedSalons,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : isWeb
            ? _buildWebLayout(filteredSalons)
            : _buildMobileLayout(filteredSalons),
      ),
    );
  }

  // ✅ WEB LAYOUT - Search Bar at Top of Content
  Widget _buildWebLayout(List<Map<String, dynamic>> filteredSalons) {
    final isDark = context.isDarkMode;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              _buildSearchBar(),
              const SizedBox(height: 12),
              if (_followedSalons.isNotEmpty) _buildFilterBar(),
              if (filteredSalons.isNotEmpty) _buildSalonCount(filteredSalons),
              Expanded(
                child: filteredSalons.isEmpty
                    ? _buildEmptyState()
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 8.0,
                        radius: const Radius.circular(10),
                        scrollbarOrientation: ScrollbarOrientation.right,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredSalons.length,
                          itemBuilder: (context, index) {
                            final salon = filteredSalons[index];
                            return _buildSalonCard(salon);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT - Search Bar at Top of Content
  Widget _buildMobileLayout(List<Map<String, dynamic>> filteredSalons) {
    final isDark = context.isDarkMode;

    return Container(
      color: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      child: Column(
        children: [
          _buildSearchBar(),
          const SizedBox(height: 8),
          if (_followedSalons.isNotEmpty) _buildFilterBar(),
          if (filteredSalons.isNotEmpty) _buildSalonCount(filteredSalons),
          Expanded(
            child: filteredSalons.isEmpty
                ? _buildEmptyState()
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

  // ✅ SEARCH BAR - Reusable Widget
  Widget _buildSearchBar() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 0.5,
        ),
      ),
      child: TextField(
        focusNode: _searchFocusNode,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: '🔍 Search your followed salons...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white70 : Colors.grey[400],
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.white70 : Colors.grey,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 18,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      ),
    );
  }

  // ✅ FILTER BAR
  Widget _buildFilterBar() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Row(
        children: [
          Text(
            'Sort:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
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
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.grey[700]),
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = selected ? filter : 'All';
                        });
                      },
                      backgroundColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.grey[100],
                      selectedColor: AppTheme.primary,
                      checkmarkColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ SALON COUNT
  Widget _buildSalonCount(List<Map<String, dynamic>> filteredSalons) {
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '${filteredSalons.length} salon${filteredSalons.length > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          const Spacer(),
          if (_searchQuery.isNotEmpty)
            Text(
              'Showing results for "$_searchQuery"',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  // ✅ EMPTY STATE
  Widget _buildEmptyState() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.store_mall_directory,
            size: 80,
            color: isDark ? Colors.white70 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No salons found matching "$_searchQuery"'
                : 'You haven\'t followed any salons yet',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow salons to get updates and book appointments',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              context.push('/customer/search-salons');
            },
            icon: const Icon(Icons.search),
            label: const Text('Find Salons to Follow'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
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
              child: Text(
                'Clear Search',
                style: TextStyle(color: AppTheme.primary),
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
    final isDark = context.isDarkMode;
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
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDark
            ? BorderSide(color: Colors.grey[700]!, width: 0.5)
            : BorderSide.none,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
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
                      color: AppTheme.primary.withValues(alpha: 0.1),
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
                                color: AppTheme.primary,
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
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
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey[600],
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
                              color: isDark ? Colors.white60 : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$openTime - $closeTime',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[600],
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
                              color: isDark ? Colors.white60 : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$followerCount followers',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.event_available,
                              size: 14,
                              color: isDark ? Colors.white60 : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$bookingCount bookings',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[500],
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
              color: isDark ? Colors.grey[700] : Colors.grey[200],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // View Details
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _viewSalonDetails(salon),
                      icon: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                      label: Text(
                        'Details',
                        style: TextStyle(fontSize: 13, color: AppTheme.primary),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        foregroundColor: isDark
                            ? Colors.white
                            : AppTheme.primary,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 25,
                    color: isDark ? Colors.grey[700] : Colors.grey[200],
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
                      label: Text(
                        'Book',
                        style: TextStyle(fontSize: 13, color: Colors.green),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 25,
                    color: isDark ? Colors.grey[700] : Colors.grey[200],
                  ),
                  // Unfollow
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _unfollowSalon(salonId, name),
                      icon: Icon(
                        Icons.star_border,
                        size: 18,
                        color: isDark ? Colors.orange.shade300 : Colors.orange,
                      ),
                      label: Text(
                        'Unfollow',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        foregroundColor: isDark
                            ? Colors.orange.shade300
                            : Colors.orange,
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
