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

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Employee specific data
  int _assignedTasks = 5;
  int _completedToday = 3;
  int _pendingTasks = 2;
  int _upcomingAppointments = 4;

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
      print('📱 Employee _loadData started');

      // Check permission status
      _hasPermission = await _notificationService.hasPermission();
      print('📱 hasPermission from system: $_hasPermission');

      // Check if should show permission card
      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'employee_dashboard',
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

  // 🔥 Setup notification listeners for employee
  void _setupNotificationListeners() {
    try {
      // Listen for new task assignments
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Received message: ${message.data}');

        if (message.data['type'] == 'new_task') {
          _showNewTaskAlert(message);
          setState(() {
            _assignedTasks++;
            _pendingTasks++;
          });
        } else if (message.data['type'] == 'booking_reminder') {
          _showReminderAlert(message);
        }
      });

      print('📱 Employee notification listeners setup complete');
    } catch (e) {
      print('❌ Error setting up notification listeners: $e');
    }
  }

  // 🔥 Show new task alert
  void _showNewTaskAlert(RemoteMessage message) {
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
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Text('New Task Assigned!'),
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
                  'You have a new task to complete',
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
              _viewTasks();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1877F3),
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
            const Text('Upcoming Appointment!'),
          ],
        ),
        content: Text(message.notification?.body ?? 'Appointment in 30 minutes'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
        action: 'employee_dashboard',
        customTitle: '🔔 Get Task Notifications',
        customMessage:
            'Get instant notifications when new tasks are assigned',
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
                  '✅ Notifications enabled! You\'ll get task alerts',
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
              backgroundColor: const Color(0xFF1877F3),
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
              '📨 Welcome! You\'ll now receive task notifications',
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
    await _permissionManager.markPermissionShown('employee_dashboard');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can enable notifications anytime from settings'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // 🔥 View tasks
  void _viewTasks() {
    print('📋 Navigating to tasks');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigating to tasks...'),
        duration: Duration(seconds: 1),
      ),
    );
    // TODO: Add actual navigation to tasks screen
  }

  // 🔥 View schedule
  void _viewSchedule() {
    print('📅 Navigating to schedule');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigating to schedule...'),
        duration: Duration(seconds: 1),
      ),
    );
    // TODO: Add actual navigation to schedule screen
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
              'This is how task notifications will appear.',
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
        title: const Text('Employee Dashboard'),
        backgroundColor: const Color(0xFF1877F3),
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
                onPressed: _viewTasks,
              ),
              if (_assignedTasks > 0)
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
                      '$_assignedTasks',
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
              color: const Color(0xFF1877F3),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // 🔥 PERMISSION CARD (if needed)
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: _enableNotifications,
                        onNotNow: _handleNotNow,
                        title: '🔔 Get Task Notifications',
                        message:
                            'Get instant notifications when new tasks are assigned',
                        compact: false,
                      ),

                    // Welcome Message
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F3).withOpacity(0.1),
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
                            'Employee Name',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '🟢 Available for work',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
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
                                  title: 'Completed Today',
                                  value: '$_completedToday',
                                  icon: Icons.check_circle,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Pending Tasks',
                                  value: '$_pendingTasks',
                                  icon: Icons.pending,
                                  color: Colors.orange,
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
                                  title: 'Upcoming',
                                  value: '$_upcomingAppointments',
                                  icon: Icons.calendar_today,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                flex: 1,
                                child: _buildStatCard(
                                  title: 'Total Tasks',
                                  value: '${_completedToday + _pendingTasks}',
                                  icon: Icons.assignment,
                                  color: Colors.purple,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Today's Schedule Section
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Today's Schedule",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton(
                                onPressed: _viewSchedule,
                                child: const Text('View All'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(
                            3,
                            (index) => _buildScheduleTile(index),
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
                                  icon: Icons.task_alt,
                                  label: 'Mark Available',
                                  color: Colors.green,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Status updated to Available'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.access_time,
                                  label: 'Break',
                                  color: Colors.orange,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Taking a break'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.event_available,
                                  label: 'Check Schedule',
                                  color: Colors.blue,
                                  onTap: _viewSchedule,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.history,
                                  label: 'History',
                                  color: Colors.purple,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Navigating to history'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
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

  // 🔥 Build schedule tile
  Widget _buildScheduleTile(int index) {
    final times = ['10:30 AM', '2:00 PM', '4:30 PM'];
    final customers = ['Mrs. Perera', 'Mr. Silva', 'Ms. Weerasinghe'];
    final services = ['Hair Cut', 'Facial', 'Massage'];
    final status = ['Confirmed', 'In Progress', 'Upcoming'];
    final statusColors = [Colors.green, Colors.blue, Colors.orange];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1877F3).withOpacity(0.1),
          child: Text(
            customers[index][0],
            style: const TextStyle(
              color: Color(0xFF1877F3),
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
        trailing: IconButton(
          icon: const Icon(Icons.check_circle_outline),
          color: Colors.green,
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Marked ${customers[index]}\'s service as completed'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
        onTap: () {
          print('📅 Tapped on schedule: ${customers[index]}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Viewing ${customers[index]}\'s details'),
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
}