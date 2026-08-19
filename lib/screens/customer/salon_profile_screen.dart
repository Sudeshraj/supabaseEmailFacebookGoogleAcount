import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';
import '../../extensions/context_extensions.dart';

class SalonProfileScreen extends StatefulWidget {
  final Map<String, dynamic> salon;

  const SalonProfileScreen({super.key, required this.salon});

  @override
  State<SalonProfileScreen> createState() => _SalonProfileScreenState();
}

class _SalonProfileScreenState extends State<SalonProfileScreen> {
  final supabase = Supabase.instance.client;

  double _averageRating = 0.0;
  int _totalReviews = 0;
  bool _isLoadingRating = true;
  bool _isFollowing = false;
  int _followersCount = 0;

  List<Map<String, dynamic>> _offers = [];
  bool _isLoadingOffers = true;

  // ==================== TIMEZONE VARIABLES ====================
  String _userTimezone = '';
  bool _isTimezoneLoaded = false;

  // Salon hours in local time (converted from UTC using user's timezone)
  String _openTimeLocal = '';
  String _closeTimeLocal = '';

  // ==================== USER STATUS CACHE ====================
  bool _isUserActive = false;
  bool _isUserLoaded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  // ==================== INITIALIZATION ====================

  Future<void> _initialize() async {
    await _initializeTimezone();
    await Future.wait([
      _loadUserStatus(),
      _loadSalonDetails(),
      _checkIfFollowing(),
      _loadFollowersCount(),
      _loadSalonOffers(),
    ]);
  }

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    _convertSalonHoursToLocal();

    if (!mounted) return;
    setState(() {
      _isTimezoneLoaded = true;
    });

    debugPrint('✅ User timezone: $_userTimezone');
  }

  // ============================================================
  // ✅ LOAD USER STATUS
  // ============================================================
  Future<void> _loadUserStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isUserActive = false;
          _isUserLoaded = true;
        });
        return;
      }

      final customerCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 3)
          .maybeSingle();

      if (customerCheck == null || customerCheck['status'] != 'active') {
        debugPrint('⚠️ User is not an active customer');
        if (!mounted) return;
        setState(() {
          _isUserActive = false;
          _isUserLoaded = true;
        });
        return;
      }

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          debugPrint('⚠️ User account is blocked');
          if (!mounted) return;
          setState(() {
            _isUserActive = false;
            _isUserLoaded = true;
          });
          return;
        }
        if (profileCheck['is_active'] == false) {
          debugPrint('⚠️ User profile is inactive');
          if (!mounted) return;
          setState(() {
            _isUserActive = false;
            _isUserLoaded = true;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _isUserActive = true;
        _isUserLoaded = true;
      });
      debugPrint('✅ User is active and has customer role');
    } catch (e) {
      debugPrint('❌ Error loading user status: $e');
      if (!mounted) return;
      setState(() {
        _isUserActive = false;
        _isUserLoaded = true;
      });
    }
  }

  // ==================== TIMEZONE CONVERSION ====================

  void _convertSalonHoursToLocal() {
    try {
      final openTimeUtc = widget.salon['open_time']?.toString() ?? '09:00:00';
      final closeTimeUtc = widget.salon['close_time']?.toString() ?? '18:00:00';

      _openTimeLocal = _utcToLocalTimeString(openTimeUtc);
      _closeTimeLocal = _utcToLocalTimeString(closeTimeUtc);

      debugPrint(
        '🔄 Hours converted: UTC $openTimeUtc-$closeTimeUtc → Local $_openTimeLocal-$_closeTimeLocal',
      );
    } catch (e) {
      debugPrint('❌ Error converting hours: $e');
      _openTimeLocal = _formatTimeString(
        widget.salon['open_time']?.toString() ?? '09:00:00',
      );
      _closeTimeLocal = _formatTimeString(
        widget.salon['close_time']?.toString() ?? '18:00:00',
      );
    }
  }

  String _utcToLocalTimeString(String utcTime) {
    try {
      return TimezoneService.utcToLocalTimeRecurring(utcTime);
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      return _formatTimeString(utcTime);
    }
  }

  String _formatTimeString(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  bool _isOpenNow() {
    try {
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;

      TimeOfDay parseTime(String timeStr) {
        final parts = timeStr.split(' ');
        final hourMinute = parts[0].split(':');
        final period = parts[1];
        int hour = int.parse(hourMinute[0]);
        if (period == 'PM' && hour != 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: int.parse(hourMinute[1]));
      }

      final openTime = parseTime(_openTimeLocal);
      final closeTime = parseTime(_closeTimeLocal);

      final openMinutes = openTime.hour * 60 + openTime.minute;
      final closeMinutes = closeTime.hour * 60 + closeTime.minute;

      if (closeMinutes < openMinutes) {
        return nowMinutes >= openMinutes || nowMinutes <= closeMinutes;
      }
      return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
    } catch (e) {
      debugPrint('Error checking open status: $e');
      return true;
    }
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadSalonDetails() async {
    try {
      final reviews = await supabase
          .from('reviews')
          .select('overall_rating')
          .eq('salon_id', widget.salon['id'])
          .eq('status', 'published');

      if (!mounted) return;

      if (reviews.isNotEmpty) {
        double total = 0;
        for (var review in reviews) {
          total += (review['overall_rating'] as num?)?.toDouble() ?? 0;
        }
        setState(() {
          _averageRating = total / reviews.length;
          _totalReviews = reviews.length;
          _isLoadingRating = false;
        });
      } else {
        setState(() {
          _averageRating = 0;
          _totalReviews = 0;
          _isLoadingRating = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading reviews: $e');
      if (!mounted) return;
      setState(() => _isLoadingRating = false);
    }
  }

  Future<void> _loadFollowersCount() async {
    try {
      final followers = await supabase
          .from('salon_followers')
          .select('id')
          .eq('salon_id', widget.salon['id']);

      if (!mounted) return;
      setState(() {
        _followersCount = followers.length;
      });
    } catch (e) {
      debugPrint('Error loading followers: $e');
      if (!mounted) return;
      setState(() => _followersCount = 0);
    }
  }

  Future<void> _loadSalonOffers() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final offers = await supabase
          .from('offers')
          .select('''
            id,
            title,
            description,
            discount_type,
            discount_value,
            points_required,
            valid_from,
            valid_to,
            image_url
          ''')
          .eq('salon_id', widget.salon['id'])
          .eq('is_active', true)
          .lte('valid_from', today)
          .gte('valid_to', today)
          .order('points_required', ascending: true);

      if (!mounted) return;
      setState(() {
        _offers = List<Map<String, dynamic>>.from(offers);
        _isLoadingOffers = false;
      });
    } catch (e) {
      debugPrint('Error loading offers: $e');
      if (!mounted) return;
      setState(() => _isLoadingOffers = false);
    }
  }

  Future<void> _checkIfFollowing() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
        });
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
        });
        return;
      }

      final result = await supabase
          .from('salon_followers')
          .select()
          .eq('customer_id', user.id)
          .eq('salon_id', widget.salon['id'])
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _isFollowing = result != null;
      });
    } catch (e) {
      debugPrint('Error checking follow status: $e');
      if (!mounted) return;
      setState(() {
        _isFollowing = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnackBar('Please login to follow salons', Colors.orange);
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        _showSnackBar(
          'Your account is not active. Please contact support.',
          Colors.red,
        );
        return;
      }

      if (_isFollowing) {
        await supabase
            .from('salon_followers')
            .delete()
            .eq('customer_id', user.id)
            .eq('salon_id', widget.salon['id']);

        if (!mounted) return;
        setState(() {
          _isFollowing = false;
          _followersCount--;
        });
        _showSnackBar('Unfollowed ${widget.salon['name']}', Colors.grey);
      } else {
        await supabase.from('salon_followers').insert({
          'customer_id': user.id,
          'salon_id': widget.salon['id'],
        });

        if (!mounted) return;
        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
        _showSnackBar('Following ${widget.salon['name']}', Colors.green);
      }
    } catch (e) {
      debugPrint('Error toggling follow: $e');
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _openWhatsApp() async {
    if (!_isUserLoaded) {
      await _loadUserStatus();
    }

    if (!_isUserActive) {
      _showSnackBar(
        'Your account is not active. Please contact support.',
        Colors.red,
      );
      return;
    }

    final phone = widget.salon['phone'];
    if (phone == null || phone.toString().isEmpty) {
      _showSnackBar('Phone number not available', Colors.orange);
      return;
    }

    String cleanPhone = phone.toString().replaceAll(RegExp(r'[^0-9+]'), '');
    if (!cleanPhone.startsWith('+')) {
      cleanPhone = '+94$cleanPhone';
    }

    final whatsappUrl = 'https://wa.me/$cleanPhone';

    try {
      final Uri url = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('WhatsApp is not installed', Colors.orange);
      }
    } catch (e) {
      debugPrint('Error opening WhatsApp: $e');
      _showSnackBar('Could not open WhatsApp', Colors.red);
    }
  }

  void _startBookingFlow() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnackBar('Please login to book appointments', Colors.orange);
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        _showSnackBar(
          'Your account is not active. Please contact support.',
          Colors.red,
        );
        return;
      }
      if (!mounted) return;
      debugPrint('🚀 Starting booking flow for salon: ${widget.salon['name']}');
      context.push('/customer/booking-flow', extra: widget.salon);
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
      _showSnackBar('Error starting booking. Please try again.', Colors.red);
    }
  }

  void _navigateToVipBooking() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnackBar('Please login to book VIP appointments', Colors.orange);
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        _showSnackBar(
          'Your account is not active. Please contact support.',
          Colors.red,
        );
        return;
      }
      if (!mounted) return;
      context.push('/customer/vip-booking', extra: widget.salon);
    } catch (e) {
      debugPrint('❌ VIP navigation error: $e');
      _showSnackBar(
        'Error starting VIP booking. Please try again.',
        Colors.red,
      );
    }
  }

  void _claimOffer(Map<String, dynamic> offer) {
    _checkAndShowOfferDialog(offer);
  }

  Future<void> _checkAndShowOfferDialog(Map<String, dynamic> offer) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnackBar('Please login to claim offers', Colors.orange);
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        _showSnackBar(
          'Your account is not active. Please contact support.',
          Colors.red,
        );
        return;
      }

      if (!mounted) return;
      _showOfferDialog(offer);
    } catch (e) {
      debugPrint('Error checking user status: $e');
      _showSnackBar('Error claiming offer. Please try again.', Colors.red);
    }
  }

  void _showOfferDialog(Map<String, dynamic> offer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: context.backgroundColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                offer['image_url'] ?? _getOfferIcon(offer['discount_type']),
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                offer['title'],
                style: context.titleLarge.copyWith(
                  color: context.textColor,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              offer['description'] ?? '',
              style: context.bodyMedium.copyWith(
                color: context.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDarkMode
                    ? Colors.grey.withValues(alpha: 0.1)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (offer['discount_type'] == 'percentage')
                    Text(
                      '${offer['discount_value']}% OFF',
                      style: context.titleLarge.copyWith(
                        color: context.primaryColor,
                      ),
                    )
                  else if (offer['discount_type'] == 'fixed')
                    Text(
                      'Rs. ${offer['discount_value']} OFF',
                      style: context.titleLarge.copyWith(
                        color: context.primaryColor,
                      ),
                    )
                  else
                    Text(
                      'FREE SERVICE',
                      style: context.titleLarge.copyWith(
                        color: context.primaryColor,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (offer['points_required'] > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${offer['points_required']} points required',
                          style: context.bodySmall.copyWith(
                            color: context.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.date_range, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'Valid until: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(offer['valid_to']))}',
                  style: context.bodySmall.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applyOffer(offer);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apply Offer'),
          ),
        ],
      ),
    );
  }

  void _applyOffer(Map<String, dynamic> offer) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnackBar('Please login to apply offers', Colors.orange);
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        _showSnackBar(
          'Your account is not active. Please contact support.',
          Colors.red,
        );
        return;
      }

      _showSnackBar('✅ Offer "${offer['title']}" applied!', Colors.green);
      if (!mounted) return;
      context.push(
        '/customer/booking-flow',
        extra: {'salon': widget.salon, 'offer': offer},
      );
    } catch (e) {
      debugPrint('Error applying offer: $e');
      _showSnackBar('Error applying offer. Please try again.', Colors.red);
    }
  }

  void _showAllOffersDialog() {
    if (!_isUserLoaded) {
      _loadUserStatus().then((_) {
        if (mounted && _isUserActive) {
          _showAllOffersBottomSheet();
        } else if (mounted) {
          _showSnackBar(
            'Your account is not active. Please contact support.',
            Colors.red,
          );
        }
      });
      return;
    }

    if (!_isUserActive) {
      _showSnackBar(
        'Your account is not active. Please contact support.',
        Colors.red,
      );
      return;
    }

    _showAllOffersBottomSheet();
  }

  void _showAllOffersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.isDarkMode ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'All Offers',
                style: context.titleLarge.copyWith(
                  color: context.textColor,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _offers.length,
                itemBuilder: (context, index) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _buildOfferCard(_offers[index], index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  String _getDiscountText(Map<String, dynamic> offer) {
    if (offer['discount_type'] == 'percentage') {
      return '${offer['discount_value']}% OFF';
    } else if (offer['discount_type'] == 'fixed') {
      return 'Rs.${offer['discount_value']} OFF';
    } else {
      return 'FREE';
    }
  }

  String _getOfferIcon(String? discountType) {
    switch (discountType) {
      case 'percentage':
        return '💰';
      case 'fixed':
        return '💵';
      case 'free_service':
        return '🎁';
      default:
        return '🏷️';
    }
  }

  Color _getOfferColor(int index) {
    final colors = [
      const Color(0xFFFF6B8B),
      Colors.purple.shade400,
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
    ];
    return colors[index % colors.length];
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== UI BUILDERS ====================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final isTablet = screenWidth > 600 && screenWidth <= 800;
    final contentWidth = isWeb ? 1000.0 : double.infinity;

    final openTime = _openTimeLocal.isNotEmpty ? _openTimeLocal : '09:00 AM';
    final closeTime = _closeTimeLocal.isNotEmpty ? _closeTimeLocal : '06:00 PM';
    final isOpen = _isOpenNow();

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: context.backgroundColor,
        appBar: AppBar(
          title: const Text('Salon Profile'),
          backgroundColor: context.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFF6B8B)),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // ✅ Frame for web view
          if (isWeb) {
            return Container(
              color: context.backgroundColor,
              child: Center(
                child: Container(
                  width: contentWidth,
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight,
                  ),
                  decoration: BoxDecoration(
                    color: context.backgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: _buildContent(isWeb, isTablet, openTime, closeTime, isOpen),
                ),
              ),
            );
          }
          return _buildContent(isWeb, isTablet, openTime, closeTime, isOpen);
        },
      ),
    );
  }

  Widget _buildContent(
    bool isWeb,
    bool isTablet,
    String openTime,
    String closeTime,
    bool isOpen,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Cover Image Section
          _buildCoverSection(isWeb),

          // ✅ Logo and Action Buttons
          _buildLogoAndActionsSection(isWeb),

          // ✅ Main Content
          Container(
            margin: EdgeInsets.only(top: 20),
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isWeb ? 1000.0 : double.infinity,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ Salon Info Section
                    _buildSalonInfoSection(isWeb, isTablet, openTime, closeTime, isOpen),

                    const SizedBox(height: 24),

                    // ✅ Booking Buttons
                    _buildBookingButtons(isWeb, isTablet),

                    const SizedBox(height: 32),
                    Divider(color: context.dividerColor, height: 1),
                    const SizedBox(height: 24),

                    // ✅ Offers Section
                    _buildOffersSection(),

                    const SizedBox(height: 24),

                    // ✅ About Section
                    _buildAboutSection(),

                    const SizedBox(height: 24),

                    // ✅ Contact Section
                    _buildContactSection(),

                    const SizedBox(height: 24),

                    // ✅ Services Section
                    _buildServicesSection(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: COVER SECTION
  // ============================================================

  Widget _buildCoverSection(bool isWeb) {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: isWeb ? 350 : 280,
          child: _buildCoverImage(),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          left: 16,
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 22,
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          top: 40,
          right: 16,
          child: Row(
            children: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isFollowing ? Icons.favorite : Icons.favorite_border,
                    color: _isFollowing ? Colors.red : Colors.white,
                    size: 22,
                  ),
                ),
                onPressed: _toggleFollow,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ✅ BUILD: LOGO AND ACTIONS
  // ✅ FIX: RenderFlex overflow (61px) on mobile. Previously:
  // Row(children: [logo, Spacer(), Row([whatsapp, follow])])
  // The inner Row had no bound, so on narrow screens the
  // WhatsApp + Follow buttons together didn't fit and overflowed
  // to the right (also caused a cascading "Incorrect use of
  // ParentDataWidget" error). Now the button group is wrapped in
  // Expanded(child: Wrap(...)) so it's bounded to the remaining
  // width and wraps to a second line instead of overflowing.
  // ============================================================

  Widget _buildLogoAndActionsSection(bool isWeb) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Transform.translate(
            offset: Offset(0, -40),
            child: _buildLogo(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildWhatsAppButton(),
                _buildFollowButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: SALON INFO SECTION
  // ============================================================

  Widget _buildSalonInfoSection(
    bool isWeb,
    bool isTablet,
    String openTime,
    String closeTime,
    bool isOpen,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.salon['name'] ?? 'Salon',
              style: context.headlineMedium.copyWith(
                color: context.textColor,
              ),
            ),
            const SizedBox(height: 6),

            if (!_isLoadingRating)
              Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStarRating(_averageRating),
                      const SizedBox(width: 6),
                      Text(
                        _averageRating.toStringAsFixed(1),
                        style: context.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.textColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($_totalReviews reviews)',
                        style: context.bodySmall.copyWith(
                          color: context.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? Colors.white30
                          : Colors.grey[400],
                      shape: BoxShape.circle,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people,
                        size: 16,
                        color: context.secondaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_followersCount followers',
                        style: context.bodySmall.copyWith(
                          color: context.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

            const SizedBox(height: 12),

            if (widget.salon['address'] != null)
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: context.secondaryTextColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.salon['address'],
                      style: context.bodyMedium.copyWith(
                        color: context.secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: context.secondaryTextColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$openTime - $closeTime',
                      style: context.bodyMedium.copyWith(
                        color: context.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOpen ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOpen ? 'Open Now' : 'Closed',
                        style: context.bodySmall.copyWith(
                          color: isOpen ? Colors.green : Colors.red,
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
    );
  }

  // ============================================================
  // ✅ BUILD: BOOKING BUTTONS
  // ============================================================

  Widget _buildBookingButtons(bool isWeb, bool isTablet) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: isWeb || isTablet
          ? Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _startBookingFlow,
                    icon: const Icon(
                      Icons.calendar_today,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: const Text(
                      'Book Appointment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToVipBooking,
                    icon: const Icon(
                      Icons.star,
                      color: Colors.amber,
                      size: 20,
                    ),
                    label: const Text(
                      'VIP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startBookingFlow,
                    icon: const Icon(
                      Icons.calendar_today,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: const Text(
                      'Book Appointment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToVipBooking,
                    icon: const Icon(
                      Icons.star,
                      color: Colors.amber,
                      size: 20,
                    ),
                    label: const Text(
                      'VIP Booking',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // ✅ BUILD: OFFERS SECTION
  // ============================================================

  Widget _buildOffersSection() {
    if (!_offers.isNotEmpty && !_isLoadingOffers) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🔥 Special Offers',
                style: context.titleLarge.copyWith(
                  color: context.textColor,
                ),
              ),
              if (_offers.length > 2)
                TextButton(
                  onPressed: _showAllOffersDialog,
                  child: Text(
                    'View All',
                    style: context.bodyMedium.copyWith(
                      color: context.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _isLoadingOffers
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  ),
                )
              : SizedBox(
                  height: 260,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _offers.length > 3 ? 3 : _offers.length,
                    itemBuilder: (context, index) =>
                        _buildOfferCard(_offers[index], index),
                  ),
                ),
          const SizedBox(height: 20),
          Divider(color: context.dividerColor, height: 1),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: ABOUT SECTION
  // ============================================================

  Widget _buildAboutSection() {
    if (widget.salon['description'] == null ||
        widget.salon['description'].toString().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About',
            style: context.titleLarge.copyWith(
              color: context.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.dividerColor),
            ),
            child: Text(
              widget.salon['description'],
              style: context.bodyMedium.copyWith(
                color: context.secondaryTextColor,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Divider(color: context.dividerColor, height: 1),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: CONTACT SECTION
  // ✅ FIX: "ListTile background color or ink splashes may be
  // invisible". Previously the ListTiles sat directly inside a
  // Container that had its own BoxDecoration(color: ...), with no
  // Material ancestor of its own — the ListTile's ink/splash layer
  // could get painted over by that decoration. Wrapped the Column
  // of ListTiles in a Material(color: Colors.transparent) so the
  // splashes render correctly, while the outer Container still
  // supplies the visible card background/border/radius.
  // ============================================================

  Widget _buildContactSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact & Location',
            style: context.titleLarge.copyWith(
              color: context.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.dividerColor),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (widget.salon['phone'] != null &&
                      widget.salon['phone'].toString().isNotEmpty)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.phone,
                          color: context.primaryColor,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        'Phone',
                        style: context.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.textColor,
                        ),
                      ),
                      subtitle: Text(
                        widget.salon['phone'],
                        style: context.bodySmall.copyWith(
                          color: context.secondaryTextColor,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: context.secondaryTextColor,
                      ),
                      onTap: _openWhatsApp,
                    ),
                  if (widget.salon['email'] != null &&
                      widget.salon['email'].toString().isNotEmpty)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.email,
                          color: context.primaryColor,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        'Email',
                        style: context.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.textColor,
                        ),
                      ),
                      subtitle: Text(
                        widget.salon['email'],
                        style: context.bodySmall.copyWith(
                          color: context.secondaryTextColor,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: context.secondaryTextColor,
                      ),
                      onTap: () {},
                    ),
                  if (widget.salon['address'] != null &&
                      widget.salon['address'].toString().isNotEmpty)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: context.primaryColor,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        'Address',
                        style: context.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.textColor,
                        ),
                      ),
                      subtitle: Text(
                        widget.salon['address'],
                        style: context.bodySmall.copyWith(
                          color: context.secondaryTextColor,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: context.secondaryTextColor,
                      ),
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Divider(color: context.dividerColor, height: 1),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUILD: SERVICES SECTION
  // ============================================================

  Widget _buildServicesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Popular Services',
            style: context.titleLarge.copyWith(
              color: context.textColor,
            ),
          ),
          const SizedBox(height: 16),
          _buildServicesPreview(),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ HELPER WIDGETS
  // ============================================================

  Widget _buildLogo() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final logoSize = isWeb ? 120.0 : 90.0;

    final logoUrl = widget.salon['logo_url'];
    final hasLogo = logoUrl != null && logoUrl.toString().isNotEmpty;

    return Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: context.isDarkMode ? Colors.grey[800]! : Colors.white,
          width: isWeb ? 4 : 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        image: hasLogo
            ? DecorationImage(image: NetworkImage(logoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: !hasLogo
          ? Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.salon['name']?.substring(0, 1).toUpperCase() ?? 'S',
                  style: TextStyle(
                    fontSize: isWeb ? 48 : 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildWhatsAppButton() {
    final phone = widget.salon['phone'];
    final hasPhone = phone != null && phone.toString().isNotEmpty;

    if (!_isUserLoaded || !_isUserActive) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.secondaryTextColor,
          side: BorderSide(color: context.dividerColor),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat, size: 18, color: context.secondaryTextColor),
            const SizedBox(width: 6),
            Text(
              'WhatsApp',
              style: context.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: context.secondaryTextColor,
              ),
            ),
          ],
        ),
      );
    }

    return OutlinedButton(
      onPressed: hasPhone ? _openWhatsApp : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: hasPhone ? const Color(0xFF25D366) : context.secondaryTextColor,
        side: BorderSide(
          color: hasPhone
              ? const Color(0xFF25D366)
              : context.dividerColor,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat, size: 18),
          const SizedBox(width: 6),
          Text(
            'WhatsApp',
            style: context.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: hasPhone
                  ? const Color(0xFF25D366)
                  : context.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton() {
    if (!_isUserLoaded || !_isUserActive) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.isDarkMode ? Colors.grey[800] : Colors.grey[200],
          foregroundColor: context.secondaryTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
        child: Text(
          'Login to Follow',
          style: context.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: context.secondaryTextColor,
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: _toggleFollow,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isFollowing
            ? (context.isDarkMode ? Colors.grey[800] : Colors.grey[200])
            : context.primaryColor,
        foregroundColor: _isFollowing
            ? context.secondaryTextColor
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ),
      child: Text(
        _isFollowing ? 'Following' : 'Follow',
        style: context.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: _isFollowing
              ? context.secondaryTextColor
              : Colors.white,
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    final coverUrl = widget.salon['cover_url'];

    if (coverUrl != null && coverUrl.toString().isNotEmpty) {
      return Image.network(
        coverUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildDefaultCover(),
      );
    }
    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDarkMode
              ? [
                  const Color(0xFFFF6B8B).withValues(alpha: 0.6),
                  const Color(0xFFFF9A9E).withValues(alpha: 0.7),
                  const Color(0xFFFF6B8B).withValues(alpha: 0.5),
                ]
              : [
                  const Color(0xFFFF6B8B).withValues(alpha: 0.8),
                  const Color(0xFFFF9A9E).withValues(alpha: 0.9),
                  const Color(0xFFFF6B8B),
                ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.content_cut,
              size: 60,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              widget.salon['name'] ?? 'Salon',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, color: Colors.amber, size: 16);
        } else if (index < rating && rating - index > 0.5) {
          return const Icon(Icons.star_half, color: Colors.amber, size: 16);
        } else {
          return Icon(
            Icons.star_border,
            color: context.isDarkMode ? Colors.white30 : Colors.amber.withValues(alpha: 0.7),
            size: 16,
          );
        }
      }),
    );
  }

  Widget _buildOfferCard(Map<String, dynamic> offer, int index) {
    final color = _getOfferColor(index);
    final validTo = DateTime.parse(offer['valid_to']);
    final daysLeft = validTo.difference(DateTime.now()).inDays;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDarkMode
              ? [
                  color.withValues(alpha: 0.15),
                  const Color(0xFF1E1E1E),
                ]
              : [
                  color.withValues(alpha: 0.1),
                  Colors.white,
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.isDarkMode ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _claimOffer(offer),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          offer['image_url'] ??
                              _getOfferIcon(offer['discount_type']),
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer['title'],
                            style: context.bodyLarge.copyWith(
                              fontWeight: FontWeight.bold,
                              color: context.isDarkMode ? Colors.white : color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getDiscountText(offer),
                              style: context.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  offer['description'] ?? '',
                  style: context.bodySmall.copyWith(
                    color: context.isDarkMode ? Colors.white60 : Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (offer['points_required'] > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${offer['points_required']} pts',
                              style: context.bodySmall.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: daysLeft <= 3
                            ? Colors.red.withValues(alpha: 0.1)
                            : (context.isDarkMode
                                ? Colors.white10
                                : Colors.grey.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 10,
                            color: daysLeft <= 3
                                ? Colors.red
                                : (context.isDarkMode ? Colors.white60 : Colors.grey[600]),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            daysLeft <= 0 ? 'Expired' : '$daysLeft days left',
                            style: context.bodySmall.copyWith(
                              color: daysLeft <= 3
                                  ? Colors.red
                                  : (context.isDarkMode
                                      ? Colors.white60
                                      : Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _claimOffer(offer),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Claim Offer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServicesPreview() {
    return FutureBuilder(
      future: supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            is_active,
            service_variants!left (
              price,
              duration
            )
          ''')
          .eq('salon_id', widget.salon['id'])
          .eq('is_active', true)
          .limit(5),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            ),
          );
        }

        if (!snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.dividerColor),
            ),
            child: Center(
              child: Text(
                'No services available',
                style: context.bodyMedium.copyWith(
                  color: context.secondaryTextColor,
                ),
              ),
            ),
          );
        }

        final services = snapshot.data! as List;

        return Column(
          children: services.map((service) {
            final variants = service['service_variants'] as List?;
            double lowestPrice = 0.0;
            if (variants != null && variants.isNotEmpty) {
              final prices = variants
                  .map<double>((v) => (v['price'] as num?)?.toDouble() ?? 0)
                  .toList();
              if (prices.isNotEmpty) {
                lowestPrice = prices.reduce((a, b) => a < b ? a : b);
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.content_cut,
                      color: context.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] ?? 'Service',
                          style: context.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.textColor,
                          ),
                        ),
                        if (service['description'] != null)
                          Text(
                            service['description'],
                            style: context.bodySmall.copyWith(
                              color: context.secondaryTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'Rs. ${lowestPrice.toInt()}',
                    style: context.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                      color: context.primaryColor,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}