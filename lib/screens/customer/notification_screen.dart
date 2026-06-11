import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  String _selectedFilter = 'all'; // all, unread, read

  // ✅ Pagination variables
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 20;

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreNotifications();
    }
  }

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
      debugPrint('🔍 Current user: ${user?.id}');

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to view notifications';
          _isLoading = false;
        });
        return;
      }

      // ✅ Load first page with pagination
      final result = await supabase
          .from('notifications')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      debugPrint('✅ Loaded ${result.length} notifications');

      if (!mounted) return;
      setState(() {
        _notifications = List<Map<String, dynamic>>.from(result);
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

      final result = await supabase
          .from('notifications')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .range(start, end);

      if (!mounted) return;

      if (result.isNotEmpty) {
        setState(() {
          _notifications.addAll(List<Map<String, dynamic>>.from(result));
          _currentPage++;
          _hasMore = result.length == _pageSize;
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

  Future<void> _markAsRead(int id) async {
    debugPrint('🔍 Marking notification $id as read');
    final success = await _notificationService.markAsRead(id);

    if (success && mounted) {
      setState(() {
        final index = _notifications.indexWhere((n) => n['id'] == id);
        if (index != -1) {
          _notifications[index]['is_read'] = true;
        }
      });
      debugPrint('✅ Notification $id marked as read');
    } else {
      debugPrint('❌ Failed to mark notification $id as read');
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

      // ✅ Return true to refresh dashboard count
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications'),
        content: const Text(
          'Are you sure you want to clear all notifications? This action cannot be undone.',
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
              // Use the dialogContext and check mounted on the State
              if (success && mounted) {
                setState(() {
                  _notifications = [];
                });
                // ✅ Return true to refresh dashboard count
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

  void _handleNotificationTap(Map<String, dynamic> notification) async {
    final notificationId = notification['id'];
    final wasUnread = notification['is_read'] == false;

    if (wasUnread) {
      await _markAsRead(notificationId);
    }

    if (!mounted) return;

    final type = notification['type'];
    final data = notification['data'] as Map<String, dynamic>?;

    if (type == 'appointment_confirmed' || type == 'booking_confirmed') {
      final appointmentId = data?['appointment_id'] ?? data?['bookingId'];
      if (appointmentId != null) {
        await context.push('/customer/booking/$appointmentId');
      } else {
        await context.push('/customer/my-bookings');
      }
    } else if (type == 'vip_approved' || type == 'vip_request_update') {
      await context.push('/customer/vip-bookings');
    } else if (type == 'special_offer') {
      await context.push('/customer/offers');
    } else if (type == 'booking_reminder') {
      await context.push('/customer/my-bookings');
    } else if (type == 'next_appointment_alert') {
      await context.push('/customer/my-bookings');
    } else if (type == 'cancellation') {
      await context.push('/customer/my-bookings');
    } else if (type == 'overflow_warning') {
      await context.push('/customer/my-bookings');
    } else {
      final actionUrl = notification['action_url'];
      if (actionUrl != null && actionUrl.isNotEmpty) {
        await context.push(actionUrl);
      } else {
        await context.push('/customer/my-bookings');
      }
    }

    if (mounted && wasUnread) {
      Navigator.pop(context, true);
    }
  }

  String _formatTime(String createdAt) {
    try {
      final date = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 7) {
        return DateFormat('MMM dd, yyyy').format(date);
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
      return createdAt;
    }
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'appointment_confirmed':
      case 'booking_confirmed':
        return Icons.check_circle;
      case 'vip_approved':
        return Icons.star;
      case 'vip_request_update':
        return Icons.star_border;
      case 'special_offer':
        return Icons.local_offer;
      case 'booking_reminder':
        return Icons.alarm;
      case 'next_appointment_alert':
        return Icons.notifications_active;
      case 'cancellation':
        return Icons.cancel;
      case 'overflow_warning':
        return Icons.warning_amber;
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
      case 'special_offer':
        return const Color(0xFFFF6B8B);
      case 'booking_reminder':
        return Colors.blue;
      case 'next_appointment_alert':
        return Colors.orange;
      case 'cancellation':
        return Colors.red;
      case 'overflow_warning':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((n) => n['is_read'] == false)
        .length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontWeight: FontWeight.bold),
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
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          if (_notifications.isNotEmpty) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
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
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading notifications...'),
                ],
              ),
            )
          : _hasError
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loadNotifications,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none,
                      size: 64,
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When you get notifications, they will appear here',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Filter Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Unread', 'unread'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Read', 'read'),
                      const Spacer(),
                      if (_filteredNotifications.isEmpty &&
                          _selectedFilter != 'all')
                        Text(
                          'No results',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),

                // Notifications List with Pagination
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshNotifications,
                    color: const Color(0xFFFF6B8B),
                    child: _filteredNotifications.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.filter_alt_off,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedFilter == 'unread'
                                      ? 'No unread notifications'
                                      : 'No read notifications',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            itemCount:
                                _filteredNotifications.length +
                                (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              // Loading indicator at the end
                              if (index == _filteredNotifications.length &&
                                  _isLoadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFFF6B8B),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final notification =
                                  _filteredNotifications[index];
                              final originalIndex = _notifications.indexWhere(
                                (n) => n['id'] == notification['id'],
                              );
                              final isUnread = notification['is_read'] == false;
                              final icon = _getNotificationIcon(
                                notification['type'],
                              );
                              final iconColor = _getNotificationColor(
                                notification['type'],
                              );
                              final timeAgo = _formatTime(
                                notification['created_at'],
                              );

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
                                  _deleteNotification(
                                    notification['id'],
                                    originalIndex,
                                  );
                                },
                                child: Material(
                                  color: isUnread
                                      ? const Color(
                                          0xFFFF6B8B,
                                        ).withValues(alpha: 0.05)
                                      : Colors.white,
                                  child: InkWell(
                                    onTap: () =>
                                        _handleNotificationTap(notification),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.grey.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                        border: isUnread
                                            ? Border.all(
                                                color: const Color(
                                                  0xFFFF6B8B,
                                                ).withValues(alpha: 0.3),
                                              )
                                            : null,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Icon
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: iconColor.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              icon,
                                              color: iconColor,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 12),

                                          // Content
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        notification['title'] ??
                                                            'Notification',
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: isUnread
                                                              ? FontWeight.bold
                                                              : FontWeight.w500,
                                                          color:
                                                              Colors.grey[800],
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      timeAgo,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey[500],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  notification['body'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey[600],
                                                    height: 1.3,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Unread indicator
                                          if (isUnread)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFFF6B8B),
                                                shape: BoxShape.circle,
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
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return FilterChip(
      label: Text(label),
      selected: _selectedFilter == value,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
      checkmarkColor: const Color(0xFFFF6B8B),
      labelStyle: TextStyle(
        color: _selectedFilter == value
            ? const Color(0xFFFF6B8B)
            : Colors.grey[600],
        fontWeight: _selectedFilter == value
            ? FontWeight.w600
            : FontWeight.normal,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: _selectedFilter == value
              ? const Color(0xFFFF6B8B)
              : Colors.grey[300]!,
        ),
      ),
    );
  }
}
