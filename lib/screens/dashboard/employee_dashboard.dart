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
import 'package:supabase_flutter/supabase_flutter.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();
  final supabase = Supabase.instance.client;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Employee Dashboard Data
  int _todaysAppointments = 0;
  int _completedToday = 0;
  int _pendingAppointments = 0;
  int _totalCustomers = 0;
  int _todayEarnings = 0;
  int _monthlyEarnings = 0;
  double _rating = 0.0;
  String _employeeName = 'Loading...';
  String _employeeRole = 'Barber';
  String _employeeId = '';
  String _employeeEmail = '';  // 🔥 ADDED: Email for Side Menu
  int? _salonBarberId;
  int? _salonId;

  // Break time status
  bool _isOnBreak = false;
  TimeOfDay? _breakStartTime;

  // Appointments list
  List<Map<String, dynamic>> _todaysAppointmentsList = [];

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
    _loadData();
    _setupNotificationListeners();
    debugPrint('🔄 EmployeeDashboard initState completed');
  }

  // ============================================================
  // LOAD EMPLOYEE DATA FROM NEW SCHEMA
  // ============================================================
  
  Future<void> _loadEmployeeData() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ No user logged in');
        return;
      }

      _employeeId = currentUser.id;
      _employeeEmail = currentUser.email ?? '';
      debugPrint('📋 Loading employee data for user: $_employeeId, email: $_employeeEmail');

      // Get user roles to verify barber role
      final userRolesResponse = await supabase
          .from('user_roles')
          .select('role_id, roles!inner(name)')
          .eq('user_id', _employeeId);

      bool isBarber = false;
      for (var role in userRolesResponse) {
        final roleData = role['roles'] as Map?;
        if (roleData != null && roleData['name'] == 'barber') {
          isBarber = true;
          break;
        }
      }

      if (!isBarber) {
        debugPrint('⚠️ User is not a barber');
        // Try to get from profile roles as fallback
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          final roles = profile['roles'] as List? ?? [];
          if (roles.contains('barber')) {
            isBarber = true;
            debugPrint('✅ Found barber role in SessionManager');
          }
        }
        
        if (!isBarber) {
          debugPrint('❌ User does not have barber role');
          return;
        }
      }

      // Get profile data
      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, email, avatar_url')
          .eq('id', _employeeId)
          .maybeSingle();

      if (profileResponse != null) {
        setState(() {
          _employeeName = profileResponse['full_name'] ?? currentUser.email?.split('@').first ?? 'Barber';
          if (profileResponse['email'] != null && profileResponse['email'].toString().isNotEmpty) {
            _employeeEmail = profileResponse['email'].toString();
          }
        });
        debugPrint('✅ Profile loaded: name=$_employeeName, email=$_employeeEmail');
      } else {
        // Fallback to SessionManager
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          setState(() {
            _employeeName = profile['name'] ?? _employeeEmail.split('@').first;
          });
          debugPrint('✅ Profile loaded from SessionManager: name=$_employeeName');
        }
      }

      // Get salon_barber record
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id, salon_id, status')
          .eq('barber_id', _employeeId)
          .eq('status', 'active')
          .maybeSingle();

      if (salonBarberResponse != null) {
        setState(() {
          _salonBarberId = salonBarberResponse['id'];
          _salonId = salonBarberResponse['salon_id'];
        });
        debugPrint('✅ Found salon_barber: id=$_salonBarberId, salon_id=$_salonId');
      } else {
        debugPrint('⚠️ No active salon_barber record found');
      }

    } catch (e) {
      debugPrint('❌ Error loading employee data: $e');
      
      // Fallback: Try to get data from SessionManager
      try {
        final email = await SessionManager.getCurrentUserEmail();
        if (email != null) {
          final profile = await SessionManager.getProfileByEmail(email);
          if (profile != null) {
            setState(() {
              _employeeEmail = email;
              _employeeName = profile['name'] ?? email.split('@').first;
            });
            debugPrint('✅ Fallback profile loaded: name=$_employeeName, email=$_employeeEmail');
          }
        }
      } catch (fallbackError) {
        debugPrint('❌ Fallback also failed: $fallbackError');
      }
    }
  }

  // ============================================================
  // LOAD DASHBOARD DATA
  // ============================================================
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📊 Loading employee dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard('employee_dashboard');
      } else {
        _showPermissionCard = false;
      }

      // Load appointments if we have salon_barber_id
      if (_salonBarberId != null) {
        await _loadAppointments();
        await _loadStatistics();
      }

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ Employee data loaded successfully');
      }
    } catch (e) {
      debugPrint('❌ Error loading employee data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ============================================================
  // LOAD APPOINTMENTS
  // ============================================================
  
  Future<void> _loadAppointments() async {
    try {
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T').first;

      // Get today's appointments for this barber
      final appointmentsResponse = await supabase
          .from('appointments')
          .select('''
            id,
            booking_number,
            customer_id,
            appointment_date,
            start_time,
            end_time,
            status,
            price,
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
              email,
              phone
            )
          ''')
          .eq('barber_id', _employeeId)
          .eq('appointment_date', todayStr)
          .order('start_time');

      debugPrint('📊 Found ${appointmentsResponse.length} appointments for today');

      final List<Map<String, dynamic>> appointments = [];
      int completed = 0;
      int pending = 0;
      int earnings = 0;

      for (var apt in appointmentsResponse) {
        final service = apt['services'] as Map?;
        final variant = apt['service_variants'] as Map?;
        final customer = apt['profiles'] as Map?;
        
        final status = apt['status'] as String? ?? 'pending';
        final price = (apt['price'] as num?)?.toDouble() ?? 
                      (variant?['price'] as num?)?.toDouble() ?? 0.0;

        if (status == 'completed') {
          completed++;
          earnings += price.toInt();
        } else if (status == 'pending' || status == 'confirmed') {
          pending++;
        }

        appointments.add({
          'id': apt['id'],
          'booking_number': apt['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': service?['name'] ?? 'Unknown Service',
          'variant_name': variant != null 
              ? '${variant['salon_genders']?['display_name'] ?? ''} • ${variant['salon_age_categories']?['display_name'] ?? ''}'
              : null,
          'start_time': apt['start_time'],
          'end_time': apt['end_time'],
          'status': status,
          'price': price,
          'duration': variant?['duration'] ?? 30,
        });
      }

      setState(() {
        _todaysAppointmentsList = appointments;
        _todaysAppointments = appointments.length;
        _completedToday = completed;
        _pendingAppointments = pending;
        _todayEarnings = earnings;
      });

    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
    }
  }

  // ============================================================
  // LOAD STATISTICS
  // ============================================================
  
  Future<void> _loadStatistics() async {
    try {
      // Get total customers served (unique customers from appointments)
      final customersResponse = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed');

      final uniqueCustomers = customersResponse.map((a) => a['customer_id']).toSet().length;
      setState(() {
        _totalCustomers = uniqueCustomers;
      });

      // Get monthly earnings
      final firstDayOfMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final firstDayStr = firstDayOfMonth.toIso8601String().split('T').first;
      final lastDayOfMonth = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
      final lastDayStr = lastDayOfMonth.toIso8601String().split('T').first;

      final monthlyResponse = await supabase
          .from('appointments')
          .select('price')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .gte('appointment_date', firstDayStr)
          .lte('appointment_date', lastDayStr);

      int monthlyTotal = 0;
      for (var apt in monthlyResponse) {
        monthlyTotal += (apt['price'] as num?)?.toInt() ?? 0;
      }
      setState(() {
        _monthlyEarnings = monthlyTotal;
      });

      // Get average rating
      final reviewsResponse = await supabase
          .from('reviews')
          .select('overall_rating')
          .eq('barber_id', _employeeId);

      if (reviewsResponse.isNotEmpty) {
        double totalRating = 0;
        for (var review in reviewsResponse) {
          totalRating += (review['overall_rating'] as num?)?.toDouble() ?? 0;
        }
        setState(() {
          _rating = totalRating / reviewsResponse.length;
        });
      }

    } catch (e) {
      debugPrint('❌ Error loading statistics: $e');
    }
  }

  // ============================================================
  // NOTIFICATION SETUP
  // ============================================================
  
  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New message: ${message.data}');

        if (message.data['type'] == 'new_booking_assigned') {
          _showNewAssignmentAlert(message);
          _loadData(); // Refresh data
        } else if (message.data['type'] == 'booking_reminder') {
          _showReminderAlert(message);
        }
      });
    } catch (e) {
      debugPrint('❌ Error setting up notification listeners: $e');
    }
  }

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
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
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
            Text(message.notification?.body ?? 'You have a new booking assigned', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewMySchedule();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B)),
            child: const Text('View'),
          ),
        ],
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
            Expanded(child: Text(message.notification?.body ?? 'Upcoming appointment')),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'View', textColor: Colors.white, onPressed: _viewMySchedule),
      ),
    );
  }

  // ============================================================
  // PERMISSIONS
  // ============================================================
  
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
        customMessage: 'Get instant notifications for new bookings, reminders, and schedule changes',
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
    await _permissionManager.markPermissionShown('employee_dashboard');
  }

  // ============================================================
  // BREAK MANAGEMENT
  // ============================================================
  
  void _toggleBreak() {
    setState(() {
      _isOnBreak = !_isOnBreak;
      if (_isOnBreak) {
        _breakStartTime = TimeOfDay.now();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [Icon(Icons.free_breakfast, color: Colors.white), SizedBox(width: 8), Text('Break started')]),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        final breakEndTime = TimeOfDay.now();
        final breakDuration = _calculateBreakDuration(_breakStartTime!, breakEndTime);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Break ended • Duration: $breakDuration'), backgroundColor: Colors.green),
        );
        _breakStartTime = null;
      }
    });
  }

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

  // ============================================================
  // ATTENDANCE
  // ============================================================
  
  void _handleAttendance() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Attendance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildAttendanceOption(
                    icon: Icons.login,
                    label: 'Check In',
                    time: _getCurrentTime(),
                    color: Colors.green,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ Checked in at ${_getCurrentTime()}'), backgroundColor: Colors.green),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAttendanceOption(
                    icon: Icons.logout,
                    label: 'Check Out',
                    time: _getCurrentTime(),
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ Checked out at ${_getCurrentTime()}'), backgroundColor: Colors.orange),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    int hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour > 12 ? hour - 12 : hour;
    if (hour == 0) hour = 12;
    return '$hour:$minute $ampm';
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
            Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // NAVIGATION
  // ============================================================
  
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
      SnackBar(content: Text('Viewing $customerName\'s booking'), duration: const Duration(seconds: 1)),
    );
  }

  void _markAppointmentComplete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Appointment'),
        content: const Text('Mark this appointment as completed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadData(); // Refresh data
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Appointment marked as completed'), backgroundColor: Colors.green),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

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

  // ============================================================
  // UI BUILDERS
  // ============================================================
  
  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isOnBreak ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isOnBreak ? Colors.orange : Colors.green, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _isOnBreak ? Colors.orange : Colors.green, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(_isOnBreak ? 'On Break' : 'Working', style: TextStyle(color: _isOnBreak ? Colors.orange : Colors.green, fontWeight: FontWeight.w500, fontSize: 12)),
        ],
      ),
    );
  }

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
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

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
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
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
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: _openDrawer, tooltip: 'Menu', iconSize: 28),
        actions: [
          IconButton(
            icon: Icon(_isOnBreak ? Icons.free_breakfast : Icons.coffee),
            onPressed: _toggleBreak,
            tooltip: _isOnBreak ? 'End Break' : 'Take Break',
            color: _isOnBreak ? Colors.orange : Colors.white,
          ),
          IconButton(icon: const Icon(Icons.access_time), onPressed: _handleAttendance, tooltip: 'Attendance'),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: _viewUpcomingAppointments),
              if (_pendingAppointments > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text('$_pendingAppointments', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      // 🔥 FIXED: SideMenu with email parameter
      drawer: SideMenu(
        userRole: 'barber',
        userName: _employeeName,
        userEmail: _employeeEmail,  // 🔥 Email passed to Side Menu
        profileImageUrl: null,
        onMenuItemSelected: () => _loadData(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : RefreshIndicator(
              onRefresh: _loadData,
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
                        message: 'Get instant notifications for new bookings and schedule changes',
                        compact: false,
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Welcome back,', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                              Row(
                                children: [
                                  Text(_employeeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                    child: Text(_employeeRole, style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w500)),
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
                        gradient: LinearGradient(colors: [Colors.amber.withValues(alpha: 0.1), Colors.orange.withValues(alpha: 0.1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.star, color: Colors.amber, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Your Rating', style: TextStyle(fontSize: 14, color: Colors.grey)),
                              Row(
                                children: [
                                  Text(_rating.toStringAsFixed(1), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amber)),
                                  const SizedBox(width: 4),
                                  const Text('/ 5.0', style: TextStyle(fontSize: 16, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                            child: const Row(children: [Icon(Icons.arrow_upward, color: Colors.green, size: 16), SizedBox(width: 4), Text('12%', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500))]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Stats Cards
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
                    const SectionHeader(title: 'Quick Actions', actionText: ''),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(child: _buildQuickAction(icon: Icons.check_circle_outline, label: 'Complete', color: Colors.green, onTap: _markAppointmentComplete)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildQuickAction(icon: Icons.schedule_outlined, label: 'My Schedule', color: Colors.blue, onTap: _viewMySchedule)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(
                              icon: Icons.message_outlined,
                              label: 'Notify Customer',
                              color: Colors.purple,
                              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📱 Customer notification sent'), backgroundColor: Colors.purple)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SectionHeader(title: 'Today\'s Schedule', actionText: 'View All'),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _todaysAppointmentsList.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                              child: const Center(child: Text('No appointments today', style: TextStyle(color: Colors.grey))),
                            )
                          : Column(
                              children: _todaysAppointmentsList.map((apt) {
                                Color statusColor;
                                switch (apt['status']) {
                                  case 'completed': statusColor = Colors.green; break;
                                  case 'confirmed': statusColor = Colors.blue; break;
                                  case 'cancelled': statusColor = Colors.red; break;
                                  default: statusColor = Colors.orange;
                                }
                                return BookingTile(
                                  customerName: apt['customer_name'],
                                  serviceName: apt['service_name'],
                                  time: apt['start_time'],
                                  status: apt['status'],
                                  statusColor: statusColor,
                                  barberName: 'You',
                                  price: apt['price'],
                                  showActions: apt['status'] != 'completed',
                                  onTap: () => _viewBookingDetails(apt['customer_name']),
                                  onComplete: _markAppointmentComplete,
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Today\'s Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _buildPerformanceItem(label: 'Completed', value: '$_completedToday', icon: Icons.check_circle, color: Colors.green)),
                              Expanded(child: _buildPerformanceItem(label: 'No-show', value: '0', icon: Icons.cancel, color: Colors.red)),
                              Expanded(child: _buildPerformanceItem(label: 'On Time', value: '100%', icon: Icons.timer, color: Colors.blue)),
                            ],
                          ),
                        ],
                      ),
                    ),
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
    );
  }
}