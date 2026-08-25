import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class BarberReviewsScreen extends StatefulWidget {
  final String? salonId;
  final String? barberId;

  const BarberReviewsScreen({super.key, this.salonId, this.barberId});

  @override
  State<BarberReviewsScreen> createState() => _BarberReviewsScreenState();
}

class _BarberReviewsScreenState extends State<BarberReviewsScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  // Stats
  double _averageRating = 0.0;
  int _totalReviews = 0;
  int _fiveStarCount = 0;
  int _fourStarCount = 0;
  int _threeStarCount = 0;
  int _twoStarCount = 0;
  int _oneStarCount = 0;

  // Barber name
  String _barberName = 'Barber';

  // Filter
  String _selectedRatingFilter = 'All';
  String _selectedSort = 'Newest';

  // Tab controller
  late TabController _tabController;

  // Reply state
  int? _replyingToReviewId;
  final TextEditingController _replyController = TextEditingController();

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // ✅ Responsive
  bool _isWeb = false;
  bool _isTablet = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReviews();
    _loadBarberName();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isWeb = size.width > 800;
    final isTablet = size.shortestSide >= 600;

    if (_isWeb != isWeb || _isTablet != isTablet) {
      setState(() {
        _isWeb = isWeb;
        _isTablet = isTablet;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBarberName() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final barberId = widget.barberId ?? currentUser.id;

      final response = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', barberId)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _barberName = response['full_name'] ?? 'Barber';
        });
      }
    } catch (e) {
      debugPrint('Error loading barber name: $e');
    }
  }

  // ============================================================
  // LOAD REVIEWS - FIXED QUERY
  // ============================================================
  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view reviews';
          _isLoading = false;
        });
        return;
      }

      final barberId = widget.barberId ?? currentUser.id;

      var query = supabase
          .from('reviews')
          .select('''
            id,
            appointment_id,
            customer_id,
            barber_id,
            salon_id,
            overall_rating,
            service_quality,
            punctuality,
            professionalism,
            cleanliness,
            comment,
            pros,
            cons,
            photos,
            barber_response,
            owner_response,
            status,
            helpful_count,
            report_count,
            created_at,
            updated_at,
            appointments (
              booking_number,
              service_id,
              appointment_date,
              start_time,
              services (
                name
              )
            )
          ''')
          .eq('barber_id', barberId)
          .eq('status', 'published');

      if (widget.salonId != null) {
        query = query.eq('salon_id', int.parse(widget.salonId!));
      }

      final response = await query.order('created_at', ascending: false);

      final List<Map<String, dynamic>> reviewsList = [];
      int totalRating = 0;
      int fiveStar = 0;
      int fourStar = 0;
      int threeStar = 0;
      int twoStar = 0;
      int oneStar = 0;

      final Set<String> customerIds = {};
      for (var item in response) {
        final customerId = item['customer_id'] as String?;
        if (customerId != null) {
          customerIds.add(customerId);
        }
      }

      Map<String, Map<String, dynamic>> customerProfiles = {};
      if (customerIds.isNotEmpty) {
        final profilesResponse = await supabase
            .from('profiles')
            .select('id, full_name, email, phone, avatar_url')
            .inFilter('id', customerIds.toList());

        for (var profile in profilesResponse) {
          customerProfiles[profile['id']] = {
            'full_name': profile['full_name'] ?? 'Anonymous',
            'email': profile['email'] ?? '',
            'phone': profile['phone'] ?? '',
            'avatar_url': profile['avatar_url'],
          };
        }
      }

      final Set<int> salonIds = {};
      for (var item in response) {
        final salonId = item['salon_id'] as int?;
        if (salonId != null) {
          salonIds.add(salonId);
        }
      }

      Map<int, String> salonNames = {};
      if (salonIds.isNotEmpty) {
        final salonsResponse = await supabase
            .from('salons')
            .select('id, name, logo_url')
            .inFilter('id', salonIds.toList());

        for (var salon in salonsResponse) {
          salonNames[salon['id']] = salon['name'] ?? 'Unknown Salon';
        }
      }

      for (var item in response) {
        final customerId = item['customer_id'] as String?;
        final customer = customerId != null
            ? customerProfiles[customerId]
            : null;
        final appointment = item['appointments'] as Map?;
        final service = appointment?['services'] as Map?;
        final salonId = item['salon_id'] as int?;
        final salonName = salonId != null
            ? salonNames[salonId]
            : 'Unknown Salon';

        final rating = (item['overall_rating'] as num?)?.toDouble() ?? 0.0;

        totalRating += rating.toInt();

        if (rating >= 5) {
          fiveStar++;
        } else if (rating >= 4) {
          fourStar++;
        } else if (rating >= 3) {
          threeStar++;
        } else if (rating >= 2) {
          twoStar++;
        } else if (rating >= 1) {
          oneStar++;
        }

        reviewsList.add({
          'id': item['id'],
          'appointment_id': item['appointment_id'],
          'customer_id': item['customer_id'],
          'customer_name': customer?['full_name'] ?? 'Anonymous',
          'customer_email': customer?['email'] ?? '',
          'customer_phone': customer?['phone'] ?? '',
          'customer_avatar': customer?['avatar_url'],
          'salon_id': item['salon_id'],
          'salon_name': salonName,
          'overall_rating': rating,
          'service_quality': (item['service_quality'] as num?)?.toDouble() ?? 0,
          'punctuality': (item['punctuality'] as num?)?.toDouble() ?? 0,
          'professionalism': (item['professionalism'] as num?)?.toDouble() ?? 0,
          'cleanliness': (item['cleanliness'] as num?)?.toDouble() ?? 0,
          'comment': item['comment'],
          'pros': item['pros'] as List? ?? [],
          'cons': item['cons'] as List? ?? [],
          'photos': item['photos'] as List? ?? [],
          'barber_response': item['barber_response'],
          'owner_response': item['owner_response'],
          'helpful_count': item['helpful_count'] ?? 0,
          'created_at': item['created_at'],
          'service_name': service?['name'] ?? 'Unknown Service',
          'appointment_date': appointment?['appointment_date'],
          'appointment_time': appointment?['start_time'],
          'booking_number': appointment?['booking_number'],
        });
      }

      final averageRating = reviewsList.isNotEmpty
          ? totalRating / reviewsList.length
          : 0.0;

      setState(() {
        _reviews = reviewsList;
        _totalReviews = reviewsList.length;
        _averageRating = averageRating;
        _fiveStarCount = fiveStar;
        _fourStarCount = fourStar;
        _threeStarCount = threeStar;
        _twoStarCount = twoStar;
        _oneStarCount = oneStar;
        _isLoading = false;
      });

      debugPrint('✅ Loaded ${reviewsList.length} reviews');
    } catch (e) {
      debugPrint('❌ Error loading reviews: $e');
      setState(() {
        _errorMessage = 'Error loading reviews: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // FILTER REVIEWS
  // ============================================================
  List<Map<String, dynamic>> get _filteredReviews {
    var filtered = List<Map<String, dynamic>>.from(_reviews);

    if (_selectedRatingFilter != 'All') {
      final rating = int.parse(_selectedRatingFilter);
      filtered = filtered.where((review) {
        final overall = (review['overall_rating'] as double?)?.toInt() ?? 0;
        return overall == rating;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((review) {
        final customerName =
            (review['customer_name'] as String?)?.toLowerCase() ?? '';
        final comment = (review['comment'] as String?)?.toLowerCase() ?? '';
        final serviceName =
            (review['service_name'] as String?)?.toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        return customerName.contains(query) ||
            comment.contains(query) ||
            serviceName.contains(query);
      }).toList();
    }

    switch (_selectedSort) {
      case 'Newest':
        filtered.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        break;
      case 'Oldest':
        filtered.sort(
          (a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''),
        );
        break;
      case 'Highest Rated':
        filtered.sort(
          (a, b) => (b['overall_rating'] as double).compareTo(
            a['overall_rating'] as double,
          ),
        );
        break;
      case 'Lowest Rated':
        filtered.sort(
          (a, b) => (a['overall_rating'] as double).compareTo(
            b['overall_rating'] as double,
          ),
        );
        break;
    }

    return filtered;
  }

  // ============================================================
  // REPLY TO REVIEW
  // ============================================================
  Future<void> _submitReply(int reviewId) async {
    if (_replyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a reply'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await supabase
          .from('reviews')
          .update({
            'barber_response': _replyController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', reviewId);

      setState(() {
        _replyingToReviewId = null;
        _replyController.clear();
      });

      await _loadReviews();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Reply submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error submitting reply: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting reply: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final filteredReviews = _filteredReviews;

    _checkScreenSize();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Reviews',
              style: TextStyle(
                fontSize: _isWeb ? 22 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_barberName.isNotEmpty)
              Text(
                _barberName,
                style: TextStyle(
                  fontSize: _isWeb ? 14 : 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Reviews'),
            Tab(text: 'Stats'),
          ],
        ),
        // ✅ REMOVED: Refresh button from AppBar
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading reviews...',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey[600],
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
                      color: isDark ? Colors.white70 : Colors.grey[400],
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
                      onPressed: _loadReviews,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _isWeb
            ? _buildWebLayout(filteredReviews, isDark)
            : _buildMobileLayout(filteredReviews, isDark),
      ),
    );
  }

  // ✅ WEB LAYOUT
  Widget _buildWebLayout(List<Map<String, dynamic>> filteredReviews, bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.right,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Reviews Tab - Web
              Column(
                children: [
                  _buildFilters(),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: filteredReviews.isEmpty
                          ? _buildEmptyState()
                          : _isTablet
                              ? GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 1.2,
                                  ),
                                  itemCount: filteredReviews.length,
                                  itemBuilder: (context, index) =>
                                      _buildReviewCard(
                                        filteredReviews[index],
                                        isDark,
                                      ),
                                )
                              : Column(
                                  children: filteredReviews
                                      .map((review) => _buildReviewCard(
                                            review,
                                            isDark,
                                          ))
                                      .toList(),
                                ),
                    ),
                  ),
                ],
              ),
              // Stats Tab - Web
              _buildStatsTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout(List<Map<String, dynamic>> filteredReviews, bool isDark) {
    return TabBarView(
      controller: _tabController,
      children: [
        // Reviews Tab - Mobile
        Column(
          children: [
            _buildFilters(),
            Expanded(
              child: filteredReviews.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredReviews.length,
                      itemBuilder: (context, index) =>
                          _buildReviewCard(filteredReviews[index], isDark),
                    ),
            ),
          ],
        ),
        // Stats Tab - Mobile
        _buildStatsTab(),
      ],
    );
  }

  // ============================================================
  // BUILD FILTERS
  // ============================================================
  Widget _buildFilters() {
    final isDark = context.isDarkMode;
    final ratingOptions = ['All', '5', '4', '3', '2', '1'];
    final sortOptions = ['Newest', 'Oldest', 'Highest Rated', 'Lowest Rated'];

    return Container(
      padding: const EdgeInsets.all(12),
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      child: Column(
        children: [
          // Search
          TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search by customer or comment...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
              prefixIcon: Icon(
                Icons.search,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),

          // Rating filter
          Row(
            children: [
              Text(
                'Rating:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ratingOptions.map((rating) {
                      final isSelected = _selectedRatingFilter == rating;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(
                            rating == 'All' ? 'All' : '$rating ★',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white60 : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedRatingFilter = selected ? rating : 'All';
                            });
                          },
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Sort
          Row(
            children: [
              Text(
                'Sort:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: sortOptions.map((sort) {
                      final isSelected = _selectedSort == sort;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(
                            sort,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white60 : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedSort = selected ? sort : 'Newest';
                            });
                          },
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD REVIEW CARD
  // ============================================================
  Widget _buildReviewCard(Map<String, dynamic> review, bool isDark) {
    final rating = review['overall_rating'] as double? ?? 0;
    final customerName = review['customer_name']?.toString() ?? 'Anonymous';
    final customerAvatar = review['customer_avatar']?.toString();
    final comment = review['comment']?.toString();
    final createdAt = review['created_at'] as String?;
    final serviceName = review['service_name']?.toString() ?? 'Unknown';
    final barberResponse = review['barber_response']?.toString();
    final helpfulCount = review['helpful_count'] as int? ?? 0;
    final isReplying = _replyingToReviewId == review['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Customer info & rating
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  backgroundImage:
                      customerAvatar != null && customerAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(customerAvatar)
                      : null,
                  child: customerAvatar == null || customerAvatar.isEmpty
                      ? Text(
                          customerName.isNotEmpty
                              ? customerName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
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
                        customerName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            serviceName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(
                              color: isDark ? Colors.white30 : Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(createdAt),
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
                // Rating stars
                Row(
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    final isFilled = starValue <= rating;
                    return Icon(
                      isFilled ? Icons.star : Icons.star_border,
                      size: 16,
                      color: isFilled
                          ? Colors.amber
                          : (isDark ? Colors.white30 : Colors.grey[300]),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Rating breakdown
            if (review['service_quality'] > 0 ||
                review['punctuality'] > 0 ||
                review['professionalism'] > 0 ||
                review['cleanliness'] > 0)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildRatingChip(
                      label: 'Service',
                      value:
                          (review['service_quality'] as double?)?.toInt() ?? 0,
                      isDark: isDark,
                    ),
                    _buildRatingChip(
                      label: 'Punctuality',
                      value: (review['punctuality'] as double?)?.toInt() ?? 0,
                      isDark: isDark,
                    ),
                    _buildRatingChip(
                      label: 'Professional',
                      value:
                          (review['professionalism'] as double?)?.toInt() ?? 0,
                      isDark: isDark,
                    ),
                    _buildRatingChip(
                      label: 'Cleanliness',
                      value: (review['cleanliness'] as double?)?.toInt() ?? 0,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // Comment
            if (comment != null && comment.isNotEmpty)
              Text(
                comment,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            const SizedBox(height: 8),

            // Pros & Cons
            if (review['pros'] != null && (review['pros'] as List).isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: (review['pros'] as List).map((pro) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.thumb_up,
                          size: 12,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          pro.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            if (review['cons'] != null && (review['cons'] as List).isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: (review['cons'] as List).map((con) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.thumb_down,
                          size: 12,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          con.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),

            // Barber response
            if (barberResponse != null && barberResponse.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.reply, size: 14, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Your Reply',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      barberResponse,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),

            // Reply input
            if (isReplying)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _replyController,
                      maxLines: 3,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Write your reply...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[400],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                        fillColor: isDark
                            ? const Color(0xFF1A1A1A)
                            : Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _replyingToReviewId = null;
                              _replyController.clear();
                            });
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _submitReply(review['id']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Submit Reply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Actions
            if (barberResponse == null || barberResponse.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _replyingToReviewId =
                              _replyingToReviewId == review['id']
                              ? null
                              : review['id'];
                          _replyController.clear();
                        });
                      },
                      icon: Icon(
                        _replyingToReviewId == review['id']
                            ? Icons.close
                            : Icons.reply,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                      tooltip: 'Reply to review',
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.thumb_up,
                          size: 14,
                          color: isDark ? Colors.white70 : Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$helpfulCount',
                          style: TextStyle(
                            fontSize: 12,
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
    );
  }

  Widget _buildRatingChip({
    required String label,
    required int value,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white70 : Colors.grey[500],
          ),
        ),
        const SizedBox(width: 4),
        Row(
          children: List.generate(5, (index) {
            final isFilled = index < value;
            return Icon(
              isFilled ? Icons.star : Icons.star_border,
              size: 10,
              color: isFilled
                  ? Colors.amber
                  : (isDark ? Colors.white30 : Colors.grey[300]),
            );
          }),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD STATS TAB
  // ============================================================
  Widget _buildStatsTab() {
    final isDark = context.isDarkMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Overall Rating
          Card(
            elevation: 2,
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Overall Rating',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _averageRating.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final isFilled = index < _averageRating.round();
                      return Icon(
                        isFilled ? Icons.star : Icons.star_border,
                        size: 28,
                        color: isFilled
                            ? Colors.amber
                            : (isDark ? Colors.white30 : Colors.grey[300]),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_totalReviews reviews',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Rating Distribution
          Card(
            elevation: 2,
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rating Distribution',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRatingBar(
                    label: '5 ★',
                    count: _fiveStarCount,
                    total: _totalReviews,
                    color: Colors.green,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildRatingBar(
                    label: '4 ★',
                    count: _fourStarCount,
                    total: _totalReviews,
                    color: Colors.lightGreen,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildRatingBar(
                    label: '3 ★',
                    count: _threeStarCount,
                    total: _totalReviews,
                    color: Colors.amber,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildRatingBar(
                    label: '2 ★',
                    count: _twoStarCount,
                    total: _totalReviews,
                    color: Colors.orange,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildRatingBar(
                    label: '1 ★',
                    count: _oneStarCount,
                    total: _totalReviews,
                    color: Colors.red,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Stats
          Card(
            elevation: 2,
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Stats',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          label: 'Total Reviews',
                          value: '$_totalReviews',
                          icon: Icons.reviews,
                          color: Colors.blue,
                          isDark: isDark,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStat(
                          label: 'Avg Rating',
                          value: _averageRating.toStringAsFixed(1),
                          icon: Icons.star,
                          color: Colors.amber,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          label: '5 Star',
                          value: '$_fiveStarCount',
                          icon: Icons.star,
                          color: Colors.green,
                          isDark: isDark,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStat(
                          label: '4 Star',
                          value: '$_fourStarCount',
                          icon: Icons.star,
                          color: Colors.lightGreen,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          label: '3 Star',
                          value: '$_threeStarCount',
                          icon: Icons.star,
                          color: Colors.amber,
                          isDark: isDark,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStat(
                          label: '2 Star',
                          value: '$_twoStarCount',
                          icon: Icons.star,
                          color: Colors.orange,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStat(
                          label: '1 Star',
                          value: '$_oneStarCount',
                          icon: Icons.star,
                          color: Colors.red,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBar({
    required String label,
    required int count,
    required int total,
    required Color color,
    required bool isDark,
  }) {
    final percentage = total > 0 ? (count / total * 100) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              '$count (${percentage.toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: percentage / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
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
      } else if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()} weeks ago';
      } else if (difference.inDays < 365) {
        return '${(difference.inDays / 30).floor()} months ago';
      } else {
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildEmptyState() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.reviews,
            size: 80,
            color: isDark ? Colors.white70 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No reviews found matching "$_searchQuery"'
                : 'No reviews yet',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reviews from your customers will appear here',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[400],
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
    );
  }
}