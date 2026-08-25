import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/permission_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';
import '../../services/notification_service.dart';
import '../../services/permission_service.dart';
import '../../services/timezone_service.dart';
import '../../widgets/permission_card.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class NotificationScreen extends StatefulWidget {
  final String? role;

  const NotificationScreen({
    super.key,
    this.role = 'customer',
  });

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  String _selectedFilter = 'all';

  bool _hasPermission = false;
  bool _showPermissionCard = false;

  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 20;

  // ✅ Scroll Controller
  final ScrollController _scrollController = ScrollController();

  bool _isTimezoneLoaded = false;

  // ✅ Responsive variables
  bool _isWeb = false;
  bool _isTablet = false;
  bool _isLargeScreen = false;

  @override
  void initState() {
    super.initState();
    _initializeTimezone();
    _checkPermission();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isWeb = size.width > 800;
    final isTablet = size.shortestSide >= 600;
    final isLarge = size.width > 800 || size.height > 800;

    if (_isWeb != isWeb || _isTablet != isTablet || _isLargeScreen != isLarge) {
      setState(() {
        _isWeb = isWeb;
        _isTablet = isTablet;
        _isLargeScreen = isLarge;
      });
    }
  }

  // ============================================
  // PERMISSION CHECK
  // ============================================

  Future<void> _checkPermission() async {
    _hasPermission = await _notificationService.hasPermission();
    
    if (!_hasPermission) {
      _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
        screen: 'notifications',
        action: 'notification',
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
    
    if (mounted) setState(() {});
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
        action: action ?? 'notifications',
        customTitle: _permissionManager.getPermissionCardTitle(action: action),
        customMessage: _permissionManager.getPermissionCardMessage(action: action),
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

            await _loadNotifications();
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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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
    await _permissionManager.markPermissionShown('notifications');
  }

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();
    
    final prefs = await SharedPreferences.getInstance();
    final userTimezone = prefs.getString('cached_timezone') ?? TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(userTimezone);
    
    setState(() {
      _isTimezoneLoaded = true;
    });
    
    await _loadNotifications();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreNotifications();
    }
  }

  // ============================================
  // TIME FORMATTING
  // ============================================

  String _formatTime(String createdAt) {
    try {
      final utcDateTime = DateTime.parse(createdAt);
      
      final localDateTime = TimezoneService.utcToLocalDateTimeForDate(
        '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00',
        utcDateTime,
      );
      
      final now = DateTime.now();
      final difference = now.difference(localDateTime);

      if (difference.inDays > 7) {
        return DateFormat('MMM dd, yyyy').format(localDateTime);
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      debugPrint('Error formatting time: $e');
      return createdAt;
    }
  }

  // ============================================
  // LOAD NOTIFICATIONS
  // ============================================

  Future<void> _loadNotifications({bool refresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _currentPage = 0;
      _hasMore = true;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to view notifications';
          _isLoading = false;
        });
        return;
      }

      final result = await _notificationService.getNotificationsWithRole(
        userId: user.id,
        role: widget.role!,
        limit: _pageSize,
        unreadOnly: _selectedFilter == 'unread',
      );

      if (!mounted) return;
      setState(() {
        _notifications = result;
        _isLoading = false;
        _hasMore = result.length == _pageSize;
        _currentPage = 1;
      });
    } catch (e) {
      debugPrint('❌ Error loading notifications: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load notifications: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (_isLoadingMore || !_hasMore || !mounted) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final start = _currentPage * _pageSize;
      final end = start + _pageSize - 1;

      final allNotifications = await _notificationService.getNotificationsWithRole(
        userId: user.id,
        role: widget.role!,
        limit: end + 1,
      );

      if (!mounted) return;

      if (allNotifications.length > _notifications.length) {
        final newNotifications = allNotifications.sublist(_notifications.length);
        setState(() {
          _notifications.addAll(newNotifications);
          _currentPage++;
          _hasMore = newNotifications.length == _pageSize;
        });
      } else {
        setState(() {
          _hasMore = false;
        });
      }

      setState(() {
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Error loading more: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refreshNotifications() async {
    await _loadNotifications(refresh: true);
  }

  List<Map<String, dynamic>> get _filteredNotifications {
    if (_selectedFilter == 'unread') {
      return _notifications.where((n) => n['is_read'] == false).toList();
    } else if (_selectedFilter == 'read') {
      return _notifications.where((n) => n['is_read'] == true).toList();
    }
    return _notifications;
  }

  // ⚠️ FIX: the web-only Scrollbar needs an actual Scrollable (ListView)
  // attached to _scrollController before it can paint. During loading /
  // error / empty states, _buildNotificationList() returns a plain
  // Center() with no ScrollPosition, which crashed the Scrollbar on web.
  // This flag tells the web layout when it's safe to wrap the Scrollbar
  // around the content.
  bool get _hasScrollableList =>
      !_isLoading && !_hasError && _filteredNotifications.isNotEmpty;

  Future<void> _markAsRead(int id) async {
    final success = await _notificationService.markAsRead(id);

    if (success && mounted) {
      setState(() {
        final index = _notifications.indexWhere((n) => n['id'] == id);
        if (index != -1) {
          _notifications[index]['is_read'] = true;
        }
      });
    }
  }

  Future<void> _markAllAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final success = await _notificationService.markAllAsRead(user.id);

    if (success && mounted) {
      setState(() {
        for (var notification in _notifications) {
          notification['is_read'] = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    }
  }

  Future<void> _clearAll() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear All Notifications',
          style: context.titleLarge.copyWith(
            color: context.textColor,
          ),
        ),
        content: Text(
          'Are you sure you want to clear all notifications? This action cannot be undone.',
          style: context.bodyMedium.copyWith(
            color: context.textColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await _notificationService.clearAllNotifications(
                user.id,
              );
              if (success && mounted) {
                setState(() {
                  _notifications = [];
                });
                Navigator.pop(context, true);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteNotification(int id, int index) async {
    final success = await _notificationService.deleteNotification(id);
    if (success && mounted) {
      setState(() {
        _notifications.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted'),
          backgroundColor: Colors.grey,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // ============================================
  // NAVIGATION
  // ============================================

  void _handleNotificationTap(Map<String, dynamic> notification) async {
    final notificationId = notification['id'];
    final wasUnread = notification['is_read'] == false;

    if (wasUnread) {
      await _markAsRead(notificationId);
    }

    if (!mounted) return;

    final type = notification['type'];
    final data = notification['data'] as Map<String, dynamic>?;
    final role = widget.role ?? 'customer';

    if (role == 'barber') {
      if (type == 'new_booking_assigned' || type == 'booking_reminder') {
        final appointmentId = data?['appointmentId'] ?? data?['bookingId'];
        if (appointmentId != null) {
          await context.push('/barber/appointment/$appointmentId');
        } else {
          await context.push('/barber/appointments');
        }
      } else if (type == 'appointment_cancelled') {
        await context.push('/barber/appointments');
      } else if (type == 'appointment_reassigned') {
        final appointmentId = data?['appointmentId'];
        if (appointmentId != null) {
          await context.push('/barber/appointment/$appointmentId');
        } else {
          await context.push('/barber/appointments');
        }
      } else if (type == 'leave_status_update') {
        await context.push('/barber/leaves');
      } else {
        await context.push('/barber/dashboard');
      }
    } else if (role == 'owner') {
      if (type == 'new_leave_request') {
        await context.push('/owner/leaves');
      } else if (type == 'new_follower') {
        await context.push('/owner/salon');
      } else if (type == 'new_review') {
        await context.push('/owner/reviews');
      } else if (type == 'new_booking') {
        await context.push('/owner/bookings');
      } else if (type == 'low_stock') {
        await context.push('/owner/inventory');
      } else if (type == 'daily_summary') {
        await context.push('/owner/dashboard');
      } else {
        await context.push('/owner/dashboard');
      }
    } else {
      if (type == 'appointment_confirmed' || type == 'booking_confirmed') {
        final appointmentId = data?['appointment_id'] ?? data?['bookingId'];
        if (appointmentId != null) {
          await context.push('/customer/booking/$appointmentId');
        } else {
          await context.push('/customer/my-bookings');
        }
      } else if (type == 'vip_approved' || type == 'vip_pending' || type == 'vip_rejected') {
        await context.push('/customer/vip-bookings');
      } else if (type == 'special_offer') {
        await context.push('/customer/offers');
      } else if (type == 'booking_reminder') {
        await context.push('/customer/my-bookings');
      } else if (type == 'next_appointment_alert') {
        await context.push('/customer/my-bookings');
      } else if (type == 'appointment_cancelled' || type == 'appointment_moved' || type == 'appointment_reassigned') {
        final appointmentId = data?['appointmentId'];
        if (appointmentId != null) {
          await context.push('/customer/booking/$appointmentId');
        } else {
          await context.push('/customer/my-bookings');
        }
      } else if (type == 'overflow_warning') {
        await context.push('/customer/my-bookings');
      } else if (type == 'review_reminder') {
        await context.push('/customer/reviews');
      } else if (type == 'loyalty_points') {
        await context.push('/customer/loyalty');
      } else if (type == 'waiting_list_available') {
        await context.push('/customer/waiting-list');
      } else {
        final actionUrl = notification['action_url'];
        if (actionUrl != null && actionUrl.isNotEmpty) {
          await context.push(actionUrl);
        } else {
          await context.push('/customer/my-bookings');
        }
      }
    }

    if (mounted && wasUnread) {
      Navigator.pop(context, true);
    }
  }

  // ============================================
  // UI HELPERS
  // ============================================

  String _getTitle() {
    switch (widget.role) {
      case 'barber':
        return 'Barber Notifications';
      case 'owner':
        return 'Owner Notifications';
      default:
        return 'Notifications';
    }
  }

  Color _getAppBarColor() {
    switch (widget.role) {
      case 'barber':
        return Colors.blue;
      case 'owner':
        return Colors.purple;
      default:
        return AppTheme.primary;
    }
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'appointment_confirmed':
      case 'booking_confirmed':
        return Icons.check_circle;
      case 'vip_approved':
        return Icons.star;
      case 'vip_pending':
        return Icons.hourglass_empty;
      case 'vip_rejected':
        return Icons.star_border;
      case 'special_offer':
        return Icons.local_offer;
      case 'booking_reminder':
        return Icons.alarm;
      case 'next_appointment_alert':
        return Icons.notifications_active;
      case 'appointment_cancelled':
        return Icons.cancel;
      case 'overflow_warning':
        return Icons.warning_amber;
      case 'new_booking_assigned':
        return Icons.assignment_add;
      case 'new_leave_request':
        return Icons.event_busy;
      case 'leave_status_update':
        return type!.contains('approved') ? Icons.check_circle : Icons.cancel;
      case 'new_follower':
        return Icons.person_add;
      case 'new_review':
        return Icons.star;
      case 'new_booking':
        return Icons.calendar_today;
      case 'low_stock':
        return Icons.inventory;
      case 'daily_summary':
        return Icons.analytics;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String? type) {
    switch (type) {
      case 'appointment_confirmed':
      case 'booking_confirmed':
        return Colors.green;
      case 'vip_approved':
        return Colors.amber;
      case 'vip_pending':
        return Colors.orange;
      case 'vip_rejected':
        return Colors.red;
      case 'special_offer':
        return AppTheme.primary;
      case 'booking_reminder':
        return Colors.blue;
      case 'next_appointment_alert':
        return Colors.orange;
      case 'appointment_cancelled':
        return Colors.red;
      case 'overflow_warning':
        return Colors.orange;
      case 'new_booking_assigned':
        return Colors.purple;
      case 'new_leave_request':
        return Colors.indigo;
      case 'leave_status_update':
        return Colors.green;
      case 'new_follower':
        return Colors.teal;
      case 'new_review':
        return Colors.amber;
      case 'new_booking':
        return Colors.blue;
      case 'low_stock':
        return Colors.red;
      case 'daily_summary':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  String _getEmptyMessage() {
    if (_selectedFilter == 'unread') {
      return 'No unread notifications';
    } else if (_selectedFilter == 'read') {
      return 'No read notifications';
    }
    return 'No notifications yet';
  }

  String _getEmptySubMessage() {
    switch (widget.role) {
      case 'barber':
        return 'You will see notifications about new bookings and schedule updates here';
      case 'owner':
        return 'You will see notifications about salon activity, reviews, and requests here';
      default:
        return 'When you get notifications, they will appear here';
    }
  }

  // ============================================
  // ✅ MAIN BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = _isWeb;

    _checkScreenSize();

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: Text(
            _getTitle(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: _getAppBarColor(),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
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

    final unreadCount = _notifications
        .where((n) => n['is_read'] == false)
        .length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              _getTitle(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: _getAppBarColor(),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          if (_notifications.isNotEmpty) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'mark_all_read') {
                  _markAllAsRead();
                } else if (value == 'clear_all') {
                  _clearAll();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_all_read',
                  child: Row(
                    children: [
                      Icon(Icons.done_all, size: 20),
                      SizedBox(width: 12),
                      Text('Mark all as read'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Clear all', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: isWeb
            ? _buildWebLayout(isDark)
            : _buildMobileLayout(isDark),
      ),
    );
  }

  // ============================================
  // ✅ WEB LAYOUT
  // ============================================

  Widget _buildWebLayout(bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            // Permission Card
            if (_showPermissionCard && !_hasPermission)
              PermissionCard(
                onEnable: () => _enableNotifications(action: 'notification'),
                onNotNow: _handleNotNow,
                title: _permissionManager.getPermissionCardTitle(action: 'notification'),
                message: _permissionManager.getPermissionCardMessage(action: 'notification'),
                compact: true,
                iconEmoji: _permissionManager.getPermissionCardIcon(action: 'notification'),
              ),
            
            // Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Unread', 'unread', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Read', 'read', isDark),
                  const Spacer(),
                  if (_filteredNotifications.isEmpty &&
                      _selectedFilter != 'all')
                    Text(
                      'No results',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),

            // ⚠️ FIX: only wrap with Scrollbar when there's an actual
            // ListView attached to _scrollController (i.e. notifications
            // have finished loading and there's something to show). During
            // loading / error / empty states there is no ScrollPosition
            // for the Scrollbar to attach to, which was crashing the web
            // build with "ScrollController has no ScrollPosition attached".
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshNotifications,
                color: _getAppBarColor(),
                child: _hasScrollableList
                    ? Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 8.0,
                        radius: const Radius.circular(10),
                        scrollbarOrientation: ScrollbarOrientation.right,
                        child: _buildNotificationList(
                          isDark,
                          controller: _scrollController,
                        ),
                      )
                    : _buildNotificationList(
                        isDark,
                        controller: _scrollController,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // ✅ MOBILE LAYOUT
  // ============================================

  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        // Permission Card
        if (_showPermissionCard && !_hasPermission)
          PermissionCard(
            onEnable: () => _enableNotifications(action: 'notification'),
            onNotNow: _handleNotNow,
            title: _permissionManager.getPermissionCardTitle(action: 'notification'),
            message: _permissionManager.getPermissionCardMessage(action: 'notification'),
            compact: true,
            iconEmoji: _permissionManager.getPermissionCardIcon(action: 'notification'),
          ),
        
        // Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
            ),
          ),
          child: Row(
            children: [
              _buildFilterChip('All', 'all', isDark),
              const SizedBox(width: 8),
              _buildFilterChip('Unread', 'unread', isDark),
              const SizedBox(width: 8),
              _buildFilterChip('Read', 'read', isDark),
              const Spacer(),
              if (_filteredNotifications.isEmpty &&
                  _selectedFilter != 'all')
                Text(
                  'No results',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
            ],
          ),
        ),

        // Notifications List (mobile has no Scrollbar, so this path is
        // unaffected by the web fix above)
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshNotifications,
            color: _getAppBarColor(),
            child: _buildNotificationList(
              isDark,
              controller: _scrollController,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // ✅ NOTIFICATION LIST
  // ============================================

  Widget _buildNotificationList(
    bool isDark, {
    required ScrollController controller,  // ✅ REQUIRED
  }) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Loading notifications...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: isDark ? Colors.white70 : Colors.grey[400]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadNotifications,
              style: ElevatedButton.styleFrom(
                backgroundColor: _getAppBarColor(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _getAppBarColor().withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none,
                size: 64,
                color: _getAppBarColor().withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getEmptyMessage(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _getEmptySubMessage(),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_off,
              size: 48,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _selectedFilter == 'unread'
                  ? 'No unread notifications'
                  : 'No read notifications',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // ✅ FIXED: ListView with controller
    return ListView.builder(
      controller: controller,  // ✅ USE CONTROLLER
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount:
          _filteredNotifications.length +
          (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _filteredNotifications.length &&
            _isLoadingMore) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
            ),
          );
        }

        final notification = _filteredNotifications[index];
        final originalIndex = _notifications.indexWhere(
          (n) => n['id'] == notification['id'],
        );
        final isUnread = notification['is_read'] == false;
        final icon = _getNotificationIcon(notification['type']);
        final iconColor = _getNotificationColor(notification['type']);
        final timeAgo = _formatTime(notification['created_at']);

        return Dismissible(
          key: Key(notification['id'].toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
          onDismissed: (direction) {
            _deleteNotification(notification['id'], originalIndex);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _handleNotificationTap(notification),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isUnread
                        ? _getAppBarColor().withValues(alpha: 0.08)
                        : (isDark ? const Color(0xFF2A2A2A) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                    border: isUnread
                        ? Border.all(
                            color: _getAppBarColor().withValues(alpha: 0.3),
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          color: iconColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    notification['title'] ?? 'Notification',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isUnread
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isDark ? Colors.white : Colors.grey[800],
                                    ),
                                  ),
                                ),
                                Text(
                                  timeAgo,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notification['body'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.grey[600],
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // ✅ FILTER CHIP
  // ============================================

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _selectedFilter == value;
    final appBarColor = _getAppBarColor();

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? appBarColor
              : (isDark ? Colors.white60 : Colors.grey[600]),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
          _loadNotifications();
        });
      },
      selectedColor: appBarColor.withValues(alpha: 0.1),
      checkmarkColor: appBarColor,
      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected
              ? appBarColor
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
      ),
    );
  }
}