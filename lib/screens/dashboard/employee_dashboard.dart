// lib/screens/employee/employee_dashboard.dart

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

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  // 🔑 GlobalKey for scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Employee Dashboard Data
  int _todaysAppointments = 5;
  int _completedToday = 3;
  int _pendingAppointments = 2;
  final int _totalCustomers = 45;
  final int _todayEarnings = 8500;
  final int _monthlyEarnings = 45000;
  final double _rating = 4.8;
  String _employeeName = 'John Doe';
  String _employeeRole = 'Senior Barber';

  // Break time status
  bool _isOnBreak = false;
  TimeOfDay? _breakStartTime;

  @override
  void initState() {
    super.initState();

    // Debug current role
  // Debug current role
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final role = await SessionManager.getCurrentRole();
    final appStateRole = appState.currentRole;
    debugPrint('🔍 EmployeeDashboard - SessionManager role: $role');
    debugPrint('🔍 EmployeeDashboard - AppState role: $appStateRole');
    
    // Load employee name - FIXED VERSION without getUserData
    try {
      final email = await SessionManager.getCurrentUserEmail();
      if (email != null && mounted) {
        // Get profile by email directly
        final profile = await SessionManager.getProfileByEmail(email);
        if (profile != null) {
          setState(() {
            _employeeName = profile['name'] ?? email.split('@').first;
            // Get role from profile or use current role
            final roles = profile['roles'] as List? ?? [];
            if (roles.isNotEmpty) {
              _employeeRole = roles.first.toString();
            } else {
              _employeeRole = role ?? 'Barber';
            }
          });
          debugPrint('✅ Loaded employee: $_employeeName ($_employeeRole)');
        } else {
          // Fallback to email
          setState(() {
            _employeeName = email.split('@').first;
            _employeeRole = role ?? 'Barber';
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading user data: $e');
    }
  });

  _loadData();
  _setupNotificationListeners();
  debugPrint('🔄 EmployeeDashboard initState completed');
  }

  // 🔥 Load initial data
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      print('📊 Loading employee dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'employee_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      // TODO: Fetch real data from API/Firebase
      // මෙතනදි අදාල employee ගේ data ගන්න

      if (mounted) {
        setState(() => _isLoading = false);
        print('✅ Employee data loaded successfully');
      }
    } catch (e) {
      print('❌ Error loading employee data: $e');
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

        if (message.data['type'] == 'new_booking_assigned') {
          _showNewAssignmentAlert(message);
          setState(() {
            _todaysAppointments++;
            _pendingAppointments++;
          });
        } else if (message.data['type'] == 'booking_reminder') {
          _showReminderAlert(message);
        }
      });
    } catch (e) {
      print('❌ Error setting up notification listeners: $e');
    }
  }

  // 🔥 Show new assignment alert
  void _showNewAssignmentAlert(RemoteMessage message) {
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
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_add, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Text('New Booking Assigned!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.notification?.title ?? 'New Appointment'),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ?? 'You have a new booking assigned',
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
              _viewMySchedule();
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
              child: Text(message.notification?.body ?? 'Upcoming appointment'),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: _viewMySchedule,
        ),
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
        action: 'employee_dashboard',
        customTitle: '🔔 Get Booking Updates',
        customMessage:
            'Get instant notifications for new bookings, reminders, and schedule changes',
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
    await _permissionManager.markPermissionShown('employee_dashboard');
  }

  // 🔥 Toggle break
  void _toggleBreak() {
    setState(() {
      _isOnBreak = !_isOnBreak;
      if (_isOnBreak) {
        _breakStartTime = TimeOfDay.now();
        // Show break started message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.free_breakfast, color: Colors.white),
                SizedBox(width: 8),
                Text('Break started at '),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        final breakEndTime = TimeOfDay.now();
        final breakDuration = _calculateBreakDuration(
          _breakStartTime!,
          breakEndTime,
        );

        // Show break ended message with duration
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Break ended • Duration: $breakDuration'),
            backgroundColor: Colors.green,
          ),
        );
        _breakStartTime = null;
      }
    });
  }

  // 🔥 Calculate break duration
  String _calculateBreakDuration(TimeOfDay start, TimeOfDay end) {
    int startMinutes = start.hour * 60 + start.minute;
    int endMinutes = end.hour * 60 + end.minute;
    int duration = endMinutes - startMinutes;

    int hours = duration ~/ 60;
    int minutes = duration % 60;

    if (hours > 0) {
      return '$hours h $minutes m';
    } else {
      return '$minutes m';
    }
  }

  // 🔥 Check in/out
  void _handleAttendance() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Attendance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildAttendanceOption(
                    icon: Icons.login,
                    label: 'Check In',
                    time: '8:30 AM',
                    color: Colors.green,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Checked in at 8:30 AM'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAttendanceOption(
                    icon: Icons.logout,
                    label: 'Check Out',
                    time: '5:30 PM',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Checked out at 5:30 PM'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceOption({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // 🔥 Navigation methods
  void _viewMySchedule() {
    context.push('/employee/schedule');
  }

  void _viewMyCustomers() {
    context.push('/employee/customers');
  }

  void _viewTodayEarnings() {
    context.push('/employee/earnings');
  }

  void _viewUpcomingAppointments() {
    context.push('/employee/appointments');
  }

  void _viewBookingDetails(String customerName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing $customerName\'s booking'),
        duration: const Duration(seconds: 1),
      ),
    );
    // TODO: Navigate to booking details
  }

  void _markAppointmentComplete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Appointment'),
        content: const Text('Mark this appointment as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _completedToday++;
                _pendingAppointments--;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Appointment marked as completed'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
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
                title: const Text('My Schedule'),
                onTap: () {
                  Navigator.pop(context);
                  _viewMySchedule();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people, color: Colors.purple),
                title: const Text('My Customers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewMyCustomers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: const Text('Earnings'),
                onTap: () {
                  Navigator.pop(context);
                  _viewTodayEarnings();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/employee/settings');
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

  // 🔥 Build status indicator
  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isOnBreak
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnBreak ? Colors.orange : Colors.green,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isOnBreak ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isOnBreak ? 'On Break' : 'Working',
            style: TextStyle(
              color: _isOnBreak ? Colors.orange : Colors.green,
              fontWeight: FontWeight.w500,
              fontSize: 12,
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
        title: const Text('Employee Dashboard'),
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
          // Break toggle button
          IconButton(
            icon: Icon(_isOnBreak ? Icons.free_breakfast : Icons.coffee),
            onPressed: _toggleBreak,
            tooltip: _isOnBreak ? 'End Break' : 'Take Break',
            color: _isOnBreak ? Colors.orange : Colors.white,
          ),

          // Attendance button
          IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: _handleAttendance,
            tooltip: 'Attendance',
          ),

          // Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _viewUpcomingAppointments,
              ),
              if (_pendingAppointments > 0)
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
                      '$_pendingAppointments',
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
        userRole: 'employee',
        userName: _employeeName,
        // userEmail: 'employee@salon.com',
        profileImageUrl: null,
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
                            'Get instant notifications for new bookings and schedule changes',
                        compact: false,
                      ),

                    // Welcome Message with Status
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _employeeName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _employeeRole,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.purple,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          _buildStatusIndicator(),
                        ],
                      ),
                    ),

                    // Rating Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.withValues(alpha: 0.1),
                            Colors.orange.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your Rating',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '$_rating',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '/ 5.0',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  color: Colors.green,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '12%',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Stats Cards Row 1
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Today\'s Appointments',
                              value: '$_todaysAppointments',
                              icon: Icons.calendar_today,
                              color: Colors.blue,
                              subtitle: '$_completedToday completed',
                              onTap: _viewMySchedule,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Pending',
                              value: '$_pendingAppointments',
                              icon: Icons.pending_actions,
                              color: Colors.orange,
                              subtitle: 'Awaiting service',
                              onTap: _viewUpcomingAppointments,
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
                              title: 'Today\'s Earnings',
                              value: 'Rs. $_todayEarnings',
                              icon: Icons.currency_rupee,
                              color: Colors.green,
                              percentageChange: 8.5,
                              onTap: _viewTodayEarnings,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DashboardStatCard(
                              title: 'Monthly',
                              value: 'Rs. $_monthlyEarnings',
                              icon: Icons.trending_up,
                              color: Colors.purple,
                              subtitle: 'This month',
                              onTap: _viewTodayEarnings,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Total Customers Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DashboardStatCard(
                        title: 'Total Customers Served',
                        value: '$_totalCustomers',
                        icon: Icons.people,
                        color: Colors.teal,
                        fullWidth: true,
                        subtitle: 'All time',
                        onTap: _viewMyCustomers,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Quick Actions
                    const SectionHeader(title: 'Quick Actions', actionText: ''),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.check_circle_outline,
                              label: 'Complete',
                              color: Colors.green,
                              onTap: _markAppointmentComplete,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.schedule_outlined,
                              label: 'My Schedule',
                              color: Colors.blue,
                              onTap: _viewMySchedule,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.message_outlined,
                              label: 'Notify Customer',
                              color: Colors.purple,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '📱 Customer notification sent',
                                    ),
                                    backgroundColor: Colors.purple,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Today's Schedule Section
                    const SectionHeader(
                      title: 'Today\'s Schedule',
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
                            status: 'In Progress',
                            statusColor: Colors.blue,
                            barberName: 'You',
                            price: 1500,
                            showActions: true,
                            onTap: () => _viewBookingDetails('Nimal Perera'),
                            onComplete:
                                _markAppointmentComplete, // ✅ Added onComplete
                          ),
                          BookingTile(
                            customerName: 'Kamal Silva',
                            serviceName: 'Beard Trim',
                            time: '2:00 PM',
                            status: 'Upcoming',
                            statusColor: Colors.orange,
                            barberName: 'You',
                            price: 800,
                            showActions: true,
                            onTap: () => _viewBookingDetails('Kamal Silva'),
                            onComplete:
                                _markAppointmentComplete, // ✅ Added onComplete
                          ),
                          BookingTile(
                            customerName: 'Sunil Weerasinghe',
                            serviceName: 'Hair Cut & Shave',
                            time: '4:30 PM',
                            status: 'Upcoming',
                            statusColor: Colors.orange,
                            barberName: 'You',
                            price: 2000,
                            showActions: true,
                            onTap: () =>
                                _viewBookingDetails('Sunil Weerasinghe'),
                            onComplete:
                                _markAppointmentComplete, // ✅ Added onComplete
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Performance Summary
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
                            'Today\'s Performance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPerformanceItem(
                                  label: 'Completed',
                                  value: '$_completedToday',
                                  icon: Icons.check_circle,
                                  color: Colors.green,
                                ),
                              ),
                              Expanded(
                                child: _buildPerformanceItem(
                                  label: 'No-show',
                                  value: '0',
                                  icon: Icons.cancel,
                                  color: Colors.red,
                                ),
                              ),
                              Expanded(
                                child: _buildPerformanceItem(
                                  label: 'On Time',
                                  value: '100%',
                                  icon: Icons.timer,
                                  color: Colors.blue,
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

  // 🔥 Build performance item
  Widget _buildPerformanceItem({
    required String label,
    required String value,
    required IconData icon,
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
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
