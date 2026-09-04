import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/widgets/dashboard_stat_card.dart';
import 'package:flutter_application_1/widgets/booking_tile.dart';
import 'package:flutter_application_1/widgets/section_header.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';
import '../../services/timezone_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key});

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> with RouteAware {
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
  int _noShowToday = 0;
  int _onTimePercentage = 0;
  int _totalCustomers = 0;
  int _todayEarnings = 0;
  int _monthlyEarnings = 0;
  double _rating = 0.0;
  String _employeeName = 'Loading...';
  String _employeeId = '';
  String _employeeEmail = '';
  String _employeeAvatar = '';

  // Multi-salon support
  List<Map<String, dynamic>> _assignedSalons = [];
  String? _selectedSalonId;
  String _selectedSalonName = '';

  // Appointments list
  List<Map<String, dynamic>> _todaysAppointmentsList = [];

  // Notification count
  int _unreadNotificationCount = 0;

  // Responsive screen variables
  bool _isLargeScreen = false;
  bool _isTablet = false;
  bool _isWeb = false;

  // Timezone variables
  String _userTimezone = '';
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  // Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeTimezone();
    await _loadEmployeeData();
    await _loadData();
    _setupNotificationListeners();
    debugPrint('🔄 EmployeeDashboard initState completed');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    _checkScreenSize();
    _checkTimezoneChange();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isLarge = size.width > 800 || size.height > 800;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isLargeScreen != isLarge || _isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isLargeScreen = isLarge;
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('🔄 Returning to EmployeeDashboard - Auto refresh');
    _loadData();
  }

  // ==================== TIMEZONE INITIALIZATION ====================

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    String cachedTimezone = prefs.getString('cached_timezone') ?? '';

    if (cachedTimezone.isNotEmpty) {
      _userTimezone = cachedTimezone;
    } else {
      _userTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString('cached_timezone', _userTimezone);
    }

    await TimezoneService.setTimezone(_userTimezone);
    _lastTimezone = _userTimezone;

    setState(() {
      _isTimezoneLoaded = true;
    });

    debugPrint('✅ User timezone: $_userTimezone');
  }

  void _checkTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();

    if (_lastTimezone != currentTimezone && _lastTimezone.isNotEmpty) {
      _userTimezone = currentTimezone;
      await TimezoneService.setTimezone(_userTimezone);
    }
    _lastTimezone = currentTimezone;
  }

  // ==================== UTC TO LOCAL CONVERSION ====================

  String _utcToLocalTimeString(String utcTime) {
    try {
      return TimezoneService.utcToLocalTimeRecurring(utcTime);
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      return _formatTimeString(utcTime);
    }
  }

  String _formatTimeString(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  String _formatDateDisplay(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return 'Today';
      }

      final tomorrow = now.add(const Duration(days: 1));
      if (date.year == tomorrow.year &&
          date.month == tomorrow.month &&
          date.day == tomorrow.day) {
        return 'Tomorrow';
      }

      final dayDiff = date.difference(now).inDays;
      if (dayDiff <= 7) {
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return weekdays[date.weekday - 1];
      }

      return '${date.day}/${date.month}';
    } catch (e) {
      return dateStr;
    }
  }

  String _getMonthName() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[DateTime.now().month - 1];
  }

  // ==================== CONTEXTUAL PERMISSION METHODS ====================

  Future<void> _showPermissionCardContext({String? action}) async {
    final shouldShow = await _permissionManager.shouldShowPermissionCard(
      screen: 'employee_dashboard',
      action: action,
    );

    if (mounted) {
      setState(() {
        _showPermissionCard = shouldShow;
      });
    }
  }

  // ============================================================
  // SHOW WEB PERMISSION HELP
  // ============================================================

  void _showWebPermissionHelp() {
    if (!mounted) return;
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Row(
          children: [
            Text('🌐'),
            SizedBox(width: 8),
            Text('Browser Notification Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To enable notifications, please follow these steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildWebStep('1', 'Click the 🔒 lock icon in the address bar'),
            const SizedBox(height: 8),
            _buildWebStep('2', 'Click "Site settings" or "Permissions"'),
            const SizedBox(height: 8),
            _buildWebStep('3', 'Find "Notifications" and select "Allow"'),
            const SizedBox(height: 8),
            _buildWebStep('4', 'Refresh the page'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Once enabled, you\'ll receive notifications even when the tab is not active',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _permissionService.refreshWebPage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Page'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebStep(String number, String text) {
    final isDark = context.isDarkMode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  // ==================== LOAD NOTIFICATION COUNT ====================

  Future<void> _loadNotificationCount() async {
    if (_employeeId.isEmpty) return;

    try {
      final count = await _notificationService.getUnreadCountWithRole(
        userId: _employeeId,
        role: 'barber',
      );
      setState(() {
        _unreadNotificationCount = count;
      });
      debugPrint('✅ Unread notifications: $count');
    } catch (e) {
      debugPrint('❌ Error loading notification count: $e');
    }
  }

  // ==================== PROFILE IMAGE ====================

  Widget _buildProfileImage() {
    final hasImage = _employeeAvatar.isNotEmpty;
    final isDark = context.isDarkMode;

    return GestureDetector(
      onTap: () {
        context.push('/profile');
      },
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          backgroundImage: hasImage ? NetworkImage(_employeeAvatar) : null,
          onBackgroundImageError: hasImage
              ? (exception, stackTrace) {
                  debugPrint('⚠️ Failed to load avatar image: $exception');
                }
              : null,
          child: !hasImage
              ? Text(
                  _employeeName.isNotEmpty
                      ? _employeeName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ==================== LOAD EMPLOYEE DATA ====================

  Future<void> _loadEmployeeData() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ No user logged in');
        return;
      }

      _employeeId = currentUser.id;
      _employeeEmail = currentUser.email ?? '';
      debugPrint(
        '📋 Loading employee data for user: $_employeeId, email: $_employeeEmail',
      );

      // STEP 1: Check if user has ACTIVE barber role
      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
          role_id,
          status,
          roles!inner (
            id,
            name
          )
        ''')
          .eq('user_id', _employeeId);

      bool isActiveBarber = false;
      String? roleStatus;
      for (var role in userRolesResponse) {
        final roleData = role['roles'] as Map?;
        final status = role['status'] as String? ?? 'active';
        if (roleData != null && roleData['name'] == 'barber') {
          roleStatus = status;
          if (status == 'active') {
            isActiveBarber = true;
          }
          break;
        }
      }

      if (!isActiveBarber && roleStatus != null) {
        if (mounted) {
          String message = 'Your barber account is ';
          switch (roleStatus) {
            case 'inactive':
              message += 'deactivated';
              break;
            case 'scheduled_for_deletion':
              message += 'scheduled for deletion';
              break;
            case 'deleted':
              message += 'deleted';
              break;
            default:
              message += 'not active';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ $message. Please contact support.'),
              backgroundColor: Colors.orange,
            ),
          );

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              context.go('/');
            }
          });
          return;
        }
      }

      if (!isActiveBarber) {
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          final roles = profile['roles'] as List? ?? [];
          if (roles.contains('barber')) {
            isActiveBarber = true;
            debugPrint(
              '✅ Found barber role in SessionManager, but DB check failed',
            );
          }
        }

        if (!isActiveBarber) {
          debugPrint('❌ User does not have barber role');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'You do not have a barber role. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
            context.go('/');
          }
          return;
        }
      }

      // Load profile
      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, email, avatar_url, is_active, is_blocked')
          .eq('id', _employeeId)
          .maybeSingle();

      if (profileResponse != null) {
        if (profileResponse['is_blocked'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been blocked. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
            context.go('/');
          }
          return;
        }

        if (profileResponse['is_active'] == false) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your profile is inactive. Please contact support.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            context.go('/');
          }
          return;
        }
      }

      if (profileResponse != null) {
        setState(() {
          _employeeName =
              profileResponse['full_name'] ??
              currentUser.email?.split('@').first ??
              'Barber';
          if (profileResponse['email'] != null &&
              profileResponse['email'].toString().isNotEmpty) {
            _employeeEmail = profileResponse['email'].toString();
          }
          _employeeAvatar = profileResponse['avatar_url'] ?? '';
        });
        debugPrint(
          '✅ Profile loaded: name=$_employeeName, email=$_employeeEmail',
        );
      } else {
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          setState(() {
            _employeeName = profile['name'] ?? _employeeEmail.split('@').first;
            _employeeAvatar = profile['avatar'] ?? '';
          });
          debugPrint(
            '✅ Profile loaded from SessionManager: name=$_employeeName',
          );
        }
      }

      // Load assigned salons
      await _loadAssignedSalons();
    } catch (e) {
      debugPrint('❌ Error loading employee data: $e');

      try {
        final email = await SessionManager.getCurrentUserEmail();
        if (email != null) {
          final profile = await SessionManager.getProfileByEmail(email);
          if (profile != null) {
            setState(() {
              _employeeEmail = email;
              _employeeName = profile['name'] ?? email.split('@').first;
              _employeeAvatar = profile['avatar'] ?? '';
            });
            debugPrint(
              '✅ Fallback profile loaded: name=$_employeeName, email=$_employeeEmail',
            );
          }
        }
      } catch (fallbackError) {
        debugPrint('❌ Fallback also failed: $fallbackError');
      }
    }
  }

  Future<void> _loadAssignedSalons() async {
    try {
      final response = await supabase
          .from('salon_barbers')
          .select('''
            id,
            salon_id,
            status,
            salons!inner (
              id,
              name,
              address,
              phone,
              logo_url,
              cover_url,
              open_time,
              close_time,
              is_active
            )
          ''')
          .eq('barber_id', _employeeId)
          .eq('status', 'active');

      debugPrint('📊 Found ${response.length} assigned salons');

      final List<Map<String, dynamic>> salons = [];

      for (var item in response) {
        final salonData = item['salons'] as Map?;
        if (salonData != null) {
          final salon = {
            'id': salonData['id'].toString(),
            'name': salonData['name'],
            'address': salonData['address'],
            'phone': salonData['phone'],
            'logo_url': salonData['logo_url'],
            'cover_url': salonData['cover_url'],
            'open_time': salonData['open_time'],
            'close_time': salonData['close_time'],
            'is_active': salonData['is_active'],
            'barber_salon_id': item['id'],
          };
          salons.add(salon);

          if (_selectedSalonId == null && salonData['is_active'] == true) {
            _selectedSalonId = salonData['id'].toString();
            _selectedSalonName = salonData['name'] ?? '';
          }
        }
      }

      if (_selectedSalonId != null) {
        await SessionManager.saveSalonId(_selectedSalonId!);
      }
      if (_selectedSalonName.isNotEmpty) {
        await SessionManager.saveSalonName(_selectedSalonName);
      }

      setState(() {
        _assignedSalons = salons;
        if (_selectedSalonId == null && salons.isNotEmpty) {
          _selectedSalonId = salons[0]['id'] as String;
          _selectedSalonName = salons[0]['name'] ?? '';
        } else if (salons.isNotEmpty) {
          final selected = salons.firstWhere(
            (s) => s['id'] == _selectedSalonId,
            orElse: () => {},
          );
          _selectedSalonName = selected['name'] ?? '';
        }
      });

      debugPrint(
        '✅ Selected salon: $_selectedSalonName (ID: $_selectedSalonId)',
      );
      debugPrint('✅ Total assigned salons: ${_assignedSalons.length}');
    } catch (e) {
      debugPrint('❌ Error loading assigned salons: $e');
    }
  }

  // ==================== SALON SELECTION ====================

  void _selectSalon(String salonId) {
    if (_isLoading) return;

    setState(() {
      _selectedSalonId = salonId;
      final selected = _assignedSalons.firstWhere(
        (s) => s['id'] == salonId,
        orElse: () => {},
      );
      _selectedSalonName = selected['name'] ?? '';
    });

    SessionManager.saveSalonId(_selectedSalonId!);
    if (_selectedSalonName.isNotEmpty) {
      SessionManager.saveSalonName(_selectedSalonName);
    }

    _loadDataForSelectedSalon();
  }

  Future<void> _loadDataForSelectedSalon() async {
    if (_selectedSalonId == null) return;

    setState(() => _isLoading = true);

    try {
      await _loadAppointments();
      await _loadStatistics();
      await _loadNotificationCount();

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ Data loaded for salon: $_selectedSalonName');
      }
    } catch (e) {
      debugPrint('❌ Error loading data for salon: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ==================== LOAD DASHBOARD DATA ====================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📊 Loading employee dashboard data...');

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          screen: 'employee_dashboard',
          action: null,
        );

        if (UniversalPlatform.isWeb && _showPermissionCard) {
          final status = await _notificationService.getWebPermissionStatus();
          if (status == 'denied') {
            _showPermissionCard = false;
            if (mounted) {
              _showWebPermissionHelp();
            }
          }
        }
      } else {
        _showPermissionCard = false;
      }

      if (_employeeId.isNotEmpty) {
        await _loadAppointments();
        await _loadStatistics();
        await _loadNotificationCount();
      }

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ Employee data loaded successfully');
        debugPrint(
          '📊 Today: $_todaysAppointments, Completed: $_completedToday, No-Show: $_noShowToday, OnTime: $_onTimePercentage%',
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading employee data: $e');
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

  // =====================================================
  // LOAD APPOINTMENTS WITH PERFORMANCE STATS
  // =====================================================
  Future<void> _loadAppointments() async {
    try {
      final salonId = _selectedSalonId;

      if (salonId == null) {
        debugPrint('⚠️ No salon selected');
        setState(() {
          _todaysAppointmentsList = [];
          _todaysAppointments = 0;
          _completedToday = 0;
          _noShowToday = 0;
          _onTimePercentage = 0;
          _todayEarnings = 0;
        });
        return;
      }

      final salonIdInt = int.parse(salonId);

      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T').first;
      final futureDate = today.add(const Duration(days: 30));
      final futureStr = futureDate.toIso8601String().split('T').first;

      debugPrint('📊 Loading appointments from $todayStr to $futureStr');

      final response = await supabase
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
            salon_id,
            queue_number,
            queue_token,
            is_vip,
            salons!inner (
              id,
              name
            ),
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
          .eq('salon_id', salonIdInt)
          .gte('appointment_date', todayStr)
          .lte('appointment_date', futureStr)
          .neq('status', 'cancelled')
          .neq('status', 'reassigned')
          .neq('status', 'moved')
          .neq('status', 'waiting_list')
          .order('appointment_date', ascending: true)
          .order('start_time', ascending: true);

      debugPrint('📊 Found ${response.length} appointments');

      final List<Map<String, dynamic>> allAppointments = [];

      int todayTotal = 0;
      int todayCompleted = 0;
      int todayNoShow = 0;
      int todayEarnings = 0;
      int totalAppointmentsToday = 0;

      for (var apt in response) {
        final service = apt['services'] as Map?;
        final variant = apt['service_variants'] as Map?;
        final customer = apt['profiles'] as Map?;
        final salon = apt['salons'] as Map?;

        final status = apt['status'] as String? ?? 'pending';
        final aptDate = apt['appointment_date'] as String;
        final isToday = aptDate == todayStr;

        final price =
            (apt['price'] as num?)?.toDouble() ??
            (variant?['price'] as num?)?.toDouble() ??
            0.0;

        final startTimeLocal = _utcToLocalTimeString(apt['start_time']);
        final endTimeLocal = _utcToLocalTimeString(apt['end_time']);

        if (isToday) {
          todayTotal++;
          totalAppointmentsToday++;
          
          if (status == 'completed') {
            todayCompleted++;
            todayEarnings += price.toInt();
          } else if (status == 'no_show') {
            todayNoShow++;
          }
        }

        allAppointments.add({
          'id': apt['id'],
          'booking_number': apt['booking_number'],
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_phone': customer?['phone'] ?? '',
          'service_name': service?['name'] ?? 'Unknown Service',
          'salon_name': salon?['name'] ?? 'Unknown Salon',
          'appointment_date': aptDate,
          'is_today': isToday,
          'display_date': _formatDateDisplay(aptDate),
          'start_time': startTimeLocal,
          'end_time': endTimeLocal,
          'status': status,
          'price': price,
          'duration': variant?['duration'] ?? 30,
          'is_vip': apt['is_vip'] ?? false,
          'queue_number': apt['queue_number'],
          'queue_token': apt['queue_token'],
        });
      }

      // ✅ Calculate On Time Percentage
      int onTimePercentage = 0;
      if (totalAppointmentsToday > 0) {
        onTimePercentage = ((todayCompleted / totalAppointmentsToday) * 100).round();
      }

      setState(() {
        _todaysAppointmentsList = allAppointments;
        _todaysAppointments = todayTotal;
        _completedToday = todayCompleted;
        _noShowToday = todayNoShow;
        _onTimePercentage = onTimePercentage;
        _todayEarnings = todayEarnings;
      });

      debugPrint('✅ Today: $_todaysAppointments appointments');
      debugPrint('✅ Today Completed: $_completedToday');
      debugPrint('✅ Today No-Show: $_noShowToday');
      debugPrint('✅ On Time: $_onTimePercentage%');
      debugPrint('✅ Total appointments in list: ${allAppointments.length}');
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
      setState(() {
        _todaysAppointmentsList = [];
        _todaysAppointments = 0;
        _completedToday = 0;
        _noShowToday = 0;
        _onTimePercentage = 0;
        _todayEarnings = 0;
      });
    }
  }

  // =====================================================
  // LOAD STATISTICS
  // =====================================================
  Future<void> _loadStatistics() async {
    try {
      final salonId = _selectedSalonId;

      if (salonId == null) {
        debugPrint('⚠️ No salon selected for statistics');
        setState(() {
          _totalCustomers = 0;
          _monthlyEarnings = 0;
          _rating = 0.0;
        });
        return;
      }

      final salonIdInt = int.parse(salonId);

      debugPrint('📊 Loading statistics for salon: $salonId');

      // 1. TOTAL CUSTOMERS SERVED
      final customersResponse = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .eq('salon_id', salonIdInt);

      final uniqueCustomers = customersResponse
          .map((a) => a['customer_id'])
          .toSet()
          .length;

      // 2. MONTHLY EARNINGS
      final firstDayOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      );
      final firstDayStr = firstDayOfMonth.toIso8601String().split('T').first;

      final lastDayOfMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month + 1,
        0,
      );
      final lastDayStr = lastDayOfMonth.toIso8601String().split('T').first;

      final monthlyResponse = await supabase
          .from('appointments')
          .select('price')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .eq('salon_id', salonIdInt)
          .gte('appointment_date', firstDayStr)
          .lte('appointment_date', lastDayStr);

      int monthlyTotal = 0;
      for (var apt in monthlyResponse) {
        monthlyTotal += (apt['price'] as num?)?.toInt() ?? 0;
      }

      // 3. AVERAGE RATING
      final reviewsResponse = await supabase
          .from('reviews')
          .select('overall_rating')
          .eq('barber_id', _employeeId)
          .eq('salon_id', salonIdInt);

      double avgRating = 0.0;
      if (reviewsResponse.isNotEmpty) {
        double totalRating = 0;
        for (var review in reviewsResponse) {
          totalRating += (review['overall_rating'] as num?)?.toDouble() ?? 0;
        }
        avgRating = totalRating / reviewsResponse.length;
      }

      setState(() {
        _totalCustomers = uniqueCustomers;
        _monthlyEarnings = monthlyTotal;
        _rating = avgRating;
      });

      debugPrint(
        '✅ Stats - Customers: $uniqueCustomers, Monthly: $monthlyTotal, Rating: $avgRating',
      );
    } catch (e) {
      debugPrint('❌ Error loading statistics: $e');
      setState(() {
        _totalCustomers = 0;
        _monthlyEarnings = 0;
        _rating = 0.0;
      });
    }
  }

  // ==================== NOTIFICATION SETUP ====================

  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New message: ${message.data}');

        if (message.data['type'] == 'new_booking_assigned') {
          _showNewAssignmentAlert(message);
          _loadData();
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
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
            Text(
              'New Booking Assigned!',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.notification?.title ?? 'New Appointment',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ?? 'You have a new booking assigned',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
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
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
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
            Expanded(
              child: Text(
                message.notification?.body ?? 'Upcoming appointment',
                style: const TextStyle(color: Colors.white),
              ),
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

  // ==================== PERMISSIONS ====================

  Future<void> _enableNotifications() async {
    setState(() => _showPermissionCard = false);

    try {
      final bool isWeb = UniversalPlatform.isWeb;

      if (isWeb) {
        final status = await _notificationService.getWebPermissionStatus();
        if (status == 'denied') {
          if (mounted) {
            _showWebPermissionHelp();
          }
          return;
        }
      }

      final canAsk = await _permissionManager.canAskSystemPermission();

      if (!canAsk) {
        _showSettingsDialog();
        return;
      }
      if (!mounted) return;

      await _permissionService.requestPermissionAtAction(
        context: context,
        action: 'employee_dashboard',
        customTitle: _permissionManager.getPermissionCardTitle(action: null),
        customMessage: _permissionManager.getPermissionCardMessage(
          action: null,
        ),
        onGranted: () async {
          await _permissionManager.markPermissionGranted();
          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isWeb
                      ? '✅ Notifications enabled in browser!'
                      : '✅ Notifications enabled!',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        onDenied: () async {
          await _permissionManager.markPermissionDenied(permanent: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isWeb
                      ? 'You can enable notifications later from browser settings'
                      : 'You can enable later from settings',
                ),
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

  void _showSettingsDialog() {
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
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

  // ==================== CONTEXTUAL NAVIGATION ====================

  void _viewMySchedule() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'schedule');
      if (_showPermissionCard) {
        return;
      }
    }
    if (_selectedSalonId != null) {
      context.push('/barber/appointments?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/appointments');
    }
  }

  void _viewMyCustomers() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'customer');
      if (_showPermissionCard) {
        return;
      }
    }
    if (_selectedSalonId != null) {
      context.push('/barber/customers?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/customers');
    }
  }

  void _viewTodayEarnings() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'earnings');
      if (_showPermissionCard) {
        return;
      }
    }
    if (_selectedSalonId != null) {
      context.push('/barber/revenue?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/revenue');
    }
  }

  void _viewUpcomingAppointments() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'appointment');
      if (_showPermissionCard) {
        return;
      }
    }
    if (_selectedSalonId != null) {
      context.push('/barber/appointments?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/appointments');
    }
  }

  void _viewNotifications() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'notification');
      if (_showPermissionCard) {
        return;
      }
    }
    context.push('/notifications?role=barber');
  }

  void _viewBookingDetails(String customerName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing $customerName\'s booking'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ==================== SALON SELECTOR DIALOG ====================

  Future<void> _showSalonSelectorDialog() async {
    final isDark = context.isDarkMode;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Salon',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a salon to view its data',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            ..._assignedSalons.map((salon) {
              final isSelected = salon['id'] == _selectedSalonId;
              return ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: isSelected
                      ? AppTheme.primary
                      : Colors.grey[200],
                  backgroundImage: salon['logo_url'] != null
                      ? NetworkImage(salon['logo_url'])
                      : null,
                  child: salon['logo_url'] == null
                      ? Icon(
                          Icons.store,
                          color: isSelected ? Colors.white : Colors.grey[600],
                          size: 20,
                        )
                      : null,
                ),
                title: Text(
                  salon['name'] ?? 'Unknown Salon',
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  salon['address'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: AppTheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _selectSalon(salon['id'] as String);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDarkMode;

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
                color: isDark ? Colors.white : color,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              _getQuickActionSubtitle(label),
              style: TextStyle(
                fontSize: 9,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getQuickActionSubtitle(String label) {
    switch (label) {
      case 'My Schedule':
        return 'View today\'s bookings';
      default:
        return '';
    }
  }

  Widget _buildPerformanceItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isDark = context.isDarkMode;

    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // =====================================================
  // BUILD METHOD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final isDark = context.isDarkMode;

    _checkScreenSize();

    if (!_isTimezoneLoaded) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Employee Dashboard'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'Menu',
              iconSize: 28,
            ),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
            iconSize: 28,
          ),
        ),
        title: Row(
          children: [
            if (!isWeb)
              Flexible(
                child: Text(
                  _selectedSalonName.isNotEmpty
                      ? _selectedSalonName
                      : 'Dashboard',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
          ],
        ),
        actions: [
          // Salon Selector (Web)
          if (isWeb && _selectedSalonName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _assignedSalons.length > 1
                    ? _showSalonSelectorDialog
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.store, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _selectedSalonName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_assignedSalons.length > 1)
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: Colors.white,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Salon Selector Chip (Mobile)
          if (_assignedSalons.length > 1 && !isWeb)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: _showSalonSelectorDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.store, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.35,
                        ),
                        child: Text(
                          _selectedSalonName.isNotEmpty
                              ? _selectedSalonName
                              : 'Salon',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Notification Icon
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  size: 22,
                  color: Colors.white,
                ),
                onPressed: _viewNotifications,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (_unreadNotificationCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _unreadNotificationCount > 99
                          ? '99+'
                          : '$_unreadNotificationCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // Profile Image
          _buildProfileImage(),
          const SizedBox(width: 8),
        ],
      ),
      drawer: SideMenu(
        userRole: 'barber',
        userName: _employeeName,
        userEmail: _employeeEmail,
        profileImageUrl: _employeeAvatar.isNotEmpty ? _employeeAvatar : null,
        selectedSalonId: _selectedSalonId,
        onMenuItemSelected: () => _loadData(),
        onSalonChanged: (String salonId) {
          _selectSalon(salonId);
        },
      ),
      body: SafeArea(
        child: isDark
            ? Container(
                color: const Color(0xFF121212),
                child: _buildBody(isWeb),
              )
            : _buildBody(isWeb),
      ),
    );
  }

  Widget _buildBody(bool isWeb) {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          )
        : Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isWeb ? 1200 : double.infinity,
              ),
              child: isWeb
                  ? Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 8.0,
                      radius: const Radius.circular(10),
                      scrollbarOrientation: ScrollbarOrientation.right,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        child: _buildDashboardContent(),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      child: _buildDashboardContent(),
                    ),
            ),
          );
  }

  // =====================================================
  // DASHBOARD CONTENT
  // =====================================================
  Widget _buildDashboardContent() {
    final isDark = context.isDarkMode;

    return Column(
      children: [
        // PERMISSION CARD
        if (_showPermissionCard && !_hasPermission)
          PermissionCard(
            onEnable: _enableNotifications,
            onNotNow: _handleNotNow,
            title: _permissionManager.getPermissionCardTitle(),
            message: _permissionManager.getPermissionCardMessage(),
          ),

        const SizedBox(height: 8),

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
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star, color: Colors.amber, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Rating',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Row(
                    children: [
                      Text(
                        _rating > 0 ? _rating.toStringAsFixed(1) : '0.0',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '/ 5.0',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward, color: Colors.green, size: 16),
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

        // Stats Cards - Responsive Grid for Tablet
        if (_isTablet)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: _isLargeScreen ? 3 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                DashboardStatCard(
                  title: "Today's",
                  value: '$_todaysAppointments',
                  icon: Icons.calendar_today,
                  color: Colors.blue,
                  subtitle: '$_completedToday completed',
                  onTap: _viewMySchedule,
                ),
                DashboardStatCard(
                  title: 'Earnings',
                  value: 'Rs. $_todayEarnings',
                  icon: Icons.currency_rupee,
                  color: Colors.green,
                  subtitle: '${_getMonthName()} ₹$_monthlyEarnings',
                  onTap: _viewTodayEarnings,
                ),
                DashboardStatCard(
                  title: 'Total Customers',
                  value: '$_totalCustomers',
                  icon: Icons.people,
                  color: Colors.teal,
                  subtitle: 'All time',
                  onTap: _viewMyCustomers,
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              // Stats Cards - Row 1
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: DashboardStatCard(
                        title: "Today's",
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
                        title: 'Earnings',
                        value: 'Rs. $_todayEarnings',
                        icon: Icons.currency_rupee,
                        color: Colors.green,
                        subtitle: '${_getMonthName()} ₹$_monthlyEarnings',
                        onTap: _viewTodayEarnings,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Stats Cards - Row 2
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
            ],
          ),
        const SizedBox(height: 16),

        // Quick Actions - Only My Schedule
        const SectionHeader(title: 'Quick Actions', actionText: ''),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.schedule_outlined,
                  label: 'My Schedule',
                  color: Colors.blue,
                  onTap: _viewMySchedule,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Today's Schedule with View All
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Today's Schedule",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _viewUpcomingAppointments,
                child: Text(
                  'View All',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child:
              _todaysAppointmentsList
                  .where((a) => a['is_today'] == true)
                  .isEmpty
              ? Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey[200]!,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'No appointments today',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: _todaysAppointmentsList
                      .where((a) => a['is_today'] == true)
                      .map((apt) {
                        Color statusColor;
                        switch (apt['status']) {
                          case 'completed':
                            statusColor = Colors.green;
                            break;
                          case 'confirmed':
                            statusColor = Colors.blue;
                            break;
                          case 'cancelled':
                            statusColor = Colors.red;
                            break;
                          case 'no_show':
                            statusColor = Colors.red;
                            break;
                          default:
                            statusColor = Colors.orange;
                        }
                        return BookingTile(
                          customerName: apt['customer_name'],
                          serviceName: apt['service_name'],
                          time: apt['start_time'],
                          status: apt['status'],
                          statusColor: statusColor,
                          barberName: 'You',
                          price: apt['price'],
                          salonName: apt['salon_name'],
                          isVip: apt['is_vip'] ?? false,
                          queueNumber: apt['queue_number'],
                          queueToken: apt['queue_token'],
                          showActions: apt['status'] != 'completed',
                          onTap: () =>
                              _viewBookingDetails(apt['customer_name']),
                        );
                      })
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),

        // ✅ Performance Card - REAL DATA
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey[200]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Performance",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
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
                      value: '$_noShowToday',
                      icon: Icons.cancel,
                      color: Colors.red,
                    ),
                  ),
                  Expanded(
                    child: _buildPerformanceItem(
                      label: 'On Time',
                      value: '$_onTimePercentage%',
                      icon: Icons.timer,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}