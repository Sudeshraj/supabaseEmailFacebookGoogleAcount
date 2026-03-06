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

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  // 🔑 GlobalKey for scaffold - මේකෙන් 100% වැඩ කරනවා
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Dashboard data
  int _pendingBookings = 3;
  final int _todayAppointments = 8;
  final int _totalRevenue = 24500;
  final int _totalCustomers = 156;
  final int _activeBarbers = 5;

  @override
  void initState() {
    super.initState();

    // කුඩා delay එකකින් පසුව data load කරන්න
    // Debug current role
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final role = await SessionManager.getCurrentRole();
      final appStateRole = appState.currentRole;
      debugPrint('🔍 OwnerDashboard - SessionManager role: $role');
      debugPrint('🔍 OwnerDashboard - AppState role: $appStateRole');
    });

    _loadData();
    _setupNotificationListeners();
    debugPrint('🔄 OwnerDashboard initState completed');
  }

  // 🔥 Load initial data
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      print('📊 Loading dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'owner_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      if (mounted) {
        setState(() => _isLoading = false);
        print('✅ Data loaded successfully');
      }
    } catch (e) {
      print('❌ Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);

        // Error message
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

        if (message.data['type'] == 'new_booking') {
          _showNewBookingAlert(message);
          setState(() {
            _pendingBookings++;
          });
        }
      });
    } catch (e) {
      print('❌ Error setting up notification listeners: $e');
    }
  }

  // 🔥 Show new booking alert
  void _showNewBookingAlert(RemoteMessage message) {
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
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_available, color: Colors.green),
            ),
            const SizedBox(width: 12),
            const Text('New Booking!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.notification?.title ?? 'New Appointment'),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ??
                  'A customer has booked an appointment',
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
              _viewBookings();
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
        action: 'owner_dashboard',
        customTitle: '🔔 Get Booking Alerts',
        customMessage:
            'Get instant notifications when customers book appointments',
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
    await _permissionManager.markPermissionShown('owner_dashboard');
  }

  // 🔥 Navigation methods
  void _viewBookings() {
    context.push('/owner/appointments');
  }

  void _viewAllCustomers() {
    context.push('/owner/customers');
  }

  void _viewBarbers() {
    context.push('/owner/barbers');
  }

  void _viewRevenue() {
    context.push('/owner/revenue');
  }

  void _viewBookingDetails(String customerName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing $customerName\'s booking'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // 🔥 Open drawer method
  void _openDrawer() {
    try {
      // Method 1: GlobalKey (most reliable)
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
        print('✅ Drawer opened via GlobalKey');
      }
      // Method 2: Scaffold.of (fallback)
      else {
        Scaffold.of(context).openDrawer();
        print('✅ Drawer opened via Scaffold.of');
      }
    } catch (e) {
      print('❌ Error opening drawer: $e');

      // Emergency fallback - show menu items in dialog
      _showMenuDialog();
    }
  }

  // 🔥 Emergency menu dialog (drawer open nathnam)
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
                onTap: () {
                  Navigator.pop(context);
                  // Already in dashboard
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.green),
                title: const Text('Appointments'),
                onTap: () {
                  Navigator.pop(context);
                  _viewBookings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people, color: Colors.purple),
                title: const Text('Customers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewAllCustomers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_cut, color: Colors.orange),
                title: const Text('Barbers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewBarbers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: const Text('Revenue'),
                onTap: () {
                  Navigator.pop(context);
                  _viewRevenue();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/owner/settings');
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
        // Show loading
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

  // 🔥 Build quick action button
  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, // 🔑 මේක හරිම වැදගත්!

      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,

        // 🟢 Menu button - 100% working
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer, // කෙලින්ම method call
          tooltip: 'Menu',
          iconSize: 28,
        ),

        actions: [
          // ➕ Add Barber Button (Notification icon එක ළඟ)
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () {
              context.push('/owner/add-barber');
            },
            tooltip: 'Add Barber',
          ),
          // 🔔 Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _viewBookings,
              ),
              if (_pendingBookings > 0)
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
                      '$_pendingBookings',
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

      // 🟢 Drawer - SideMenu widget
      drawer: SideMenu(
        userRole: 'owner',
        userName: 'Salon Owner',
        // userEmail: 'owner@salon.com',
        profileImageUrl: null,
        onMenuItemSelected: () {
          // Refresh data when returning from menu
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
                        title: '🔔 Get Booking Alerts',
                        message:
                            'Get instant notifications when customers book appointments',
                        compact: false,
                      ),

                    // Welcome Message
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const Text(
                                'Salon Owner 👑',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF6B8B,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Color(0xFFFF6B8B),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'March 4, 2026',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFFF6B8B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Stats Cards Row 1
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Today\'s Appointments',
                              value: '$_todayAppointments',
                              icon: Icons.calendar_today,
                              color: Colors.blue,
                              percentageChange: 12.5,
                              onTap: _viewBookings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Pending Bookings',
                              value: '$_pendingBookings',
                              icon: Icons.pending_actions,
                              color: Colors.orange,
                              subtitle: 'Awaiting confirmation',
                              onTap: _viewBookings,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Stats Cards Row 2
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Total Customers',
                              value: '$_totalCustomers',
                              icon: Icons.people,
                              color: Colors.purple,
                              percentageChange: 8.2,
                              onTap: _viewAllCustomers,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Active Barbers',
                              value: '$_activeBarbers',
                              icon: Icons.content_cut,
                              color: Colors.green,
                              subtitle: '3 working today',
                              onTap: _viewBarbers,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Revenue Card (full width)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DashboardStatCard(
                        title: 'Today\'s Revenue',
                        value: 'Rs. $_totalRevenue',
                        icon: Icons.currency_rupee,
                        color: Colors.green,
                        fullWidth: true,
                        percentageChange: 5.0,
                        showProgress: true,
                        onTap: _viewRevenue,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Quick Actions
                    const SectionHeader(
                      title: 'Quick Actions',
                      actionText: 'See All',
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildQuickAction(
                            icon: Icons.add_circle_outline,
                            label: 'New Booking',
                            color: Colors.blue,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'New Booking feature coming soon',
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _buildQuickAction(
                            icon: Icons.person_add_outlined,
                            label: 'Add Barber',
                            color: Colors.purple,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Add Barber feature coming soon',
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _buildQuickAction(
                            icon: Icons.inventory_2_outlined,
                            label: 'Add Service',
                            color: Colors.orange,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Add Service feature coming soon',
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Recent Bookings Section
                    const SectionHeader(
                      title: 'Recent Bookings',
                      actionText: 'View All',
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          BookingTile(
                            customerName: 'Nimal Perera',
                            serviceName: 'Hair Cut',
                            time: '10:30 AM',
                            status: 'Confirmed',
                            statusColor: Colors.green,
                            barberName: 'Kamal',
                            price: 1500,
                            onTap: () => _viewBookingDetails('Nimal Perera'),
                          ),
                          BookingTile(
                            customerName: 'Kamal Silva',
                            serviceName: 'Facial',
                            time: '2:00 PM',
                            status: 'Pending',
                            statusColor: Colors.orange,
                            barberName: 'Sunil',
                            price: 2500,
                            onTap: () => _viewBookingDetails('Kamal Silva'),
                          ),
                          BookingTile(
                            customerName: 'Sunil Weerasinghe',
                            serviceName: 'Massage',
                            time: '4:30 PM',
                            status: 'Completed',
                            statusColor: Colors.blue,
                            barberName: 'Nuwan',
                            price: 3000,
                            onTap: () =>
                                _viewBookingDetails('Sunil Weerasinghe'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

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
}
