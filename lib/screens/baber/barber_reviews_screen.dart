import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/services/timezone_service.dart';

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
  List<Map<String, dynamic>> _filteredReviewsCache = [];
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

  // ✅ Salon timezone (for appointment time conversion)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';
  String _salonTimezone = _kDefaultSalonTimezone;

  // Filter
  String _selectedRatingFilter = 'All';
  String _selectedSort = 'Newest';

  // Tab controller
  late TabController _tabController;

  // Reply state - ✅ per-review controller map
  int? _replyingToReviewId;
  final Map<int, TextEditingController> _replyControllers = {};

  // ✅ Search controller (for clear button to work)
  final TextEditingController _searchController = TextEditingController();

  // ✅ Separate scroll controllers for Reviews + Stats tabs
  final ScrollController _reviewsScrollController = ScrollController();
  final ScrollController _statsScrollController = ScrollController();

  // ✅ Responsive
  bool _isWeb = false;
  bool _isTablet = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
  }

  /// ✅ Timezone loaded FIRST (reviews depend on it for TZ conversion)
  Future<void> _initialize() async {
    await TimezoneService.initialize();

    // ✅ Load timezone + barber name in parallel (no dependencies)
    await Future.wait([
      _loadBarberName(),
      _loadSalonTimezone(),
    ]);

    // ✅ Load reviews AFTER timezone (uses TZ for appointment times)
    await _loadReviews();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  /// ✅ MediaQuery.sizeOf (only reacts to size changes)
  void _checkScreenSize() {
    final size = MediaQuery.sizeOf(context);
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
    _searchController.dispose();
    _reviewsScrollController.dispose();
    _statsScrollController.dispose();
    for (var controller in _replyControllers.values) {
      controller.dispose();
    }
    _replyControllers.clear();
    super.dispose();
  }

  /// ✅ Get or create reply controller for a specific review
  TextEditingController _getReplyController(int reviewId) {
    return _replyControllers.putIfAbsent(
      reviewId,
      () => TextEditingController(),
    );
  }

  // ============================================================
  // ✅ LOAD SALON TIMEZONE
  // ============================================================
  Future<void> _loadSalonTimezone() async {
    if (widget.salonId == null) return;

    try {
      final salonResponse = await supabase
          .from('salons')
          .select('timezone')
          .eq('id', int.parse(widget.salonId!))
          .maybeSingle();

      if (salonResponse != null && mounted) {
        final tz = salonResponse['timezone'] as String?;
        if (tz != null && tz.isNotEmpty) {
          setState(() => _salonTimezone = tz);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading salon timezone: $e');
    }
  }

  /// ✅ Specific date TZ conversion (NOT recurring)
  /// ✅ Fallback reference date instead of DateTime.now()
  String _formatAppointmentTime(String? utcTime, DateTime? appointmentDate) {
    if (utcTime == null || utcTime.isEmpty) return '';
    // ✅ Use reference date if appointment date is missing
    final date = appointmentDate ?? DateTime(2024, 1, 1);
    try {
      return TimezoneService.utcToLocalTimeForDateWithTimezone(
        utcTime,
        date,
        _salonTimezone,
      );
    } catch (e) {
      debugPrint('❌ Error converting time: $e');
      return utcTime;
    }
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

      if (response != null && mounted) {
        setState(() {
          _barberName = response['full_name'] ?? 'Barber';
        });
      }
    } catch (e) {
      debugPrint('Error loading barber name: $e');
    }
  }

  // ============================================================
  // ✅ LOAD REVIEWS — FIXED QUERY (appointment_services)
  // ✅ mounted checks between all awaits
  // ============================================================
  Future<void> _loadReviews() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Please login to view reviews';
          _isLoading = false;
        });
        return;
      }

      final barberId = widget.barberId ?? currentUser.id;

      // ✅ appointments has NO service_id — use appointment_services
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
              appointment_date,
              start_time,
              appointment_services (
                service_name,
                variant_label
              )
            )
          ''')
          .eq('barber_id', barberId)
          .eq('status', 'published');

      if (widget.salonId != null) {
        query = query.eq('salon_id', int.parse(widget.salonId!));
      }

      final response = await query.order('created_at', ascending: false);

      // ✅ mounted check after await
      if (!mounted) return;

      final List<Map<String, dynamic>> reviewsList = [];
      int totalRating = 0;
      int fiveStar = 0;
      int fourStar = 0;
      int threeStar = 0;
      int twoStar = 0;
      int oneStar = 0;

      // Load customer profiles
      final Set<String> customerIds = {};
      for (var item in response) {
        final customerId = item['customer_id'] as String?;
        if (customerId != null) customerIds.add(customerId);
      }

      Map<String, Map<String, dynamic>> customerProfiles = {};
      if (customerIds.isNotEmpty) {
        final profilesResponse = await supabase
            .from('profiles')
            .select('id, full_name, email, avatar_url')
            .inFilter('id', customerIds.toList());

        // ✅ mounted check after await
        if (!mounted) return;

        for (var profile in profilesResponse) {
          customerProfiles[profile['id']] = {
            'full_name': profile['full_name'] ?? 'Anonymous',
            'email': profile['email'] ?? '',
            'avatar_url': profile['avatar_url'],
          };
        }
      }

      // Load salon names
      final Set<int> salonIds = {};
      for (var item in response) {
        final salonId = item['salon_id'] as int?;
        if (salonId != null) salonIds.add(salonId);
      }

      Map<int, String> salonNames = {};
      if (salonIds.isNotEmpty) {
        final salonsResponse = await supabase
            .from('salons')
            .select('id, name, logo_url')
            .inFilter('id', salonIds.toList());

        // ✅ mounted check after await
        if (!mounted) return;

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
        final salonId = item['salon_id'] as int?;
        final salonName = salonId != null
            ? salonNames[salonId]
            : 'Unknown Salon';

        // ✅ Multi-service name resolution
        final appointmentServices =
            appointment?['appointment_services'] as List?;
        String serviceName = 'Unknown Service';
        if (appointmentServices != null && appointmentServices.isNotEmpty) {
          final names = appointmentServices
              .map((s) => s['service_name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          if (names.isNotEmpty) {
            serviceName = names.length == 1
                ? names.first
                : '${names.first} +${names.length - 1} more';
          }
        }

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

        // ✅ Parse appointment_date for TZ conversion
        DateTime? appointmentDate;
        final appointmentDateStr = appointment?['appointment_date']?.toString();
        if (appointmentDateStr != null && appointmentDateStr.isNotEmpty) {
          try {
            appointmentDate = DateTime.parse(appointmentDateStr);
          } catch (_) {}
        }

        reviewsList.add({
          'id': item['id'],
          'appointment_id': item['appointment_id'],
          'customer_id': item['customer_id'],
          'barber_id': item['barber_id'],
          'customer_name': customer?['full_name'] ?? 'Anonymous',
          'customer_email': customer?['email'] ?? '',
          'customer_avatar': customer?['avatar_url'],
          'salon_id': item['salon_id'],
          'salon_name': salonName,
          'overall_rating': rating,
          'service_quality':
              (item['service_quality'] as num?)?.toDouble() ?? 0,
          'punctuality': (item['punctuality'] as num?)?.toDouble() ?? 0,
          'professionalism':
              (item['professionalism'] as num?)?.toDouble() ?? 0,
          'cleanliness': (item['cleanliness'] as num?)?.toDouble() ?? 0,
          'comment': item['comment'],
          'pros': item['pros'] as List? ?? [],
          'cons': item['cons'] as List? ?? [],
          'photos': item['photos'] as List? ?? [],
          'barber_response': item['barber_response'],
          'owner_response': item['owner_response'],
          'helpful_count': item['helpful_count'] ?? 0,
          'created_at': item['created_at'],
          'service_name': serviceName,
          'appointment_date': appointmentDateStr,
          'appointment_time': appointment?['start_time'],
          'booking_number': appointment?['booking_number'],
          '_appointment_date_parsed': appointmentDate,
        });
      }

      final averageRating = reviewsList.isNotEmpty
          ? totalRating / reviewsList.length
          : 0.0;

      if (!mounted) return;
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
        _applyFilters(); // ✅ Update filtered cache
      });

      debugPrint('✅ Loaded ${reviewsList.length} reviews');
    } catch (e) {
      debugPrint('❌ Error loading reviews: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading reviews: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // ✅ FILTER REVIEWS (cached, recomputed on state change)
  // ============================================================
  void _applyFilters() {
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

    _filteredReviewsCache = filtered;
  }

  // ============================================================
  // ✅ REPLY TO REVIEW (with authorization check)
  // ============================================================
  Future<void> _submitReply(int reviewId) async {
    final controller = _getReplyController(reviewId);
    if (controller.text.trim().isEmpty) {
      _showSnack('Please enter a reply', Colors.orange);
      return;
    }

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        _showSnack('Please login first', Colors.red);
        return;
      }

      // ✅ Authorization check (type-safe)
      final review = _reviews.firstWhere(
        (r) => r['id'] == reviewId,
        orElse: () => <String, dynamic>{},
      );

      if (review.isEmpty ||
          review['barber_id']?.toString() != currentUser.id) {
        _showSnack('You can only reply to your own reviews', Colors.red);
        return;
      }

      await supabase
          .from('reviews')
          .update({
            'barber_response': controller.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', reviewId);

      if (!mounted) return;

      setState(() {
        _replyingToReviewId = null;
      });
      controller.clear();

      await _loadReviews();

      if (mounted) {
        _showSnack('✅ Reply submitted successfully', Colors.green);
      }
    } catch (e) {
      debugPrint('❌ Error submitting reply: $e');
      if (mounted) {
        _showSnack('Error submitting reply: ${e.toString()}', Colors.red);
      }
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // ============================================================
  // BUILD METHODS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      // ✅ AppBar — TabBar ඉවත් කරලා (Appointments screen එකේ වගේ)
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color:
                                  isDark ? Colors.white60 : Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
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
                    ? _buildWebLayout(isDark)
                    : _buildMobileLayout(isDark),
      ),
    );
  }

  // ✅ WEB LAYOUT — TabBar body එකේ (Appointments screen වගේ)
  Widget _buildWebLayout(bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ✅ TabBar — body එකේ (Appointments screen වගේ)
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.reviews, size: 18),
                        const SizedBox(width: 8),
                        Text('Reviews ($_totalReviews)'),
                      ],
                    ),
                  ),
                  const Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.analytics, size: 18),
                        SizedBox(width: 8),
                        Text('Stats'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ✅ TabBarView — content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Reviews Tab - Web
                  Column(
                    children: [
                      _buildFilters(),
                      Expanded(
                        child: Scrollbar(
                          controller: _reviewsScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 8.0,
                          radius: const Radius.circular(10),
                          scrollbarOrientation: ScrollbarOrientation.right,
                          child: SingleChildScrollView(
                            controller: _reviewsScrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: _filteredReviewsCache.isEmpty
                                ? _buildEmptyState()
                                : _isTablet
                                    ? GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          childAspectRatio: 1.2,
                                        ),
                                        itemCount: _filteredReviewsCache.length,
                                        itemBuilder: (context, index) =>
                                            _buildReviewCard(
                                          _filteredReviewsCache[index],
                                          isDark,
                                        ),
                                      )
                                    : Column(
                                        children: _filteredReviewsCache
                                            .map((review) => _buildReviewCard(
                                                  review,
                                                  isDark,
                                                ))
                                            .toList(),
                                      ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Stats Tab - Web (own scrollbar)
                  Scrollbar(
                    controller: _statsScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 8.0,
                    radius: const Radius.circular(10),
                    scrollbarOrientation: ScrollbarOrientation.right,
                    child: SingleChildScrollView(
                      controller: _statsScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: _buildStatsTab(),
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

  // ✅ MOBILE LAYOUT — TabBar body එකේ (Appointments screen වගේ)
  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        // ✅ TabBar — body එකේ
        Container(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.normal,
            ),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.reviews, size: 16),
                    const SizedBox(width: 6),
                    Text('Reviews ($_totalReviews)'),
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics, size: 16),
                    SizedBox(width: 6),
                    Text('Stats'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ✅ TabBarView — content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Reviews Tab - Mobile
              Column(
                children: [
                  _buildFilters(),
                  Expanded(
                    child: _filteredReviewsCache.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredReviewsCache.length,
                            itemBuilder: (context, index) => _buildReviewCard(
                              _filteredReviewsCache[index],
                              isDark,
                            ),
                          ),
                  ),
                ],
              ),
              // Stats Tab - Mobile
              SingleChildScrollView(child: _buildStatsTab()),
            ],
          ),
        ),
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
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _applyFilters();
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
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _applyFilters();
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
                                  : (isDark
                                      ? Colors.white60
                                      : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedRatingFilter =
                                  selected ? rating : 'All';
                              _applyFilters();
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
                                  : (isDark
                                      ? Colors.white60
                                      : Colors.grey[700]),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedSort = selected ? sort : 'Newest';
                              _applyFilters();
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
    final reviewId = review['id'] as int;
    final rating = review['overall_rating'] as double? ?? 0;
    final customerName = review['customer_name']?.toString() ?? 'Anonymous';
    final customerAvatar = review['customer_avatar']?.toString();
    final comment = review['comment']?.toString();
    final createdAt = review['created_at'] as String?;
    final serviceName = review['service_name']?.toString() ?? 'Unknown';
    final barberResponse = review['barber_response']?.toString();
    final ownerResponse = review['owner_response']?.toString();
    final helpfulCount = review['helpful_count'] as int? ?? 0;
    final isReplying = _replyingToReviewId == reviewId;

    // ✅ Appointment info
    final bookingNumber = review['booking_number']?.toString();
    final appointmentDate = review['appointment_date']?.toString();
    final appointmentDateParsed =
        review['_appointment_date_parsed'] as DateTime?;
    final appointmentTime = _formatAppointmentTime(
      review['appointment_time']?.toString(),
      appointmentDateParsed,
    );

    // ✅ Photos
    final photos = (review['photos'] as List?) ?? [];

    // ✅ Build appointment info list
    final appointmentParts = <String>[
      if (bookingNumber != null && bookingNumber.isNotEmpty) bookingNumber,
      if (appointmentDate != null && appointmentDate.isNotEmpty)
        appointmentDate,
      if (appointmentTime.isNotEmpty) appointmentTime,
    ];

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
                          Flexible(
                            child: Text(
                              serviceName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white30
                                  : Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey[500],
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

            // ✅ Appointment info
            if (appointmentParts.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event,
                      size: 14,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appointmentParts.join(' • '),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Rating breakdown
            if ((review['service_quality'] as double?) != null &&
                ((review['service_quality'] as double) > 0 ||
                    (review['punctuality'] as double) > 0 ||
                    (review['professionalism'] as double) > 0 ||
                    (review['cleanliness'] as double) > 0))
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

            // ✅ Photos
            if (photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final photoUrl = photos[index].toString();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: photoUrl,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            width: 80,
                            height: 80,
                            color:
                                isDark ? Colors.grey[800] : Colors.grey[200],
                          ),
                          errorWidget: (_, _, _) => Container(
                            width: 80,
                            height: 80,
                            color:
                                isDark ? Colors.grey[800] : Colors.grey[200],
                            child: const Icon(Icons.broken_image, size: 20),
                          ),
                        ),
                      );
                    },
                  ),
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

            // ✅ Owner response
            if (ownerResponse != null && ownerResponse.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.store,
                          size: 14,
                          color: Colors.purple,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Salon Owner Reply',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.purple[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ownerResponse,
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
                      controller: _getReplyController(reviewId),
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
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
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
                            });
                            _getReplyController(reviewId).clear();
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color:
                                  isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _submitReply(reviewId),
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
                              _replyingToReviewId == reviewId
                                  ? null
                                  : reviewId;
                        });
                        if (_replyingToReviewId != reviewId) {
                          _getReplyController(reviewId).clear();
                        }
                      },
                      icon: Icon(
                        _replyingToReviewId == reviewId
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
                          color:
                              isDark ? Colors.white70 : Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$helpfulCount',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white70 : Colors.grey[500],
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

    return Padding(
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
                    style: const TextStyle(
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
  /// ✅ Guard against future dates (clock skew / wrong data)
  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      // ✅ Convert to local time (UTC stored in DB)
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);

      // ✅ If future date, just show the actual date
      if (difference.isNegative) {
        return DateFormat('MMM dd, yyyy').format(date);
      }

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
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Reviews from your customers will appear here',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _applyFilters();
                });
              },
              child: const Text('Clear Search'),
            ),
        ],
      ),
    );
  }
}