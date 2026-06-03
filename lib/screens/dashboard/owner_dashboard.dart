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
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  // ── Pulse animation for next step ──────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;
  bool _isSwitchingSalon = false;

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

    // Pulse: 1.0 → 1.06 → 1.0, repeating
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _loadAllData();
    _setupNotificationListeners();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
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
          } else if (_ownerSalons.isEmpty) {
            _hasSalon = false;
          } else {
            _hasSalon = true;
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
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<void> _loadDashboardStats() async {
    if (_selectedSalonId == null || _ownerSalons.isEmpty) return;
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

      final uniqueCustomers =
          totalCustomers.map((a) => a['customer_id'] as String).toSet().length;
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
    if (_ownerSalons.isEmpty || _selectedSalonId == null) {
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

    try {
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

      if (mounted) {
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
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
    }
  }

  Future<void> _refreshAllData() async => _loadAllData();

  Future<void> _switchSalon(String salonId) async {
    if (_isSwitchingSalon || salonId == _selectedSalonId) return;
    
    setState(() {
      _isSwitchingSalon = true;
      _selectedSalonId = salonId;
    });
    
    try {
      await Future.wait([
        _loadDashboardStats(),
        _checkOnboardingStatus(),
      ]);
    } catch (e) {
      debugPrint('Error switching salon: $e');
    } finally {
      if (mounted) {
        setState(() => _isSwitchingSalon = false);
      }
    }
  }

  // ============================================================
  // SALON SETUP STEP FLOW
  // ============================================================

  Widget _buildStepFlow() {
    final steps = [
      {
        'label': 'Create Salon',
        'subtitle': 'Set up your profile',
        'isCompleted': _hasSalon,
        'onTap': _navigateToCreateSalon,
        'icon': Icons.storefront_outlined,
        'locked': false,
      },
      {
        'label': 'Add Services',
        'subtitle': 'Services & pricing',
        'isCompleted': _hasServices,
        'onTap': _navigateToAddService,
        'icon': Icons.content_cut_outlined,
        'locked': !_hasSalon,
      },
      {
        'label': 'Add Barbers',
        'subtitle': 'Your team',
        'isCompleted': _hasBarbers,
        'onTap': _navigateToAddBarber,
        'icon': Icons.people_outline,
        'locked': !_hasSalon,
      },
      {
        'label': 'Set Schedules',
        'subtitle': 'Working hours',
        'isCompleted': _hasBarberSchedule,
        'onTap': _navigateToBarberSchedule,
        'icon': Icons.calendar_month_outlined,
        'locked': !_hasBarbers,
      },
      {
        'label': 'Set Holidays',
        'subtitle': 'Days off',
        'isCompleted': _hasHolidays,
        'onTap': _viewSalonHolidays,
        'icon': Icons.wb_sunny_outlined,
        'locked': !_hasSalon,
      },
    ];

    final nextIdx = steps.indexWhere(
      (s) => !(s['isCompleted'] as bool) && !(s['locked'] as bool? ?? false),
    );

    const pink = Color(0xFFFF6B8B);
    const green = Color(0xFF22C55E);
    final pct = _totalSteps == 0 ? 0.0 : _completedSteps / _totalSteps;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: pink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rocket_launch_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Salon Setup',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      '$_completedSteps of $_totalSteps steps complete',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: pct == 1.0
                      ? green.withValues(alpha: 0.12)
                      : pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: pct == 1.0 ? green : pink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: pct),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, value, _) => Stack(
              children: [
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: value >= 1.0 ? green : pink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              const arrowSlot = 16.0;
              final availableWidth = constraints.maxWidth - (arrowSlot * 4);
              final cardWidth = availableWidth > 0 ? availableWidth / 5 : 60.0;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(steps.length, (i) {
                  final step = steps[i];
                  final isCompleted = step['isCompleted'] as bool;
                  final isLocked = step['locked'] as bool? ?? false;
                  final isActive = !isCompleted && !isLocked;
                  final isNext = i == nextIdx;

                  return Row(
                    children: [
                      _buildStepCard(
                        label: step['label'] as String,
                        subtitle: step['subtitle'] as String,
                        icon: step['icon'] as IconData,
                        isCompleted: isCompleted,
                        isLocked: isLocked,
                        isActive: isActive,
                        isNext: isNext,
                        cardWidth: cardWidth,
                        onTap: isActive
                            ? step['onTap'] as VoidCallback?
                            : null,
                      ),
                      if (i < steps.length - 1)
                        SizedBox(
                          width: arrowSlot,
                          child: Center(
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 10,
                              color: isCompleted
                                  ? green.withValues(alpha: 0.7)
                                  : const Color(0xFFE0E0E0),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              );
            },
          ),
          if (_completedSteps > 0 &&
              _completedSteps < _totalSteps &&
              nextIdx >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: pink,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Up next:  ${steps[nextIdx]['label'] as String}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: pink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (_completedSteps == _totalSteps)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (context, v, _) => Transform.scale(
                scale: v,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.celebration_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Your salon is ready to launch! 🎉',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Step Card ───────────────────────────────────────────────
  Widget _buildStepCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isCompleted,
    required bool isLocked,
    required bool isActive,
    required bool isNext,
    required double cardWidth,
    VoidCallback? onTap,
  }) {
    const pink = Color(0xFFFF6B8B);
    const green = Color(0xFF22C55E);

    final Color circleBg = isCompleted
        ? green
        : isActive
            ? pink
            : const Color(0xFFE5E7EB);

    final Color labelColor = isCompleted
        ? const Color(0xFF15803D)
        : isActive
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFB0B5BF);

    final Color subtitleColor = isCompleted
        ? green.withValues(alpha: 0.8)
        : isActive
            ? const Color(0xFF6B7280)
            : const Color(0xFFD1D5DB);

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: cardWidth,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: isCompleted
            ? green.withValues(alpha: 0.06)
            : isNext
                ? pink.withValues(alpha: 0.07)
                : isActive
                    ? pink.withValues(alpha: 0.04)
                    : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? green.withValues(alpha: 0.4)
              : isNext
                  ? pink.withValues(alpha: 0.65)
                  : isActive
                      ? pink.withValues(alpha: 0.3)
                      : const Color(0xFFEEEEEE),
          width: isNext ? 1.8 : isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon Circle - FIXED: No boxShadow inside AnimatedContainer
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: circleBg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    )
                  : isLocked
                      ? const Icon(
                          Icons.lock_outline_rounded,
                          color: Color(0xFFADB5BD),
                          size: 18,
                        )
                      : Icon(
                          icon,
                          color: Colors.white,
                          size: 20,
                        ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: labelColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: subtitleColor, height: 1.2),
          ),
          const SizedBox(height: 8),
          _buildStatusChip(
            isCompleted: isCompleted,
            isLocked: isLocked,
            isNext: isNext,
          ),
        ],
      ),
    );

    if (isNext) {
      card = ScaleTransition(scale: _pulseAnim, child: card);
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  // ── Status Chip ─────────────────────────────────────────────
  Widget _buildStatusChip({
    required bool isCompleted,
    required bool isLocked,
    required bool isNext,
  }) {
    if (isCompleted) {
      return _chip('Done', const Color(0xFF16A34A), const Color(0xFFDCFCE7));
    }
    if (isLocked) {
      return _chip('Locked', const Color(0xFFADB5BD), const Color(0xFFF3F4F6));
    }
    if (isNext) {
      return _chip(
        'Do This',
        const Color(0xFFFF6B8B),
        const Color(0xFFFFEDF1),
      );
    }
    return _chip('Pending', const Color(0xFFFF6B8B), const Color(0xFFFFEDF1));
  }

  Widget _chip(String text, Color textColor, Color bgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    ),
  );

  // ============================================================
  // MANAGEMENT SECTION
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
            blurRadius: 8.0,
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
          const Text(
            'Reports',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
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
            blurRadius: 8.0,
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
                  final isSelected =
                      _selectedSalonId == salon['id'].toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        salon['name'] ?? 'Salon',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: isSelected,
                      onSelected: (_) =>
                          _switchSalon(salon['id'].toString()),
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
    if (_ownerSalons.length == 1) {
      final salon = _ownerSalons.first;
      final salonId = salon['id'] as int;
      final salonName = salon['name'] as String;
      context.push(
        '/owner/services?salonId=$salonId&salonName=${Uri.encodeComponent(salonName)}',
      );
    } else {
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
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/owner/services?salonId=$salonId&salonName=${Uri.encodeComponent(salonName)}',
                  );
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

  void _viewReports() => context.push('/owner/reports');
  void _viewAnalytics() => context.push('/owner/analytics');
  void _viewSettings() => context.push('/owner/settings');

  void _viewSalonHolidays() {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/salon/holidays?salonId=$_selectedSalonId');
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  // ============================================================
  // BUILD
  // ============================================================

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
      body: _isLoading
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
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
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
                    if (_ownerSalons.isNotEmpty)
                      _isSwitchingSalon
                          ? const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFF6B8B),
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: DashboardStatCard(
                                          title: "Today's Appointments",
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
                            ),
                    const SizedBox(height: 16),
                    _buildManagementSection(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }
}