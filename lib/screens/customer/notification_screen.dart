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
  
  // Pagination
  bool _isLoadingMore = false;
  static const int _pageSize = 20;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
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
      
      final notifications = await _notificationService.getNotifications(user.id);
      
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoading = false;
        _hasMore = notifications.length >= _pageSize;
      });
      
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load notifications';
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
      
      final allNotifications = await _notificationService.getNotifications(user.id);
      
      if (!mounted) return;
      setState(() {
        _notifications = allNotifications;
        _isLoadingMore = false;
        _hasMore = false;
      });
      
    } catch (e) {
      debugPrint('Error loading more: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
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
    await _notificationService.markAsRead(id);
    if (!mounted) return;
    setState(() {
      final index = _notifications.indexWhere((n) => n['id'] == id);
      if (index != -1) {
        _notifications[index]['is_read'] = true;
      }
    });
  }

  Future<void> _markAllAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    
    await _notificationService.markAllAsRead(user.id);
    if (!mounted) return;
    
    setState(() {
      for (var notification in _notifications) {
        notification['is_read'] = true;
      }
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications marked as read'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearAll() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to clear all notifications? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _notificationService.clearAllNotifications(user.id);
              if (!mounted) return;
              setState(() {
                _notifications = [];
              });             
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteNotification(int id, int index) async {
    await _notificationService.deleteNotification(id);
    if (!mounted) return;
    setState(() {
      _notifications.removeAt(index);
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification deleted'),
        backgroundColor: Colors.grey,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notification) async {
    // Mark as read (async operation)
    if (notification['is_read'] == false) {
      await _markAsRead(notification['id']);
    }
    
    // Check mounted before navigation
    if (!mounted) return;
    
    // Handle navigation based on type
    final type = notification['type'];
    final data = notification['data'] as Map<String, dynamic>?;
    
    if (type == 'appointment_confirmed' || type == 'booking_confirmed') {
      final appointmentId = data?['appointment_id'] ?? data?['bookingId'];
      if (appointmentId != null) {
        context.push('/customer/booking/$appointmentId');
      } else {
        context.push('/customer/my-bookings');
      }
    } else if (type == 'vip_approved' || type == 'vip_request_update') {
      context.push('/customer/vip-bookings');
    } else if (type == 'special_offer') {
      context.push('/customer/offers');
    } else if (type == 'booking_reminder') {
      context.push('/customer/my-bookings');
    } else if (type == 'next_appointment_alert') {
      context.push('/customer/my-bookings');
    } else if (type == 'cancellation') {
      context.push('/customer/my-bookings');
    } else if (type == 'overflow_warning') {
      context.push('/customer/my-bookings');
    } else {
      final actionUrl = notification['action_url'];
      if (actionUrl != null && actionUrl.isNotEmpty) {
        context.push(actionUrl);
      }
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
    final unreadCount = _notifications.where((n) => n['is_read'] == false).length;
    
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Filter Bar - Facebook Style
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              if (_filteredNotifications.isEmpty && _selectedFilter != 'all')
                                Text(
                                  'No results',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                ),
                            ],
                          ),
                        ),
                        
                        // Notifications List - Facebook Style
                        Expanded(
                          child: _filteredNotifications.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.filter_alt_off, size: 48, color: Colors.grey[400]),
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
                              : NotificationListener<ScrollNotification>(
                                  onNotification: (scrollInfo) {
                                    if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent && _hasMore && !_isLoadingMore) {
                                      _loadMoreNotifications();
                                    }
                                    return false;
                                  },
                                  child: ListView.builder(
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: _filteredNotifications.length + (_isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _filteredNotifications.length && _isLoadingMore) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B8B)),
                                            ),
                                          ),
                                        );
                                      }
                                      
                                      final notification = _filteredNotifications[index];
                                      final originalIndex = _notifications.indexWhere((n) => n['id'] == notification['id']);
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
                                        child: Material(
                                          color: isUnread ? const Color(0xFFFF6B8B).withValues(alpha: 0.05) : Colors.white,
                                          child: InkWell(
                                            onTap: () => _handleNotificationTap(notification),
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              padding: const EdgeInsets.all(16),
                                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.grey.withValues(alpha: 0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ],
                                                border: isUnread
                                                    ? Border.all(color: const Color(0xFFFF6B8B).withValues(alpha: 0.3))
                                                    : null,
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Icon
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
                                                  
                                                  // Content
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                notification['title'],
                                                                style: TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                                                                  color: Colors.grey[800],
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
                                                          overflow: TextOverflow.ellipsis,
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
        color: _selectedFilter == value ? const Color(0xFFFF6B8B) : Colors.grey[600],
        fontWeight: _selectedFilter == value ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: _selectedFilter == value ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
        ),
      ),
    );
  }
}