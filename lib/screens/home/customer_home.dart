import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:go_router/go_router.dart';
import '../authantication/command/multi_continue_screen.dart';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Customer specific data
  int _upcomingBookings = 2;
  int _pastBookings = 8;
  int _favoriteSalons = 3;
  int _pendingPayments = 1;
  int _loyaltyPoints = 350;

  // Selected tab for bookings
  int _selectedBookingTab = 0;

  @override
  void initState() {
    super.initState();

    // Small delay to ensure everything is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });

    _setupNotificationListeners();
  }

  // 🔥 Load initial data with proper error handling
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      print('📱 Customer _loadData started');

      // Check permission status
      _hasPermission = await _notificationService.hasPermission();
      print('📱 hasPermission from system: $_hasPermission');

      // Check if should show permission card
      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'customer_home',
        );
        print('📱 shouldShowPermissionCard: $_showPermissionCard');
      } else {
        _showPermissionCard = false;
      }

      // Get permission stats for debugging
      final stats = await _permissionManager.getPermissionStats();
      print('📊 Permission Stats: $stats');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ Error loading data: $e');
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

  // 🔥 Setup notification listeners for customer
  void _setupNotificationListeners() {
    try {
      // Listen for booking updates
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Received message: ${message.data}');

        if (message.data['type'] == 'booking_confirmed') {
          _showBookingConfirmedAlert(message);
          setState(() {
            _upcomingBookings++;
          });
        } else if (message.data['type'] == 'booking_reminder') {
          _showReminderAlert(message);
        } else if (message.data['type'] == 'promotion') {
          _showPromotionAlert(message);
        }
      });

      print('📱 Customer notification listeners setup complete');
    } catch (e) {
      print('❌ Error setting up notification listeners: $e');
    }
  }

  // 🔥 Show booking confirmed alert
  void _showBookingConfirmedAlert(RemoteMessage message) {
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
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green),
            ),
            const SizedBox(width: 12),
            const Text('Booking Confirmed!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.notification?.title ?? 'Appointment Confirmed'),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ??
                  'Your appointment has been confirmed',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewBookings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9C27B0),
            ),
            child: const Text('View Booking'),
          ),
        ],
      ),
    );
  }

  // 🔥 Show reminder alert
  void _showReminderAlert(RemoteMessage message) {
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
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.access_time, color: Colors.orange),
            ),
            const SizedBox(width: 12),
            const Text('Appointment Reminder!'),
          ],
        ),
        content: Text(message.notification?.body ?? 'Your appointment is in 30 minutes'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // 🔥 Show promotion alert
  void _showPromotionAlert(RemoteMessage message) {
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
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_offer, color: Colors.purple),
            ),
            const SizedBox(width: 12),
            const Text('Special Offer!'),
          ],
        ),
        content: Text(message.notification?.body ?? '20% off on your next visit'),
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
              backgroundColor: const Color(0xFF9C27B0),
            ),
            child: const Text('View Offer'),
          ),
        ],
      ),
    );
  }

  // 🔥 Enable notifications with proper flow
  Future<void> _enableNotifications() async {
    print('🔔 _enableNotifications called');

    setState(() => _showPermissionCard = false);

    try {
      final canAsk = await _permissionManager.canAskSystemPermission();
      print('🔍 canAskSystemPermission: $canAsk');

      if (!canAsk) {
        _showSettingsDialog();
        return;
      }

      await _permissionService.requestPermissionAtAction(
        context: context,
        action: 'customer_home',
        customTitle: '🔔 Get Booking Updates',
        customMessage:
            'Get instant notifications about your appointments and special offers',
        onGranted: () async {
          print('✅ User granted permission');

          await _permissionManager.markPermissionGranted();

          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '✅ Notifications enabled! You\'ll get booking updates',
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }

          _sendWelcomeNotification();
        },
        onDenied: () async {
          print('❌ User denied permission');

          await _permissionManager.markPermissionDenied(permanent: false);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'You can enable notifications later from settings',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
      );
    } catch (e) {
      print('❌ Error enabling notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🔥 Show settings dialog
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔔 Notifications Disabled'),
        content: const Text(
          'You have denied notifications multiple times. '
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
              backgroundColor: const Color(0xFF9C27B0),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // 🔥 Send welcome notification
  void _sendWelcomeNotification() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '📨 Welcome! You\'ll now receive booking notifications',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    });
  }

  // 🔥 Handle not now
  Future<void> _handleNotNow() async {
    print('👋 User clicked Not Now');

    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('customer_home');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can enable notifications anytime from settings'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // 🔥 View bookings
  void _viewBookings() {
    print('📅 Navigating to bookings');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigating to my bookings...'),
        duration: Duration(seconds: 1),
      ),
    );
    // TODO: Add actual navigation to bookings screen
  }

  // 🔥 Book new appointment
  void _bookNewAppointment() {
    print('📅 Navigating to booking');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting new booking...'),
        duration: Duration(seconds: 1),
      ),
    );
    // TODO: Add actual navigation to booking screen
  }

  // 🔥 View favorite salons
  void _viewFavorites() {
    print('❤️ Navigating to favorites');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigating to favorite salons...'),
        duration: Duration(seconds: 1),
      ),
    );
    // TODO: Add actual navigation to favorites screen
  }

  // 🔥 View offers
  void _viewOffers() {
    print('🎁 Navigating to offers');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigating to offers...'),
        duration: Duration(seconds: 1),
      ),
    );
    // TODO: Add actual navigation to offers screen
  }

  // 🔥 Send test notification (for debugging)
  Future<void> _sendTestNotification() async {
    print('🔍 Sending test notification...');

    if (!_hasPermission) {
      setState(() {
        _showPermissionCard = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable notifications first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📤 Sending test notification...'),
        duration: Duration(seconds: 1),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('📨 Test Notification'),
            content: const Text(
              'This is how booking notifications will appear.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  // 🔥 Show permission stats
  Future<void> _showPermissionStats() async {
    final stats = await _permissionManager.getPermissionStats();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 Permission Stats'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow('System Permission', stats['has_system_permission']),
              _buildStatRow('Stored Permission', stats['has_stored_permission']),
              const Divider(),
              _buildStatRow('Last Screen', stats['last_screen'] ?? 'none'),
              _buildStatRow('User Action', stats['user_action'] ?? 'none'),
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

  // Helper for stats dialog
  Widget _buildStatRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.toString() ?? 'null',
              style: TextStyle(
                color: value == true
                    ? Colors.green
                    : value == false
                    ? Colors.red
                    : Colors.blue,
              ),
            ),
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
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(0),
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );

      try {
        // Call your logout function
        await SessionManager.logoutForContinue();

        // Close loading dialog safely
        if (context.mounted) {
          // Check if we can pop before trying
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }

        // Update app state
        await appState.refreshState();

        // Navigate to login/splash screen using post frame callback
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              // Clear all routes and go to login
              context.go('/');
            }
          });
        }
      } catch (e) {
        // Close loading dialog safely
        if (context.mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }

        // Show error message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logout failed: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home c'),
        backgroundColor: const Color(0xFF9C27B0),
        foregroundColor: Colors.white,
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report),
              onPressed: _showPermissionStats,
              tooltip: 'Permission Stats',
            ),

          // 🔔 Notification bell with badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _viewBookings,
              ),
              if (_upcomingBookings > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
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

          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendTestNotification,
              tooltip: 'Send test notification',
            ),

          IconButton(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF9C27B0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // 🔥 PERMISSION CARD (if needed)
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: _enableNotifications,
                        onNotNow: _handleNotNow,
                        title: '🔔 Get Booking Updates',
                        message:
                            'Get instant notifications about your appointments and special offers',
                        compact: false,
                      ),

                    // Welcome Section with Loyalty Points
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9C27B0).withOpacity(0.1),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Welcome back,',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const Text(
                            'Valued Customer',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  '$_loyaltyPoints Loyalty Points',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Stats Cards
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Upcoming',
                                  value: '$_upcomingBookings',
                                  icon: Icons.calendar_today,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Completed',
                                  value: '$_pastBookings',
                                  icon: Icons.history,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Favorites',
                                  value: '$_favoriteSalons',
                                  icon: Icons.favorite,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Pending',
                                  value: '$_pendingPayments',
                                  icon: Icons.payment,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Quick Actions
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.add_circle_outline,  // Fixed: changed from calendar_add_on
                                  label: 'Book Now',
                                  color: Colors.purple,
                                  onTap: _bookNewAppointment,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.favorite,
                                  label: 'Favorites',
                                  color: Colors.red,
                                  onTap: _viewFavorites,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.local_offer,
                                  label: 'Offers',
                                  color: Colors.orange,
                                  onTap: _viewOffers,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.history,
                                  label: 'History',
                                  color: Colors.blue,
                                  onTap: _viewBookings,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // My Bookings Section with Tabs
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Bookings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Custom Tab Bar
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildTabButton(
                                    'Upcoming',
                                    0,
                                    _selectedBookingTab == 0,
                                  ),
                                ),
                                Expanded(
                                  child: _buildTabButton(
                                    'Past',
                                    1,
                                    _selectedBookingTab == 1,
                                  ),
                                ),
                                Expanded(
                                  child: _buildTabButton(
                                    'Cancelled',
                                    2,
                                    _selectedBookingTab == 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Booking List based on selected tab
                          if (_selectedBookingTab == 0)
                            ...List.generate(
                              2,
                              (index) => _buildBookingTile(index, isUpcoming: true),
                            )
                          else if (_selectedBookingTab == 1)
                            ...List.generate(
                              3,
                              (index) => _buildBookingTile(index, isUpcoming: false),
                            )
                          else
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.cancel,
                                      size: 48,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No cancelled bookings',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          
                          // View All Button
                          Center(
                            child: TextButton(
                              onPressed: _viewBookings,
                              child: const Text('View All Bookings'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Recommended Salons
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recommended for You',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton(
                                onPressed: _viewFavorites,
                                child: const Text('View All'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: 3,
                              itemBuilder: (context, index) {
                                return _buildSalonCard(index);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Permission status indicator
                    if (_hasPermission)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
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

  // 🔥 Build stat card
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // 🔥 Build tab button
  Widget _buildTabButton(String label, int index, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedBookingTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9C27B0) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 🔥 Build booking tile
  Widget _buildBookingTile(int index, {required bool isUpcoming}) {
    final upcomingSalons = ['Glamour Salon', 'Style Studio', 'Beauty Hub'];
    final pastSalons = ['Luxury Spa', 'Style Studio', 'Glamour Salon', 'Beauty Hub'];
    final dates = ['Tomorrow, 10:30 AM', 'Feb 25, 2:00 PM', 'Feb 20, 4:30 PM'];
    final services = ['Hair Cut & Styling', 'Facial Treatment', 'Manicure & Pedicure'];
    final status = isUpcoming ? 'Confirmed' : 'Completed';
    final statusColor = isUpcoming ? Colors.green : Colors.grey;

    final salonName = isUpcoming 
        ? upcomingSalons[index % upcomingSalons.length]
        : pastSalons[index % pastSalons.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF9C27B0).withOpacity(0.1),
          child: Text(
            salonName[0],
            style: const TextStyle(
              color: Color(0xFF9C27B0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          salonName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(services[index % services.length]),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  dates[index % dates.length],
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: isUpcoming
            ? IconButton(
                icon: const Icon(Icons.cancel_outlined),  // Fixed: changed from cancel_outline
                color: Colors.red,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Cancel Booking?'),
                      content: const Text('Are you sure you want to cancel this appointment?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('No'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Booking cancelled'),
                                backgroundColor: Colors.red,
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
                },
              )
            : Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
        onTap: () {
          print('📅 Tapped on booking: $salonName');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Viewing booking details for $salonName'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }

  // 🔥 Build action button
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 Build salon card
  Widget _buildSalonCard(int index) {
    final salons = ['Glamour Salon', 'Style Studio', 'Luxury Spa'];
    final ratings = [4.8, 4.6, 4.9];
    final distances = ['0.5 km', '1.2 km', '2.0 km'];
    final images = [
      Icons.spa,
      Icons.content_cut,
      Icons.face,
    ];

    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF9C27B0).withOpacity(0.2),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Center(
                child: Icon(
                  images[index],
                  size: 50,
                  color: const Color(0xFF9C27B0),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    salons[index],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 12, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        ratings[index].toString(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.location_on, size: 10, color: Colors.grey[600]),
                      const SizedBox(width: 2),
                      Text(
                        distances[index],
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _bookNewAppointment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9C27B0),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 28),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('Book', style: TextStyle(fontSize: 11)),
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