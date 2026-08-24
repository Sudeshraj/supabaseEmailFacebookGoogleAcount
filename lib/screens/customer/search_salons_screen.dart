// screens/customer/search_salons_screen.dart
// Search salons screen with suggestions, search results, and navigation

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class SearchSalonsScreen extends StatefulWidget {
  const SearchSalonsScreen({super.key});

  @override
  State<SearchSalonsScreen> createState() => _SearchSalonsScreenState();
}

class _SearchSalonsScreenState extends State<SearchSalonsScreen> {
  final supabase = Supabase.instance.client;

  // Search state
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isSearching = false;

  // Results
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _recentSalons = [];

  // Recent searches
  List<String> _recentSearches = [];

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // Debounce timer
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _loadRecentSalons();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // LOAD RECENT SEARCHES
  // ============================================================
  Future<void> _loadRecentSearches() async {
    // Load from shared preferences or memory
    // For now, using in-memory
    setState(() {
      _recentSearches = _recentSearches;
    });
  }

  // ============================================================
  // LOAD RECENT SALONS (For suggestions)
  // ============================================================
  Future<void> _loadRecentSalons() async {
    try {
      final response = await supabase
          .from('salons')
          .select('id, name, logo_url, address')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(10);

      setState(() {
        _recentSalons = List<Map<String, dynamic>>.from(response);
        _suggestions = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error loading recent salons: $e');
    }
  }

  // ============================================================
  // SEARCH SALONS
  // ============================================================
  Future<void> _searchSalons(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = true;
    });

    try {
      final response = await supabase
          .from('salons')
          .select('''
            id,
            name,
            address,
            logo_url,
            cover_url,
            open_time,
            close_time,
            phone,
            email,
            description,
            is_active,
            created_at
          ''')
          .eq('is_active', true)
          .ilike('name', '%$query%')
          .order('name')
          .limit(20);

      final results = List<Map<String, dynamic>>.from(response);

      // Get follower counts for each salon
      for (var salon in results) {
        final followers = await supabase
            .from('salon_followers')
            .select('id')
            .eq('salon_id', salon['id']);
        salon['follower_count'] = followers.length;
      }

      setState(() {
        _searchResults = results;
        _isLoading = false;
        _isSearching = false;
      });

      // Add to recent searches
      if (results.isNotEmpty) {
        _addRecentSearch(query);
      }
    } catch (e) {
      debugPrint('Error searching salons: $e');
      setState(() {
        _isLoading = false;
        _isSearching = false;
      });
    }
  }

  // ============================================================
  // ADD RECENT SEARCH
  // ============================================================
  void _addRecentSearch(String query) {
    setState(() {
      _recentSearches.remove(query);
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) {
        _recentSearches = _recentSearches.sublist(0, 10);
      }
    });
  }

  // ============================================================
  // CLEAR RECENT SEARCHES
  // ============================================================
  void _clearRecentSearches() {
    setState(() {
      _recentSearches.clear();
    });
  }

  // ============================================================
  // GET SUGGESTIONS
  // ============================================================
  Future<void> _getSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = _recentSalons;
      });
      return;
    }

    try {
      final response = await supabase
          .from('salons')
          .select('id, name, logo_url, address')
          .eq('is_active', true)
          .ilike('name', '%$query%')
          .order('name')
          .limit(5);

      setState(() {
        _suggestions = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error getting suggestions: $e');
    }
  }

  // ============================================================
  // NAVIGATE TO SALON PROFILE
  // ============================================================
  void _navigateToSalonProfile(Map<String, dynamic> salon) {
    context.push('/customer/salon-profile', extra: salon);
  }

  // ============================================================
  // NAVIGATE TO BOOKING
  // ============================================================
  void _navigateToBooking(Map<String, dynamic> salon) {
    context.push('/customer/booking-flow', extra: salon);
  }

  // ============================================================
  // CLEAR SEARCH
  // ============================================================
  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _searchResults = [];
      _isSearching = false;
    });
    _searchFocusNode.unfocus();
  }

  // ============================================================
  // ON SEARCH CHANGED (with debounce)
  // ============================================================
  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchSalons(value);
    });

    if (value.isNotEmpty) {
      _getSuggestions(value);
    } else {
      setState(() {
        _suggestions = _recentSalons;
      });
    }
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Find Salons',
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
      ),
      body: SafeArea(child: isWeb ? _buildWebLayout() : _buildMobileLayout()),
    );
  }

  // ✅ WEB LAYOUT
  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildSearchBar(),
            const SizedBox(height: 16),
            Expanded(
              child: _isSearching ? _buildSearchResults() : _buildSuggestions(),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Search Bar
        _buildSearchBar(),

        // Results or Suggestions
        Expanded(
          child: _isSearching ? _buildSearchResults() : _buildSuggestions(),
        ),
      ],
    );
  }

  // ✅ SEARCH BAR
  Widget _buildSearchBar() {
    final isDark = context.isDarkMode;
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWeb ? 16 : 12,
        vertical: isWeb ? 16 : 8,
      ),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _searchFocusNode.hasFocus
                ? AppTheme.primary
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: _searchFocusNode.hasFocus ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: isDark ? Colors.white70 : Colors.grey[500],
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: isWeb ? 16 : 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search for salons...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[400],
                    fontSize: isWeb ? 15 : 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: isDark ? Colors.white70 : Colors.grey[500],
                  size: 20,
                ),
                onPressed: _clearSearch,
                splashRadius: 20,
              ),
            if (_isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ✅ SUGGESTIONS
  Widget _buildSuggestions() {
    final isDark = context.isDarkMode;
    final isWeb = MediaQuery.of(context).size.width > 800;

    if (_searchQuery.isNotEmpty && _suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No salons found',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(isWeb ? 16 : 12),
      children: [
        // Recent Searches
        if (_recentSearches.isNotEmpty && _searchQuery.isEmpty)
          _buildRecentSearches(),

        // Recent Salons (Suggestions)
        if (_suggestions.isNotEmpty) _buildSuggestionsList(),
      ],
    );
  }

  // ✅ RECENT SEARCHES
  Widget _buildRecentSearches() {
    final isDark = context.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearRecentSearches,
                child: Text(
                  'Clear',
                  style: TextStyle(fontSize: 12, color: AppTheme.primary),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _recentSearches.map((query) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _searchQuery = query;
                  _searchController.text = query;
                });
                _searchSalons(query);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 14,
                      color: isDark ? Colors.white70 : Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      query,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  // ✅ SUGGESTIONS LIST
  Widget _buildSuggestionsList() {
    final isDark = context.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            _searchQuery.isNotEmpty ? 'Suggestions' : 'Recent Salons',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        ..._suggestions.map((salon) => _buildSuggestionTile(salon)),
      ],
    );
  }

  // ✅ SUGGESTION TILE
  Widget _buildSuggestionTile(Map<String, dynamic> salon) {
    final isDark = context.isDarkMode;
    final name = salon['name']?.toString() ?? 'Salon';
    final address = salon['address']?.toString() ?? '';
    final logoUrl = salon['logo_url']?.toString();

    return GestureDetector(
      onTap: () => _navigateToSalonProfile(salon),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[100]!,
          ),
        ),
        child: Row(
          children: [
            // Logo
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address.isNotEmpty)
                    Text(
                      address,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: isDark ? Colors.white30 : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  // ✅ SEARCH RESULTS
  Widget _buildSearchResults() {
    final isDark = context.isDarkMode;
    final isWeb = MediaQuery.of(context).size.width > 800;

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Searching salons...'),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No salons found for "$_searchQuery"',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return isWeb
        ? GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final salon = _searchResults[index];
              return _buildSalonResultCard(salon);
            },
          )
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final salon = _searchResults[index];
              return _buildSalonResultCard(salon);
            },
          );
  }

  // ✅ SALON RESULT CARD
  Widget _buildSalonResultCard(Map<String, dynamic> salon) {
    final isDark = context.isDarkMode;
    final name = salon['name']?.toString() ?? 'Salon';
    final address = salon['address']?.toString() ?? '';
    final logoUrl = salon['logo_url']?.toString();
    final coverUrl = salon['cover_url']?.toString();
    final description = salon['description']?.toString() ?? '';
    final followerCount = salon['follower_count'] as int? ?? 0;
    final isWeb = MediaQuery.of(context).size.width > 800;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover Image
          Container(
            height: isWeb ? 120 : 100,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              image: coverUrl != null && coverUrl.isNotEmpty
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(coverUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: AppTheme.primary.withValues(alpha: 0.2),
            ),
            child: (coverUrl == null || coverUrl.isEmpty)
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        name.substring(0, 2).toUpperCase(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  )
                : null,
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Image (Clickable)
                GestureDetector(
                  onTap: () => _navigateToSalonProfile(salon),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.white,
                        width: 2,
                      ),
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
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name (Clickable)
                      GestureDetector(
                        onTap: () => _navigateToSalonProfile(salon),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (address.isNotEmpty)
                        Text(
                          address,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.grey[500],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 14,
                            color: isDark ? Colors.white70 : Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$followerCount followers',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.grey[500],
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
                // View Profile (Clickable)
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _navigateToSalonProfile(salon),
                    icon: Icon(Icons.store, size: 18, color: AppTheme.primary),
                    label: Text(
                      'Profile',
                      style: TextStyle(fontSize: 13, color: AppTheme.primary),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      foregroundColor: isDark ? Colors.white : AppTheme.primary,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 25,
                  color: isDark ? Colors.grey[700] : Colors.grey[200],
                ),
                // Book Now
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _navigateToBooking(salon),
                    icon: const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: Colors.green,
                    ),
                    label: Text(
                      'Book Now',
                      style: TextStyle(fontSize: 13, color: Colors.green),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      foregroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
