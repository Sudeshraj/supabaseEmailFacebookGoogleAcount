import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/timezone_service.dart';

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
  
  @override
  void initState() {
    super.initState();
    _initializeTimezone();
    _scrollController.addListener(_onScroll);
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
    _userTimezone = prefs.getString('cached_timezone') ?? TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);
    
    setState(() {
      _isTimezoneLoaded = true;
    });
    
      await _loadSalonAndOffers();
  }
  
  // ============================================
  // TIMEZONE HELPER METHODS
  // ============================================
  
  /// Convert UTC date string to local date for display
  DateTime _utcToLocalDate(String utcDateStr) {
    try {
      final utcDateTime = DateTime.parse(utcDateStr);
      final localDateTime = TimezoneService.utcToLocalDateTime('12:00', utcDateTime);
      return DateTime(localDateTime.year, localDateTime.month, localDateTime.day);
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      return DateTime.parse(utcDateStr);
    }
  }
  
  /// Format UTC date to local date string
  String _formatLocalDate(String utcDateStr) {
    try {
      final localDate = _utcToLocalDate(utcDateStr);
      return DateFormat('MMM dd, yyyy').format(localDate);
    } catch (e) {
      debugPrint('Error formatting date: $e');
      return utcDateStr;
    }
  }
  
  /// Check if offer is active based on local date
  bool _isOfferActive(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final nowLocal = DateTime(now.year, now.month, now.day);    
  
    final validToLocal = _utcToLocalDate(offer['valid_to']);
    
    return offer['is_active'] == true && validToLocal.isAfter(nowLocal);
  }
  
  /// Check if offer is expired based on local date
  bool _isOfferExpired(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final nowLocal = DateTime(now.year, now.month, now.day);
    
    final validToLocal = _utcToLocalDate(offer['valid_to']);
    final validFromLocal = _utcToLocalDate(offer['valid_from']);
    
    return validToLocal.isBefore(nowLocal) || validFromLocal.isAfter(nowLocal);
  }
  
  /// Get days left in local timezone
  int _getDaysLeft(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final nowLocal = DateTime(now.year, now.month, now.day);
    final validToLocal = _utcToLocalDate(offer['valid_to']);
    return validToLocal.difference(nowLocal).inDays;
  }
      
  void _onScroll() {
    if (_scrollController.position.pixels > 200 && _showFloatingButton) {
      setState(() => _showFloatingButton = false);
    } else if (_scrollController.position.pixels <= 200 && !_showFloatingButton) {
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
          _errorMessage = 'You don\'t own any salon. Please create a salon first.';
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
        _errorMessage = 'Failed to load salon data. Please check your connection.';
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
    switch(_selectedFilter) {
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
      // Prepare insert data (dates already in UTC format from dialog)
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
      
      // Add time range if provided
      if (offerData['valid_from_time'] != null && offerData['valid_to_time'] != null) {
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
        const SnackBar(
          content: Text('✨ Offer created successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      debugPrint('Error creating offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to create offer: ${e.toString().substring(0, 100)}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _sendOfferNotificationsToFollowers(Map<String, dynamic> offer) async {
    final salonId = _currentSalonId;
    if (salonId == null) return;
    
    try {
      final followers = await supabase
          .from('salon_followers')
          .select('customer_id')
          .eq('salon_id', salonId);
      
      if (followers.isEmpty) {
        debugPrint('No followers to notify');
        return;
      }
      
      String discountText = '';
      if (offer['discount_type'] == 'percentage') {
        discountText = '${offer['discount_value']}% OFF';
      } else if (offer['discount_type'] == 'fixed') {
        discountText = '₹${offer['discount_value']} OFF';
      } else {
        discountText = 'FREE SERVICE';
      }
      
      for (var follower in followers) {
        await _notificationService.sendSpecialOffer(
          customerId: follower['customer_id'],
          offerTitle: offer['title'],
          offerDescription: offer['description'] ?? '',
          discountText: discountText,
          offerId: offer['id'],
          salonName: _currentSalonName ?? 'Salon',
        );
      }      
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📢 Notifications sent to ${followers.length} followers'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      debugPrint('Error sending notifications: $e');
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
      
      // Add time range if provided
      if (offerData['valid_from_time'] != null && offerData['valid_to_time'] != null) {
        updateData['valid_from_time'] = offerData['valid_from_time'];
        updateData['valid_to_time'] = offerData['valid_to_time'];
      } else {
        updateData['valid_from_time'] = null;
        updateData['valid_to_time'] = null;
      }
      
      await supabase
          .from('offers')
          .update(updateData)
          .eq('id', offerId);
      
      await _loadOffers();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✏️ Offer updated successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      debugPrint('Error updating offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to update offer: ${e.toString().substring(0, 100)}'),
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
          content: Text(!isActive ? '✅ Offer activated' : '⏸️ Offer deactivated'),
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
          content: Text('❌ Failed to update offer status'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _deleteOffer(int offerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Offer'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this offer?\n\nThis action cannot be undone and will remove this offer from all customers.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        const SnackBar(
          content: Text('🗑️ Offer deleted successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      debugPrint('Error deleting offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to delete offer: ${e.toString().substring(0, 100)}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  String _getDiscountText(Map<String, dynamic> offer) {
    switch(offer['discount_type']) {
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
      final from = TimeOfDay.fromDateTime(DateTime.parse('2000-01-01 $fromTime'));
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
  // TIMEZONE INFO WIDGET (NEW)
  // ============================================
  

  
  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (!_isTimezoneLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage Offers'),
          backgroundColor: const Color(0xFFFF6B8B),
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
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage Offers',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_currentSalonName != null)
              Text(
                _currentSalonName!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterMenu(),
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOffers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading && _offers.isEmpty
          ? _buildLoadingState()
          : _hasError
              ? _buildErrorState()
              : _buildMainContent(isSmallScreen, isDarkMode),
      floatingActionButton: _showFloatingButton && !_isLoading && !_hasError && _offers.isNotEmpty
          ? FloatingActionButton(
              onPressed: _createOffer,
              backgroundColor: const Color(0xFFFF6B8B),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
  
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFFFF6B8B)),
          SizedBox(height: 16),
          Text('Loading your offers...'),
        ],
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSalonAndOffers,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMainContent(bool isSmallScreen, bool isDarkMode) {
    return Column(
      children: [
        _buildSalonInfoCard(isDarkMode),      
        _buildFilterChips(isSmallScreen),
        Expanded(
          child: _filteredOffers.isEmpty
              ? _buildEmptyState(isSmallScreen)
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 12 : 24,
                    vertical: 8,
                  ),
                  itemCount: _filteredOffers.length,
                  itemBuilder: (context, index) {
                    final offer = _filteredOffers[index];
                    return _buildOfferCard(offer, isSmallScreen);
                  },
                ),
        ),
      ],
    );
  }
  
  Widget _buildSalonInfoCard(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.local_offer,
              color: Color(0xFFFF6B8B),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '📊 ${_offers.length} Total  •  🟢 $_activeCount Active',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
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
  
  Widget _buildFilterChips(bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isSmallScreen
          ? SingleChildScrollView(
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
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFilterChip('All Offers', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Active Offers', 'active'),
                const SizedBox(width: 8),
                _buildFilterChip('Expired/Inactive', 'expired'),
              ],
            ),
    );
  }
  
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
      checkmarkColor: const Color(0xFFFF6B8B),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(bool isSmallScreen) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _selectedFilter == 'active' 
                    ? Icons.local_offer_outlined
                    : _selectedFilter == 'expired'
                    ? Icons.timer_off_outlined
                    : Icons.add_circle_outline,
                size: isSmallScreen ? 60 : 80,
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getEmptyStateMessage(),
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _getEmptyStateSubMessage(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
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
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
    switch(_selectedFilter) {
      case 'active':
        return 'No Active Offers';
      case 'expired':
        return 'No Expired Offers';
      default:
        return _offers.isEmpty ? 'No Offers Yet' : 'No Offers Found';
    }
  }
  
  String _getEmptyStateSubMessage() {
    switch(_selectedFilter) {
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
  
  Widget _buildOfferCard(Map<String, dynamic> offer, bool isSmallScreen) {
    final statusColor = _getStatusColor(offer);
    final statusText = _getStatusText(offer);
    final discountText = _getDiscountText(offer);
    
    // ✅ Use local date conversion for display
    final validFrom = _formatLocalDate(offer['valid_from']);
    final validTo = _formatLocalDate(offer['valid_to']);
    
    final usageLimit = offer['usage_limit'];
    final usedCount = offer['used_count'] ?? 0;
    
    final timeRangeText = _getTimeRangeText(offer['valid_from_time'], offer['valid_to_time']);
    final hasTimeRestriction = timeRangeText.isNotEmpty;
    
    final usageLimitText = _getUsageLimitText(usageLimit, usedCount);
    final usageLimitColor = _getUsageLimitColor(usageLimit, usedCount);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color(0xFFFF6B8B), const Color(0xFFFF6B8B).withValues(alpha: 0.7)],
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // Description
              if (offer['description'] != null && offer['description'].isNotEmpty)
                Text(
                  offer['description'],
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              
              if (offer['description'] != null && offer['description'].isNotEmpty)
                const SizedBox(height: 12),
              
              // Details chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((offer['points_required'] ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          isSmallScreen ? validFrom : '$validFrom - $validTo',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  
                  if (hasTimeRestriction)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, size: 12, color: Colors.purple),
                          const SizedBox(width: 4),
                          Text(
                            timeRangeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.purple[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: usageLimitColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          usageLimitText.contains('♾️') ? Icons.unpublished : 
                          usageLimitText.contains('🔴') ? Icons.cancel :
                          usageLimitText.contains('⚠️') ? Icons.warning_amber : Icons.people,
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
                            color: Colors.grey[500],
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
                        backgroundColor: Colors.grey[200],
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
                      onPressed: () => _toggleOfferStatus(offer['id'], offer['is_active']),
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
                      onPressed: () => _toggleOfferStatus(offer['id'], offer['is_active']),
                      icon: Icon(offer['is_active'] ? Icons.pause : Icons.play_arrow, size: 20),
                      color: offer['is_active'] ? Colors.orange : Colors.green,
                      tooltip: offer['is_active'] ? 'Deactivate' : 'Activate',
                    ),
                    IconButton(
                      onPressed: () => _editOffer(offer),
                      icon: const Icon(Icons.edit, size: 20),
                      color: Colors.blue,
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      onPressed: () => _deleteOffer(offer['id']),
                      icon: const Icon(Icons.delete, size: 20),
                      color: Colors.red,
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
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
  
  void _showFilterMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Filter Offers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    return ListTile(
      leading: Icon(icon, color: _selectedFilter == value ? const Color(0xFFFF6B8B) : null),
      title: Text(title),
      trailing: _selectedFilter == value ? const Icon(Icons.check, color: Color(0xFFFF6B8B)) : null,
      onTap: () {
        setState(() => _selectedFilter = value);
        Navigator.pop(context);
      },
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
  
  @override
  void initState() {
    super.initState();
    _sendNotification = widget.sendNotificationToFollowers;
    
    if (widget.isEditing && widget.offer != null) {
      _titleController = TextEditingController(text: widget.offer!['title']);
      _descriptionController = TextEditingController(text: widget.offer!['description'] ?? '');
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
      
      // Load time range if exists
      if (widget.offer!.containsKey('valid_from_time') && widget.offer!['valid_from_time'] != null) {
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
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _validFrom,
        end: _validTo,
      ),
      helpText: 'Select Offer Validity Period',
      confirmText: 'Apply',
      cancelText: 'Cancel',
    );
    
    if (picked != null) {
      setState(() {
        _validFrom = picked.start;
        _validTo = picked.end;
      });
    }
  }
  
  Future<void> _selectFromTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _validFromTime ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Select Start Time',
    );
    if (picked != null) {
      setState(() {
        _validFromTime = picked;
        _validToTime ??= TimeOfDay(hour: picked.hour + 1, minute: picked.minute);
      });
    }
  }
  
  Future<void> _selectToTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _validToTime ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'Select End Time',
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
          const SnackBar(
            content: Text('End date must be after start date'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      if (_hasTimeRestriction) {
        if (_validFromTime == null || _validToTime == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select both start and end times'),
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
        'discount_value': _discountType != 'free_service' ? double.parse(_discountValueController.text) : 0,
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
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    
    return Dialog(
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
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.isEditing ? Icons.edit : Icons.add,
                    color: const Color(0xFFFF6B8B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.isEditing ? 'Edit Offer' : 'Create New Offer',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
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
                      const Text(
                        'Offer Title *',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Summer Special Sale',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      const Text('Description (Optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Describe your offer details...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Discount Type
                      const Text('Discount Type *'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Percentage %'),
                              selected: _discountType == 'percentage',
                              onSelected: (selected) {
                                if (selected) setState(() => _discountType = 'percentage');
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                              backgroundColor: Colors.grey[100],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Fixed ₹'),
                              selected: _discountType == 'fixed',
                              onSelected: (selected) {
                                if (selected) setState(() => _discountType = 'fixed');
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                              backgroundColor: Colors.grey[100],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Free Service'),
                              selected: _discountType == 'free_service',
                              onSelected: (selected) {
                                if (selected) setState(() => _discountType = 'free_service');
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                              backgroundColor: Colors.grey[100],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Discount Value
                      if (_discountType != 'free_service') ...[
                        const Text('Discount Value *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _discountValueController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: _discountType == 'percentage' ? 'e.g., 20' : 'e.g., 500',
                            prefixText: _discountType == 'percentage' ? '% ' : '₹ ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      const Text('Points Required'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _pointsRequiredController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '0 (Available for all customers)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      const Text('Usage Limit (Optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usageLimitController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g., 10 (First 10 customers only)',
                          helperText: 'Leave empty for unlimited uses',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      const Text('Valid Period *'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: Color(0xFFFF6B8B), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${DateFormat('MMM dd, yyyy').format(_validFrom)} → ${DateFormat('MMM dd, yyyy').format(_validTo)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, color: Colors.grey),
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
                          border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text(
                                'Restrict to specific time range',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: const Text('Offer valid only during selected hours'),
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
                              activeThumbColor: const Color(0xFFFF6B8B),
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
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[50],
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.grey[300]!),
                                          ),
                                          child: Column(
                                            children: [
                                              const Text(
                                                'Start Time',
                                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _validFromTime != null 
                                                    ? _formatTimeOfDay(_validFromTime!)
                                                    : 'Select Time',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: _validFromTime != null 
                                                      ? const Color(0xFFFF6B8B) 
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(Icons.arrow_forward, color: Colors.grey),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: InkWell(
                                        onTap: _selectToTime,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[50],
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.grey[300]!),
                                          ),
                                          child: Column(
                                            children: [
                                              const Text(
                                                'End Time',
                                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _validToTime != null 
                                                    ? _formatTimeOfDay(_validToTime!)
                                                    : 'Select Time',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: _validToTime != null 
                                                      ? const Color(0xFFFF6B8B) 
                                                      : Colors.grey,
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
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
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
                                    const Text(
                                      'Notify Followers',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Send push notification to all salon followers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
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
                                activeThumbColor: const Color(0xFFFF6B8B),
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
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(widget.isEditing ? 'Update Offer' : 'Create Offer'),
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