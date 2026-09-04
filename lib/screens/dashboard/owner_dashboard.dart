import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/widgets/dashboard_stat_card.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard>
    with SingleTickerProviderStateMixin, RouteAware {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;
  bool _isSwitchingSalon = false;

  // Dashboard data
  int _completedToday = 0;
  int _pendingBookings = 0;
  int _todayAppointments = 0;
  int _totalRevenue = 0;
  int _totalCustomers = 0;
  int _activeBarbers = 0;

  // Multiple salons support
  List<Map<String, dynamic>> _ownerSalons = [];
  String? _selectedSalonId;
  String? _selectedSalonName;

  // User info
  String _userName = 'Salon Owner';
  String? _userEmail;
  String? _profileImageUrl;

  // Notification count
  int _unreadNotificationCount = 0;

  // ✅ Android 16: Responsive screen variables
  bool _isLargeScreen = false;
  bool _isTablet = false;
  bool _isWeb = false;

  // Onboarding steps
  int _completedSteps = 0;
  final int _totalSteps = 5;
  bool _hasSalon = false;
  bool _hasServices = false;
  bool _hasBarbers = false;
  bool _hasBarberSchedule = false;
  bool _hasHolidays = false;

  final supabase = Supabase.instance.client;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _initializeAndLoad();
    _setupNotificationListeners();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
    _checkScreenSize();
  }

  // ✅ Android 16: Check screen size for responsive layout
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
  void didPopNext() {
    debugPrint('🔄 Dashboard: Returning from child screen, refreshing data');
    _refreshAllData();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _pulseCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoad() async {
    await _ensureOwnerRole();
    await _loadAllData();
  }

  Future<void> _ensureOwnerRole() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ No user logged in');
        return;
      }

      debugPrint('🔍 Ensuring owner role for user: $userId');

      final ownerCheck = await supabase
          .from('user_roles')
          .select('id, status')
          .eq('user_id', userId)
          .eq('role_id', 1)
          .maybeSingle();

      if (ownerCheck == null) {
        debugPrint('🔄 Creating owner role...');
        await supabase.from('user_roles').insert({
          'user_id': userId,
          'role_id': 1,
          'status': 'active',
        });
        debugPrint('✅ Owner role created');
      } else if (ownerCheck['status'] != 'active') {
        debugPrint('🔄 Updating owner role to active...');
        await supabase
            .from('user_roles')
            .update({
              'status': 'active',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', userId)
            .eq('role_id', 1);
        debugPrint('✅ Owner role activated');
      } else {
        debugPrint('✅ Owner role already active');
      }

      for (var roleId in [2, 3]) {
        final check = await supabase
            .from('user_roles')
            .select('id, status')
            .eq('user_id', userId)
            .eq('role_id', roleId)
            .maybeSingle();

        if (check == null) {
          await supabase.from('user_roles').insert({
            'user_id': userId,
            'role_id': roleId,
            'status': 'active',
          });
          debugPrint('✅ Role $roleId created');
        } else if (check['status'] != 'active') {
          await supabase
              .from('user_roles')
              .update({
                'status': 'active',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('user_id', userId)
              .eq('role_id', roleId);
          debugPrint('✅ Role $roleId activated');
        }
      }

      await supabase.auth.refreshSession();
      debugPrint('✅ Session refreshed');
    } catch (e) {
      debugPrint('❌ Error ensuring owner role: $e');
    }
  }

  // ============================================================
  // ✅ PROFILE IMAGE - Navigates to Profile Screen
  // ============================================================

  Widget _buildProfileImage() {
    final hasImage = _profileImageUrl != null && _profileImageUrl!.isNotEmpty;
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
          backgroundImage: hasImage ? NetworkImage(_profileImageUrl!) : null,
          onBackgroundImageError: hasImage
              ? (exception, stackTrace) {
                  debugPrint('⚠️ Failed to load avatar image: $exception');
                }
              : null,
          child: !hasImage
              ? Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
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

  // ============================================================
  // ✅ NOTIFICATION COUNT
  // ============================================================

  Future<void> _loadNotificationCount() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ No user ID for notification count');
        return;
      }

      final count = await _notificationService.getUnreadCountWithRole(
        userId: userId,
        role: 'owner',
      );

      if (mounted) {
        setState(() {
          _unreadNotificationCount = count;
        });
      }
      debugPrint('✅ Unread notifications (owner): $count');
    } catch (e) {
      debugPrint('❌ Error loading notification count: $e');
    }
  }

  // ============================================================
  // ✅ NOTIFICATION ICON WITH BADGE
  // ============================================================

  Widget _buildNotificationIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
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
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
    );
  }

  // ============================================================
  // ✅ NOTIFICATION DIALOGS
  // ============================================================

  void _showNewBookingAlert(RemoteMessage message) {
    if (!mounted) return;
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active,
                color: AppTheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'New Booking!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.notification?.body ??
                          'A customer has booked an appointment',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Would you like to view this booking now?',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.grey[500],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white60 : Colors.grey[600],
            ),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewBookings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('View Now'),
          ),
        ],
      ),
    );
  }

  void _showNewAssignmentAlert(RemoteMessage message) {
    if (!mounted) return;
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_add,
                color: Colors.blue,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'New Booking Assigned!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.notification?.title ?? 'New Appointment',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message.notification?.body ??
                  'You have a new booking assigned to your salon',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.grey[500],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white60 : Colors.grey[600],
            ),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewBookings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('View Now'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ SALON SELECTOR CHIP
  // ============================================================

  Widget _buildSalonSelectorChip() {
    if (_ownerSalons.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _showSalonSelectorDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _selectedSalonName != null && _selectedSalonName!.isNotEmpty
                    ? _selectedSalonName!
                    : 'Salon',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_ownerSalons.length > 1)
              const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Future<void> _showSalonSelectorDialog() async {
    if (_ownerSalons.length <= 1) return;
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
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
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
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _ownerSalons.length,
                  itemBuilder: (context, index) {
                    final salon = _ownerSalons[index];
                    final isSelected =
                        salon['id'].toString() == _selectedSalonId;
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
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[600],
                                size: 20,
                              )
                            : null,
                      ),
                      title: Text(
                        salon['name'] ?? 'Unknown Salon',
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
                          ? const Icon(
                              Icons.check_circle,
                              color: AppTheme.primary,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _switchSalon(salon['id'].toString());
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ PERMISSION METHODS
  // ============================================================

  Future<void> _showPermissionCardContext({String? action}) async {
    final shouldShow = await _permissionManager.shouldShowPermissionCard(
      screen: 'owner_dashboard',
      action: action,
    );

    if (mounted) {
      setState(() {
        _showPermissionCard = shouldShow;
      });
    }
  }

  Future<void> _enableNotifications({String? action}) async {
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
        if (mounted) {
          _showSettingsDialog();
        }
        return;
      }

      if (!mounted) return;

      await _permissionService.requestPermissionAtAction(
        context: context,
        action: action ?? 'owner_dashboard',
        customTitle: _permissionManager.getPermissionCardTitle(action: action),
        customMessage: _permissionManager.getPermissionCardMessage(
          action: action,
        ),
        onGranted: () async {
          debugPrint('✅ Permission granted callback');
          await _permissionManager.markPermissionGranted();

          if (mounted) {
            setState(() {
              _hasPermission = true;
              _showPermissionCard = false;
            });

            final message = isWeb
                ? '✅ Notifications enabled in browser!'
                : '✅ Notifications enabled!';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );

            _refreshAllData();
          }
        },
        onDenied: () async {
          debugPrint('❌ Permission denied callback');
          await _permissionManager.markPermissionDenied(permanent: false);

          if (mounted) {
            final message = isWeb
                ? 'You can enable notifications later from browser settings'
                : 'You can enable later from settings';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error enabling notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showWebPermissionHelp() {
    if (!mounted) return;
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌐'),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Browser Notification Settings',
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Flexible(
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
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh Page'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebStep(String number, String text) {
    final isDark = context.isDarkMode;

    return Row(
      mainAxisSize: MainAxisSize.min,
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
        Flexible(
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
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('owner_dashboard');
  }

  // ============================================================
  // ✅ NAVIGATION METHODS
  // ============================================================

  void _showNoSalonSelectedDialog() {
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text('No Salon Selected'),
        content: const Text(
          'Please select a salon first to view this data.\n\n'
          'You can select a salon from the dropdown above or create a new salon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToCreateSalon();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create Salon'),
          ),
        ],
      ),
    );
  }

  void _viewBookings() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId == null || _ownerSalons.isEmpty) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/appointments?salonId=$_selectedSalonId');
  }

  void _navigateToOffers() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'offer');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/offers/$_selectedSalonId');
  }

  void _navigateToAddBarber() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/add-barber?salonId=$_selectedSalonId');
  }

  void _navigateToAddService() async {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    final result = await context.push(
      '/owner/services/add?salonId=$_selectedSalonId',
    );
    if (result == true) await _refreshAllData();
  }

  void _navigateToBarberLeaves() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/barber-leaves?salonId=$_selectedSalonId');
  }

  void _navigateToBarberSchedule() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/barber-schedule?salonId=$_selectedSalonId');
  }

  void _navigateToBarberList() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/barbers?salonId=$_selectedSalonId');
  }

  void _navigateToServiceList() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    if (_ownerSalons.length == 1) {
      final salon = _ownerSalons.first;
      context.push(
        '/owner/services?salonId=${salon['id']}&salonName=${Uri.encodeComponent(salon['name'])}',
      );
    } else {
      _showSalonSelectionDialogForServices();
    }
  }

  void _viewAllCustomers() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId == null || _ownerSalons.isEmpty) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/customers?salonId=$_selectedSalonId');
  }

  void _viewRevenue() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId == null || _ownerSalons.isEmpty) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/revenue?salonId=$_selectedSalonId');
  }

  void _viewSalonHolidays() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId == null) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/salon/holidays?salonId=$_selectedSalonId');
  }

  void _viewReports() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'report');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId == null || _ownerSalons.isEmpty) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/reports?salonId=$_selectedSalonId');
  }

  void _viewAnalytics() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'analytics');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId == null || _ownerSalons.isEmpty) {
      _showNoSalonSelectedDialog();
      return;
    }
    context.push('/owner/analytics?salonId=$_selectedSalonId');
  }

  void _viewNotifications() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'notification');
      if (_showPermissionCard) return;
    }
    context.push('/notifications?role=owner');
  }

  // ============================================================
  // ✅ LOAD DATA - MAIN
  // ============================================================

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('🔄 _loadAllData() started');

      await _loadUserProfile();
      debugPrint('✅ User profile loaded');

      await _loadOwnerSalons();
      debugPrint('✅ Owner salons loaded: ${_ownerSalons.length}');

      try {
        await _loadDashboardStats();
        debugPrint('✅ Dashboard stats loaded');
      } catch (e) {
        debugPrint('⚠️ Dashboard stats error (non-critical): $e');
        setState(() {
          _todayAppointments = 0;
          _pendingBookings = 0;
          _activeBarbers = 0;
          _totalCustomers = 0;
          _totalRevenue = 0;
          _completedToday = 0;
        });
      }

      try {
        await _checkOnboardingStatus();
        debugPrint('✅ Onboarding status checked');
      } catch (e) {
        debugPrint('⚠️ Onboarding status error (non-critical): $e');
      }

      await _loadNotificationCount();
      debugPrint('✅ Notification count loaded');

      _hasPermission = await _notificationService.hasPermission();
      debugPrint('✅ Has permission: $_hasPermission');

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          screen: 'owner_dashboard',
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

      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('✅ _loadAllData() completed');
      }
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          debugPrint('⚠️ User account is blocked');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been blocked. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          debugPrint('⚠️ User profile is inactive');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your profile is inactive. Please contact support.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

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

  // ============================================================
  // ✅ LOAD OWNER SALONS
  // ============================================================

  Future<void> _loadOwnerSalons() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      debugPrint('🔍 Current User ID: $userId');

      if (userId == null) {
        debugPrint('❌ No user logged in');
        if (mounted) {
          setState(() {
            _ownerSalons = [];
            _hasSalon = false;
          });
        }
        return;
      }

      debugPrint('🔍 Loading salons for owner: $userId');

      final response = await supabase
          .from('salons')
          .select(
            'id, name, address, phone, email, description, is_active, created_at, updated_at, logo_url, cover_url, open_time, close_time, timezone',
          )
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      debugPrint('🔍 Found ${response.length} salons');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          if (_ownerSalons.isNotEmpty) {
            _hasSalon = true;
            if (_selectedSalonId == null) {
              final firstCreatedSalon = _ownerSalons.last;
              _selectedSalonId = firstCreatedSalon['id'].toString();
              _selectedSalonName = firstCreatedSalon['name']?.toString();
              debugPrint(
                '✅ Selected first-created salon: $_selectedSalonName (ID: $_selectedSalonId)',
              );
            } else {
              final selected = _ownerSalons.firstWhere(
                (s) => s['id'].toString() == _selectedSalonId,
                orElse: () => {},
              );
              _selectedSalonName = selected['name']?.toString();
            }
          } else {
            _hasSalon = false;
            debugPrint('⚠️ No active salons found for this owner');
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading salons: $e');
      if (mounted) {
        setState(() {
          _ownerSalons = [];
          _hasSalon = false;
        });
      }
    }
  }

  // ============================================================
  // ✅ LOAD DASHBOARD STATS
  // ============================================================

  Future<void> _loadDashboardStats() async {
    debugPrint('📊 _loadDashboardStats() called');
    debugPrint('📊 _selectedSalonId: $_selectedSalonId');
    debugPrint('📊 _ownerSalons.length: ${_ownerSalons.length}');

    if (_selectedSalonId == null || _ownerSalons.isEmpty) {
      debugPrint('⚠️ No salon selected or no salons found');
      setState(() {
        _todayAppointments = 0;
        _pendingBookings = 0;
        _activeBarbers = 0;
        _totalCustomers = 0;
        _totalRevenue = 0;
        _completedToday = 0;
      });
      return;
    }

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final salonIdInt = int.parse(_selectedSalonId!);

      debugPrint('📊 Today: $today, Salon ID: $salonIdInt');

      final results = await Future.wait([
        supabase
            .from('appointments')
            .select('id, status, price')
            .eq('salon_id', salonIdInt)
            .eq('appointment_date', today),

        supabase
            .from('appointments')
            .select('id')
            .eq('salon_id', salonIdInt)
            .eq('appointment_date', today)
            .eq('status', 'pending'),

        supabase
            .from('salon_barbers')
            .select('barber_id')
            .eq('salon_id', salonIdInt)
            .eq('status', 'active'),

        supabase
            .from('salon_followers')
            .select('id')
            .eq('salon_id', salonIdInt),
      ]);

      final todayAppointments = results[0] as List;
      final pendingBookings = results[1] as List;
      final activeBarbers = results[2] as List;
      final followers = results[3] as List;

      debugPrint('📊 Today appointments count: ${todayAppointments.length}');
      debugPrint('📊 Pending bookings count: ${pendingBookings.length}');
      debugPrint(
        '📊 Active barbers from salon_barbers: ${activeBarbers.length}',
      );

      int activeBarberCount = 0;
      if (activeBarbers.isNotEmpty) {
        final barberIds = activeBarbers
            .map((b) => b['barber_id'] as String)
            .toList();

        final validBarbers = await supabase
            .from('user_roles')
            .select('user_id')
            .inFilter('user_id', barberIds)
            .eq('role_id', 2)
            .eq('status', 'active');

        activeBarberCount = validBarbers.length;
        debugPrint('📊 Active barbers with valid roles: $activeBarberCount');
      }

      final totalFollowers = followers.length;
      debugPrint('📊 Total followers (Customers): $totalFollowers');

      final revenue = todayAppointments.fold<int>(
        0,
        (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0),
      );
      debugPrint('📊 Revenue: $revenue');

      final completedToday = todayAppointments
          .where((a) => a['status'] == 'completed')
          .length;

      if (mounted) {
        setState(() {
          _todayAppointments = todayAppointments.length;
          _pendingBookings = pendingBookings.length;
          _activeBarbers = activeBarberCount;
          _totalCustomers = totalFollowers;
          _totalRevenue = revenue;
          _completedToday = completedToday;
        });
        debugPrint(
          '📊 Stats updated: Today: $_todayAppointments, Pending: $_pendingBookings, Customers(Followers): $_totalCustomers, Barbers: $_activeBarbers, Revenue: $_totalRevenue',
        );
      }
    } catch (e) {
      debugPrint('❌ Dashboard stats error: $e');
      if (mounted) {
        setState(() {
          _todayAppointments = 0;
          _pendingBookings = 0;
          _activeBarbers = 0;
          _totalCustomers = 0;
          _totalRevenue = 0;
          _completedToday = 0;
        });
      }
    }
  }

  // ============================================================
  // ✅ CHECK ONBOARDING STATUS
  // ============================================================

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

      final barbers = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', salonId)
          .eq('status', 'active');

      bool hasActiveBarbers = false;
      if (barbers.isNotEmpty) {
        final barberIds = barbers.map((b) => b['barber_id'] as String).toList();

        final validBarbers = await supabase
            .from('user_roles')
            .select('user_id')
            .inFilter('user_id', barberIds)
            .eq('role_id', 2)
            .eq('status', 'active')
            .limit(1);

        hasActiveBarbers = validBarbers.isNotEmpty;
      }
      _hasBarbers = hasActiveBarbers;

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

      debugPrint(
        '📊 Onboarding: Salon: $_hasSalon, Services: $_hasServices, Barbers: $_hasBarbers, Steps: $_completedSteps',
      );
    } catch (e) {
      debugPrint('❌ Onboarding error: $e');
    }
  }

  Future<void> _refreshAllData() async => _loadAllData();

  Future<void> _switchSalon(String salonId) async {
    if (_isSwitchingSalon || salonId == _selectedSalonId) return;

    setState(() {
      _isSwitchingSalon = true;
      _selectedSalonId = salonId;
      final selected = _ownerSalons.firstWhere(
        (s) => s['id'].toString() == salonId,
        orElse: () => {},
      );
      _selectedSalonName = selected['name']?.toString();
    });

    try {
      await Future.wait([_loadDashboardStats(), _checkOnboardingStatus()]);
      await _loadNotificationCount();
    } catch (e) {
      debugPrint('Error switching salon: $e');
    } finally {
      if (mounted) setState(() => _isSwitchingSalon = false);
    }
  }

  // ============================================================
  // ✅ NOTIFICATION LISTENERS
  // ============================================================

  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📨 New notification received: ${message.data}');

        if (message.data['type'] == 'new_booking') {
          _showNewBookingAlert(message);
          setState(() {
            _pendingBookings++;
          });
          _loadNotificationCount();
        } else if (message.data['type'] == 'new_booking_assigned') {
          _showNewAssignmentAlert(message);
          _loadNotificationCount();
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data['type'] == 'new_booking') _viewBookings();
      });

      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          debugPrint('📱 App launched from terminated state with notification');
          _loadNotificationCount();
          if (message.data['type'] == 'new_booking') {
            _viewBookings();
          }
        }
      });
    } catch (e) {
      debugPrint('Error setting up notification listeners: $e');
    }
  }

  // ============================================================
  // ✅ UI BUILDERS
  // ============================================================

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final isDark = context.isDarkMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.15),
        highlightColor: color.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: enabled
                ? (isDark
                      ? color.withValues(alpha: 0.14)
                      : color.withValues(alpha: 0.08))
                : (isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.grey.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: isDark ? 0.35 : 0.18)
                  : (isDark
                        ? Colors.white12
                        : Colors.grey.withValues(alpha: 0.12)),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: enabled
                      ? color.withValues(alpha: isDark ? 0.28 : 0.15)
                      : (isDark
                            ? Colors.white10
                            : Colors.grey.withValues(alpha: 0.12)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: enabled
                      ? color
                      : (isDark ? Colors.grey[600] : Colors.grey[400]),
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled
                      ? (isDark ? color.withValues(alpha: 0.95) : color)
                      : (isDark ? Colors.grey[500] : Colors.grey[500]),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Android 16: Responsive Stat Cards
// ✅ Android 16: Responsive Stat Cards
Widget _buildResponsiveStatCards() {
  if (_isTablet) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: _isLargeScreen ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
        children: [
          DashboardStatCard(
            title: "Today's",
            value: '$_todayAppointments',
            icon: Icons.calendar_today,
            color: Colors.blue,
            subtitle: '$_completedToday completed, $_pendingBookings pending',
            onTap: _viewBookings,
          ),
          DashboardStatCard(
            title: 'Customers',
            value: '$_totalCustomers',
            icon: Icons.people,
            color: Colors.purple,
            subtitle: 'Active followers',
            onTap: _viewAllCustomers,
          ),
          DashboardStatCard(
            title: 'Barbers',
            value: '$_activeBarbers',
            icon: Icons.content_cut,
            color: Colors.green,
            onTap: _navigateToBarberList,
          ),
          DashboardStatCard(
            title: 'Revenue',
            value: 'Rs. $_totalRevenue',
            icon: Icons.currency_rupee,
            color: Colors.orange,
            onTap: _viewRevenue,
          ),
        ],
      ),
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: DashboardStatCard(
                title: "Today's",
                value: '$_todayAppointments',
                icon: Icons.calendar_today,
                color: Colors.blue,
                subtitle: '$_completedToday completed, $_pendingBookings pending',
                onTap: _viewBookings,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DashboardStatCard(
                title: 'Customers',
                value: '$_totalCustomers',
                icon: Icons.people,
                color: Colors.purple,
                subtitle: 'Active followers',
                onTap: _viewAllCustomers,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: DashboardStatCard(
                title: 'Barbers',
                value: '$_activeBarbers',
                icon: Icons.content_cut,
                color: Colors.green,
                onTap: _navigateToBarberList,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DashboardStatCard(
                title: 'Revenue',
                value: 'Rs. $_totalRevenue',
                icon: Icons.currency_rupee,
                color: Colors.orange,
                fullWidth: true,
                onTap: _viewRevenue,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

  // ============================================================
  // ✅ BUILD METHOD - WITH EDGE-TO-EDGE SUPPORT
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final isDark = context.isDarkMode;

    _checkScreenSize();

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
                  _selectedSalonName != null && _selectedSalonName!.isNotEmpty
                      ? _selectedSalonName!
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
            if (!isWeb && _ownerSalons.length > 1)
              Flexible(child: _buildSalonSelectorChip()),
          ],
        ),
        actions: [
          if (isWeb &&
              _selectedSalonName != null &&
              _selectedSalonName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: GestureDetector(
                  onTap: _ownerSalons.length > 1
                      ? _showSalonSelectorDialog
                      : null,
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
                        Icon(Icons.store, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _selectedSalonName!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_ownerSalons.length > 1)
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
          _buildNotificationIcon(),
          _buildProfileImage(),
        ],
      ),
      drawer: SideMenu(
        userRole: 'owner',
        userName: _userName,
        userEmail: _userEmail,
        profileImageUrl: _profileImageUrl,
        selectedSalonId: _selectedSalonId,
        onMenuItemSelected: () => _refreshAllData(),
        onSalonChanged: (String salonId) {
          _switchSalon(salonId);
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

  // ============================================================
  // ✅ DASHBOARD CONTENT
  // ============================================================

  Widget _buildDashboardContent() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    final isDark = context.isDarkMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showPermissionCard && !_hasPermission)
          PermissionCard(
            onEnable: () => _enableNotifications(action: null),
            onNotNow: _handleNotNow,
            title: _permissionManager.getPermissionCardTitle(),
            message: _permissionManager.getPermissionCardMessage(),
            compact: true,
          ),

        const SizedBox(height: 8),

        if (_completedSteps < _totalSteps) _buildStepFlow(),

        if (_ownerSalons.isEmpty)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 40),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _navigateToCreateSalon,
                  icon: const Icon(Icons.add_business, size: 18),
                  label: const Text('Create Salon'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
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
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                )
              : _buildResponsiveStatCards(),

        const SizedBox(height: 16),

        _buildManagementSection(isDesktop: isDesktop, isDark: isDark),

        const SizedBox(height: 80),
      ],
    );
  }

  // ============================================================
  // ✅ MANAGEMENT SECTION — fully responsive redesign
  // ============================================================

  Widget _buildManagementSection({
    required bool isDesktop,
    required bool isDark,
  }) {
    final categories = <_ManagementCategory>[
      _ManagementCategory(
        title: 'Salon Management',
        icon: Icons.storefront_rounded,
        color: AppTheme.primary,
        actions: [
          _ManagementAction(
            icon: Icons.add_business,
            label: 'Create Salon',
            color: AppTheme.primary,
            onTap: _navigateToCreateSalon,
          ),
          _ManagementAction(
            icon: Icons.edit,
            label: 'Edit Salon',
            color: Colors.blue,
            onTap: _navigateToEditSalon,
            enabled: _ownerSalons.isNotEmpty,
          ),
          _ManagementAction(
            icon: Icons.beach_access,
            label: 'Holidays',
            color: Colors.teal,
            onTap: _viewSalonHolidays,
            enabled: _ownerSalons.isNotEmpty,
          ),
        ],
      ),
      _ManagementCategory(
        title: 'Service Management',
        icon: Icons.design_services_rounded,
        color: Colors.green,
        actions: [
          _ManagementAction(
            icon: Icons.build,
            label: 'Add Service',
            color: Colors.green,
            onTap: _navigateToAddService,
            enabled: _ownerSalons.isNotEmpty,
          ),
          _ManagementAction(
            icon: Icons.list,
            label: 'Service List',
            color: Colors.cyan,
            onTap: _navigateToServiceList,
            enabled: _ownerSalons.isNotEmpty,
          ),
        ],
      ),
      _ManagementCategory(
        title: 'Barber Management',
        icon: Icons.content_cut_rounded,
        color: Colors.purple,
        actions: [
          _ManagementAction(
            icon: Icons.person_add,
            label: 'Add Barber',
            color: Colors.purple,
            onTap: _navigateToAddBarber,
            enabled: _ownerSalons.isNotEmpty,
          ),
          _ManagementAction(
            icon: Icons.calendar_month,
            label: 'Schedule',
            color: Colors.teal,
            onTap: _navigateToBarberSchedule,
            enabled: _ownerSalons.isNotEmpty,
          ),
          _ManagementAction(
            icon: Icons.beach_access,
            label: 'Leaves',
            color: Colors.orange,
            onTap: _navigateToBarberLeaves,
            enabled: _ownerSalons.isNotEmpty,
          ),
          _ManagementAction(
            icon: Icons.list,
            label: 'Barber List',
            color: Colors.indigo,
            onTap: _navigateToBarberList,
            enabled: _ownerSalons.isNotEmpty,
          ),
        ],
      ),
      _ManagementCategory(
        title: 'Offers & Promotions',
        icon: Icons.local_offer_rounded,
        color: Colors.pinkAccent,
        actions: [
          _ManagementAction(
            icon: Icons.local_offer,
            label: 'Manage Offers',
            color: AppTheme.primary,
            onTap: _navigateToOffers,
            enabled: _ownerSalons.isNotEmpty,
          ),
        ],
      ),
      _ManagementCategory(
        title: 'Reports & Insights',
        icon: Icons.insights_rounded,
        color: Colors.deepOrange,
        actions: [
          _ManagementAction(
            icon: Icons.bar_chart,
            label: 'Reports',
            color: Colors.deepOrange,
            onTap: _viewReports,
          ),
          _ManagementAction(
            icon: Icons.analytics,
            label: 'Analytics',
            color: Colors.indigoAccent,
            onTap: _viewAnalytics,
          ),
          _ManagementAction(
            icon: Icons.settings,
            label: 'Settings',
            color: Colors.grey,
            onTap: _viewSettings,
          ),
        ],
      ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.settings_suggest_rounded,
                  size: 20,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Management',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...categories.map(
            (category) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _buildManagementCategoryCard(
                category: category,
                isDesktop: isDesktop,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagementCategoryCard({
    required _ManagementCategory category,
    required bool isDesktop,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : category.color.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : category.color.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: isDark ? 0.24 : 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(category.icon, size: 15, color: category.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final minTileWidth = isDesktop ? 128.0 : 96.0;
              int columns = (maxWidth / minTileWidth).floor();
              if (columns < 1) columns = 1;
              if (columns > 6) columns = 6;
              const spacing = 10.0;
              final tileWidth = (maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: category.actions
                    .map(
                      (action) => SizedBox(
                        width: tileWidth,
                        child: _buildQuickAction(
                          icon: action.icon,
                          label: action.label,
                          color: action.color,
                          onTap: action.onTap,
                          enabled: action.enabled,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ NAVIGATION HELPERS
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

  void _showSalonSelectionDialogForServices() {
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text('Select Salon'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _ownerSalons.length,
            itemBuilder: (context, index) {
              final salon = _ownerSalons[index];
              return ListTile(
                leading: const Icon(Icons.store, color: AppTheme.primary),
                title: Text(
                  salon['name'] ?? 'Salon',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/owner/services?salonId=${salon['id']}&salonName=${Uri.encodeComponent(salon['name'] ?? 'Salon')}',
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

  void _viewSettings() => context.push('/settings');

  void _showCreateSalonFirstDialog() {
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Create Salon'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ STEP FLOW
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
    const pink = AppTheme.primary;
    const green = Color(0xFF22C55E);
    final pct = _totalSteps == 0 ? 0.0 : _completedSteps / _totalSteps;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
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
                    Text(
                      'Salon Setup',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      '$_completedSteps of $_totalSteps steps complete',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Color(0xFF9CA3AF),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Builder(
              builder: (context) {
                const arrowSlot = 16.0;
                final cardWidth = isDesktop ? 96.0 : 80.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(steps.length, (i) {
                    final step = steps[i];
                    final isCompleted = step['isCompleted'] as bool;
                    final isLocked = step['locked'] as bool? ?? false;
                    final isActive = !isCompleted && !isLocked;
                    final isNext = i == nextIdx;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
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
          ),
          if (_completedSteps > 0 &&
              _completedSteps < _totalSteps &&
              nextIdx >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                  Flexible(
                    child: Text(
                      'Up next:  ${steps[nextIdx]['label'] as String}',
                      style: TextStyle(
                        fontSize: 12,
                        color: pink,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
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
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.celebration_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Your salon is ready to launch! 🎉',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
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
    const pink = AppTheme.primary;
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
          width: isNext
              ? 1.8
              : isActive
              ? 1.5
              : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
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
                  : Icon(icon, color: Colors.white, size: 20),
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
    if (isNext) card = ScaleTransition(scale: _pulseAnim, child: card);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

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
      return _chip('Do This', AppTheme.primary, const Color(0xFFFFEDF1));
    }
    return _chip('Pending', AppTheme.primary, const Color(0xFFFFEDF1));
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
}

// ============================================================
// ✅ Small data holders for the responsive Management section
// ============================================================

class _ManagementCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<_ManagementAction> actions;

  _ManagementCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.actions,
  });
}

class _ManagementAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  _ManagementAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });
}