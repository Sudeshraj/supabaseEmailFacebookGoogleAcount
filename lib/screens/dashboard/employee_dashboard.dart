import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/services/currency_service.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/widgets/dashboard_stat_card.dart';
import 'package:flutter_application_1/widgets/booking_tile.dart';
import 'package:flutter_application_1/widgets/section_header.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import '../../services/timezone_service.dart';
import 'package:intl/intl.dart';

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

  // ==================== ✅ CURRENCY SERVICE ====================
  final CurrencyService _currencyService = CurrencyService.instance;
  String _salonCurrencyCode = 'LKR';

  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_salonCurrencyCode);

  /// ✅ LKR වගේ රටවලට icon එක වෙනුවට "Rs." text එක පෙන්නන්න
  /// USD, EUR වගේ රටවලට icon එක පෙන්නන්න
  bool get _useCurrencyText =>
      _salonCurrencyCode == 'LKR' || _salonCurrencyCode == 'INR';

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;

  // Status check state
  bool _isActive = true;
  bool _isCheckingStatus = true;
  String _inactiveReason = 'Your barber profile is not active.';

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

  // ✅ SALON TIMEZONE (for converting times) — NOT user timezone!
  String _salonTimezone = 'Asia/Colombo';

  // Appointments list
  List<Map<String, dynamic>> _todaysAppointmentsList = [];

  // Notification count
  int _unreadNotificationCount = 0;

  // Responsive screen variables
  bool _isLargeScreen = false;
  bool _isTablet = false;
  bool _isWeb = false;

  // Timezone variables (user timezone — only for reference)
  String _userTimezone = '';
  String _lastTimezone = '';
  bool _isTimezoneLoaded = false;

  // Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // ============================================================
  // ✅ SALON "NOW" — consistent timezone reference
  // ============================================================
  DateTime get _salonNow {
    final tz = _salonTimezone.isNotEmpty ? _salonTimezone : 'Asia/Colombo';
    try {
      return TimezoneService.getNowInTimezone(tz);
    } catch (e) {
      debugPrint('❌ Error getting salon now: $e');
      return DateTime.now();
    }
  }

  DateTime get _salonToday {
    final now = _salonNow;
    return DateTime(now.year, now.month, now.day);
  }

  // ============================================================
  // ✅ CURRENCY HELPERS
  // ============================================================

  /// ✅ withSymbol parameter — Earnings tile එකේදී symbol ඉවත් කරන්න
  String _formatPrice(dynamic price, {bool withSymbol = true}) {
    return _currencyService.format(
      price: price,
      currencyCode: _salonCurrencyCode,
      withSymbol: withSymbol,
    );
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // ✅ Parallel — independent
    await Future.wait([_initializeTimezone(), _checkEmployeeStatus()]);

    if (_isActive) {
      await _loadAssignedSalons();
      await _loadData();
      _setupNotificationListeners();
    }

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
    final size = MediaQuery.sizeOf(context);
    final isLarge = size.width > 800;
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

    _userTimezone = TimezoneService.getCurrentTimezone();
    if (_userTimezone.isEmpty) {
      _userTimezone = 'Asia/Colombo';
    }

    _lastTimezone = _userTimezone;

    if (!mounted) return;
    setState(() {
      _isTimezoneLoaded = true;
    });

    debugPrint('✅ User timezone: $_userTimezone');
  }

  Future<void> _checkTimezoneChange() async {
    if (!_isTimezoneLoaded) return;

    final currentTimezone = TimezoneService.getCurrentTimezone();

    if (_lastTimezone != currentTimezone && _lastTimezone.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _userTimezone = currentTimezone;
        _lastTimezone = currentTimezone;
      });
    }
  }

  // ==================== UTC TO LOCAL CONVERSION ====================

  String _utcToSalonTime(String utcTime, {DateTime? appointmentDate}) {
    if (utcTime.isEmpty) return '--:--';
    try {
      final tz = _salonTimezone.isNotEmpty ? _salonTimezone : 'Asia/Colombo';

      if (appointmentDate != null) {
        return TimezoneService.utcToLocalTimeForDateWithTimezone(
          utcTime,
          appointmentDate,
          tz,
        );
      }
      return TimezoneService.utcToLocalTimeForDateWithTimezone(
        utcTime,
        DateTime(2024, 1, 1),
        tz,
      );
    } catch (e) {
      debugPrint('Error converting UTC to salon time: $e');
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
      final now = _salonToday;

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
      if (dayDiff <= 7 && dayDiff >= 0) {
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return weekdays[date.weekday - 1];
      }

      return '${date.day}/${date.month}';
    } catch (e) {
      return dateStr;
    }
  }

  /// ✅ Use salon timezone for month name
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
    return months[_salonToday.month - 1];
  }

  // ==================== CONTEXTUAL PERMISSION METHODS ====================

  Future<bool> _showPermissionCardContext({String? action}) async {
    final shouldShow = await _permissionManager.shouldShowPermissionCard(
      screen: 'employee_dashboard',
      action: action,
    );

    if (mounted) {
      setState(() {
        _showPermissionCard = shouldShow;
      });
    }
    return shouldShow;
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
            Expanded(
              child: Text(
                'Browser Notification Settings',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
              style: const TextStyle(
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
      if (!mounted) return;
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

  Future<void> _checkEmployeeStatus() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        if (mounted) setState(() => _isActive = false);
        return;
      }

      _employeeId = currentUser.id;
      _employeeEmail = currentUser.email ?? '';

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

      if (!mounted) return;

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
        String message = 'Your barber account is ';
        switch (roleStatus) {
          case 'inactive':
            message += 'deactivated.';
            break;
          case 'scheduled_for_deletion':
            message += 'scheduled for deletion.';
            break;
          case 'deleted':
            message += 'deleted.';
            break;
          default:
            message += 'not active.';
        }
        if (mounted) {
          setState(() {
            _isActive = false;
            _inactiveReason = '$message Please contact support.';
          });
        }
        return;
      }

      if (!isActiveBarber) {
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null) {
          final roles = profile['roles'] as List? ?? [];
          if (roles.contains('barber')) {
            isActiveBarber = true;
          }
        }

        if (!isActiveBarber) {
          if (mounted) {
            setState(() {
              _isActive = false;
              _inactiveReason =
                  'You do not have a barber role. Please contact support.';
            });
          }
          return;
        }
      }

      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, email, avatar_url, is_active, is_blocked')
          .eq('id', _employeeId)
          .maybeSingle();

      if (!mounted) return;

      if (profileResponse != null) {
        if (profileResponse['is_blocked'] == true) {
          if (mounted) {
            setState(() {
              _isActive = false;
              _inactiveReason =
                  'Your account has been blocked. Please contact support.';
            });
          }
          return;
        }

        if (profileResponse['is_active'] == false) {
          if (mounted) {
            setState(() {
              _isActive = false;
              _inactiveReason =
                  'Your profile is inactive. Please contact support.';
            });
          }
          return;
        }

        if (mounted) {
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
        }
      } else {
        final profile = await SessionManager.getProfileByEmail(_employeeEmail);
        if (profile != null && mounted) {
          setState(() {
            _employeeName = profile['name'] ?? _employeeEmail.split('@').first;
            _employeeAvatar = profile['avatar'] ?? '';
          });
        }
      }

      if (mounted) setState(() => _isActive = true);
    } catch (e) {
      debugPrint('❌ Error checking employee status: $e');

      try {
        final email = await SessionManager.getCurrentUserEmail();
        if (email != null) {
          final profile = await SessionManager.getProfileByEmail(email);
          if (profile != null) {
            if (mounted) {
              setState(() {
                _employeeEmail = email;
                _employeeName = profile['name'] ?? email.split('@').first;
                _employeeAvatar = profile['avatar'] ?? '';
                _isActive = true;
              });
            }
            return;
          }
        }
      } catch (fallbackError) {
        debugPrint('❌ Fallback also failed: $fallbackError');
      }
      if (mounted) setState(() => _isActive = true);
    } finally {
      if (mounted && _isCheckingStatus) {
        setState(() => _isCheckingStatus = false);
      }
    }
  }

  // ==================== LOAD ASSIGNED SALONS ====================

  Future<void> _loadAssignedSalons() async {
    try {
      final response = await supabase
          .from('salon_barbers')
          .select('''
            id,
            salon_id,
            status,
            salons!salon_id (
              id,
              name,
              address,
              phone,
              logo_url,
              cover_url,
              open_time,
              close_time,
              is_active,
              currency_code,
              timezone
            )
          ''')
          .eq('barber_id', _employeeId)
          .eq('status', 'active');

      if (!mounted) return;

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
            'currency_code': salonData['currency_code'],
            'timezone': salonData['timezone'],
            'barber_salon_id': item['id'],
          };
          salons.add(salon);

          if (_selectedSalonId == null && salonData['is_active'] == true) {
            _selectedSalonId = salonData['id'].toString();
            _selectedSalonName = salonData['name'] ?? '';
            _salonCurrencyCode = salonData['currency_code'] as String? ?? 'LKR';
            final tz = salonData['timezone'] as String?;
            if (tz != null && tz.isNotEmpty) {
              _salonTimezone = tz;
            }
          }
        }
      }

      if (_selectedSalonId != null) {
        await SessionManager.saveSalonId(_selectedSalonId!);
      }
      if (_selectedSalonName.isNotEmpty) {
        await SessionManager.saveSalonName(_selectedSalonName);
      }

      if (!mounted) return;
      setState(() {
        _assignedSalons = salons;
        if (_selectedSalonId == null && salons.isNotEmpty) {
          _selectedSalonId = salons[0]['id'] as String;
          _selectedSalonName = salons[0]['name'] ?? '';
          _salonCurrencyCode = salons[0]['currency_code'] as String? ?? 'LKR';
          final tz = salons[0]['timezone'] as String?;
          if (tz != null && tz.isNotEmpty) {
            _salonTimezone = tz;
          }
        } else if (salons.isNotEmpty) {
          final selected = salons.firstWhere(
            (s) => s['id'] == _selectedSalonId,
            orElse: () => {},
          );
          _selectedSalonName = selected['name'] ?? '';
          if (selected.isNotEmpty) {
            _salonCurrencyCode = selected['currency_code'] as String? ?? 'LKR';
            final tz = selected['timezone'] as String?;
            if (tz != null && tz.isNotEmpty) {
              _salonTimezone = tz;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading assigned salons: $e');
    }
  }

  // ==================== SALON SELECTION ====================

  Future<void> _selectSalon(String salonId) async {
    if (_isLoading) return;

    setState(() {
      _selectedSalonId = salonId;
      final selected = _assignedSalons.firstWhere(
        (s) => s['id'] == salonId,
        orElse: () => {},
      );
      _selectedSalonName = selected['name'] ?? '';

      if (selected.isNotEmpty) {
        _salonCurrencyCode = selected['currency_code'] as String? ?? 'LKR';
        final tz = selected['timezone'] as String?;
        if (tz != null && tz.isNotEmpty) {
          _salonTimezone = tz;
        }
      }
    });

    await SessionManager.saveSalonId(_selectedSalonId!);
    if (_selectedSalonName.isNotEmpty) {
      await SessionManager.saveSalonName(_selectedSalonName);
    }

    await _loadDataForSelectedSalon();
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
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
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
  // LOAD APPOINTMENTS
  // =====================================================
  Future<void> _loadAppointments() async {
    try {
      final salonId = _selectedSalonId;

      if (salonId == null) {
        if (!mounted) return;
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

      final today = _salonToday;
      final todayStr = DateFormat('yyyy-MM-dd').format(today);
      final futureDate = today.add(const Duration(days: 30));
      final futureStr = DateFormat('yyyy-MM-dd').format(futureDate);

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
            original_price,
            discount_amount,
            extra_charge,
            salon_id,
            queue_number,
            queue_token,
            is_vip,
            salons!inner (
              id,
              name
            ),
            appointment_services (
              id,
              service_id,
              variant_id,
              service_name,
              variant_label,
              duration,
              original_price,
              discount_amount,
              final_price
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

      if (!mounted) return;

      final List<Map<String, dynamic>> allAppointments = [];

      int todayTotal = 0;
      int todayCompleted = 0;
      int todayNoShow = 0;
      int todayEarnings = 0;
      int totalAppointmentsToday = 0;

      for (var apt in response) {
        final customer = apt['profiles'] as Map?;
        final salon = apt['salons'] as Map?;

        final status = apt['status'] as String? ?? 'pending';
        final aptDateStr = apt['appointment_date'] as String;
        final isToday = aptDateStr == todayStr;

        double price = (apt['price'] as num?)?.toDouble() ?? 0.0;
        final servicesList = (apt['appointment_services'] as List?) ?? [];
        if (price <= 0 && servicesList.isNotEmpty) {
          price = servicesList.fold<double>(
            0.0,
            (acc, s) => acc + ((s['final_price'] as num?)?.toDouble() ?? 0.0),
          );
        }

        String serviceName = 'No services';
        int totalDuration = 30;
        if (servicesList.isNotEmpty) {
          final names = servicesList
              .map((s) => s['service_name']?.toString() ?? 'Service')
              .toList();
          serviceName = names.length == 1
              ? names.first
              : '${names.first} +${names.length - 1} more';
          totalDuration = servicesList.fold<int>(
            0,
            (acc, s) => acc + ((s['duration'] as num?)?.toInt() ?? 30),
          );
        }

        DateTime? aptDate;
        try {
          aptDate = DateTime.parse(aptDateStr);
        } catch (_) {}

        final startTimeLocal = _utcToSalonTime(
          apt['start_time'] as String? ?? '',
          appointmentDate: aptDate,
        );
        final endTimeLocal = _utcToSalonTime(
          apt['end_time'] as String? ?? '',
          appointmentDate: aptDate,
        );

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
          'service_name': serviceName,
          'salon_name': salon?['name'] ?? 'Unknown Salon',
          'appointment_date': aptDateStr,
          'is_today': isToday,
          'display_date': _formatDateDisplay(aptDateStr),
          'start_time': startTimeLocal,
          'end_time': endTimeLocal,
          'status': status,
          'price': price,
          'duration': totalDuration,
          'is_vip': apt['is_vip'] ?? false,
          'queue_number': apt['queue_number'],
          'queue_token': apt['queue_token'],
        });
      }

      int onTimePercentage = 0;
      if (totalAppointmentsToday > 0) {
        onTimePercentage = ((todayCompleted / totalAppointmentsToday) * 100)
            .round();
      }

      if (!mounted) return;
      setState(() {
        _todaysAppointmentsList = allAppointments;
        _todaysAppointments = todayTotal;
        _completedToday = todayCompleted;
        _noShowToday = todayNoShow;
        _onTimePercentage = onTimePercentage;
        _todayEarnings = todayEarnings;
      });
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
      if (!mounted) return;
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
        if (!mounted) return;
        setState(() {
          _totalCustomers = 0;
          _monthlyEarnings = 0;
          _rating = 0.0;
        });
        return;
      }

      final salonIdInt = int.parse(salonId);

      final customersResponse = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .eq('salon_id', salonIdInt);

      if (!mounted) return;

      final uniqueCustomers = customersResponse
          .map((a) => a['customer_id'])
          .whereType<String>()
          .toSet()
          .length;

      final salonToday = _salonToday;
      final firstDayOfMonth = DateTime(salonToday.year, salonToday.month, 1);
      final firstDayStr = DateFormat('yyyy-MM-dd').format(firstDayOfMonth);

      final lastDayOfMonth = DateTime(salonToday.year, salonToday.month + 1, 0);
      final lastDayStr = DateFormat('yyyy-MM-dd').format(lastDayOfMonth);

      final monthlyResponse = await supabase
          .from('appointments')
          .select('price')
          .eq('barber_id', _employeeId)
          .eq('status', 'completed')
          .eq('salon_id', salonIdInt)
          .gte('appointment_date', firstDayStr)
          .lte('appointment_date', lastDayStr);

      if (!mounted) return;

      int monthlyTotal = 0;
      for (var apt in monthlyResponse) {
        monthlyTotal += (apt['price'] as num?)?.toInt() ?? 0;
      }

      final reviewsResponse = await supabase
          .from('reviews')
          .select('overall_rating')
          .eq('barber_id', _employeeId)
          .eq('salon_id', salonIdInt)
          .eq('status', 'published');

      if (!mounted) return;

      double avgRating = 0.0;
      if (reviewsResponse.isNotEmpty) {
        double totalRating = 0;
        for (var review in reviewsResponse) {
          totalRating += (review['overall_rating'] as num?)?.toDouble() ?? 0;
        }
        avgRating = totalRating / reviewsResponse.length;
      }

      if (!mounted) return;
      setState(() {
        _totalCustomers = uniqueCustomers;
        _monthlyEarnings = monthlyTotal;
        _rating = avgRating;
      });
    } catch (e) {
      debugPrint('❌ Error loading statistics: $e');
      if (!mounted) return;
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
            Expanded(
              child: Text(
                'New Booking Assigned!',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
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
              _viewMyAppointments();
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
          onPressed: _viewMyAppointments,
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
          if (!mounted) return;
          setState(() {
            _hasPermission = true;
            _showPermissionCard = false;
          });
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
    if (!mounted) return;
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

  Future<void> _viewMySchedule() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(action: 'schedule');
      if (shouldShow) return;
    }
    if (!mounted) return;
    if (_selectedSalonId != null) {
      context.push('/barber/schedule?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/schedule');
    }
  }

  Future<void> _viewMyAppointments() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(action: 'schedule');
      if (shouldShow) return;
    }
    if (!mounted) return;
    if (_selectedSalonId != null) {
      context.push('/barber/appointments?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/appointments');
    }
  }

  Future<void> _viewMyReviews() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(action: 'review');
      if (shouldShow) return;
    }
    if (!mounted) return;
    if (_selectedSalonId != null) {
      context.push('/barber/reviews?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/reviews');
    }
  }

  Future<void> _viewMyCustomers() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(action: 'customer');
      if (shouldShow) return;
    }
    if (!mounted) return;
    if (_selectedSalonId != null) {
      context.push('/barber/customers?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/customers');
    }
  }

  Future<void> _viewTodayEarnings() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(action: 'earnings');
      if (shouldShow) return;
    }
    if (!mounted) return;
    if (_selectedSalonId != null) {
      context.push('/barber/revenue?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/revenue');
    }
  }

  Future<void> _viewUpcomingAppointments() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(
        action: 'appointment',
      );
      if (shouldShow) return;
    }
    if (!mounted) return;
    if (_selectedSalonId != null) {
      context.push('/barber/appointments?salonId=$_selectedSalonId');
    } else {
      context.push('/barber/appointments');
    }
  }

  Future<void> _viewNotifications() async {
    if (!_hasPermission) {
      final shouldShow = await _showPermissionCardContext(
        action: 'notification',
      );
      if (shouldShow) return;
    }
    if (!mounted) return;
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
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
                  contentPadding: EdgeInsets.zero,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  // ============================================================
  // ✅ SALON SELECTOR CHIP — Center chip below AppBar (in body top)
  // ============================================================

  /// Single salon: just show the name as text (no chip, no dropdown)
  /// Multiple salons: show a dropdown chip centered
  /// Long names: responsive with ellipsis
  Widget _buildSalonSelectorChip() {
    if (_assignedSalons.isEmpty) return const SizedBox.shrink();

    final isDark = context.isDarkMode;
    final hasMultipleSalons = _assignedSalons.length > 1;

    // ✅ Single salon: just show name (no chip, no dropdown)
    if (!hasMultipleSalons) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store,
              size: 16,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _selectedSalonName.isNotEmpty ? _selectedSalonName : 'Salon',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Multiple salons: dropdown chip centered
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.7,
          ),
          child: GestureDetector(
            onTap: _showSalonSelectorDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.primary.withValues(alpha: 0.15)
                    : AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.store,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _selectedSalonName.isNotEmpty
                          ? _selectedSalonName
                          : 'Salon',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
          ),
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
    final subtitle = _getQuickActionSubtitle(label);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : color,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
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
        return 'View work schedule';
      case 'My Appointments':
        return 'View bookings';
      case 'My Reviews':
        return 'View ratings';
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : color,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingCard() {
    return GestureDetector(
      onTap: _viewMyReviews,
      child: Container(
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTrend = constraints.maxWidth >= 280;

            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, color: Colors.amber, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Rating',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
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
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showTrend) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.amber,
                    size: 24,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // =====================================================
  // ✅ FIX: Stats cards
  //   - LKR/INR → "Rs."/"₹" text icon එක විදිහට
  //   - USD/EUR/etc → Icon එක
  //   - Value එකේ currency symbol නැහැ (withSymbol: false)
  // =====================================================
  Widget _buildStatsSection() {
    final todaysCard = DashboardStatCard(
      title: "Today's",
      value: '$_todaysAppointments',
      icon: Icons.calendar_today,
      color: Colors.blue,
      subtitle: '$_completedToday completed',
      onTap: _viewMySchedule,
    );

    // ✅ FIX: Earnings card — LKR/INR සඳහා text, වෙනත් සඳහා icon
    final earningsCard = DashboardStatCard(
      title: 'Earnings',
      value: _formatPrice(_todayEarnings, withSymbol: false),
      // ✅ LKR/INR → null (text පෙන්නන්න), වෙනත් → icon
      icon: _useCurrencyText ? null : _currencyService.getIcon(_salonCurrencyCode),
      // ✅ LKR/INR → "Rs."/"₹" text, වෙනත් → null (icon පෙන්නන්න)
      iconText: _useCurrencyText ? _salonCurrencySymbol : null,
      color: Colors.green,
      subtitle:
          '${_getMonthName()}: ${_formatPrice(_monthlyEarnings, withSymbol: false)}',
      onTap: _viewTodayEarnings,
    );

    if (_isTablet) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: todaysCard),
            const SizedBox(width: 12),
            Expanded(child: earningsCard),
            const SizedBox(width: 12),
            Expanded(
              child: DashboardStatCard(
                title: 'Total Customers',
                value: '$_totalCustomers',
                icon: Icons.people,
                color: Colors.teal,
                subtitle: 'All time',
                onTap: _viewMyCustomers,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrow = constraints.maxWidth < 340;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: isVeryNarrow
                  ? Column(
                      children: [
                        todaysCard,
                        const SizedBox(height: 12),
                        earningsCard,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: todaysCard),
                        const SizedBox(width: 12),
                        Expanded(child: earningsCard),
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
          ],
        );
      },
    );
  }

  // =====================================================
  // BUILD METHOD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWeb = screenWidth > 800;
    final isDark = context.isDarkMode;

    if (screenWidth < 240) {
      return const SizedBox.shrink();
    }

    if (!_isTimezoneLoaded || _isCheckingStatus) {
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
        drawer: SideMenu(
          userRole: 'barber',
          userName: _employeeName,
          userEmail: _employeeEmail,
          profileImageUrl: _employeeAvatar.isNotEmpty ? _employeeAvatar : null,
          onMenuItemSelected: () {},
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Loading your dashboard...'),
            ],
          ),
        ),
      );
    }

    if (!_isActive) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
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
          title: null,
          actions: [_buildProfileImage()],
        ),
        drawer: SideMenu(
          userRole: 'barber',
          userName: _employeeName,
          userEmail: _employeeEmail,
          profileImageUrl: _employeeAvatar.isNotEmpty ? _employeeAvatar : null,
          onMenuItemSelected: () {},
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_off_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Profile Inactive',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _inactiveReason,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    setState(() => _isCheckingStatus = true);
                    await _checkEmployeeStatus();
                    if (_isActive) {
                      await _loadAssignedSalons();
                      await _loadData();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Check Status'),
                ),
              ],
            ),
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
        centerTitle: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
            iconSize: 28,
          ),
        ),
        // ✅ Salon selector REMOVED from AppBar title — now shows nothing
        title: null,
        actions: [
          // ✅ Salon selector chip REMOVED from AppBar actions (was web-only chip)
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
                padding: const EdgeInsets.symmetric(horizontal: 6),
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

  Widget _buildDashboardContent() {
    final isDark = context.isDarkMode;
    final todayList = _todaysAppointmentsList
        .where((a) => a['is_today'] == true)
        .toList();

    return Column(
      children: [
        // ✅ Salon selector chip — CENTERED at top of body
        if (_assignedSalons.isNotEmpty) _buildSalonSelectorChip(),

        if (_showPermissionCard && !_hasPermission)
          PermissionCard(
            onEnable: _enableNotifications,
            onNotNow: _handleNotNow,
            title: _permissionManager.getPermissionCardTitle(),
            message: _permissionManager.getPermissionCardMessage(),
          ),

        const SizedBox(height: 8),

        _buildRatingCard(),
        const SizedBox(height: 16),

        _buildStatsSection(),
        const SizedBox(height: 16),

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
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.calendar_month_outlined,
                  label: 'My Appointments',
                  color: Colors.purple,
                  onTap: _viewMyAppointments,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.star_outline,
                  label: 'My Reviews',
                  color: Colors.amber,
                  onTap: _viewMyReviews,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's Schedule",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _viewUpcomingAppointments,
                child: Text(
                  'View All',
                  maxLines: 1,
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: todayList.isEmpty
              ? Container(
                  width: double.infinity,
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
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: todayList.map((apt) {
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
                      formattedPrice: _formatPrice(apt['price']),
                      salonName: apt['salon_name'],
                      isVip: apt['is_vip'] ?? false,
                      queueNumber: apt['queue_number'],
                      queueToken: apt['queue_token'],
                      showActions: apt['status'] != 'completed',
                      onTap: () => _viewBookingDetails(apt['customer_name']),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 16),

        Container(
          width: double.infinity,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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