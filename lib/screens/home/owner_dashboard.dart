import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/multi_continue_screen.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();
  
  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;
  
  // Sample booking data
  int _pendingBookings = 3;
  int _todayAppointments = 8;
  int _totalRevenue = 24500;

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
      print('📱 _loadData started');
      
      // Check permission status
      _hasPermission = await _notificationService.hasPermission();
      print('📱 hasPermission from system: $_hasPermission');
      
      // Check if should show permission card
      if (!_hasPermission) {
        // IMPORTANT: Use correct screen name
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard('owner_dashboard');
        print('📱 shouldShowPermissionCard: $_showPermissionCard');
      } else {
        _showPermissionCard = false;
        print('📱 Already has permission - hiding card');
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
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔥 Setup notification listeners for owner
  void _setupNotificationListeners() {
    try {
      // Listen for new booking notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Received message: ${message.data}');
        
        if (message.data['type'] == 'new_booking') {
          _showNewBookingAlert(message);
          
          // Update pending bookings count
          setState(() {
            _pendingBookings++;
          });
        }
      });
      
      print('📱 Notification listeners setup complete');
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
                color: Colors.green.withOpacity(0.1),
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
              message.notification?.body ?? 'A customer has booked an appointment',
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

  // 🔥 Enable notifications with proper flow
  Future<void> _enableNotifications() async {
    print('🔔 _enableNotifications called');
    
    setState(() => _showPermissionCard = false);
    
    try {
      // Check if we can ask for system permission
      final canAsk = await _permissionManager.canAskSystemPermission();
      print('🔍 canAskSystemPermission: $canAsk');
      
      if (!canAsk) {
        // Show settings dialog
        _showSettingsDialog();
        return;
      }
      
      await _permissionService.requestPermissionAtAction(
        context: context,
        action: 'owner_dashboard',
        customTitle: '🔔 Get Booking Alerts',
        customMessage: 'Get instant notifications when customers book appointments',
        onGranted: () async {
          print('✅ User granted permission');
          
          // Mark as granted in PermissionManager
          await _permissionManager.markPermissionGranted();
          
          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Notifications enabled! You\'ll get booking alerts'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
          
          // Send test notification after permission granted
          _sendWelcomeNotification();
        },
        onDenied: () async {
          print('❌ User denied permission');
          
          // Mark as denied
          await _permissionManager.markPermissionDenied(permanent: false);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can enable notifications later from settings'),
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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
          'To enable notifications, please go to your device settings.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Open app settings (platform specific)
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

  // 🔥 Send welcome notification
  void _sendWelcomeNotification() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📨 Welcome! You\'ll now receive booking notifications'),
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
    await _permissionManager.markPermissionShown('owner_dashboard');
    
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
    
    // Navigate to bookings screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigating to bookings...'),
        duration: Duration(seconds: 1),
      ),
    );
    
    // TODO: Add actual navigation
    // Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingsScreen()));
  }

  // 🔥 Send test notification (for debugging)
  Future<void> _sendTestNotification() async {
    print('🔍 Sending test notification...');
    print('🔍 hasPermission: $_hasPermission');
    
    if (!_hasPermission) {
      // Show permission card if not enabled
      setState(() {
        _showPermissionCard = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable notifications first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Show sending indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📤 Sending test notification...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Simulate notification
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('📨 Test Notification'),
            content: const Text('This is how notifications will appear when customers book.'),
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
              _buildStatRow('Last Denied', stats['last_denied']?.toString() ?? 'never'),
              _buildStatRow('User Action', stats['user_action'] ?? 'none'),
              _buildStatRow('Permanent Deny', stats['permanent_deny']),
              const Divider(),
              const Text('Screen Counts:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(stats['screen_counts'] as Map<String, int>).entries.map(
                (e) => _buildStatRow(e.key, e.value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await _permissionManager.resetPermissionState();
              Navigator.pop(context);
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Permission state reset')),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
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
                color: value == true ? Colors.green : 
                       value == false ? Colors.red : 
                       Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 Logout
  Future<void> _logout(BuildContext context) async {
    try {
      print('🚪 Logging out...');
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      await Future.delayed(const Duration(milliseconds: 500));

      if (!context.mounted) return;

      Navigator.pop(context); // Close loading dialog
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ContinueScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      
      Navigator.pop(context); // Close loading dialog if open
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF1E2732),
          title: const Text(
            'Logout Failed 😕',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            e.toString(),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFF1877F3))),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        actions: [
          // Debug button (only in debug mode)
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
              if (_pendingBookings > 0)
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
          
          // Test notification button (debug only)
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
              color: const Color(0xFFFF6B8B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // 🔥 PERMISSION CARD (if needed)
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: _enableNotifications,
                        onNotNow: _handleNotNow,
                        title: '🔔 Get Booking Alerts',
                        message: 'Get instant notifications when customers book appointments',
                        compact: false,
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
                                  title: 'Today\'s Appointments',
                                  value: '$_todayAppointments',
                                  icon: Icons.calendar_today,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Pending Bookings',
                                  value: '$_pendingBookings',
                                  icon: Icons.pending_actions,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildStatCard(
                            title: 'Today\'s Revenue',
                            value: 'Rs. $_totalRevenue',
                            icon: Icons.currency_rupee,
                            color: Colors.green,
                            fullWidth: true,
                          ),
                        ],
                      ),
                    ),
                    
                    // Recent Bookings Section
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recent Bookings',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton(
                                onPressed: _viewBookings,
                                child: const Text('View All'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(3, (index) => _buildBookingTile(index)),
                        ],
                      ),
                    ),
                    
                    // Permission status indicator
                    if (_hasPermission)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
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
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 Build booking tile
  Widget _buildBookingTile(int index) {
    final customers = ['Nimal Perera', 'Kamal Silva', 'Sunil Weerasinghe'];
    final times = ['10:30 AM', '2:00 PM', '4:30 PM'];
    final services = ['Hair Cut', 'Facial', 'Massage'];
    final status = ['Confirmed', 'Pending', 'Completed'];
    final statusColors = [Colors.green, Colors.orange, Colors.blue];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFFF6B8B).withOpacity(0.1),
          child: Text(
            customers[index][0],
            style: const TextStyle(
              color: Color(0xFFFF6B8B),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customers[index],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${services[index]} • ${times[index]}'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColors[index].withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status[index],
                style: TextStyle(
                  fontSize: 10,
                  color: statusColors[index],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          print('📅 Tapped on booking: ${customers[index]}');
          // View booking details
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Viewing ${customers[index]}\'s booking'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }
}