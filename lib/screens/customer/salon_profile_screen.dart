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

  // ✅ Track claim state per offer
  final Set<int> _claimingOfferIds = {};

  // ==================== TIMEZONE VARIABLES ====================
  String _userTimezone = '';
  bool _isTimezoneLoaded = false;

  String _openTimeLocal = '';
  String _closeTimeLocal = '';

  // ==================== USER STATUS CACHE ====================
  bool _isUserActive = false;
  bool _isUserLoaded = false;

  // ==================== SERVICE MENU ====================
  late Future<List<Map<String, dynamic>>> _menuTreeFuture;
  final Map<String, Map<String, dynamic>> _selectedBookingItems = {};

  final List<Map<String, dynamic>> _menuIconSuggestions = [
    {'icon': Icons.content_cut, 'name': 'content_cut'},
    {'icon': Icons.face, 'name': 'face'},
    {'icon': Icons.face_retouching_natural, 'name': 'face_retouching_natural'},
    {'icon': Icons.spa, 'name': 'spa'},
    {'icon': Icons.handshake, 'name': 'handshake'},
    {'icon': Icons.build, 'name': 'build'},
    {'icon': Icons.brush, 'name': 'brush'},
    {'icon': Icons.water_drop, 'name': 'water_drop'},
    {'icon': Icons.masks, 'name': 'masks'},
    {'icon': Icons.spa_outlined, 'name': 'spa_outlined'},
  ];

  @override
  void initState() {
    super.initState();
    _menuTreeFuture = _loadCategoryTree();
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
    ]);
    // ✅ Load offers AFTER user status is known (for claim_status)
    await _loadSalonOffers();
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

      // ✅ Role check by name (not hardcoded role_id)
      final customerCheck = await supabase
          .from('user_roles')
          .select('status, roles!inner(name)')
          .eq('user_id', user.id)
          .eq('roles.name', 'customer')
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

  // ============================================================
  // ✅ LOAD OFFERS (with variant info + claim status)
  // ============================================================
  Future<void> _loadSalonOffers() async {
    try {
      final user = supabase.auth.currentUser;
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
            image_url,
            usage_limit,
            used_count,
            offer_services (
              service_id,
              variant_id,
              services:service_id (id, name),
              service_variants:variant_id (id, salon_gender_id, salon_age_category_id)
            )
          ''')
          .eq('salon_id', widget.salon['id'])
          .eq('is_active', true)
          .lte('valid_from', today)
          .gte('valid_to', today)
          .order('points_required', ascending: true);

      // ✅ Load claims for this customer
      Map<int, String> claimStatus = {};
      if (user != null && offers.isNotEmpty) {
        try {
          final offerIds = offers.map<int>((o) => o['id'] as int).toList();
          final claims = await supabase
              .from('customer_offers')
              .select('offer_id, status')
              .eq('customer_id', user.id)
              .inFilter('offer_id', offerIds);

          for (var claim in claims) {
            claimStatus[claim['offer_id'] as int] = claim['status'] as String;
          }
        } catch (e) {
          debugPrint('Error loading claims: $e');
        }
      }

      // ✅ Load gender/age lookups for variant labels
      final genderIds = <int>{};
      final ageIds = <int>{};
      for (final o in offers) {
        final svcList = o['offer_services'] as List? ?? [];
        for (final os in svcList) {
          final variant = os['service_variants'];
          if (variant != null) {
            final gid = variant['salon_gender_id'] as int?;
            final aid = variant['salon_age_category_id'] as int?;
            if (gid != null) genderIds.add(gid);
            if (aid != null) ageIds.add(aid);
          }
        }
      }

      final Map<int, String> genderMap = {};
      if (genderIds.isNotEmpty) {
        final genders = await supabase
            .from('salon_genders')
            .select('id, display_name')
            .inFilter('id', genderIds.toList());
        for (var g in genders) {
          genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
        }
      }

      final Map<int, String> ageMap = {};
      if (ageIds.isNotEmpty) {
        final ages = await supabase
            .from('salon_age_categories')
            .select('id, display_name')
            .inFilter('id', ageIds.toList());
        for (var a in ages) {
          ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
        }
      }

      // ✅ Build variant/scope summary for each offer
      final enriched = offers.map<Map<String, dynamic>>((o) {
        final offer = Map<String, dynamic>.from(o);
        final svcList = (offer['offer_services'] as List? ?? []);
        final scopeParts = <String>[];

        for (final os in svcList) {
          final service = os['services'];
          final variant = os['service_variants'];
          final serviceName = service?['name']?.toString() ?? 'Service';

          if (variant == null) {
            // Service-level
            scopeParts.add(serviceName);
          } else {
            final gid = variant['salon_gender_id'] as int?;
            final aid = variant['salon_age_category_id'] as int?;
            final gender = gid != null ? (genderMap[gid] ?? '') : '';
            final age = aid != null ? (ageMap[aid] ?? '') : '';
            final labelParts = <String>[];
            if (gender.isNotEmpty) labelParts.add(gender);
            if (age.isNotEmpty) labelParts.add(age);
            final vLabel = labelParts.isEmpty ? 'Standard' : labelParts.join(' ');
            scopeParts.add('$serviceName · $vLabel');
          }
        }

        offer['scope_summary'] =
            scopeParts.isEmpty ? 'All services' : scopeParts.join(', ');
        offer['claim_status'] = claimStatus[offer['id'] as int];
        return offer;
      }).toList();

      if (!mounted) return;
      setState(() {
        _offers = enriched;
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
        setState(() => _isFollowing = false);
        return;
      }

      if (!_isUserLoaded) {
        await _loadUserStatus();
      }

      if (!_isUserActive) {
        if (!mounted) return;
        setState(() => _isFollowing = false);
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
      setState(() => _isFollowing = false);
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

  // ============================================================
  // ✅ OFFER CLAIM (uses claim_offer RPC, atomic)
  // ============================================================

  Future<void> _claimOffer(Map<String, dynamic> offer) async {
    final offerId = offer['id'] as int;

    if (_claimingOfferIds.contains(offerId)) return;

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

      // ✅ Must follow salon first
      if (!_isFollowing) {
        _showSnackBar(
          'Please follow ${widget.salon['name'] ?? 'this salon'} to claim offers',
          Colors.orange,
        );
        return;
      }

      // ✅ Already claimed / used guard
      final claimStatus = offer['claim_status'];
      if (claimStatus == 'active') {
        _showSnackBar('You have already claimed this offer', Colors.orange);
        return;
      }
      if (claimStatus == 'used') {
        _showSnackBar('You have already used this offer', Colors.red);
        return;
      }

      if (!mounted) return;
      final confirmed = await _showClaimConfirmDialog(offer);
      if (confirmed != true) return;

      setState(() => _claimingOfferIds.add(offerId));

      // ✅ Atomic RPC (handles points + used_count + validation)
      final response = await supabase.rpc(
        'claim_offer',
        params: {'p_offer_id': offerId},
      );

      if (!mounted) return;
      setState(() => _claimingOfferIds.remove(offerId));

      final result = response is Map ? response : <String, dynamic>{};
      if (result['success'] == true) {
        _showSnackBar('✅ "${offer['title']}" claimed!', Colors.green);
        await _loadSalonOffers();
      } else {
        final msg = (result['message'] ?? 'Failed to claim offer').toString();
        _showSnackBar(msg, Colors.red);
        await _loadSalonOffers();
      }
    } catch (e) {
      debugPrint('Error claiming offer: $e');
      if (mounted) {
        setState(() => _claimingOfferIds.remove(offerId));
        _showSnackBar('Error claiming offer. Please try again.', Colors.red);
      }
    }
  }

  Future<bool?> _showClaimConfirmDialog(Map<String, dynamic> offer) {
    final pointsRequired = offer['points_required'] ?? 0;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                style: context.titleLarge.copyWith(color: context.textColor),
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
              style: context.bodyMedium
                  .copyWith(color: context.secondaryTextColor),
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
                  Text(
                    _getDiscountText(offer),
                    style: context.titleLarge.copyWith(
                      color: context.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scope: ${offer['scope_summary']}',
                    textAlign: TextAlign.center,
                    style: context.bodySmall
                        .copyWith(color: context.secondaryTextColor),
                  ),
                  if (pointsRequired > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star,
                            color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$pointsRequired points required',
                          style: context.bodySmall.copyWith(
                            color: context.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                  style: context.bodySmall.copyWith(color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Claim Offer'),
          ),
        ],
      ),
    );
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
                color:
                    context.isDarkMode ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'All Offers',
                style: context.titleLarge.copyWith(color: context.textColor),
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
          if (isWeb) {
            return Container(
              color: context.backgroundColor,
              child: Center(
                child: Container(
                  width: contentWidth,
                  constraints:
                      BoxConstraints(maxHeight: constraints.maxHeight),
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
                  child: _buildContent(
                      isWeb, isTablet, openTime, closeTime, isOpen),
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
          _buildCoverSection(isWeb),
          _buildLogoAndActionsSection(isWeb),
          Container(
            margin: const EdgeInsets.only(top: 20),
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isWeb ? 1000.0 : double.infinity,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSalonInfoSection(
                        isWeb, isTablet, openTime, closeTime, isOpen),
                    const SizedBox(height: 20),
                    _buildMenuTreeSection(isWeb),
                    const SizedBox(height: 32),
                    Divider(color: context.dividerColor, height: 1),
                    const SizedBox(height: 24),
                    _buildOffersSection(),
                    const SizedBox(height: 24),
                    _buildAboutSection(),
                    const SizedBox(height: 24),
                    _buildContactSection(),
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
  // COVER SECTION
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
              child: const Icon(Icons.arrow_back,
                  color: Colors.white, size: 22),
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
                  child: const Icon(Icons.share,
                      color: Colors.white, size: 22),
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
  // LOGO + ACTIONS
  // ============================================================

  Widget _buildLogoAndActionsSection(bool isWeb) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Transform.translate(
            offset: const Offset(0, -40),
            child: _buildLogo(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildIconActionButton(
                    icon: Icons.calendar_today,
                    tooltip: 'Book Appointment',
                    color: context.primaryColor,
                    onTap: _startBookingFlow,
                  ),
                  const SizedBox(width: 8),
                  _buildIconActionButton(
                    icon: Icons.star,
                    tooltip: 'VIP Booking',
                    color: Colors.amber.shade700,
                    onTap: _navigateToVipBooking,
                  ),
                  const SizedBox(width: 8),
                  _buildWhatsAppButton(),
                  const SizedBox(width: 8),
                  _buildFollowButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconActionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

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
              style: context.headlineMedium.copyWith(color: context.textColor),
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
                      Icon(Icons.people,
                          size: 16, color: context.secondaryTextColor),
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
                  Icon(Icons.location_on,
                      size: 16, color: context.secondaryTextColor),
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
                    Icon(Icons.access_time,
                        size: 16, color: context.secondaryTextColor),
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
                      horizontal: 10, vertical: 4),
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

  Widget _buildOffersSection() {
    if (_offers.isEmpty && !_isLoadingOffers) {
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
                style: context.titleLarge.copyWith(color: context.textColor),
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
          if (!_isLoadingOffers && _offers.isNotEmpty && !_isFollowing) ...[
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Follow this salon to claim its offers',
                      style: context.bodySmall.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _isLoadingOffers
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child:
                        CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  ),
                )
              : SizedBox(
                  height: 300,
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
            style: context.titleLarge.copyWith(color: context.textColor),
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

  Widget _buildContactSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact & Location',
            style: context.titleLarge.copyWith(color: context.textColor),
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
                          color: context.primaryColor
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.phone,
                            color: context.primaryColor, size: 22),
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
                      trailing: Icon(Icons.chevron_right,
                          size: 20, color: context.secondaryTextColor),
                      onTap: _openWhatsApp,
                    ),
                  if (widget.salon['email'] != null &&
                      widget.salon['email'].toString().isNotEmpty)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.primaryColor
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.email,
                            color: context.primaryColor, size: 22),
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
                      trailing: Icon(Icons.chevron_right,
                          size: 20, color: context.secondaryTextColor),
                      onTap: () {},
                    ),
                  if (widget.salon['address'] != null &&
                      widget.salon['address'].toString().isNotEmpty)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.primaryColor
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.location_on,
                            color: context.primaryColor, size: 22),
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
                      trailing: Icon(Icons.chevron_right,
                          size: 20, color: context.secondaryTextColor),
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPER WIDGETS
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
            ? DecorationImage(
                image: NetworkImage(logoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: !hasLogo
          ? Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFF6B8B),
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
    final enabled = _isUserLoaded && _isUserActive && hasPhone;

    const whatsappGreen = Color(0xFF25D366);

    return Tooltip(
      message: 'WhatsApp',
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: enabled ? whatsappGreen : context.dividerColor,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: enabled ? _openWhatsApp : null,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              Icons.chat,
              size: 22,
              color: enabled ? whatsappGreen : context.secondaryTextColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    if (!_isUserLoaded || !_isUserActive) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              context.isDarkMode ? Colors.grey[800] : Colors.grey[200],
          foregroundColor: context.secondaryTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
        foregroundColor:
            _isFollowing ? context.secondaryTextColor : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ),
      child: Text(
        _isFollowing ? 'Following' : 'Follow',
        style: context.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: _isFollowing ? context.secondaryTextColor : Colors.white,
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
            color: context.isDarkMode
                ? Colors.white30
                : Colors.amber.withValues(alpha: 0.7),
            size: 16,
          );
        }
      }),
    );
  }

  // ============================================================
  // ✅ OFFER CARD (variant-aware + claim state)
  // ============================================================
  Widget _buildOfferCard(Map<String, dynamic> offer, int index) {
    final color = _getOfferColor(index);
    final validTo = DateTime.parse(offer['valid_to']);
    final daysLeft = validTo.difference(DateTime.now()).inDays;

    final offerId = offer['id'] as int;
    final isClaiming = _claimingOfferIds.contains(offerId);
    final claimStatus = offer['claim_status'] as String?;
    final isClaimed = claimStatus == 'active';
    final isUsed = claimStatus == 'used';
    final scopeSummary = offer['scope_summary']?.toString() ?? '';

    // Button state
    final String buttonLabel;
    final bool buttonEnabled;
    if (!_isFollowing) {
      buttonLabel = 'Follow to Claim';
      buttonEnabled = false;
    } else if (isUsed) {
      buttonLabel = 'Used';
      buttonEnabled = false;
    } else if (isClaimed) {
      buttonLabel = 'Claimed';
      buttonEnabled = false;
    } else if (isClaiming) {
      buttonLabel = 'Claiming...';
      buttonEnabled = false;
    } else {
      buttonLabel = 'Claim Offer';
      buttonEnabled = true;
    }

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
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
          onTap: buttonEnabled ? () => _claimOffer(offer) : null,
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
                                horizontal: 8, vertical: 2),
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
                    color:
                        context.isDarkMode ? Colors.white60 : Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // ✅ Scope summary (which services / variants)
                if (scopeSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.content_cut,
                          size: 11,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            scopeSummary,
                            style: context.bodySmall.copyWith(
                              color: color,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Row(
                  children: [
                    if ((offer['points_required'] ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 12),
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

                    // Claim badge overrides days-left badge
                    if (isUsed || isClaimed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isUsed ? Colors.grey : Colors.green)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isUsed ? Icons.check_circle : Icons.bookmark,
                              size: 10,
                              color: isUsed ? Colors.grey : Colors.green,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              isUsed ? 'Used' : 'Claimed',
                              style: context.bodySmall.copyWith(
                                color: isUsed ? Colors.grey : Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
                                  : (context.isDarkMode
                                      ? Colors.white60
                                      : Colors.grey[600]),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              daysLeft <= 0
                                  ? 'Expired'
                                  : '$daysLeft days left',
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
                    onPressed: buttonEnabled ? () => _claimOffer(offer) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: context.isDarkMode
                          ? Colors.grey[800]
                          : Colors.grey[300],
                      disabledForegroundColor: context.isDarkMode
                          ? Colors.white38
                          : Colors.grey[600],
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isClaiming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            buttonLabel,
                            style: const TextStyle(
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

  // ============================================================
  // SERVICE MENU — unchanged
  // ============================================================

  Widget _buildMenuTreeSection(bool isWeb) {
    final hPad = isWeb ? 20.0 : 10.0;

    final section = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: isWeb ? BorderRadius.circular(16) : null,
        border: isWeb
            ? Border.all(color: context.dividerColor)
            : Border.symmetric(
                horizontal: BorderSide(color: context.dividerColor),
              ),
        boxShadow: isWeb
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(hPad, 22, hPad, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  context.primaryColor.withValues(alpha: 0.12),
                  context.primaryColor.withValues(alpha: 0.0),
                ],
              ),
              borderRadius: isWeb
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : null,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.primaryColor.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: context.primaryColor,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Service Menu',
                  textAlign: TextAlign.center,
                  style: context.titleLarge.copyWith(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: context.primaryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tick the options you want, then choose Regular or VIP booking',
                  textAlign: TextAlign.center,
                  style: context.bodySmall.copyWith(
                    color: context.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _menuTreeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                    ),
                  );
                }

                final tree = snapshot.data ?? [];
                if (tree.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No services available yet',
                        style: context.bodyMedium
                            .copyWith(color: context.secondaryTextColor),
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      tree.map((cat) => _buildMenuCategoryBlock(cat)).toList(),
                );
              },
            ),
          ),

          Divider(color: context.dividerColor, height: 1),

          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 500;

                final regularButton = ElevatedButton.icon(
                  onPressed: _selectedBookingItems.isEmpty
                      ? null
                      : _bookSelectedServices,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _selectedBookingItems.isEmpty
                        ? 'Select to book'
                        : 'Book Selected (${_selectedBookingItems.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedBookingItems.isEmpty
                        ? (context.isDarkMode
                            ? Colors.grey[800]
                            : Colors.grey[300])
                        : context.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );

                final vipButton = ElevatedButton.icon(
                  onPressed: _selectedBookingItems.isEmpty
                      ? null
                      : _bookSelectedServicesVIP,
                  icon: const Icon(Icons.star, size: 18),
                  label: Text(
                    _selectedBookingItems.isEmpty
                        ? 'Select for VIP'
                        : 'VIP Book Selected (${_selectedBookingItems.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedBookingItems.isEmpty
                        ? (context.isDarkMode
                            ? Colors.grey[800]
                            : Colors.grey[300])
                        : Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: regularButton),
                      const SizedBox(width: 10),
                      Expanded(child: vipButton),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    regularButton,
                    const SizedBox(height: 10),
                    vipButton,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );

    if (isWeb) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: section,
      );
    }
    return section;
  }

  Widget _buildMenuCategoryBlock(Map<String, dynamic> cat) {
    final color = _hexToMenuColor(cat['color']?.toString() ?? '#FF6B8B');
    final icon = _menuIconFromName(cat['icon_name'] as String?);
    final services = cat['services'] as List;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.18),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cat['display_name']?.toString() ?? 'Category',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.textColor,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${services.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: services.asMap().entries.map((e) {
                  final isLast = e.key == services.length - 1;
                  return _buildMenuServiceBlock(
                    e.value as Map<String, dynamic>,
                    color,
                    isLast,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuServiceBlock(
    Map<String, dynamic> service,
    Color catColor,
    bool isLastService,
  ) {
    final variants = service['variants'] as List;

    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: isLastService ? 2 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 2,
                color: catColor.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service['name']?.toString() ?? 'Service',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textColor,
                  ),
                ),
              ),
            ],
          ),
          if (variants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 4),
              child: Text(
                'No pricing options yet',
                style: context.bodySmall.copyWith(
                  color: context.secondaryTextColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: catColor.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Column(
                  children: variants
                      .map(
                        (v) => _buildMenuVariantRow(
                          service,
                          v as Map<String, dynamic>,
                          catColor,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuVariantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
    Color catColor,
  ) {
    final sid = service['id'] as int;
    final vid = variant['id'] as int;
    final key = '${sid}_$vid';
    final isSelected = _selectedBookingItems.containsKey(key);
    final price = variant['price'] as double?;
    final duration = variant['duration'] as int?;
    final gender = variant['gender']?.toString() ?? '';
    final age = variant['age']?.toString() ?? '';
    final ageRange = variant['age_range']?.toString() ?? '';

    final ageText = age.isEmpty
        ? ''
        : (ageRange.isEmpty ? age : '$age ($ageRange)');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 1.5,
            color: catColor.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggleMenuSelection(service, variant),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.primaryColor.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? context.primaryColor.withValues(alpha: 0.5)
                          : context.dividerColor.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (_) =>
                              _toggleMenuSelection(service, variant),
                          activeColor: context.primaryColor,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (gender.isNotEmpty)
                                  _buildInfoChip(
                                    Icons.person_outline,
                                    gender,
                                    Colors.blue.shade400,
                                  ),
                                if (ageText.isNotEmpty)
                                  _buildInfoChip(
                                    Icons.cake_outlined,
                                    ageText,
                                    Colors.purple.shade400,
                                  ),
                                if (gender.isEmpty && ageText.isEmpty)
                                  _buildInfoChip(
                                    Icons.check_circle_outline,
                                    'Standard',
                                    Colors.grey.shade600,
                                  ),
                              ],
                            ),
                            if (duration != null && duration > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 12,
                                    color: context.secondaryTextColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$duration min',
                                    style: context.bodySmall.copyWith(
                                      color: context.secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        price != null
                            ? 'Rs. ${price.toStringAsFixed(0)}'
                            : '—',
                        style: context.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: price != null
                              ? context.primaryColor
                              : context.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _ageRangeText(int? minAge, int? maxAge) {
    if (minAge == null || maxAge == null) return '';
    if (maxAge >= 100) return '$minAge+ yrs';
    return '$minAge–$maxAge yrs';
  }

  void _toggleMenuSelection(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) {
    final sid = service['id'] as int;
    final vid = variant['id'] as int;
    final key = '${sid}_$vid';
    setState(() {
      if (_selectedBookingItems.containsKey(key)) {
        _selectedBookingItems.remove(key);
      } else {
        _selectedBookingItems[key] = {'service_id': sid, 'variant_id': vid};
      }
    });
  }

  // ============================================================
  // REGULAR BOOKING
  // ============================================================
  void _bookSelectedServices() async {
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

      if (_selectedBookingItems.isEmpty) return;
      if (!mounted) return;

      final salonWithExtras = Map<String, dynamic>.from(widget.salon);
      salonWithExtras['preselected_services'] =
          _selectedBookingItems.values.toList();
      salonWithExtras['skip_to_date'] = true;

      context.push('/customer/booking-flow', extra: salonWithExtras);
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
      _showSnackBar('Error starting booking. Please try again.', Colors.red);
    }
  }

  void _bookSelectedServicesVIP() async {
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

      if (_selectedBookingItems.isEmpty) return;
      if (!mounted) return;

      final salonWithExtras = Map<String, dynamic>.from(widget.salon);
      salonWithExtras['preselected_services'] =
          _selectedBookingItems.values.toList();
      salonWithExtras['skip_to_date'] = true;

      context.push('/customer/vip-booking', extra: salonWithExtras);
    } catch (e) {
      debugPrint('❌ VIP navigation error: $e');
      _showSnackBar(
        'Error starting VIP booking. Please try again.',
        Colors.red,
      );
    }
  }

  Color _hexToMenuColor(String hex) {
    if (hex.startsWith('#')) {
      try {
        return Color(int.parse('0xFF${hex.substring(1)}'));
      } catch (_) {}
    }
    return const Color(0xFFFF6B8B);
  }

  IconData _menuIconFromName(String? name) {
    final found = _menuIconSuggestions.firstWhere(
      (i) => i['name'] == name,
      orElse: () => _menuIconSuggestions.first,
    );
    return found['icon'] as IconData;
  }

  Future<List<Map<String, dynamic>>> _loadCategoryTree() async {
    try {
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color, display_order')
          .eq('salon_id', widget.salon['id'])
          .eq('is_active', true)
          .order('display_order');

      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id')
          .eq('salon_id', widget.salon['id'])
          .eq('is_active', true)
          .order('name');

      if (servicesResponse.isEmpty) return [];

      final serviceIds =
          servicesResponse.map<int>((s) => s['id'] as int).toList();

      final variantsResponse = await supabase
          .from('service_variants')
          .select(
              'id, service_id, price, duration, salon_gender_id, salon_age_category_id')
          .inFilter('service_id', serviceIds)
          .eq('is_active', true);

      final genderIds = variantsResponse
          .map<int?>((v) => v['salon_gender_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final ageIds = variantsResponse
          .map<int?>((v) => v['salon_age_category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      final Map<int, String> genderMap = {};
      if (genderIds.isNotEmpty) {
        try {
          final genders = await supabase
              .from('salon_genders')
              .select('id, display_name')
              .inFilter('id', genderIds);
          for (var g in genders) {
            genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('Error loading genders: $e');
        }
      }

      final Map<int, String> ageMap = {};
      final Map<int, String> ageRangeMap = {};
      if (ageIds.isNotEmpty) {
        try {
          final ages = await supabase
              .from('salon_age_categories')
              .select('id, display_name, min_age, max_age')
              .inFilter('id', ageIds);
          for (var a in ages) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
            ageRangeMap[a['id'] as int] = _ageRangeText(
              (a['min_age'] as num?)?.toInt(),
              (a['max_age'] as num?)?.toInt(),
            );
          }
        } catch (e) {
          debugPrint('Error loading age categories: $e');
        }
      }

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var v in variantsResponse) {
        final sid = v['service_id'] as int;
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        variantsByService.putIfAbsent(sid, () => []).add({
          'id': v['id'],
          'price': (v['price'] as num?)?.toDouble(),
          'duration': (v['duration'] as num?)?.toInt(),
          'gender': genderId != null ? (genderMap[genderId] ?? '') : '',
          'age': ageId != null ? (ageMap[ageId] ?? '') : '',
          'age_range': ageId != null ? (ageRangeMap[ageId] ?? '') : '',
        });
      }

      final Map<int, List<Map<String, dynamic>>> servicesByCategory = {};
      final List<Map<String, dynamic>> uncategorized = [];
      for (var s in servicesResponse) {
        final sid = s['id'] as int;
        final catId = s['category_id'] as int?;
        final entry = {
          'id': sid,
          'name': s['name'] ?? 'Service',
          'description': s['description'] ?? '',
          'icon_name': s['icon_name'],
          'variants': variantsByService[sid] ?? <Map<String, dynamic>>[],
        };
        if (catId != null) {
          servicesByCategory.putIfAbsent(catId, () => []).add(entry);
        } else {
          uncategorized.add(entry);
        }
      }

      final List<Map<String, dynamic>> tree = [];
      for (var c in categoriesResponse) {
        final cid = c['id'] as int;
        final services = servicesByCategory[cid] ?? [];
        if (services.isEmpty) continue;
        tree.add({
          'id': cid,
          'display_name': c['display_name'] ?? 'Category',
          'icon_name': c['icon_name'],
          'color': c['color'],
          'services': services,
        });
      }
      if (uncategorized.isNotEmpty) {
        tree.add({
          'id': null,
          'display_name': 'Other',
          'icon_name': null,
          'color': '#9E9E9E',
          'services': uncategorized,
        });
      }
      return tree;
    } catch (e) {
      debugPrint('Error loading category tree: $e');
      return [];
    }
  }
}