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

  // Multiple salons support
  List<Map<String, dynamic>> _ownerSalons = [];
  String? _selectedSalonId;
  final bool _isLoadingSalons = false;

  // User info
  String _userName = 'Salon Owner';
  String? _userEmail;
  String? _profileImageUrl;

  // Onboarding steps
  int _completedSteps = 0;
  final int _totalSteps = 5;
  bool _hasSalon = false;
  bool _hasServices = false;
  bool _hasBarbers = false;
  bool _hasBarberSchedule = false;
  bool _hasHolidays = false;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _setupNotificationListeners();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([_loadUserProfile(), _loadOwnerSalons()]);
      await _loadDashboardStats();
      await _checkOnboardingStatus();

      _hasPermission = await _notificationService.hasPermission();
      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          'owner_dashboard',
        );
      } else {
        _showPermissionCard = false;
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
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

  Future<void> _loadOwnerSalons() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('salons')
          .select('id, name, address, is_active, created_at')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          if (_ownerSalons.isNotEmpty && _selectedSalonId == null) {
            _selectedSalonId = _ownerSalons.first['id'].toString();
            _hasSalon = true;
          } else {
            _hasSalon = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading salons: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, email, avatar_url, extra_data')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (profileResponse != null && mounted) {
        setState(() {
          _userName =
              profileResponse['full_name'] ??
              profileResponse['extra_data']?['full_name'] ??
              'Salon Owner';
          _userEmail = profileResponse['email'] ?? currentUser.email;
          _profileImageUrl = profileResponse['avatar_url'];
        });
      }

      final rolesResponse = await supabase
          .from('user_roles')
          .select('roles!inner (name)')
          .eq('user_id', currentUser.id);

      final List<String> roleNames = [];
      for (var roleEntry in rolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<void> _loadDashboardStats() async {
    if (_selectedSalonId == null) return;

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final salonIdInt = int.parse(_selectedSalonId!);

      final todayAppointments = await supabase
          .from('appointments')
          .select('id, status, price')
          .eq('salon_id', salonIdInt)
          .eq('appointment_date', today);

      final pendingBookings = await supabase
          .from('appointments')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('appointment_date', today)
          .eq('status', 'pending');

      final activeBarbers = await supabase
          .from('salon_barbers')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('status', 'active');

      final totalCustomers = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('salon_id', salonIdInt);

      final uniqueCustomers = totalCustomers
          .map((a) => a['customer_id'] as String)
          .toSet()
          .length;
      final revenue = todayAppointments.fold<int>(
        0,
        (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0),
      );

      if (mounted) {
        setState(() {
          _todayAppointments = todayAppointments.length;
          _pendingBookings = pendingBookings.length;
          _activeBarbers = activeBarbers.length;
          _totalCustomers = uniqueCustomers;
          _totalRevenue = revenue;
          pendingAppointments = _pendingBookings;
          completedToday = todayAppointments
              .where((a) => a['status'] == 'completed')
              .length;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard stats: $e');
    }
  }

  Future<void> _checkOnboardingStatus() async {
    if (_ownerSalons.isEmpty) {
      setState(() {
        _hasSalon = false;
        _hasServices = false;
        _hasBarbers = false;
        _hasBarberSchedule = false;
        _hasHolidays = false;
        _completedSteps = 0;
      });
      return;
    }

    final salonId = int.parse(_selectedSalonId!);

    final servicesResponse = await supabase
        .from('services')
        .select('id')
        .eq('salon_id', salonId)
        .eq('is_active', true)
        .limit(1);
    _hasServices = servicesResponse.isNotEmpty;

    final barbersResponse = await supabase
        .from('salon_barbers')
        .select('id')
        .eq('salon_id', salonId)
        .eq('status', 'active')
        .limit(1);
    _hasBarbers = barbersResponse.isNotEmpty;

    if (_hasBarbers) {
      final schedulesResponse = await supabase
          .from('barber_schedules')
          .select('id')
          .eq('salon_id', salonId)
          .limit(1);
      _hasBarberSchedule = schedulesResponse.isNotEmpty;
    } else {
      _hasBarberSchedule = false;
    }

    final holidaysResponse = await supabase
        .from('salon_holidays')
        .select('id')
        .eq('salon_id', salonId)
        .limit(1);
    _hasHolidays = holidaysResponse.isNotEmpty;

    setState(() {
      _hasSalon = true;
      _completedSteps =
          (_hasSalon ? 1 : 0) +
          (_hasServices ? 1 : 0) +
          (_hasBarbers ? 1 : 0) +
          (_hasBarberSchedule ? 1 : 0) +
          (_hasHolidays ? 1 : 0);
    });
  }

  Future<void> _refreshAllData() async {
    await _loadAllData();
  }

  void _switchSalon(String salonId) {
    setState(() => _selectedSalonId = salonId);
    _loadDashboardStats();
    _checkOnboardingStatus();
  }

  // ============================================================
  // BEAUTIFUL STEP FLOW WITH ARROWS & ANIMATED ICONS
  // ============================================================

  Widget _buildStepFlow() {
    final steps = [
      {
        'label': 'Create\nSalon',
        'isCompleted': _hasSalon,
        'onTap': _navigateToCreateSalon,
        'icon': Icons.store,
        'completedIcon': Icons.check_circle,
        'color': const Color(0xFFFF6B8B),
        'description': 'Set up your salon profile',
      },
      {
        'label': 'Add\nServices',
        'isCompleted': _hasServices,
        'onTap': _navigateToAddService,
        'icon': Icons.build,
        'completedIcon': Icons.check_circle,
        'color': Colors.green,
        'locked': !_hasSalon,
        'description': 'Add your services and pricing',
      },
      {
        'label': 'Add\nBarbers',
        'isCompleted': _hasBarbers,
        'onTap': _navigateToAddBarber,
        'icon': Icons.person_add,
        'completedIcon': Icons.check_circle,
        'color': Colors.purple,
        'locked': !_hasSalon,
        'description': 'Add your team members',
      },
      {
        'label': 'Set\nSchedules',
        'isCompleted': _hasBarberSchedule,
        'onTap': _navigateToBarberSchedule,
        'icon': Icons.schedule,
        'completedIcon': Icons.check_circle,
        'color': Colors.orange,
        'locked': !_hasBarbers,
        'description': 'Set working hours',
      },
      {
        'label': 'Set\nHolidays',
        'isCompleted': _hasHolidays,
        'onTap': _viewSalonHolidays,
        'icon': Icons.beach_access,
        'completedIcon': Icons.check_circle,
        'color': Colors.teal,
        'locked': !_hasSalon,
        'description': 'Add holidays and off days',
      },
    ];

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF6B8B).withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B8B), Color(0xFFFF9BAB)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.rocket_launch,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Salon Setup Progress',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Complete all steps to launch your salon',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up,
                      size: 14,
                      color: const Color(0xFFFF6B8B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_completedSteps/$_totalSteps',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF6B8B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress Bar with Animation
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _completedSteps / _totalSteps),
            duration: const Duration(milliseconds: 500),
            builder: (context, value, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.grey[200],
                  color: const Color(0xFFFF6B8B),
                  minHeight: 6,
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Steps with Horizontal Scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: steps.asMap().entries.map((entry) {
                final index = entry.key;
                final step = entry.value;
                final isCompleted = step['isCompleted'] as bool;
                final isLocked = step['locked'] as bool? ?? false;
                final isActive = !isCompleted && !isLocked;
                final color = step['color'] as Color;

                return Row(
                  children: [
                    // Step Card with Animation
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0.8,
                        end: isActive ? 1.0 : 0.95,
                      ),
                      duration: const Duration(milliseconds: 300),
                      builder: (context, scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: GestureDetector(
                            onTap: isActive
                                ? step['onTap'] as VoidCallback
                                : null,
                            child: Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: isCompleted
                                    ? LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.green.withValues(alpha: 0.15),
                                          Colors.green.withValues(alpha: 0.05),
                                        ],
                                      )
                                    : isActive
                                    ? LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          color.withValues(alpha: 0.15),
                                          color.withValues(alpha: 0.05),
                                        ],
                                      )
                                    : null,
                                color: !isCompleted && !isActive
                                    ? Colors.grey.withValues(alpha: 0.05)
                                    : null,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCompleted
                                      ? Colors.green.withValues(alpha: 0.5)
                                      : isActive
                                      ? color.withValues(alpha: 0.5)
                                      : Colors.grey.withValues(alpha: 0.3),
                                  width: isActive ? 1.5 : 1,
                                ),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  // Animated Icon Container
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOutBack,
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: isCompleted
                                          ? const LinearGradient(
                                              colors: [
                                                Colors.green,
                                                Color(0xFF4CAF50),
                                              ],
                                            )
                                          : isActive
                                          ? LinearGradient(
                                              colors: [
                                                color,
                                                color.withValues(alpha: 0.8),
                                              ],
                                            )
                                          : null,
                                      color: !isCompleted && !isActive
                                          ? Colors.grey[300]
                                          : null,
                                      shape: BoxShape.circle,
                                      boxShadow: isActive
                                          ? [
                                              BoxShadow(
                                                color: color.withValues(
                                                  alpha: 0.4,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        transitionBuilder: (child, animation) {
                                          return ScaleTransition(
                                            scale: animation,
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: isCompleted
                                            ? Icon(
                                                step['completedIcon']
                                                    as IconData,
                                                key: const ValueKey(
                                                  'completed',
                                                ),
                                                color: Colors.white,
                                                size: 28,
                                              )
                                            : Icon(
                                                step['icon'] as IconData,
                                                key: const ValueKey(
                                                  'incomplete',
                                                ),
                                                color: isActive
                                                    ? Colors.white
                                                    : Colors.grey[500],
                                                size: isActive ? 26 : 24,
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Step Label with Animation
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 300),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isCompleted
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isCompleted
                                          ? Colors.green[700]
                                          : isActive
                                          ? color
                                          : Colors.grey[500],
                                    ),
                                    child: Text(
                                      step['label'] as String,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  // Status Indicator
                                  if (!isCompleted && !isLocked)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Pending',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: color,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    )
                                  else if (isLocked && !isCompleted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.lock,
                                            size: 8,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            'Locked',
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (isCompleted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Done ✓',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.green[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Animated Arrow between steps
                    if (index < steps.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          child: Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: steps[index]['isCompleted'] as bool
                                ? Colors.green
                                : steps[index + 1]['isCompleted'] as bool
                                ? Colors.green.withValues(alpha: 0.5)
                                : Colors.grey[400],
                          ),
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),

          // Path/Follow Line Indicator
          if (_completedSteps > 0 && _completedSteps < _totalSteps)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, value, child) {
                        return Transform.rotate(
                          angle: value * 3.14159 * 2,
                          child: const Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Color(0xFFFF6B8B),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Next: ${_getNextStepLabel(steps)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFFFF6B8B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Completion Message with Animation
          if (_completedSteps == _totalSteps)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green, Colors.green[700]!],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.celebration,
                              size: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '🎉 Congratulations! Your salon is ready to launch! 🎉',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Helper method to get next step label
  String _getNextStepLabel(List<Map<String, dynamic>> steps) {
    for (var step in steps) {
      if (!(step['isCompleted'] as bool) &&
          !(step['locked'] as bool? ?? false)) {
        return (step['label'] as String).replaceAll('\n', ' ');
      }
    }
    return 'Complete remaining steps';
  }

  // ============================================================
  // ORIGINAL MANAGEMENT SECTION - SAME DESIGN AS BEFORE
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              const SizedBox(width: 8),
              _buildQuickAction(
                icon: Icons.beach_access,
                label: 'Holidays',
                color: Colors.teal,
                onTap: _viewSalonHolidays,
                enabled: _ownerSalons.isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Row 2: Service Management
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
                icon: Icons.list,
                label: 'Service List',
                color: Colors.cyan,
                onTap: _navigateToServiceList,
                enabled: _ownerSalons.isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Row 3: Barber Management
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
                onTap: _navigateToBarberList,
                enabled: _ownerSalons.isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Row 4: VIP & Reports
          const Text(
            'VIP & Reports',
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
                icon: Icons.star,
                label: 'VIP Requests',
                color: Colors.deepOrange,
                onTap: _viewVIPRequests,
                enabled: _ownerSalons.isNotEmpty,
              ),
              const SizedBox(width: 8),
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

          // Row 5: Category Management
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
        ],
      ),
    );
  }

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
              Icon(icon, color: enabled ? color : Colors.grey[400], size: 28),
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
      child: Row(
        children: [
          const Icon(Icons.store, size: 18, color: Color(0xFFFF6B8B)),
          const SizedBox(width: 8),
          const Text(
            'Salon:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _ownerSalons.map((salon) {
                  final isSelected = _selectedSalonId == salon['id'].toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        salon['name'] ?? 'Salon',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: isSelected,
                      onSelected: (_) => _switchSalon(salon['id'].toString()),
                      backgroundColor: Colors.grey[100],
                      selectedColor: const Color(
                        0xFFFF6B8B,
                      ).withValues(alpha: 0.2),
                      checkmarkColor: const Color(0xFFFF6B8B),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[800],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: _navigateToEditSalon,
            tooltip: 'Edit Salon',
            color: const Color(0xFFFF6B8B),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NAVIGATION METHODS
  // ============================================================

  void _navigateToCreateSalon() async {
    final result = await context.push('/owner/salon/create');
    if (result == true) await _refreshAllData();
  }

  void _navigateToEditSalon() async {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    final result = await context.push(
      '/owner/salon/edit?salonId=$_selectedSalonId',
    );
    if (result == true) await _refreshAllData();
  }

  void _navigateToAddBarber() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/add-barber?salonId=$_selectedSalonId');
  }

  void _navigateToBarberLeaves() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/barber-leaves?salonId=$_selectedSalonId');
  }

  void _navigateToBarberSchedule() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/barber-schedule?salonId=$_selectedSalonId');
  }

  void _navigateToBarberList() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/barbers?salonId=$_selectedSalonId');
  }

  void _navigateToAddService() async {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    final result = await context.push(
      '/owner/services/add?salonId=$_selectedSalonId',
    );
    if (result == true) await _refreshAllData();
  }

void _navigateToServiceList() {
  if (_ownerSalons.isEmpty) {
    _showCreateSalonFirstDialog();
    return;
  }
  
  // If there are multiple salons, show selection dialog
  if (_ownerSalons.length == 1) {
    // Single salon - navigate directly
    final salon = _ownerSalons.first;
    final salonId = salon['id'] as int;
    final salonName = salon['name'] as String;
    
    debugPrint('📍 Navigating to service management for salon: $salonName (ID: $salonId)');
    
    // ✅ FIXED: Use the correct route path
    context.push('/owner/services?salonId=$salonId&salonName=${Uri.encodeComponent(salonName)}');
  } else {
    // Multiple salons - show selection dialog
    _showSalonSelectionDialogForServices();
  }
}

void _showSalonSelectionDialogForServices() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Salon'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _ownerSalons.length,
          itemBuilder: (context, index) {
            final salon = _ownerSalons[index];
            final salonId = salon['id'] as int;
            final salonName = salon['name'] as String;
            
            return ListTile(
              leading: const Icon(Icons.store, color: Color(0xFFFF6B8B)),
              title: Text(salonName),
              subtitle: Text('ID: $salonId'),
              onTap: () {
                Navigator.pop(context);
                debugPrint('📍 Navigating to service management for salon: $salonName (ID: $salonId)');
                // ✅ FIXED: Use the correct route path
                context.push('/owner/services?salonId=$salonId&salonName=${Uri.encodeComponent(salonName)}');
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

  void _navigateToAddCategory() async {
    final result = await context.push('/owner/categories/add');
    if (result == true) await _refreshAllData();
  }

  void _navigateToCategoryList() {
    context.push('/owner/categories');
  }

  void _navigateToAddGender() async {
    final result = await context.push('/owner/genders/add');
    if (result == true) await _refreshAllData();
  }

  void _navigateToGenderList() {
    context.push('/owner/genders');
  }

  void _navigateToAddAgeCategory() async {
    final result = await context.push('/owner/age-categories/add');
    if (result == true) await _refreshAllData();
  }

  void _navigateToAgeCategoryList() {
    context.push('/owner/age-categories');
  }

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
    context.push('/owner/reports');
  }

  void _viewAnalytics() {
    context.push('/owner/analytics');
  }

  void _viewSettings() {
    context.push('/owner/settings');
  }

  void _viewSalonHolidays() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/salon/holidays?salonId=$_selectedSalonId');
  }

  void _viewVIPRequests() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/vip-requests?salonId=$_selectedSalonId');
  }

  void _showCreateSalonFirstDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Salon First'),
        content: const Text(
          'You need to create a salon before managing barbers or services.',
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
                  content: Text('✅ Appointment completed'),
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
  // NOTIFICATION METHODS
  // ============================================================

  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data['type'] == 'new_booking') {
          _showNewBookingAlert(message);
          setState(() {
            _pendingBookings++;
            pendingAppointments++;
          });
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data['type'] == 'new_booking') _viewBookings();
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _showNewBookingAlert(RemoteMessage message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Booking!'),
        content: Text(
          message.notification?.body ?? 'A customer has booked an appointment',
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

  Future<void> _enableNotifications() async {
    setState(() => _showPermissionCard = false);
    try {
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
        },
        onDenied: () async =>
            await _permissionManager.markPermissionDenied(permanent: false),
      );
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('owner_dashboard');
  }

  void _openDrawer() {
    try {
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
      } else {
        Scaffold.of(context).openDrawer();
      }
    } catch (e) {
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
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Appointments'),
                onTap: () {
                  Navigator.pop(context);
                  _viewBookings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Customers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewAllCustomers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_cut),
                title: const Text('Barbers'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToBarberList();
                },
              ),
              const Divider(),
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
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
          ),
        );
        try {
          await SessionManager.logoutForContinue();
          await appState.refreshState();
          if (context.mounted) {
            Navigator.pop(context);
            context.go('/');
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context);
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

  String _getFormattedDate() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

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
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAllData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: SideMenu(
        userRole: 'owner',
        userName: _userName,
        userEmail: _userEmail,
        profileImageUrl: _profileImageUrl,
        onMenuItemSelected: () => _refreshAllData(),
      ),
      body: _isLoading || _isLoadingSalons
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : RefreshIndicator(
              onRefresh: _refreshAllData,
              color: const Color(0xFFFF6B8B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: _enableNotifications,
                        onNotNow: _handleNotNow,
                        title: '🔔 Get Booking Alerts',
                        message:
                            'Get instant notifications when customers book appointments',
                        compact: true,
                      ),

                    // Header
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF6B8B,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: Color(0xFFFF6B8B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getFormattedDate(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFFF6B8B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Step Flow (NEW DESIGN)
                    if (_completedSteps < _totalSteps) _buildStepFlow(),

                    if (_ownerSalons.length > 1) _buildSalonSelector(),

                    if (_ownerSalons.isEmpty)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.warning,
                              color: Colors.orange,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'No Salons Found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Create your first salon to get started',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _navigateToCreateSalon,
                              icon: const Icon(Icons.add_business, size: 18),
                              label: const Text('Create Salon'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B8B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_ownerSalons.isNotEmpty) ...[
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
                                onTap: _viewBookings,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DashboardStatCard(
                                title: 'Pending',
                                value: '$_pendingBookings',
                                icon: Icons.pending_actions,
                                color: Colors.orange,
                                onTap: _viewBookings,
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
                                title: 'Customers',
                                value: '$_totalCustomers',
                                icon: Icons.people,
                                color: Colors.purple,
                                onTap: _viewAllCustomers,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DashboardStatCard(
                                title: 'Barbers',
                                value: '$_activeBarbers',
                                icon: Icons.content_cut,
                                color: Colors.green,
                                onTap: _navigateToBarberList,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: DashboardStatCard(
                          title: 'Revenue',
                          value: 'Rs. $_totalRevenue',
                          icon: Icons.currency_rupee,
                          color: Colors.green,
                          fullWidth: true,
                          onTap: _viewRevenue,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    _buildManagementSection(),
                    const SizedBox(height: 16),

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
                  ],
                ),
              ),
            ),
    );
  }
}
