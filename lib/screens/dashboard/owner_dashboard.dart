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

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  // 🔑 GlobalKey for scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Dashboard data
  int completedToday = 0;
  int pendingAppointments = 0;
  int _pendingBookings = 0;
  int _todayAppointments = 0;
  int _totalRevenue = 0;
  int _totalCustomers = 0;
  int _activeBarbers = 0;
  
  // 🔥 Multiple salons support
  List<Map<String, dynamic>> _ownerSalons = [];
  String? _selectedSalonId;
  bool _isLoadingSalons = false;
  
  // User info
  String _userName = 'Salon Owner';
  String? _userEmail;
  String? _profileImageUrl;
  List<String> _userRoles = [];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _loadData();
    _loadUserProfile();
    _loadOwnerSalons();
    _setupNotificationListeners();
    
    debugPrint('🔄 OwnerDashboard initState completed');
  }

  // ============================================================
  // 🔥 Load owner's salons (multiple)
  // ============================================================
  Future<void> _loadOwnerSalons() async {
    setState(() => _isLoadingSalons = true);
    
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('salons')
          .select('id, name, address, is_active, created_at')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      debugPrint('📊 Owner salons loaded: ${response.length}');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          if (_ownerSalons.isNotEmpty) {
            _selectedSalonId = _ownerSalons.first['id'].toString();
          }
          _isLoadingSalons = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salons: $e');
      if (mounted) {
        setState(() => _isLoadingSalons = false);
      }
    }
  }

  // ============================================================
  // 🔥 Load user profile from database
  // ============================================================
  Future<void> _loadUserProfile() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final profileResponse = await supabase
          .from('profiles')
          .select('''
            full_name,
            email,
            avatar_url,
            extra_data
          ''')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (profileResponse != null) {
        setState(() {
          _userName = profileResponse['full_name'] ?? 
                      profileResponse['extra_data']?['full_name'] ?? 
                      'Salon Owner';
          _userEmail = profileResponse['email'] ?? currentUser.email;
          _profileImageUrl = profileResponse['avatar_url'];
        });
      }

      final rolesResponse = await supabase
          .from('user_roles')
          .select('''
            roles!inner (
              name
            )
          ''')
          .eq('user_id', currentUser.id);

      final List<String> roleNames = [];
      for (var roleEntry in rolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }
      
      _userRoles = roleNames.toSet().toList();
      
      debugPrint('👤 User profile loaded: $_userName');
      debugPrint('👤 User roles: $_userRoles');
    } catch (e) {
      debugPrint('❌ Error loading user profile: $e');
    }
  }

  // ============================================================
  // 🔥 Load dashboard stats for selected salon
  // ============================================================
  Future<void> _loadDashboardStats() async {
    if (_selectedSalonId == null) {
      debugPrint('⚠️ No salon selected');
      return;
    }
    
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      debugPrint('📊 Loading stats for salon ID: $_selectedSalonId');

      // Get today's appointments for selected salon
      final todayAppointments = await supabase
          .from('appointments')
          .select('id, status, price')
          .eq('salon_id', int.parse(_selectedSalonId!))
          .eq('appointment_date', today);

      debugPrint('📊 Today appointments: ${todayAppointments.length}');

      // Get pending bookings
      final pendingBookings = await supabase
          .from('appointments')
          .select('id')
          .eq('salon_id', int.parse(_selectedSalonId!))
          .eq('appointment_date', today)
          .eq('status', 'pending');

      debugPrint('📊 Pending bookings: ${pendingBookings.length}');

      // Get active barbers for this salon
      final activeBarbers = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', int.parse(_selectedSalonId!))
          .eq('is_active', true);

      debugPrint('📊 Active barbers: ${activeBarbers.length}');

      // Get total customers (all time)
      final totalCustomers = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('salon_id', int.parse(_selectedSalonId!));

      final uniqueCustomers = totalCustomers
          .map((a) => a['customer_id'] as String)
          .toSet()
          .length;

      debugPrint('📊 Total customers: $uniqueCustomers');

      // Get today's revenue
      final revenue = todayAppointments.fold<int>(
        0,
        (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0),
      );

      debugPrint('📊 Today revenue: $revenue');

      if (mounted) {
        setState(() {
          _todayAppointments = todayAppointments.length;
          _pendingBookings = pendingBookings.length;
          _activeBarbers = activeBarbers.length;
          _totalCustomers = uniqueCustomers;
          _totalRevenue = revenue;
          pendingAppointments = _pendingBookings;
          completedToday = todayAppointments.where((a) => a['status'] == 'completed').length;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading dashboard stats: $e');
    }
  }

  // ============================================================
  // 🔥 Load initial data
  // ============================================================
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📊 Loading dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'owner_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      await _loadDashboardStats();

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ Data loaded successfully');
      }
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
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

  // ============================================================
  // 🔥 Refresh all data
  // ============================================================
  Future<void> _refreshAllData() async {
    debugPrint('🔄 Refreshing all data...');
    
    await Future.wait([
      _loadOwnerSalons(),
      _loadUserProfile(),
      _loadData(),
    ]);
  }

  // ============================================================
  // 🔥 Switch salon
  // ============================================================
  void _switchSalon(String salonId) {
    debugPrint('🔄 Switching to salon ID: $salonId');
    setState(() {
      _selectedSalonId = salonId;
    });
    _loadData();
  }

  // ============================================================
  // 🔥 Navigation Methods - All Required Features
  // ============================================================
  
  // Salon Management
  void _navigateToCreateSalon() {
    debugPrint('📍 Navigating to create salon screen');
    context.push('/owner/salon/create');
  }

  void _navigateToEditSalon() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to edit salon screen');
    context.push('/owner/salon/edit?salonId=$_selectedSalonId');
  }

  // Barber Management
  void _navigateToAddBarber() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to add barber screen');
    context.push('/owner/add-barber?salonId=$_selectedSalonId');
  }

  void _navigateToBarberLeaves() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to barber leaves screen');
    context.push('/owner/barber-leaves?salonId=$_selectedSalonId');
  }

  void _navigateToBarberSchedule() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to barber schedule screen');
    context.push('/owner/barber-schedule?salonId=$_selectedSalonId');
  }

  void _navigateToBarberList() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to barber list screen');
    context.push('/owner/barbers?salonId=$_selectedSalonId');
  }

  // Service Management
  void _navigateToAddService() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to add service screen');
    context.push('/owner/services/add');
  }

  void _navigateToAddServiceVariant() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to add service variant screen');
    context.push('/owner/service-variants/add');
  }

  void _navigateToServiceList() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    debugPrint('📍 Navigating to service list screen');
    context.push('/owner/services');
  }

  // Category Management
  void _navigateToAddCategory() {
    debugPrint('📍 Navigating to add category screen');
    context.push('/owner/categories/add');
  }

  void _navigateToCategoryList() {
    debugPrint('📍 Navigating to category list screen');
    context.push('/owner/categories');
  }

  // Gender Management
  void _navigateToAddGender() {
    debugPrint('📍 Navigating to add gender screen');
    context.push('/owner/genders/add');
  }

  void _navigateToGenderList() {
    debugPrint('📍 Navigating to gender list screen');
    context.push('/owner/genders');
  }

  // Age Category Management
  void _navigateToAddAgeCategory() {
    debugPrint('📍 Navigating to add age category screen');
    context.push('/owner/age-categories/add');
  }

  void _navigateToAgeCategoryList() {
    debugPrint('📍 Navigating to age category list screen');
    context.push('/owner/age-categories');
  }

  // Appointment Management
  void _viewBookings() {
    if (_selectedSalonId != null) {
      context.push('/owner/appointments?salonId=$_selectedSalonId');
    } else {
      context.push('/owner/appointments');
    }
  }

  void _viewAllCustomers() {
    if (_selectedSalonId != null) {
      context.push('/owner/customers?salonId=$_selectedSalonId');
    } else {
      context.push('/owner/customers');
    }
  }

  void _viewRevenue() {
    if (_selectedSalonId != null) {
      context.push('/owner/revenue?salonId=$_selectedSalonId');
    } else {
      context.push('/owner/revenue');
    }
  }

  void _viewReports() {
    debugPrint('📍 Navigating to reports screen');
    context.push('/owner/reports');
  }

  void _viewAnalytics() {
    debugPrint('📍 Navigating to analytics screen');
    context.push('/owner/analytics');
  }

  void _viewSettings() {
    debugPrint('📍 Navigating to settings screen');
    context.push('/owner/settings');
  }

  void _viewBarberList() {
  if (_ownerSalons.isEmpty) {
    _showCreateSalonFirstDialog();
    return;
  }
  debugPrint('📍 Navigating to barber list screen');
  context.push('/owner/barbers?salonId=$_selectedSalonId');
}

  // ============================================================
  // 🔥 Helper Methods
  // ============================================================
  void _showCreateSalonFirstDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Salon First'),
        content: const Text(
          'You need to create a salon before adding barbers or services. Would you like to create one now?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToCreateSalon();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Create Salon'),
          ),
        ],
      ),
    );
  }

  void _viewBookingDetails(String customerName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing $customerName\'s booking'),
        duration: const Duration(seconds: 1),
      ),
    );
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
                completedToday++;
                pendingAppointments--;
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

  // ============================================================
  // 🔥 Setup notification listeners
  // ============================================================
  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New message: ${message.data}');

        if (message.data['type'] == 'new_booking') {
          _showNewBookingAlert(message);
          setState(() {
            _pendingBookings++;
            pendingAppointments++;
          });
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('📨 Message opened: ${message.data}');
        if (message.data['type'] == 'new_booking') {
          _viewBookings();
        }
      });
    } catch (e) {
      debugPrint('❌ Error setting up notification listeners: $e');
    }
  }

  // ============================================================
  // 🔥 Show new booking alert
  // ============================================================
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

  // ============================================================
  // 🔥 Enable notifications
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
      debugPrint('❌ Error enabling notifications: $e');
    }
  }

  // ============================================================
  // 🔥 Show settings dialog
  // ============================================================
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

  // ============================================================
  // 🔥 Handle Not Now
  // ============================================================
  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('owner_dashboard');
  }

  // ============================================================
  // 🔥 Open drawer method
  // ============================================================
  void _openDrawer() {
    try {
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
        debugPrint('✅ Drawer opened via GlobalKey');
      } else {
        Scaffold.of(context).openDrawer();
        debugPrint('✅ Drawer opened via Scaffold.of');
      }
    } catch (e) {
      debugPrint('❌ Error opening drawer: $e');
      _showMenuDialog();
    }
  }

  // ============================================================
  // 🔥 Emergency menu dialog
  // ============================================================
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
                  _navigateToBarberList();
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
                  _viewSettings();
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

  // ============================================================
  // 🔥 Logout
  // ============================================================
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
          await appState.refreshState();

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

  // ============================================================
  // 🔥 Build quick action button
  // ============================================================
  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: enabled 
                ? color.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon, 
                color: enabled ? color : Colors.grey[400], 
                size: 28
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? color : Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🔥 Build salon selector
  // ============================================================
  Widget _buildSalonSelector() {
    if (_ownerSalons.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
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
              const Icon(Icons.store, size: 18, color: Color(0xFFFF6B8B)),
              const SizedBox(width: 8),
              const Text(
                'Select Salon',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: _navigateToEditSalon,
                    tooltip: 'Edit Salon',
                    color: const Color(0xFFFF6B8B),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _navigateToCreateSalon,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B8B),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _ownerSalons.map((salon) {
                final isSelected = _selectedSalonId == salon['id'].toString();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(salon['name'] ?? 'Salon'),
                    selected: isSelected,
                    onSelected: (_) => _switchSalon(salon['id'].toString()),
                    backgroundColor: Colors.grey[100],
                    selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                    checkmarkColor: const Color(0xFFFF6B8B),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[800],
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 Build main management section
  // ============================================================
// ============================================================
// 🔥 Build main management section
// ============================================================
Widget _buildManagementSection() {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.settings, size: 20, color: Color(0xFFFF6B8B)),
            SizedBox(width: 8),
            Text(
              'Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Row 1: Salon Management
        const Text(
          'Salon Management',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.add_business,
              label: 'Create Salon',
              color: const Color(0xFFFF6B8B),
              onTap: _navigateToCreateSalon,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.edit,
              label: 'Edit Salon',
              color: Colors.blue,
              onTap: _navigateToEditSalon,
              enabled: _ownerSalons.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Row 2: Barber Management
        const Text(
          'Barber Management',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.person_add,
              label: 'Add Barber',
              color: Colors.purple,
              onTap: _navigateToAddBarber,
              enabled: _ownerSalons.isNotEmpty,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.calendar_month,
              label: 'Schedule',
              color: Colors.teal,
              onTap: _navigateToBarberSchedule,
              enabled: _ownerSalons.isNotEmpty,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.beach_access,
              label: 'Leaves',
              color: Colors.orange,
              onTap: _navigateToBarberLeaves,
              enabled: _ownerSalons.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.list,
              label: 'Barber List',
              color: Colors.indigo,
              onTap: _viewBarberList, // ✅ Now defined
              enabled: _ownerSalons.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Row 3: Service Management
        const Text(
          'Service Management',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.build,
              label: 'Add Service',
              color: Colors.green,
              onTap: _navigateToAddService,
              enabled: _ownerSalons.isNotEmpty,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.tune,
              label: 'Add Variant',
              color: Colors.lime,
              onTap: _navigateToAddServiceVariant,
              enabled: _ownerSalons.isNotEmpty,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.list,
              label: 'Service List',
              color: Colors.cyan,
              onTap: _navigateToServiceList,
              enabled: _ownerSalons.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Row 4: Category Management
        const Text(
          'Category Management',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.category,
              label: 'Add Category',
              color: Colors.brown,
              onTap: _navigateToAddCategory,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.list,
              label: 'Category List',
              color: Colors.deepPurple,
              onTap: _navigateToCategoryList,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.wc,
              label: 'Add Gender',
              color: Colors.pink,
              onTap: _navigateToAddGender,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.cake,
              label: 'Add Age Cat',
              color: Colors.amber,
              onTap: _navigateToAddAgeCategory,
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Row 5: Reports & Analytics
        const Text(
          'Reports & Analytics',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildQuickAction(
              icon: Icons.bar_chart,
              label: 'Reports',
              color: Colors.deepOrange,
              onTap: _viewReports,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.analytics,
              label: 'Analytics',
              color: Colors.indigoAccent,
              onTap: _viewAnalytics,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(
              icon: Icons.settings,
              label: 'Settings',
              color: Colors.grey,
              onTap: _viewSettings,
            ),
          ],
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      key: _scaffoldKey,

      appBar: AppBar(
        title: Text(
          isWeb ? 'Owner Dashboard' : 'Dashboard',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
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

        actions: [
          // Add Menu Button (Create Salon, Add Barber, Add Service)
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: 'Add New',
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              switch (value) {
                case 'salon':
                  _navigateToCreateSalon();
                  break;
                case 'barber':
                  _navigateToAddBarber();
                  break;
                case 'service':
                  _navigateToAddService();
                  break;
                case 'variant':
                  _navigateToAddServiceVariant();
                  break;
                case 'category':
                  _navigateToAddCategory();
                  break;
                case 'gender':
                  _navigateToAddGender();
                  break;
                case 'age':
                  _navigateToAddAgeCategory();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'salon',
                child: Row(
                  children: [
                    Icon(Icons.add_business, color: Color(0xFFFF6B8B), size: 18),
                    SizedBox(width: 12),
                    Text('Create New Salon'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'barber',
                child: Row(
                  children: [
                    Icon(Icons.person_add, color: Colors.purple, size: 18),
                    SizedBox(width: 12),
                    Text('Add New Barber'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'service',
                child: Row(
                  children: [
                    Icon(Icons.build, color: Colors.green, size: 18),
                    SizedBox(width: 12),
                    Text('Add New Service'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'variant',
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Colors.lime, size: 18),
                    SizedBox(width: 12),
                    Text('Add Service Variant'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'category',
                child: Row(
                  children: [
                    Icon(Icons.category, color: Colors.brown, size: 18),
                    SizedBox(width: 12),
                    Text('Add Category'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'gender',
                child: Row(
                  children: [
                    Icon(Icons.wc, color: Colors.pink, size: 18),
                    SizedBox(width: 12),
                    Text('Add Gender'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'age',
                child: Row(
                  children: [
                    Icon(Icons.cake, color: Colors.amber, size: 18),
                    SizedBox(width: 12),
                    Text('Add Age Category'),
                  ],
                ),
              ),
            ],
          ),

          // Notification bell
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllData,
            tooltip: 'Refresh',
          ),
        ],
      ),

      // Drawer with SideMenu
      drawer: SideMenu(
        userRole: 'owner',
        userName: _userName,
        userEmail: _userEmail,
        profileImageUrl: _profileImageUrl,
        onMenuItemSelected: () {
          _refreshAllData();
        },
      ),

      body: _isLoading || _isLoadingSalons
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refreshAllData,
              color: const Color(0xFFFF6B8B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Permission Card
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
                              Text(
                                _userName,
                                style: const TextStyle(
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
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Color(0xFFFF6B8B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getFormattedDate(),
                                  style: const TextStyle(
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

                    // 🔥 Salon Selector (if multiple salons)
                    if (_ownerSalons.length > 1) _buildSalonSelector(),

                    // No salon warning (if no salons)
                    if (_ownerSalons.isEmpty)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 40),
                            const SizedBox(height: 8),
                            const Text(
                              'No Salons Found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Create your first salon to get started',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _navigateToCreateSalon,
                              icon: const Icon(Icons.add_business),
                              label: const Text('Create Salon'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B8B),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Stats Cards - Only show if salon exists
                    if (_ownerSalons.isNotEmpty) ...[
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
                     // Stats Cards Row 2 - FIXED
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
          subtitle: 'Working today',
          onTap: _viewBarberList, // Now this is defined
        ),
      ),
    ],
  ),
),

                      const SizedBox(height: 12),

                      // Revenue Card
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
                    ],

                    const SizedBox(height: 16),

                    // 🔥 Management Section - All buttons
                    _buildManagementSection(),

                    const SizedBox(height: 16),

                    // Recent Bookings Section (only if salon exists)
                    if (_ownerSalons.isNotEmpty) ...[
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
                              onComplete: _markAppointmentComplete,
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
                              onComplete: _markAppointmentComplete,
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
                              onComplete: _markAppointmentComplete,
                            ),
                          ],
                        ),
                      ),
                    ],

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

  // ============================================================
  // 🔥 Helper: Get formatted date
  // ============================================================
  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}