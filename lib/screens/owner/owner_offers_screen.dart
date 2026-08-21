import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/timezone_service.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class OwnerOffersScreen extends StatefulWidget {
  final String? salonId;

  const OwnerOffersScreen({super.key, this.salonId});

  @override
  State<OwnerOffersScreen> createState() => _OwnerOffersScreenState();
}

class _OwnerOffersScreenState extends State<OwnerOffersScreen> {
  final supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int? _currentSalonId;
  String? _currentSalonName;

  // Filter
  String _selectedFilter = 'active';

  // Notification option for new offer
  bool _sendNotificationToFollowers = true;

  // Scroll controller for responsive behavior
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingButton = true;

  // ============================================
  // TIMEZONE VARIABLES
  // ============================================
  String _userTimezone = '';
  bool _isTimezoneLoaded = false;

  // ============================================
  // RESPONSIVE VARIABLES
  // ============================================
  late bool _isDark;

  @override
  void initState() {
    super.initState();
    _initializeTimezone();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadSalonAndOffers();
  }

  // ============================================
  // TIMEZONE HELPER METHODS
  // ============================================

  DateTime _utcToLocalDate(String utcDateStr) {
    try {
      final utcDateTime = DateTime.parse(utcDateStr);
      final localDateTime = TimezoneService.utcToLocalDateTimeForDate(
        '12:00:00',
        utcDateTime,
      );
      return DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      return DateTime.parse(utcDateStr);
    }
  }

  String _formatLocalDate(String utcDateStr) {
    try {
      final localDate = _utcToLocalDate(utcDateStr);
      return DateFormat('MMM dd, yyyy').format(localDate);
    } catch (e) {
      debugPrint('Error formatting date: $e');
      return utcDateStr;
    }
  }

  bool _isOfferActive(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final nowLocal = DateTime(now.year, now.month, now.day);

    final validToLocal = _utcToLocalDate(offer['valid_to']);

    return offer['is_active'] == true && validToLocal.isAfter(nowLocal);
  }

  bool _isOfferExpired(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final nowLocal = DateTime(now.year, now.month, now.day);

    final validToLocal = _utcToLocalDate(offer['valid_to']);
    final validFromLocal = _utcToLocalDate(offer['valid_from']);

    return validToLocal.isBefore(nowLocal) || validFromLocal.isAfter(nowLocal);
  }

  int _getDaysLeft(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final nowLocal = DateTime(now.year, now.month, now.day);
    final validToLocal = _utcToLocalDate(offer['valid_to']);
    return validToLocal.difference(nowLocal).inDays;
  }

  void _onScroll() {
    if (_scrollController.position.pixels > 200 && _showFloatingButton) {
      setState(() => _showFloatingButton = false);
    } else if (_scrollController.position.pixels <= 200 &&
        !_showFloatingButton) {
      setState(() => _showFloatingButton = true);
    }
  }

  Future<void> _loadSalonAndOffers() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }

      final ownerCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 1)
          .maybeSingle();

      if (ownerCheck == null || ownerCheck['status'] != 'active') {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage =
              'Your account is not active as an owner. Please contact support.';
          _isLoading = false;
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
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMessage =
                'Your account has been blocked. Please contact support.';
            _isLoading = false;
          });
          return;
        }
        if (profileCheck['is_active'] == false) {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMessage = 'Your profile is inactive. Please contact support.';
            _isLoading = false;
          });
          return;
        }
      }

      if (widget.salonId != null && widget.salonId!.isNotEmpty) {
        final salonResult = await supabase
            .from('salons')
            .select('id, name')
            .eq('id', int.parse(widget.salonId!))
            .eq('owner_id', user.id)
            .maybeSingle();

        if (salonResult != null) {
          setState(() {
            _currentSalonId = salonResult['id'] as int;
            _currentSalonName = salonResult['name'];
          });
          await _loadOffers();
          return;
        }
      }

      final salonResult = await supabase
          .from('salons')
          .select('id, name')
          .eq('owner_id', user.id)
          .maybeSingle();

      if (salonResult == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage =
              'You don\'t own any salon. Please create a salon first.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _currentSalonId = salonResult['id'] as int;
        _currentSalonName = salonResult['name'];
      });

      await _loadOffers();
    } catch (e) {
      debugPrint('Error loading salon: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage =
            'Failed to load salon data. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOffers() async {
    final salonId = _currentSalonId;
    if (salonId == null) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final result = await supabase
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
            valid_from_time,
            valid_to_time,
            image_url,
            is_active,
            usage_limit,
            used_count,
            created_at
          ''')
          .eq('salon_id', salonId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _offers = List<Map<String, dynamic>>.from(result);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading offers: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load offers. Please try again.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredOffers {
    switch (_selectedFilter) {
      case 'active':
        return _offers.where((offer) => _isOfferActive(offer)).toList();
      case 'expired':
        return _offers.where((offer) => !_isOfferActive(offer)).toList();
      default:
        return _offers;
    }
  }

  int get _activeCount => _offers.where((o) => _isOfferActive(o)).length;

  Future<void> _createOffer() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => OfferFormDialog(
        isEditing: false,
        sendNotificationToFollowers: _sendNotificationToFollowers,
        onNotificationToggle: (value) {
          _sendNotificationToFollowers = value;
        },
      ),
    );

    if (result != null && mounted) {
      await _saveOffer(result);
    }
  }

  Future<void> _editOffer(Map<String, dynamic> offer) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => OfferFormDialog(
        isEditing: true,
        offer: offer,
        sendNotificationToFollowers: false,
        onNotificationToggle: (value) {},
      ),
    );

    if (result != null && mounted) {
      await _updateOffer(offer['id'], result);
    }
  }

  Future<void> _saveOffer(Map<String, dynamic> offerData) async {
    final salonId = _currentSalonId;
    if (salonId == null) return;

    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> insertData = {
        'salon_id': salonId,
        'title': offerData['title'],
        'description': offerData['description'],
        'discount_type': offerData['discount_type'],
        'discount_value': offerData['discount_value'],
        'points_required': offerData['points_required'] ?? 0,
        'valid_from': offerData['valid_from'],
        'valid_to': offerData['valid_to'],
        'image_url': offerData['image_url'],
        'is_active': true,
        'usage_limit': offerData['usage_limit'],
        'used_count': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (offerData['valid_from_time'] != null &&
          offerData['valid_to_time'] != null) {
        insertData['valid_from_time'] = offerData['valid_from_time'];
        insertData['valid_to_time'] = offerData['valid_to_time'];
      }

      final result = await supabase.from('offers').insert(insertData).select();

      if (offerData['send_notification'] == true && result.isNotEmpty) {
        await _sendOfferNotificationsToFollowers(result.first);
      }

      await _loadOffers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✨ Offer created successfully!',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error creating offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Failed to create offer: ${e.toString().substring(0, 100)}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendOfferNotificationsToFollowers(
    Map<String, dynamic> offer,
  ) async {
    final salonId = _currentSalonId;
    if (salonId == null) return;

    setState(() => _isLoading = true);

    try {
      final followers = await supabase.rpc(
        'get_active_customer_followers',
        params: {'p_salon_id': salonId},
      );

      if (followers == null || followers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ No active followers to notify',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      debugPrint('📊 Found ${followers.length} active followers');

      String discountText = '';
      if (offer['discount_type'] == 'percentage') {
        discountText = '${offer['discount_value']}% OFF';
      } else if (offer['discount_type'] == 'fixed') {
        discountText = '₹${offer['discount_value']} OFF';
      } else {
        discountText = 'FREE SERVICE';
      }

      int sentCount = 0;
      int failedCount = 0;

      for (var follower in followers) {
        try {
          final customerId = follower['customer_id'] as String;
          final customerName = follower['full_name'] ?? 'Customer';

          await _notificationService.sendSpecialOffer(
            customerId: customerId,
            offerTitle: offer['title'] ?? 'Special Offer',
            offerDescription: offer['description'] ?? '',
            discountText: discountText,
            offerId: offer['id'] ?? 0,
            salonName: _currentSalonName ?? 'Salon',
          );

          sentCount++;
          debugPrint('✅ Notification sent to $customerName ($customerId)');
        } catch (e) {
          debugPrint('❌ Failed to send to ${follower['customer_id']}: $e');
          failedCount++;
        }
      }

      debugPrint('📊 Notifications sent: $sentCount, Failed: $failedCount');

      if (mounted) {
        String message;
        if (sentCount > 0 && failedCount == 0) {
          message =
              '📢 Notifications sent to $sentCount followers successfully!';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message, style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (sentCount > 0 && failedCount > 0) {
          message = '📢 $sentCount sent, $failedCount failed';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message, style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          message = '⚠️ No notifications sent. $failedCount followers failed.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message, style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Failed: ${e.toString().substring(0, 100)}',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateOffer(int offerId, Map<String, dynamic> offerData) async {
    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> updateData = {
        'title': offerData['title'],
        'description': offerData['description'],
        'discount_type': offerData['discount_type'],
        'discount_value': offerData['discount_value'],
        'points_required': offerData['points_required'] ?? 0,
        'valid_from': offerData['valid_from'],
        'valid_to': offerData['valid_to'],
        'image_url': offerData['image_url'],
        'usage_limit': offerData['usage_limit'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (offerData['valid_from_time'] != null &&
          offerData['valid_to_time'] != null) {
        updateData['valid_from_time'] = offerData['valid_from_time'];
        updateData['valid_to_time'] = offerData['valid_to_time'];
      } else {
        updateData['valid_from_time'] = null;
        updateData['valid_to_time'] = null;
      }

      await supabase.from('offers').update(updateData).eq('id', offerId);

      await _loadOffers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✏️ Offer updated successfully',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error updating offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Failed to update offer: ${e.toString().substring(0, 100)}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleOfferStatus(int offerId, bool isActive) async {
    setState(() => _isLoading = true);

    try {
      await supabase
          .from('offers')
          .update({
            'is_active': !isActive,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', offerId);

      await _loadOffers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !isActive ? '✅ Offer activated' : '⏸️ Offer deactivated',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: !isActive ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error toggling offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Failed to update offer status',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteOffer(int offerId) async {
    final isDark = _isDark;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Offer',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this offer?\n\nThis action cannot be undone and will remove this offer from all customers.',
          style: TextStyle(
            height: 1.4,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white60 : Colors.grey,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await supabase.from('offers').delete().eq('id', offerId);
      await _loadOffers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🗑️ Offer deleted successfully',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error deleting offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Failed to delete offer: ${e.toString().substring(0, 100)}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getDiscountText(Map<String, dynamic> offer) {
    switch (offer['discount_type']) {
      case 'percentage':
        return '${offer['discount_value']}% OFF';
      case 'fixed':
        return '₹${offer['discount_value']} OFF';
      default:
        return 'FREE SERVICE';
    }
  }

  Color _getStatusColor(Map<String, dynamic> offer) {
    if (!offer['is_active']) return Colors.grey;
    if (_isOfferExpired(offer)) return Colors.red;
    return Colors.green;
  }

  String _getStatusText(Map<String, dynamic> offer) {
    if (!offer['is_active']) return 'Inactive';
    if (_isOfferExpired(offer)) return 'Expired';

    final daysLeft = _getDaysLeft(offer);
    return daysLeft == 0 ? 'Ends today' : '$daysLeft days left';
  }

  String _getTimeRangeText(String? fromTime, String? toTime) {
    if (fromTime == null || toTime == null) return '';
    try {
      final from = TimeOfDay.fromDateTime(
        DateTime.parse('2000-01-01 $fromTime'),
      );
      final to = TimeOfDay.fromDateTime(DateTime.parse('2000-01-01 $toTime'));
      final fromFormatted = _formatTimeOfDay(from);
      final toFormatted = _formatTimeOfDay(to);
      return '🕐 $fromFormatted - $toFormatted';
    } catch (e) {
      return '';
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _getUsageLimitText(int? usageLimit, int usedCount) {
    if (usageLimit == null) return '♾️ Unlimited';
    final remaining = usageLimit - usedCount;
    if (remaining <= 0) return '🔴 Fully Redeemed';
    if (remaining <= 3) return '⚠️ Only $remaining left!';
    return '✅ $remaining uses left';
  }

  Color _getUsageLimitColor(int? usageLimit, int usedCount) {
    if (usageLimit == null) return Colors.grey.shade600;
    final remaining = usageLimit - usedCount;
    if (remaining <= 0) return Colors.red;
    if (remaining <= 3) return Colors.orange;
    return Colors.green;
  }

  // ============================================
  // BUILD METHOD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: const Text('Manage Offers'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage Offers',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_currentSalonName != null)
              Text(
                _currentSalonName!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_alt_outlined, color: Colors.white),
            onPressed: () => _showFilterMenu(),
            tooltip: 'Filter',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOffers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading && _offers.isEmpty
            ? _buildLoadingState()
            : _hasError
            ? _buildErrorState()
            : isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
      floatingActionButton:
          _showFloatingButton && !_isLoading && !_hasError && _offers.isNotEmpty
          ? FloatingActionButton(
              onPressed: _createOffer,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  // ============================================
  // WEB LAYOUT
  // ============================================

  Widget _buildWebLayout() {
    final isDark = _isDark;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Sidebar
            Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSalonInfoCard(isDark),
                  const SizedBox(height: 16),
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  // ✅ Quick Actions Card - Fixed
                  _buildQuickActionsCard(),
                ],
              ),
            ),
            // Right Content
            Expanded(
              child: Column(
                children: [
                  _buildFilterChips(true),
                  Expanded(
                    child: _filteredOffers.isEmpty
                        ? _buildEmptyState(false)
                        : Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            thickness: 8.0,
                            radius: const Radius.circular(10),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: _filteredOffers.length,
                              itemBuilder: (context, index) {
                                final offer = _filteredOffers[index];
                                return _buildOfferCard(offer, false);
                              },
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

  // ============================================
  // MOBILE LAYOUT
  // ============================================

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildSalonInfoCard(_isDark),
        _buildFilterChips(false),
        Expanded(
          child: _filteredOffers.isEmpty
              ? _buildEmptyState(true)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _filteredOffers.length,
                  itemBuilder: (context, index) {
                    final offer = _filteredOffers[index];
                    return _buildOfferCard(offer, true);
                  },
                ),
        ),
      ],
    );
  }

  // ============================================
  // STATS CARD (Web Only)
  // ============================================

  Widget _buildStatsCard() {
    final isDark = _isDark;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 Statistics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatItem(
              'Total Offers',
              _offers.length.toString(),
              Colors.blue,
            ),
            _buildStatItem('Active', _activeCount.toString(), Colors.green),
            _buildStatItem(
              'Expired',
              (_offers.length - _activeCount).toString(),
              Colors.red,
            ),
            _buildStatItem(
              'Total Redemptions',
              _offers
                  .fold<int>(
                    0,
                    (sum, o) => sum + (o['used_count'] as int? ?? 0),
                  )
                  .toString(),
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    final isDark = _isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // QUICK ACTIONS CARD (Web Only)
  // ============================================

  Widget _buildQuickActionsCard() {
    final isDark = _isDark;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚡ Quick Actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // ✅ Button 1: Create Offer
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createOffer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create New Offer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ✅ Button 2: Refresh
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadOffers,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.grey,
                  side: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ✅ Button 3: View All Offers
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedFilter = 'all';
                  });
                },
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('View All Offers'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.blue,
                  side: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.blue.shade200,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // LOADING STATE
  // ============================================

  Widget _buildLoadingState() {
    final isDark = _isDark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 16),
          Text(
            'Loading your offers...',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
          ),
        ],
      ),
    );
  }

  // ============================================
  // ERROR STATE
  // ============================================

  Widget _buildErrorState() {
    final isDark = _isDark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSalonAndOffers,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // SALON INFO CARD
  // ============================================

  Widget _buildSalonInfoCard(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_offer,
              color: AppTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentSalonName ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '📊 ${_offers.length} Total  •  🟢 $_activeCount Active',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  'Your Salon',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // FILTER CHIPS
  // ============================================

  Widget _buildFilterChips(bool isWeb) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isWeb
          ? Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildFilterChip('All Offers', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Active Offers', 'active'),
                const SizedBox(width: 8),
                _buildFilterChip('Expired/Inactive', 'expired'),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Active', 'active'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Expired', 'expired'),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isDark = _isDark;
    final isSelected = _selectedFilter == value;

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? Colors.white70 : Colors.grey[600]),
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.1),
      checkmarkColor: AppTheme.primary,
      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
      ),
    );
  }

  // ============================================
  // EMPTY STATE
  // ============================================

  Widget _buildEmptyState(bool isSmallScreen) {
    final isDark = _isDark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _selectedFilter == 'active'
                    ? Icons.local_offer_outlined
                    : _selectedFilter == 'expired'
                    ? Icons.timer_off_outlined
                    : Icons.add_circle_outline,
                size: isSmallScreen ? 60 : 80,
                color: AppTheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getEmptyStateMessage(),
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _getEmptyStateSubMessage(),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_offers.isEmpty)
              ElevatedButton.icon(
                onPressed: _createOffer,
                icon: const Icon(Icons.add),
                label: const Text('Create Your First Offer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getEmptyStateMessage() {
    switch (_selectedFilter) {
      case 'active':
        return 'No Active Offers';
      case 'expired':
        return 'No Expired Offers';
      default:
        return _offers.isEmpty ? 'No Offers Yet' : 'No Offers Found';
    }
  }

  String _getEmptyStateSubMessage() {
    switch (_selectedFilter) {
      case 'active':
        return 'Create a new offer to attract customers';
      case 'expired':
        return 'Your offers will appear here after they expire';
      default:
        return _offers.isEmpty
            ? 'Tap the + button to create your first offer'
            : 'Try changing the filter to see more offers';
    }
  }

  // ============================================
  // OFFER CARD
  // ============================================

  Widget _buildOfferCard(Map<String, dynamic> offer, bool isSmallScreen) {
    final isDark = _isDark;
    final statusColor = _getStatusColor(offer);
    final statusText = _getStatusText(offer);
    final discountText = _getDiscountText(offer);

    final validFrom = _formatLocalDate(offer['valid_from']);
    final validTo = _formatLocalDate(offer['valid_to']);

    final usageLimit = offer['usage_limit'];
    final usedCount = offer['used_count'] ?? 0;

    final timeRangeText = _getTimeRangeText(
      offer['valid_from_time'],
      offer['valid_to_time'],
    );
    final hasTimeRestriction = timeRangeText.isNotEmpty;

    final usageLimitText = _getUsageLimitText(usageLimit, usedCount);
    final usageLimitColor = _getUsageLimitColor(usageLimit, usedCount);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _editOffer(offer),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        discountText,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                offer['title'],
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Description
              if (offer['description'] != null &&
                  offer['description'].isNotEmpty)
                Text(
                  offer['description'],
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              if (offer['description'] != null &&
                  offer['description'].isNotEmpty)
                const SizedBox(height: 12),

              // Details chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((offer['points_required'] ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${offer['points_required']} pts',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: isDark ? Colors.white70 : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSmallScreen ? validFrom : '$validFrom - $validTo',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (hasTimeRestriction)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: isDark ? Colors.purple[300] : Colors.purple,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeRangeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.purple[300]
                                  : Colors.purple[700],
                            ),
                          ),
                        ],
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: usageLimitColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          usageLimitText.contains('♾️')
                              ? Icons.unpublished
                              : usageLimitText.contains('🔴')
                              ? Icons.cancel
                              : usageLimitText.contains('⚠️')
                              ? Icons.warning_amber
                              : Icons.people,
                          size: 12,
                          color: usageLimitColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          usageLimitText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: usageLimitColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Progress indicator
              if (usageLimit != null && usageLimit > 0) ...[
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Redemption Progress',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.grey[500],
                          ),
                        ),
                        Text(
                          '$usedCount / $usageLimit',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: usageLimitColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: usedCount / usageLimit,
                        backgroundColor: isDark
                            ? Colors.grey[800]
                            : Colors.grey[200],
                        color: usageLimitColor,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isSmallScreen) ...[
                    _buildActionButton(
                      onPressed: () =>
                          _toggleOfferStatus(offer['id'], offer['is_active']),
                      icon: offer['is_active'] ? Icons.pause : Icons.play_arrow,
                      label: offer['is_active'] ? 'Deactivate' : 'Activate',
                      color: offer['is_active'] ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      onPressed: () => _editOffer(offer),
                      icon: Icons.edit,
                      label: 'Edit',
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      onPressed: () => _deleteOffer(offer['id']),
                      icon: Icons.delete,
                      label: 'Delete',
                      color: Colors.red,
                    ),
                  ] else ...[
                    IconButton(
                      onPressed: () =>
                          _toggleOfferStatus(offer['id'], offer['is_active']),
                      icon: Icon(
                        offer['is_active'] ? Icons.pause : Icons.play_arrow,
                        size: 20,
                      ),
                      color: offer['is_active'] ? Colors.orange : Colors.green,
                      tooltip: offer['is_active'] ? 'Deactivate' : 'Activate',
                    ),
                    IconButton(
                      onPressed: () => _editOffer(offer),
                      icon: Icon(Icons.edit, size: 20, color: Colors.blue),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      onPressed: () => _deleteOffer(offer['id']),
                      icon: Icon(Icons.delete, size: 20, color: Colors.red),
                      tooltip: 'Delete',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isDark = _isDark;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: isDark ? Colors.white : color),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: isDark ? color.withValues(alpha: 0.5) : color),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ============================================
  // FILTER MENU
  // ============================================

  void _showFilterMenu() {
    final isDark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Filter Offers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            _buildFilterOption('All Offers', 'all', Icons.list_alt),
            _buildFilterOption('Active Offers', 'active', Icons.check_circle),
            _buildFilterOption('Expired/Inactive', 'expired', Icons.timer_off),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(String title, String value, IconData icon) {
    final isDark = _isDark;
    final isSelected = _selectedFilter == value;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? AppTheme.primary
              : (isDark ? Colors.white60 : null),
        ),
        title: Text(
          title,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        trailing: isSelected
            ? Icon(Icons.check, color: AppTheme.primary)
            : null,
        onTap: () {
          setState(() => _selectedFilter = value);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ============================================================
// Offer Form Dialog with Time Range
// ============================================================

class OfferFormDialog extends StatefulWidget {
  final bool isEditing;
  final Map<String, dynamic>? offer;
  final bool sendNotificationToFollowers;
  final Function(bool) onNotificationToggle;

  const OfferFormDialog({
    super.key,
    required this.isEditing,
    this.offer,
    required this.sendNotificationToFollowers,
    required this.onNotificationToggle,
  });

  @override
  State<OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<OfferFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _discountValueController;
  late TextEditingController _pointsRequiredController;
  late TextEditingController _usageLimitController;

  String _discountType = 'percentage';
  DateTime _validFrom = DateTime.now();
  DateTime _validTo = DateTime.now().add(const Duration(days: 30));
  bool _sendNotification = true;

  // Time range variables
  bool _hasTimeRestriction = false;
  TimeOfDay? _validFromTime;
  TimeOfDay? _validToTime;

  late bool _isDark;

  @override
  void initState() {
    super.initState();
    _sendNotification = widget.sendNotificationToFollowers;

    if (widget.isEditing && widget.offer != null) {
      _titleController = TextEditingController(text: widget.offer!['title']);
      _descriptionController = TextEditingController(
        text: widget.offer!['description'] ?? '',
      );
      _discountValueController = TextEditingController(
        text: widget.offer!['discount_value']?.toString() ?? '',
      );
      _pointsRequiredController = TextEditingController(
        text: widget.offer!['points_required']?.toString() ?? '0',
      );
      _usageLimitController = TextEditingController(
        text: widget.offer!['usage_limit']?.toString() ?? '',
      );
      _discountType = widget.offer!['discount_type'] ?? 'percentage';
      _validFrom = DateTime.parse(widget.offer!['valid_from']);
      _validTo = DateTime.parse(widget.offer!['valid_to']);

      if (widget.offer!.containsKey('valid_from_time') &&
          widget.offer!['valid_from_time'] != null) {
        final fromTimeStr = widget.offer!['valid_from_time'].toString();
        final toTimeStr = widget.offer!['valid_to_time'].toString();
        if (fromTimeStr.isNotEmpty && toTimeStr.isNotEmpty) {
          _hasTimeRestriction = true;
          _validFromTime = _parseTimeString(fromTimeStr);
          _validToTime = _parseTimeString(toTimeStr);
        }
      }
    } else {
      _titleController = TextEditingController();
      _descriptionController = TextEditingController();
      _discountValueController = TextEditingController();
      _pointsRequiredController = TextEditingController(text: '0');
      _usageLimitController = TextEditingController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = context.isDarkMode;
  }

  TimeOfDay _parseTimeString(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _discountValueController.dispose();
    _pointsRequiredController.dispose();
    _usageLimitController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final isDark = _isDark;

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _validFrom, end: _validTo),
      helpText: 'Select Offer Validity Period',
      confirmText: 'Apply',
      cancelText: 'Cancel',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(primary: AppTheme.primary)
                : ColorScheme.light(primary: AppTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _validFrom = picked.start;
        _validTo = picked.end;
      });
    }
  }

  Future<void> _selectFromTime() async {
    final isDark = _isDark;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _validFromTime ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Select Start Time',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(primary: AppTheme.primary)
                : ColorScheme.light(primary: AppTheme.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _validFromTime = picked;
        _validToTime ??= TimeOfDay(
          hour: picked.hour + 1,
          minute: picked.minute,
        );
      });
    }
  }

  Future<void> _selectToTime() async {
    final isDark = _isDark;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _validToTime ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'Select End Time',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(primary: AppTheme.primary)
                : ColorScheme.light(primary: AppTheme.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _validToTime = picked;
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_validTo.isBefore(_validFrom)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'End date must be after start date',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_hasTimeRestriction) {
        if (_validFromTime == null || _validToTime == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please select both start and end times',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      Navigator.pop(context, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'discount_type': _discountType,
        'discount_value': _discountType != 'free_service'
            ? double.parse(_discountValueController.text)
            : 0,
        'points_required': int.parse(_pointsRequiredController.text),
        'valid_from': _validFrom.toIso8601String().split('T')[0],
        'valid_to': _validTo.toIso8601String().split('T')[0],
        'valid_from_time': _hasTimeRestriction && _validFromTime != null
            ? '${_validFromTime!.hour.toString().padLeft(2, '0')}:${_validFromTime!.minute.toString().padLeft(2, '0')}:00'
            : null,
        'valid_to_time': _hasTimeRestriction && _validToTime != null
            ? '${_validToTime!.hour.toString().padLeft(2, '0')}:${_validToTime!.minute.toString().padLeft(2, '0')}:00'
            : null,
        'image_url': null,
        'usage_limit': _usageLimitController.text.isNotEmpty
            ? int.parse(_usageLimitController.text)
            : null,
        'send_notification': _sendNotification,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = context.isMobile;
    final isDark = context.isDarkMode;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isSmallScreen ? double.infinity : 600,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.isEditing ? Icons.edit : Icons.add,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.isEditing ? 'Edit Offer' : 'Create New Offer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white60 : Colors.grey,
                  ),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Form
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        'Offer Title *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., Summer Special Sale',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
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
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter offer title';
                          }
                          if (value.length < 3) {
                            return 'Title must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Description
                      Text(
                        'Description (Optional)',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Describe your offer details...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
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
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Discount Type
                      Text(
                        'Discount Type *',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'Percentage %',
                                style: TextStyle(
                                  color: _discountType == 'percentage'
                                      ? AppTheme.primary
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                ),
                              ),
                              selected: _discountType == 'percentage',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _discountType = 'percentage');
                                }
                              },
                              selectedColor: AppTheme.primary.withValues(
                                alpha: 0.2,
                              ),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[100],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'Fixed ₹',
                                style: TextStyle(
                                  color: _discountType == 'fixed'
                                      ? AppTheme.primary
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                ),
                              ),
                              selected: _discountType == 'fixed',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _discountType = 'fixed');
                                }
                              },
                              selectedColor: AppTheme.primary.withValues(
                                alpha: 0.2,
                              ),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[100],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'Free Service',
                                style: TextStyle(
                                  color: _discountType == 'free_service'
                                      ? AppTheme.primary
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                ),
                              ),
                              selected: _discountType == 'free_service',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(
                                    () => _discountType = 'free_service',
                                  );
                                }
                              },
                              selectedColor: AppTheme.primary.withValues(
                                alpha: 0.2,
                              ),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[100],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Discount Value
                      if (_discountType != 'free_service') ...[
                        Text(
                          'Discount Value *',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _discountValueController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: _discountType == 'percentage'
                                ? 'e.g., 20'
                                : 'e.g., 500',
                            prefixText: _discountType == 'percentage'
                                ? '% '
                                : '₹ ',
                            prefixStyle: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey,
                            ),
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
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
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter discount value';
                            }
                            final number = double.tryParse(value);
                            if (number == null) {
                              return 'Please enter a valid number';
                            }
                            if (number <= 0) {
                              return 'Discount must be greater than 0';
                            }
                            if (_discountType == 'percentage' && number > 100) {
                              return 'Percentage cannot exceed 100%';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Points Required
                      Text(
                        'Points Required',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _pointsRequiredController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: '0 (Available for all customers)',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
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
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          final points = int.tryParse(value);
                          if (points == null) {
                            return 'Please enter a valid number';
                          }
                          if (points < 0) {
                            return 'Points cannot be negative';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Usage Limit
                      Text(
                        'Usage Limit (Optional)',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usageLimitController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., 10 (First 10 customers only)',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          helperText: 'Leave empty for unlimited uses',
                          helperStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
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
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          final limit = int.tryParse(value);
                          if (limit == null) {
                            return 'Please enter a valid number';
                          }
                          if (limit <= 0) {
                            return 'Usage limit must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Valid Period
                      Text(
                        'Valid Period *',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${DateFormat('MMM dd, yyyy').format(_validFrom)} → ${DateFormat('MMM dd, yyyy').format(_validTo)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: isDark ? Colors.white70 : Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Time Range Section
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.purple.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: Text(
                                'Restrict to specific time range',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              subtitle: Text(
                                'Offer valid only during selected hours',
                                style: TextStyle(
                                  color: isDark ? Colors.white60 : Colors.grey,
                                ),
                              ),
                              value: _hasTimeRestriction,
                              onChanged: (value) {
                                setState(() {
                                  _hasTimeRestriction = value;
                                  if (!value) {
                                    _validFromTime = null;
                                    _validToTime = null;
                                  }
                                });
                              },
                              activeThumbColor: AppTheme.primary,
                            ),
                            if (_hasTimeRestriction) ...[
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: _selectFromTime,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF2A2A2A)
                                                : Colors.grey[50],
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.grey[700]!
                                                  : Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'Start Time',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _validFromTime != null
                                                    ? _formatTimeOfDay(
                                                        _validFromTime!,
                                                      )
                                                    : 'Select Time',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: _validFromTime != null
                                                      ? AppTheme.primary
                                                      : (isDark
                                                            ? Colors.white70
                                                            : Colors.grey),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Icon(
                                      Icons.arrow_forward,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: InkWell(
                                        onTap: _selectToTime,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF2A2A2A)
                                                : Colors.grey[50],
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.grey[700]!
                                                  : Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'End Time',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _validToTime != null
                                                    ? _formatTimeOfDay(
                                                        _validToTime!,
                                                      )
                                                    : 'Select Time',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: _validToTime != null
                                                      ? AppTheme.primary
                                                      : (isDark
                                                            ? Colors.white70
                                                            : Colors.grey),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Send Notification to Followers
                      if (!widget.isEditing)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.notifications_active,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Notify Followers',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Send push notification to all salon followers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _sendNotification,
                                onChanged: (value) {
                                  setState(() {
                                    _sendNotification = value;
                                  });
                                  widget.onNotificationToggle(value);
                                },
                                activeThumbColor: AppTheme.primary,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white60 : Colors.grey,
                      side: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.isEditing ? 'Update Offer' : 'Create Offer',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
