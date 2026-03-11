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

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  // 🔑 GlobalKey for scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Customer Dashboard Data
  int _upcomingBookings = 2;
  int _completedBookings = 15;
  int _cancelledBookings = 1;
  int _loyaltyPoints = 450;
  int _totalSpent = 24500;
  String _customerName = 'Guest User';
  String _customerEmail = '';
  String? _customerImage;
  
  // Favorite barbers/services
  final List<Map<String, dynamic>> _favoriteBarbers = [
    {'name': 'Kamal', 'specialty': 'Hair Cut Specialist', 'rating': 4.9},
    {'name': 'Sunil', 'specialty': 'Facial Expert', 'rating': 4.8},
  ];
  
  // Special offers
  final List<Map<String, dynamic>> _offers = [
    {'title': '20% Off', 'description': 'On your next hair cut', 'code': 'HAIR20'},
    {'title': 'Buy 1 Get 1', 'description': 'On facials', 'code': 'FACIALB1G1'},
  ];

  @override
  void initState() {
    super.initState();
    
    // Load customer data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final role = await SessionManager.getCurrentRole();
      final appStateRole = appState.currentRole;
      debugPrint('🔍 CustomerDashboard - SessionManager role: $role');
      debugPrint('🔍 CustomerDashboard - AppState role: $appStateRole');
      
      // Load customer name from session
      try {
        final email = await SessionManager.getCurrentUserEmail();
        if (email != null && mounted) {
          final profile = await SessionManager.getProfileByEmail(email);
          if (profile != null) {
            setState(() {
              _customerName = profile['name'] ?? email.split('@').first;
              _customerEmail = email;
              _customerImage = profile['photo'];
            });
            debugPrint('✅ Loaded customer: $_customerName');
          } else {
            setState(() {
              _customerName = email.split('@').first;
              _customerEmail = email;
            });
          }
        }
      } catch (e) {
        debugPrint('❌ Error loading customer data: $e');
      }
    });

    _loadData();
    _setupNotificationListeners();
    debugPrint('🔄 CustomerDashboard initState completed');
  }

  // 🔥 Load initial data
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      print('📊 Loading customer dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'customer_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      // TODO: Fetch real booking data from API/Firebase
      // මෙතනදි අදාල customer ගේ bookings, points etc ගන්න

      if (mounted) {
        setState(() => _isLoading = false);
        print('✅ Customer data loaded successfully');
      }
    } catch (e) {
      print('❌ Error loading customer data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔥 Setup notification listeners
  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 New message: ${message.data}');

        if (message.data['type'] == 'booking_confirmed') {
          _showBookingUpdateAlert(message, 'confirmed');
          setState(() {
            _upcomingBookings++;
          });
        } else if (message.data['type'] == 'booking_reminder') {
          _showReminderAlert(message);
        } else if (message.data['type'] == 'special_offer') {
          _showOfferAlert(message);
        }
      });
    } catch (e) {
      print('❌ Error setting up notification listeners: $e');
    }
  }

  // 🔥 Show booking update alert
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
                color: type == 'confirmed' 
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                type == 'confirmed' ? Icons.check_circle : Icons.info,
                color: type == 'confirmed' ? Colors.green : Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Text(type == 'confirmed' ? 'Booking Confirmed!' : 'Booking Update'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.notification?.title ?? 'Appointment Update'),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ??
                  'Your booking has been ${type == 'confirmed' ? 'confirmed' : 'updated'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewMyBookings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  // 🔥 Show reminder alert
  void _showReminderAlert(RemoteMessage message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message.notification?.body ?? 'Upcoming appointment in 1 hour'),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: _viewMyBookings,
        ),
      ),
    );
  }

  // 🔥 Show offer alert
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
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_offer, color: Colors.amber),
            ),
            const SizedBox(width: 12),
            const Text('Special Offer!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.notification?.title ?? 'New Offer Available'),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ?? 'Check out our latest deals',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewOffers();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('View Offer'),
          ),
        ],
      ),
    );
  }

  // 🔥 Enable notifications
  Future<void> _enableNotifications() async {
    setState(() => _showPermissionCard = false);

    try {
      final canAsk = await _permissionManager.canAskSystemPermission();

      if (!canAsk) {
        _showSettingsDialog();
        return;
      }

      await _permissionService.requestPermissionAtAction(
        context: context,
        action: 'customer_dashboard',
        customTitle: '🔔 Get Booking Updates',
        customMessage:
            'Get instant notifications for booking confirmations, reminders, and special offers',
        onGranted: () async {
          await _permissionManager.markPermissionGranted();
          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Notifications enabled!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        onDenied: () async {
          await _permissionManager.markPermissionDenied(permanent: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can enable later from settings'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
      );
    } catch (e) {
      print('❌ Error enabling notifications: $e');
    }
  }

  // 🔥 Show settings dialog
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔔 Notifications Disabled'),
        content: const Text(
          'To enable notifications, please go to your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _permissionService.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // 🔥 Handle Not Now
  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('customer_dashboard');
  }

  // 🔥 Navigation methods
  void _viewMyBookings() {
    context.push('/customer/bookings');
  }

  void _bookAppointment() {
    context.push('/customer/book-appointment');
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

  void _viewBookingDetails(String customerName) {
    // TODO: Navigate to booking details
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing booking details'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _rescheduleBooking() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reschedule Appointment'),
        content: const Text('Select new date and time'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Appointment rescheduled'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _cancelBooking() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: const Text('Are you sure you want to cancel this appointment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _upcomingBookings--;
                _cancelledBookings++;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Appointment cancelled'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _applyOffer(String code) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Offer code "$code" applied!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 🔥 Open drawer method
  void _openDrawer() {
    try {
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
        print('✅ Drawer opened via GlobalKey');
      } else {
        Scaffold.of(context).openDrawer();
        print('✅ Drawer opened via Scaffold.of');
      }
    } catch (e) {
      print('❌ Error opening drawer: $e');
      _showMenuDialog();
    }
  }

  // 🔥 Emergency menu dialog
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
              ListTile(
                leading: const Icon(Icons.dashboard, color: Colors.blue),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.green),
                title: const Text('My Bookings'),
                onTap: () {
                  Navigator.pop(context);
                  _viewMyBookings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.book_online, color: Colors.purple),
                title: const Text('Book Appointment'),
                onTap: () {
                  Navigator.pop(context);
                  _bookAppointment();
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: const Text('Favorites'),
                onTap: () {
                  Navigator.pop(context);
                  _viewFavoriteBarbers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_offer, color: Colors.amber),
                title: const Text('Offers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewOffers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard, color: Colors.green),
                title: const Text('Loyalty Program'),
                onTap: () {
                  Navigator.pop(context);
                  _viewLoyaltyProgram();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/customer/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(context);
                  _logout(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // 🔥 Logout
  Future<void> _logout(BuildContext context) async {
    showLogoutConfirmation(
      context,
      onLogoutConfirmed: () async {
        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
          ),
        );

        try {
          await SessionManager.logoutForContinue();
          appState.refreshState();

          if (context.mounted) {
            Navigator.pop(context); // Close loading
            context.go('/');
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context); // Close loading
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Logout failed: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  // 🔥 Build offer card
  Widget _buildOfferCard(Map<String, dynamic> offer) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade300, Colors.orange.shade300],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer['title'],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            offer['description'],
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  offer['code'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                onPressed: () => _applyOffer(offer['code']),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🔥 Build favorite barber card
  Widget _buildFavoriteBarberCard(Map<String, dynamic> barber) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
            child: Text(
              barber['name'][0],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            barber['name'],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            barber['specialty'],
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 14),
              const SizedBox(width: 2),
              Text(
                '${barber['rating']}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                padding: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Book', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,

      appBar: AppBar(
        title: const Text('Customer Dashboard'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer,
          tooltip: 'Menu',
          iconSize: 28,
        ),

        actions: [
          // Book Appointment button
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _bookAppointment,
            tooltip: 'Book Appointment',
          ),
          
          // Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _viewMyBookings,
              ),
              if (_upcomingBookings > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$_upcomingBookings',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),

          // Refresh button
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),

      // Drawer
      drawer: SideMenu(
        userRole: 'customer',
        userName: _customerName,
        // userEmail: _customerEmail,
        profileImageUrl: _customerImage,
        onMenuItemSelected: () {
          _loadData();
        },
      ),

      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFFFF6B8B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // 🔥 PERMISSION CARD
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: _enableNotifications,
                        onNotNow: _handleNotNow,
                        title: '🔔 Get Booking Updates',
                        message:
                            'Get instant notifications for booking confirmations and special offers',
                        compact: false,
                      ),

                    // Welcome Message with Profile
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                            backgroundImage: _customerImage != null
                                ? NetworkImage(_customerImage!)
                                : null,
                            child: _customerImage == null
                                ? Text(
                                    _customerName.isNotEmpty
                                        ? _customerName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF6B8B),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome back,',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  _customerName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _customerEmail,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Loyalty Points Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple.shade400, Colors.purple.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Loyalty Points',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  '$_loyaltyPoints pts',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Gold Member',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Stats Cards Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Upcoming',
                              value: '$_upcomingBookings',
                              icon: Icons.calendar_today,
                              color: Colors.blue,
                              subtitle: 'Appointments',
                              onTap: _viewMyBookings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Completed',
                              value: '$_completedBookings',
                              icon: Icons.check_circle,
                              color: Colors.green,
                              subtitle: 'All time',
                              onTap: _viewMyBookings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Total Spent',
                              value: 'Rs. $_totalSpent',
                              icon: Icons.currency_rupee,
                              color: Colors.purple,
                              subtitle: 'Lifetime',
                              onTap: _viewLoyaltyProgram,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Quick Actions
                    const SectionHeader(
                      title: 'Quick Actions',
                      actionText: '',
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.book_online,
                              label: 'Book Now',
                              color: Colors.blue,
                              onTap: _bookAppointment,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.history,
                              label: 'History',
                              color: Colors.purple,
                              onTap: _viewMyBookings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.local_offer,
                              label: 'Offers',
                              color: Colors.amber,
                              onTap: _viewOffers,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Upcoming Bookings Section
                    const SectionHeader(
                      title: 'Upcoming Bookings',
                      actionText: 'View All',
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _upcomingBookings > 0
                          ? Column(
                              children: [
                                BookingTile(
                                  customerName: 'You',
                                  serviceName: 'Hair Cut & Beard Trim',
                                  time: 'Tomorrow, 10:30 AM',
                                  status: 'Confirmed',
                                  statusColor: Colors.green,
                                  barberName: 'Kamal',
                                  price: 1800,
                                  onTap: () => _viewBookingDetails('Your Booking'),
                                ),
                                BookingTile(
                                  customerName: 'You',
                                  serviceName: 'Facial Treatment',
                                  time: 'Mar 15, 2:00 PM',
                                  status: 'Pending',
                                  statusColor: Colors.orange,
                                  barberName: 'Sunil',
                                  price: 2500,
                                  onTap: () => _viewBookingDetails('Your Booking'),
                                ),
                              ],
                            )
                          : Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No upcoming bookings',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: _bookAppointment,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF6B8B),
                                    ),
                                    child: const Text('Book Now'),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    const SizedBox(height: 16),

                    // Special Offers Section
                    const SectionHeader(
                      title: 'Special Offers',
                      actionText: 'View All',
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _offers.length,
                        itemBuilder: (context, index) {
                          return _buildOfferCard(_offers[index]);
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Favorite Barbers Section
                    const SectionHeader(
                      title: 'Favorite Barbers',
                      actionText: 'View All',
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 210,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _favoriteBarbers.length,
                        itemBuilder: (context, index) {
                          return _buildFavoriteBarberCard(_favoriteBarbers[index]);
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Recent Activity Summary
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
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildActivityItem(
                                  icon: Icons.check_circle,
                                  label: 'Completed',
                                  value: '$_completedBookings',
                                  color: Colors.green,
                                ),
                              ),
                              Expanded(
                                child: _buildActivityItem(
                                  icon: Icons.cancel,
                                  label: 'Cancelled',
                                  value: '$_cancelledBookings',
                                  color: Colors.red,
                                ),
                              ),
                              Expanded(
                                child: _buildActivityItem(
                                  icon: Icons.star,
                                  label: 'Points Earned',
                                  value: '$_loyaltyPoints',
                                  color: Colors.amber,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Notification Status
                    if (_hasPermission)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_active,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Notifications active',
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
              ),
            ),
    );
  }

  // 🔥 Build quick action button
  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
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
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 Build activity item
  Widget _buildActivityItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}