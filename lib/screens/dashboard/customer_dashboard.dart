// lib/screens/customer/customer_dashboard.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/widgets/dashboard_stat_card.dart';
import 'package:flutter_application_1/widgets/booking_tile.dart';
import 'package:flutter_application_1/widgets/section_header.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();
  final supabase = Supabase.instance.client;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Customer Data
  String _customerName = 'Guest User';
  String _customerEmail = '';
  String? _customerImage;

  // Booking Statistics
  int _upcomingBookings = 0;
  int _pendingBookings = 0;
  int _completedBookings = 0;
  int _cancelledBookings = 0;
  int _totalSpent = 0;
  int _loyaltyPoints = 0;

  // VIP Bookings
  int _vipBookings = 0;
  int _pendingVipBookings = 0;

  // Upcoming Appointments
  List<Map<String, dynamic>> _upcomingAppointments = [];

  // Favorite Barbers
  List<Map<String, dynamic>> _favoriteBarbers = [];

  // Special Offers
  List<Map<String, dynamic>> _offers = [];

  // ==================== SEARCH STATE ====================
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  OverlayEntry? _searchOverlay;

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
    _loadDashboardData();
    _setupNotificationListeners();
    _searchController.addListener(_onSearchTextChanged);
    debugPrint('🔄 CustomerDashboard initState completed');
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeSearchOverlay();
    super.dispose();
  }

  // ==================== SEARCH METHODS ====================
  void _onSearchTextChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _searchSalons(query);
    } else {
      _hideSearchResults();
    }
  }

  Future<void> _searchSalons(String query) async {
    if (query.isEmpty) {
      _hideSearchResults();
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    try {
      final results = await supabase
          .from('salons')
          .select('''
            id, 
            name, 
            address, 
            open_time, 
            close_time, 
            logo_url,
            cover_url,
            phone,
            email,
            description,
            is_active
          ''')
          .ilike('name', '%$query%')
          .eq('is_active', true)
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
        _isSearching = false;
      });

      if (_searchResults.isNotEmpty && _showSearchResults) {
        _showSearchOverlay();
      } else {
        _hideSearchResults();
      }
    } catch (e) {
      debugPrint('Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  void _showSearchOverlay() {
    _removeSearchOverlay();

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _searchOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 65, // Adjusted for search bar height
        left: 0,
        right: 0,
        child: Material(
          elevation: 4,
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B8B)),
                      ),
                    ),
                  )
                : _searchResults.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text('No salons found'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) => _buildSearchResultTile(_searchResults[index]),
                      ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_searchOverlay!);
  }

  Widget _buildSearchResultTile(Map<String, dynamic> salon) {
    return InkWell(
      onTap: () {
        _hideSearchResults();
        _searchController.clear();
        // 🔧 MODIFIED: Navigate to Salon Profile instead of Booking Flow
        _navigateToSalonProfile(salon);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            // Salon Logo or Placeholder
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: salon['logo_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        salon['logo_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            salon['name']?.substring(0, 1) ?? 'S',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B)),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        salon['name']?.substring(0, 1) ?? 'S',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B)),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salon['name'] ?? 'Salon',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  if (salon['address'] != null)
                    Text(
                      salon['address'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 10, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text(
                        '${salon['open_time']?.toString().substring(0, 5) ?? '09:00'} - ${salon['close_time']?.toString().substring(0, 5) ?? '18:00'}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chevron_right, size: 14, color: Color(0xFFFF6B8B)),
                  const SizedBox(width: 2),
                  Text(
                    'View',
                    style: TextStyle(fontSize: 11, color: const Color(0xFFFF6B8B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideSearchResults() {
    if (_searchOverlay != null) {
      _searchOverlay!.remove();
      _searchOverlay = null;
    }
    setState(() {
      _showSearchResults = false;
      _searchResults = [];
    });
  }

  void _removeSearchOverlay() {
    if (_searchOverlay != null) {
      _searchOverlay!.remove();
      _searchOverlay = null;
    }
  }

  // 🔧 MODIFIED: Navigate to Salon Profile Screen
  void _navigateToSalonProfile(Map<String, dynamic> salon) {
    // Navigate to salon profile screen with selected salon data
    context.push('/customer/salon-profile', extra: salon);
  }

  // ==================== LOAD CUSTOMER DATA ====================
  Future<void> _loadCustomerData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      _customerEmail = user.email ?? '';

      // Get profile from database
      final profile = await supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null) {
        setState(() {
          _customerName = profile['full_name'] ?? user.email?.split('@').first ?? 'Guest User';
          _customerImage = profile['avatar_url'];
        });
      } else {
        setState(() {
          _customerName = user.email?.split('@').first ?? 'Guest User';
        });
      }

      debugPrint('✅ Loaded customer: $_customerName ($_customerEmail)');
    } catch (e) {
      debugPrint('❌ Error loading customer data: $e');
    }
  }

  // ==================== LOAD DASHBOARD DATA ====================
  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Get all appointments for this customer
      final appointments = await supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            appointment_date,
            start_time,
            end_time,
            status,
            is_vip,
            vip_booking_id,
            price,
            queue_number,
            queue_token,
            barber_id,
            service_id,
            variant_id,
            services!inner (
              name
            ),
            service_variants!left (
              price,
              duration,
              salon_genders!left (display_name),
              salon_age_categories!left (display_name)
            ),
            profiles!appointments_customer_id_fkey (
              full_name,
              avatar_url
            )
          ''')
          .eq('customer_id', user.id)
          .order('appointment_date', ascending: false);

      // Calculate statistics
      int upcoming = 0;
      int pending = 0;
      int completed = 0;
      int cancelled = 0;
      int vip = 0;
      int pendingVip = 0;
      double totalSpent = 0.0;
      List<Map<String, dynamic>> upcomingList = [];

      for (var apt in appointments) {
        final status = apt['status'] as String;
        final isVip = apt['is_vip'] == true;
        
        // Convert price to double
        final double price = (apt['price'] as num?)?.toDouble() ?? 
                             (apt['service_variants']?['price'] as num?)?.toDouble() ?? 
                             0.0;

        // Count by status
        if (status == 'confirmed' || status == 'pending') {
          final dateStr = apt['appointment_date'] as String;
          final date = DateTime.parse(dateStr);
          if (date.isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
            upcoming++;
            upcomingList.add(apt);
          }
        }

        if (status == 'pending') pending++;
        if (status == 'completed') {
          completed++;
          totalSpent += price;
        }
        if (status == 'cancelled') cancelled++;

        // VIP counts
        if (isVip) {
          vip++;
          if (status == 'pending') pendingVip++;
        }
      }

      // Get favorite barbers (from completed appointments)
      final favoriteBarbers = await _getFavoriteBarbers(user.id);

      // Sample offers (can be from database)
      final offers = [
        {
          'title': '20% Off',
          'description': 'On your next hair cut',
          'code': 'HAIR20',
          'expiry': '2024-12-31',
          'image': '🎯',
        },
        {
          'title': 'Buy 1 Get 1',
          'description': 'On facials',
          'code': 'FACIALB1G1',
          'expiry': '2024-11-30',
          'image': '💆',
        },
        {
          'title': 'VIP Treatment',
          'description': 'Free upgrade to VIP',
          'code': 'VIPFREE',
          'expiry': '2024-10-15',
          'image': '👑',
        },
      ];

      if (mounted) {
        setState(() {
          _upcomingBookings = upcoming;
          _pendingBookings = pending;
          _completedBookings = completed;
          _cancelledBookings = cancelled;
          _vipBookings = vip;
          _pendingVipBookings = pendingVip;
          _totalSpent = totalSpent.toInt();
          _loyaltyPoints = (totalSpent / 10).round();
          _upcomingAppointments = upcomingList.take(3).toList();
          _favoriteBarbers = favoriteBarbers;
          _offers = offers;
        });
      }

      // Check notification permission
      _hasPermission = await _notificationService.hasPermission();
      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard('customer_dashboard');
      } else {
        _showPermissionCard = false;
      }

      debugPrint('✅ Dashboard data loaded: $upcoming upcoming, $vip VIP');
    } catch (e) {
      debugPrint('❌ Error loading dashboard data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== GET FAVORITE BARBERS ====================
  Future<List<Map<String, dynamic>>> _getFavoriteBarbers(String customerId) async {
    try {
      // Get barbers with most completed appointments
      final response = await supabase
          .from('appointments')
          .select('''
            barber_id,
            profiles!appointments_barber_id_fkey (
              full_name,
              avatar_url
            )
          ''')
          .eq('customer_id', customerId)
          .eq('status', 'completed');

      // Count occurrences per barber
      final Map<String, Map<String, dynamic>> barberCount = {};
      for (var apt in response) {
        final barberId = apt['barber_id'] as String;
        final barberData = apt['profiles'] as Map?;
        
        if (!barberCount.containsKey(barberId)) {
          barberCount[barberId] = {
            'id': barberId,
            'name': barberData?['full_name'] ?? 'Unknown',
            'avatar': barberData?['avatar_url'],
            'count': 0,
          };
        }
        barberCount[barberId]!['count'] = barberCount[barberId]!['count'] + 1;
      }

      // Convert to list and sort by count
      List<Map<String, dynamic>> barbers = barberCount.values.toList();
      barbers.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      
      // Add rating
      for (var barber in barbers.take(5)) {
        final reviews = await supabase
            .from('reviews')
            .select('overall_rating')
            .eq('barber_id', barber['id']);
        
        double avgRating = 0;
        if (reviews.isNotEmpty) {
          double total = 0;
          for (var review in reviews) {
            total += (review['overall_rating'] as num?)?.toDouble() ?? 0;
          }
          avgRating = total / reviews.length;
        }
        barber['rating'] = avgRating > 0 ? avgRating : 4.5;
      }

      return barbers.take(5).toList();
    } catch (e) {
      debugPrint('❌ Error getting favorite barbers: $e');
      return [];
    }
  }

  // ==================== SETUP NOTIFICATION LISTENERS ====================
  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New message: ${message.data}');

        final type = message.data['type'];

        if (type == 'booking_confirmed') {
          _showBookingUpdateAlert(message, 'confirmed');
          _loadDashboardData();
        } else if (type == 'vip_approved') {
          _showVipApprovedAlert(message);
          _loadDashboardData();
        } else if (type == 'booking_reminder') {
          _showReminderAlert(message);
        } else if (type == 'special_offer') {
          _showOfferAlert(message);
        } else if (type == 'vip_request_update') {
          _showVipRequestUpdateAlert(message);
          _loadDashboardData();
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('👆 Message opened: ${message.data}');
        _handleNotificationNavigation(message.data);
      });
    } catch (e) {
      debugPrint('❌ Error setting up notification listeners: $e');
    }
  }

  // ==================== NOTIFICATION HANDLERS ====================
  void _showBookingUpdateAlert(RemoteMessage message, String type) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: type == 'confirmed' ? Colors.green.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(type == 'confirmed' ? Icons.check_circle : Icons.info, color: type == 'confirmed' ? Colors.green : Colors.blue),
            ),
            const SizedBox(width: 12),
            Text(type == 'confirmed' ? 'Booking Confirmed!' : 'Booking Update'),
          ],
        ),
        content: Text(message.notification?.body ?? 'Your booking has been updated'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewMyBookings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B)),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  void _showVipApprovedAlert(RemoteMessage message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.star, color: Colors.amber),
            ),
            const SizedBox(width: 12),
            const Text('✨ VIP Booking Approved!'),
          ],
        ),
        content: Text(message.notification?.body ?? 'Your VIP request has been approved'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewVipBookings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B)),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  void _showVipRequestUpdateAlert(RemoteMessage message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.star, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(message.notification?.body ?? 'VIP request updated')),
          ],
        ),
        backgroundColor: Colors.amber.shade700,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'View', textColor: Colors.white, onPressed: _viewVipBookings),
      ),
    );
  }

  void _showReminderAlert(RemoteMessage message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message.notification?.body ?? 'Upcoming appointment reminder')),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'View', textColor: Colors.white, onPressed: _viewMyBookings),
      ),
    );
  }

  void _showOfferAlert(RemoteMessage message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.local_offer, color: Colors.amber),
            ),
            const SizedBox(width: 12),
            const Text('Special Offer!'),
          ],
        ),
        content: Text(message.notification?.body ?? 'New offer available'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewOffers();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B)),
            child: const Text('View Offer'),
          ),
        ],
      ),
    );
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'booking_confirmed' || type == 'booking_reminder') {
      _viewMyBookings();
    } else if (type == 'vip_approved' || type == 'vip_request_update') {
      _viewVipBookings();
    } else if (type == 'special_offer') {
      _viewOffers();
    }
  }

  // ==================== PERMISSION HANDLERS ====================
  Future<void> _enableNotifications() async {
    setState(() => _showPermissionCard = false);

    try {
      final canAsk = await _permissionManager.canAskSystemPermission();

      if (!canAsk) {
        _showSettingsDialog();
        return;
      }

      if (!mounted) return;
      await _permissionService.requestPermissionAtAction(
        context: context,
        action: 'customer_dashboard',
        customTitle: '🔔 Get Booking Updates',
        customMessage: 'Get instant notifications for booking confirmations, VIP approvals, and special offers',
        onGranted: () async {
          await _permissionManager.markPermissionGranted();
          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Notifications enabled!'), backgroundColor: Colors.green),
            );
          }
        },
        onDenied: () async {
          await _permissionManager.markPermissionDenied(permanent: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You can enable later from settings'), backgroundColor: Colors.orange),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error enabling notifications: $e');
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔔 Notifications Disabled'),
        content: const Text('To enable notifications, please go to your device settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _permissionService.openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B)),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('customer_dashboard');
  }

  // ==================== NAVIGATION METHODS ====================
  void _viewMyBookings() {
    context.push('/customer/bookings');
  }

  void _viewVipBookings() {
    context.push('/customer/vip-bookings');
  }

  void _createVipBooking() {
    context.push('/customer/vip-booking');
  }

  void _bookAppointment() {
    context.push('/customer/booking-flow');
  }

  void _viewOffers() {
    context.push('/customer/offers');
  }

  void _viewLoyaltyProgram() {
    context.push('/customer/loyalty');
  }

  void _viewFavoriteBarbers() {
    context.push('/customer/favorites');
  }

  void _viewBookingDetails(String bookingId) {
    context.push('/customer/booking/$bookingId');
  }

  void _applyOffer(String code) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Offer code "$code" applied!'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
    );
  }

  // ==================== DRAWER METHODS ====================
  void _openDrawer() {
    try {
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
      } else {
        Scaffold.of(context).openDrawer();
      }
    } catch (e) {
      debugPrint('❌ Error opening drawer: $e');
      _showMenuDialog();
    }
  }

  void _showMenuDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Menu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(leading: const Icon(Icons.dashboard, color: Colors.blue), title: const Text('Dashboard'), onTap: () => Navigator.pop(context)),
              ListTile(leading: const Icon(Icons.calendar_today, color: Colors.green), title: const Text('My Bookings'), onTap: () { Navigator.pop(context); _viewMyBookings(); }),
              ListTile(leading: const Icon(Icons.star, color: Colors.amber), title: const Text('VIP Bookings'), onTap: () { Navigator.pop(context); _viewVipBookings(); }),
              ListTile(leading: const Icon(Icons.book_online, color: Colors.purple), title: const Text('Book Appointment'), onTap: () { Navigator.pop(context); _bookAppointment(); }),
              ListTile(leading: const Icon(Icons.favorite, color: Colors.red), title: const Text('Favorites'), onTap: () { Navigator.pop(context); _viewFavoriteBarbers(); }),
              ListTile(leading: const Icon(Icons.local_offer, color: Colors.amber), title: const Text('Offers'), onTap: () { Navigator.pop(context); _viewOffers(); }),
              ListTile(leading: const Icon(Icons.card_giftcard, color: Colors.green), title: const Text('Loyalty Program'), onTap: () { Navigator.pop(context); _viewLoyaltyProgram(); }),
              const Divider(),
              ListTile(leading: const Icon(Icons.settings, color: Colors.grey), title: const Text('Settings'), onTap: () { Navigator.pop(context); context.push('/customer/settings'); }),
              ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout'), onTap: () { Navigator.pop(context); _logout(context); }),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  // ==================== LOGOUT ====================
  Future<void> _logout(BuildContext context) async {
    showLogoutConfirmation(
      context,
      onLogoutConfirmed: () async {
        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B))),
        );

        try {
          await SessionManager.logoutForContinue();
          appState.refreshState();

          if (context.mounted) {
            Navigator.pop(context);
            context.go('/');
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  // ==================== UI BUILDERS ====================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('My Dashboard'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer,
          tooltip: 'Menu',
          iconSize: 28,
        ),
        // Search Bar in App Bar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '🔍 Search for salons...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _hideSearchResults();
                          },
                          child: const Icon(Icons.close, color: Colors.white),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onTap: () {
                  if (_searchController.text.isNotEmpty && _searchResults.isNotEmpty) {
                    _showSearchOverlay();
                  }
                },
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.star, color: Colors.white),
            onPressed: _createVipBooking,
            tooltip: 'VIP Booking',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _bookAppointment,
            tooltip: 'Book Appointment',
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _viewMyBookings,
              ),
              if (_pendingBookings + _pendingVipBookings > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      '${_pendingBookings + _pendingVipBookings}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      drawer: SideMenu(
        userRole: 'customer',
        userName: _customerName,
        userEmail: _customerEmail,
        profileImageUrl: _customerImage,
        onMenuItemSelected: () => _loadDashboardData(),
      ),
      body: GestureDetector(
        onTap: () {
          _searchFocusNode.unfocus();
          _hideSearchResults();
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                color: const Color(0xFFFF6B8B),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      if (_showPermissionCard && !_hasPermission)
                        PermissionCard(
                          onEnable: _enableNotifications,
                          onNotNow: _handleNotNow,
                          title: '🔔 Get Booking Updates',
                          message: 'Get instant notifications for booking confirmations, VIP approvals, and special offers',
                          compact: false,
                        ),
                      // Welcome text only (without profile image)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back,',
                                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                              ),
                              Text(
                                _customerName,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Quick Action Buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(child: _buildQuickActionButton(icon: Icons.book_online, label: 'Book Now', color: Colors.blue, onTap: _bookAppointment)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildQuickActionButton(
                                icon: Icons.star,
                                label: 'VIP Booking',
                                color: Colors.amber,
                                badge: _pendingVipBookings > 0 ? '$_pendingVipBookings' : null,
                                onTap: _createVipBooking,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _buildQuickActionButton(icon: Icons.history, label: 'History', color: Colors.purple, onTap: _viewMyBookings)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Stats Cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(child: DashboardStatCard(title: 'Upcoming', value: '$_upcomingBookings', icon: Icons.calendar_today, color: Colors.blue, subtitle: 'Appointments', onTap: _viewMyBookings)),
                            const SizedBox(width: 12),
                            Expanded(child: DashboardStatCard(title: 'VIP Bookings', value: '$_vipBookings', icon: Icons.star, color: Colors.amber, subtitle: 'Total', onTap: _viewVipBookings)),
                            const SizedBox(width: 12),
                            Expanded(child: DashboardStatCard(title: 'Loyalty', value: '$_loyaltyPoints', icon: Icons.card_giftcard, color: Colors.green, subtitle: 'Points', onTap: _viewLoyaltyProgram)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // VIP Pending Banner
                      if (_pendingVipBookings > 0)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.amber.shade300, Colors.amber.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                                child: const Icon(Icons.star, color: Colors.white, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('VIP Request Pending', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                    Text(
                                      '$_pendingVipBookings VIP booking${_pendingVipBookings != 1 ? 's' : ''} waiting for approval',
                                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9)),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _viewVipBookings,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.amber.shade700),
                                child: const Text('View'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Upcoming Bookings Section
                      SectionHeader(title: 'Upcoming Bookings', actionText: _upcomingBookings > 3 ? 'View All' : ''),
                      const SizedBox(height: 8),
                      _upcomingAppointments.isNotEmpty
                          ? ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _upcomingAppointments.length,
                              itemBuilder: (context, index) {
                                final apt = _upcomingAppointments[index];
                                final isVip = apt['is_vip'] == true;
                                final service = apt['services'] as Map<String, dynamic>?;
                                final variant = apt['service_variants'] as Map<String, dynamic>?;
                                
                                String serviceName = service?['name'] ?? 'Service';
                                if (variant != null) {
                                  final gender = variant['salon_genders'] as Map<String, dynamic>?;
                                  final age = variant['salon_age_categories'] as Map<String, dynamic>?;
                                  if (gender != null && age != null) {
                                    serviceName += ' • ${gender['display_name']} ${age['display_name']}';
                                  }
                                }

                                final date = DateTime.parse(apt['appointment_date']);
                                final dateStr = DateFormat('MMM dd, yyyy').format(date);
                                final timeStr = apt['start_time'].toString().substring(0, 5);

                                return BookingTile(
                                  customerName: 'You',
                                  serviceName: serviceName,
                                  time: '$dateStr at $timeStr',
                                  status: apt['status'] == 'confirmed' ? 'Confirmed' : 'Pending',
                                  statusColor: apt['status'] == 'confirmed' ? Colors.green : Colors.orange,
                                  barberName: 'Barber',
                                  price: (apt['price'] as num?)?.toDouble() ?? 
                                         (apt['service_variants']?['price'] as num?)?.toDouble() ?? 
                                         0.0,
                                  isVip: isVip,
                                  queueNumber: apt['queue_number'],
                                  queueToken: apt['queue_token'],
                                  onTap: () => _viewBookingDetails(apt['id'].toString()),
                                );
                              },
                            )
                          : Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.calendar_today, size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 12),
                                  Text('No upcoming bookings', style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton(
                                        onPressed: _bookAppointment,
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B)),
                                        child: const Text('Book Now'),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton(
                                        onPressed: _createVipBooking,
                                        style: OutlinedButton.styleFrom(foregroundColor: Colors.amber, side: const BorderSide(color: Colors.amber)),
                                        child: const Text('VIP Booking'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                      const SizedBox(height: 16),
                      // Special Offers Section
                      SectionHeader(title: 'Special Offers', actionText: 'View All'),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _offers.length,
                          itemBuilder: (context, index) => _buildOfferCard(_offers[index]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Favorite Barbers Section
                      if (_favoriteBarbers.isNotEmpty) ...[
                        SectionHeader(title: 'Favorite Barbers', actionText: 'View All'),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _favoriteBarbers.length,
                            itemBuilder: (context, index) => _buildFavoriteBarberCard(_favoriteBarbers[index]),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Activity Summary
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Activity Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildActivityItem(icon: Icons.check_circle, label: 'Completed', value: '$_completedBookings', color: Colors.green)),
                                Expanded(child: _buildActivityItem(icon: Icons.cancel, label: 'Cancelled', value: '$_cancelledBookings', color: Colors.red)),
                                Expanded(child: _buildActivityItem(icon: Icons.star, label: 'VIP', value: '$_vipBookings', color: Colors.amber)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _buildActivityItem(icon: Icons.currency_rupee, label: 'Total Spent', value: 'Rs. $_totalSpent', color: Colors.purple)),
                                Expanded(child: _buildActivityItem(icon: Icons.card_giftcard, label: 'Points', value: '$_loyaltyPoints', color: Colors.blue)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Notification Status
                      if (_hasPermission)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: Colors.green[700]),
                              const SizedBox(width: 4),
                              Text('Notifications active', style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ==================== HELPER WIDGETS ====================
  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                badge,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOfferCard(Map<String, dynamic> offer) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.amber.shade300, Colors.orange.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(offer['image'] ?? '🎯', style: const TextStyle(fontSize: 32)),
          const Spacer(),
          Text(offer['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(offer['description'], style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Text(offer['code'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const Spacer(),
              Text('Exp: ${offer['expiry']}', style: const TextStyle(fontSize: 9, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _applyOffer(offer['code']),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Apply', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteBarberCard(Map<String, dynamic> barber) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            backgroundImage: barber['avatar'] != null ? NetworkImage(barber['avatar']) : null,
            child: barber['avatar'] == null
                ? Text(barber['name'][0].toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B)))
                : null,
          ),
          const SizedBox(height: 8),
          Text(barber['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 14),
              const SizedBox(width: 2),
              Text(barber['rating'].toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text('(${barber['count']} cuts)', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _bookAppointment,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B8B),
                side: const BorderSide(color: Color(0xFFFF6B8B)),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Book', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem({required IconData icon, required String label, required String value, required Color color}) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}