// screens/owner/barber_leaves_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/ip_helper.dart';  // Import IP helper

class BarberLeavesScreen extends StatefulWidget {
  final String? salonId;
  
  const BarberLeavesScreen({super.key, this.salonId});

  @override
  State<BarberLeavesScreen> createState() => _BarberLeavesScreenState();
}

class _BarberLeavesScreenState extends State<BarberLeavesScreen> {
  final supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _barbers = [];
  List<Map<String, dynamic>> _leaves = [];
  Map<String, Map<String, dynamic>> _barberProfiles = {};
  
  // Salon working hours
  String? _salonOpenTime;
  String? _salonCloseTime;
  
  // Filters
  DateTime? _selectedDate;
  String? _selectedBarberId;
  String _selectedStatus = 'all';
  String _selectedType = 'all';
  
  // IP address
  String? _currentIp;
  bool _isLoadingIp = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadIpAddress();
  }

  // Load IP address
  Future<void> _loadIpAddress() async {
    if (_isLoadingIp) return;
    
    setState(() => _isLoadingIp = true);
    
    try {
      _currentIp = await IpHelper.getPublicIp();
      debugPrint('🌐 Current IP: $_currentIp');
    } catch (e) {
      debugPrint('❌ Error loading IP: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingIp = false);
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load salon details for working hours
      final salonResponse = await supabase
          .from('salons')
          .select('open_time, close_time')
          .eq('id', int.parse(widget.salonId!))
          .maybeSingle();

      if (salonResponse != null) {
        _salonOpenTime = salonResponse['open_time'];
        _salonCloseTime = salonResponse['close_time'];
        debugPrint('🕒 Salon hours: $_salonOpenTime - $_salonCloseTime');
      }

      // Get barber IDs from salon_barbers
      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', int.parse(widget.salonId!))
          .eq('is_active', true);

      final barberIds = salonBarbersResponse.map((sb) => sb['barber_id'] as String).toList();
      debugPrint('📋 Found barber IDs: $barberIds');

      if (barberIds.isNotEmpty) {
        // Get profiles for these barbers
        List<Map<String, dynamic>> allProfiles = [];
        for (String barberId in barberIds) {
          final profile = await supabase
              .from('profiles')
              .select('id, full_name, email, avatar_url')
              .eq('id', barberId)
              .maybeSingle();
          
          if (profile != null) {
            allProfiles.add(profile);
          }
        }

        _barbers = allProfiles.map<Map<String, dynamic>>((p) {
          return {
            'id': p['id'],
            'name': p['full_name'] ?? 'Unknown',
            'email': p['email'],
            'avatar': p['avatar_url'],
          };
        }).toList();

        _barberProfiles = {};
        for (var profile in allProfiles) {
          _barberProfiles[profile['id']] = profile;
        }

        // Get leaves for these barbers
        await _loadLeavesWithFilters(barberIds);
      } else {
        _barbers = [];
        _leaves = [];
      }
      
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLeavesWithFilters(List<String> barberIds) async {
    List<Map<String, dynamic>> allLeaves = [];
    
    for (String barberId in barberIds) {
      var query = supabase
          .from('barber_leaves')
          .select()
          .eq('barber_id', barberId)
          .eq('salon_id', int.parse(widget.salonId!));

      if (_selectedBarberId != null) {
        query = query.eq('barber_id', _selectedBarberId!);
      }

      if (_selectedDate != null) {
        final dateStr = '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
        query = query.eq('leave_date', dateStr);
      }

      if (_selectedStatus != 'all') {
        query = query.eq('status', _selectedStatus);
      }

      if (_selectedType != 'all') {
        query = query.eq('leave_type', _selectedType);
      }

      final leavesForBarber = await query;
      allLeaves.addAll(leavesForBarber);
    }

    // Sort by date (newest first)
    allLeaves.sort((a, b) {
      final dateA = a['leave_date'] ?? '';
      final dateB = b['leave_date'] ?? '';
      return dateB.compareTo(dateA);
    });

    if (mounted) {
      setState(() {
        _leaves = allLeaves;
      });
    }
  }

  Future<void> _applyFilters() async {
    setState(() => _isLoading = true);
    
    final salonBarbersResponse = await supabase
        .from('salon_barbers')
        .select('barber_id')
        .eq('salon_id', int.parse(widget.salonId!))
        .eq('is_active', true);

    final barberIds = salonBarbersResponse.map((sb) => sb['barber_id'] as String).toList();
    
    await _loadLeavesWithFilters(barberIds);
    
    setState(() => _isLoading = false);
  }

  // Log owner activity with IP
  Future<void> _logOwnerActivity({
    required String actionType,
    required String targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final ownerId = supabase.auth.currentUser?.id;
      if (ownerId == null) return;

      // Get IP (use cached or fetch if needed)
      final ip = _currentIp ?? await IpHelper.getPublicIp();

      final logData = {
        'owner_id': ownerId,
        'action_type': actionType,
        'target_type': targetType,
        'target_id': targetId,
        'details': details ?? {},
        'ip_address': ip,
        'created_at': DateTime.now().toIso8601String(),
      };

      debugPrint('📝 Logging activity: $actionType');
      
      await supabase.from('owner_activity_log').insert(logData);
      
      debugPrint('✅ Activity logged: $actionType');
    } catch (e) {
      debugPrint('❌ Error logging activity: $e');
      // Don't throw - logging failure shouldn't break the main flow
    }
  }

  Future<void> _addLeave() async {
    if (_barbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No barbers to add leave'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEditLeaveDialog(
        barbers: _barbers,
        salonId: widget.salonId!,
        salonOpenTime: _salonOpenTime,
        salonCloseTime: _salonCloseTime,
      ),
    );

    if (result != null && result['success'] == true) {
      // Log add activity
      await _logOwnerActivity(
        actionType: 'add_leave',
        targetType: 'barber_leave',
        targetId: result['leave_id']?.toString(),
        details: {
          'barber_id': result['barber_id'],
          'barber_name': result['barber_name'],
          'leave_date': result['leave_date'],
          'leave_type': result['leave_type'],
          'reason': result['reason'],
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request added'),
          backgroundColor: Colors.green,
        ),
      );
      
      await _loadData();
    }
  }

  // Edit leave method with logging
  Future<void> _editLeave(Map<String, dynamic> leave) async {
    final oldData = Map<String, dynamic>.from(leave);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEditLeaveDialog(
        barbers: _barbers,
        salonId: widget.salonId!,
        salonOpenTime: _salonOpenTime,
        salonCloseTime: _salonCloseTime,
        leaveToEdit: leave,
      ),
    );

    if (result != null && result['success'] == true) {
      // Log edit activity
      await _logOwnerActivity(
        actionType: 'edit_leave',
        targetType: 'barber_leave',
        targetId: leave['id'].toString(),
        details: {
          'leave_id': leave['id'],
          'barber_id': leave['barber_id'],
          'barber_name': _barberProfiles[leave['barber_id']]?['full_name'] ?? 'Unknown',
          'leave_date': leave['leave_date'],
          'old_data': {
            'leave_type': oldData['leave_type'],
            'reason': oldData['reason'],
            'start_time': oldData['start_time'],
            'end_time': oldData['end_time'],
            'status': oldData['status'],
          },
          'new_data': {
            'leave_type': result['leave_type'],
            'reason': result['reason'],
            'start_time': result['start_time'],
            'end_time': result['end_time'],
          },
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      await _loadData();
    }
  }

  // Update leave status with logging
  Future<void> _updateLeaveStatus(int leaveId, String status, {Map<String, dynamic>? leaveData}) async {
    // Show confirmation dialog first
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${status == 'approved' ? 'Approve' : status == 'rejected' ? 'Reject' : 'Update'} Leave'),
          content: Text('Are you sure you want to change status to ${status.toUpperCase()}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: status == 'approved' ? Colors.green : 
                                 status == 'rejected' ? Colors.red : Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(status == 'approved' ? 'Approve' : 
                         status == 'rejected' ? 'Reject' : 'Update'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        // Get current leave data if not provided
        Map<String, dynamic> currentLeave = leaveData ?? {};
        if (currentLeave.isEmpty) {
          final response = await supabase
              .from('barber_leaves')
              .select()
              .eq('id', leaveId)
              .single();
          currentLeave = response;
        }

        final oldStatus = currentLeave['status'] ?? 'pending';
        
        // Update status
        await supabase
            .from('barber_leaves')
            .update({'status': status})
            .eq('id', leaveId);

        // Log the status change
        await _logOwnerActivity(
          actionType: 'update_leave_status',
          targetType: 'barber_leave',
          targetId: leaveId.toString(),
          details: {
            'leave_id': leaveId,
            'barber_id': currentLeave['barber_id'],
            'barber_name': _barberProfiles[currentLeave['barber_id']]?['full_name'] ?? 'Unknown',
            'leave_date': currentLeave['leave_date'],
            'old_status': oldStatus,
            'new_status': status,
            'leave_type': currentLeave['leave_type'],
          },
        );

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated to ${status.toUpperCase()}'),
              backgroundColor: status == 'approved' ? Colors.green : 
                               status == 'rejected' ? Colors.red : Colors.orange,
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating leave: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Delete leave method with logging
  Future<void> _deleteLeave(Map<String, dynamic> leave) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Leave'),
          content: const Text('Are you sure you want to delete this leave request? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        // Log before deleting
        await _logOwnerActivity(
          actionType: 'delete_leave',
          targetType: 'barber_leave',
          targetId: leave['id'].toString(),
          details: {
            'leave_id': leave['id'],
            'barber_id': leave['barber_id'],
            'barber_name': _barberProfiles[leave['barber_id']]?['full_name'] ?? 'Unknown',
            'leave_date': leave['leave_date'],
            'leave_type': leave['leave_type'],
            'status': leave['status'],
            'reason': leave['reason'],
            'start_time': leave['start_time'],
            'end_time': leave['end_time'],
          },
        );

        await supabase
            .from('barber_leaves')
            .delete()
            .eq('id', leave['id']);

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting leave: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Show status dropdown for web
  void _showStatusMenuWeb(BuildContext context, Offset offset, Map<String, dynamic> leave) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx + 200,
        offset.dy + 150,
      ),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'pending',
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Pending'),
              if (leave['status'] == 'pending')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16, color: Colors.orange),
                ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'approved',
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Approved'),
              if (leave['status'] == 'approved')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16, color: Colors.green),
                ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rejected',
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Rejected'),
              if (leave['status'] == 'rejected')
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16, color: Colors.red),
                ),
            ],
          ),
        ),
      ],
    );

    if (result != null && result != leave['status']) {
      _updateLeaveStatus(leave['id'], result, leaveData: leave);
    }
  }

  // Show status dropdown for mobile
  void _showStatusBottomSheet(BuildContext context, Map<String, dynamic> leave) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Change Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              _buildStatusOption(context, leave, 'pending', 'Pending', Colors.orange),
              _buildStatusOption(context, leave, 'approved', 'Approved', Colors.green),
              _buildStatusOption(context, leave, 'rejected', 'Rejected', Colors.red),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusOption(BuildContext dialogContext, Map<String, dynamic> leave, String status, String label, Color color) {
    return ListTile(
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: leave['status'] == status ? FontWeight.bold : FontWeight.normal,
          color: leave['status'] == status ? color : null,
        ),
      ),
      trailing: leave['status'] == status 
          ? Icon(Icons.check, color: color, size: 20)
          : null,
      onTap: () {
        Navigator.pop(dialogContext);
        if (status != leave['status']) {
          _updateLeaveStatus(leave['id'], status, leaveData: leave);
        }
      },
    );
  }

  // Status cell widget
  Widget _buildStatusCell(Map<String, dynamic> leave, String status) {
    final Color statusColor = _getStatusColor(status);
    final GlobalKey cellKey = GlobalKey();
    
    return GestureDetector(
      key: cellKey,
      onTapDown: (TapDownDetails details) {
        final RenderBox? renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final Offset localPosition = details.localPosition;
          final Offset globalPosition = renderBox.localToGlobal(localPosition);
          _showStatusMenuWeb(context, globalPosition, leave);
        } else {
          _showStatusBottomSheet(context, leave);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              status.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: statusColor,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '${displayHour}:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '';
    }
  }

  String _getLeaveTypeIcon(String type) {
    switch (type) {
      case 'full_day': return '📅';
      case 'half_day': return '⌛';
      case 'emergency': return '🚨';
      case 'short_leave': return '⏱️';
      default: return '📝';
    }
  }

  String _getLeaveTypeName(String type) {
    switch (type) {
      case 'full_day': return 'Full Day';
      case 'half_day': return 'Half Day';
      case 'emergency': return 'Emergency';
      case 'short_leave': return 'Short Leave';
      default: return type;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved': 
        return Colors.green;
      case 'rejected': 
        return Colors.red;
      case 'pending': 
        return Colors.orange;
      default: 
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barber Leaves'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: isWeb
                ? Row(
                    children: [
                      Expanded(child: _buildBarberFilter()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateFilter()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTypeFilter()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatusFilter()),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.filter_alt),
                        label: const Text('Apply Filters'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildBarberFilter(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildDateFilter()),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTypeFilter()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildStatusFilter()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _applyFilters,
                              icon: const Icon(Icons.filter_alt),
                              label: const Text('Apply'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B8B),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // Leaves List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
                : _barbers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(padding),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off, size: isWeb ? 80 : 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              const Text(
                                'No barbers found',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add barbers first to manage leaves',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => context.pop(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6B8B),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Go Back'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _leaves.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(padding),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.beach_access, size: isWeb ? 80 : 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No leave records',
                                    style: TextStyle(fontSize: 18, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Use + button to add leave for barbers',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : isWeb
                            ? _buildWebView(padding)
                            : _buildMobileView(padding),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLeave,
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBarberFilter() {
    return Container(
      height: 50,
      child: DropdownButtonFormField<String>(
        value: _selectedBarberId,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        hint: const Text('All Barbers'),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('All Barbers'),
          ),
          ..._barbers.map<DropdownMenuItem<String>>((b) {
            return DropdownMenuItem<String>(
              value: b['id'] as String,
              child: Text(b['name'] as String),
            );
          }).toList(),
        ],
        onChanged: (String? value) {
          setState(() {
            _selectedBarberId = value;
          });
        },
      ),
    );
  }

  Widget _buildDateFilter() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (date != null) setState(() => _selectedDate = date);
      },
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedDate != null
                    ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                    : 'Select Date',
                style: TextStyle(
                  color: _selectedDate != null ? Colors.black : Colors.grey[500],
                ),
              ),
            ),
            if (_selectedDate != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _selectedDate = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      height: 50,
      child: DropdownButtonFormField<String>(
        value: _selectedType,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: const [
          DropdownMenuItem<String>(value: 'all', child: Text('All Types')),
          DropdownMenuItem<String>(value: 'full_day', child: Text('Full Day')),
          DropdownMenuItem<String>(value: 'half_day', child: Text('Half Day')),
          DropdownMenuItem<String>(value: 'emergency', child: Text('Emergency')),
          DropdownMenuItem<String>(value: 'short_leave', child: Text('Short Leave')),
        ],
        onChanged: (String? value) {
          setState(() {
            _selectedType = value ?? 'all';
          });
        },
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      height: 50,
      child: DropdownButtonFormField<String>(
        value: _selectedStatus,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: const [
          DropdownMenuItem<String>(value: 'all', child: Text('All Status')),
          DropdownMenuItem<String>(value: 'pending', child: Text('Pending')),
          DropdownMenuItem<String>(value: 'approved', child: Text('Approved')),
          DropdownMenuItem<String>(value: 'rejected', child: Text('Rejected')),
        ],
        onChanged: (String? value) {
          setState(() {
            _selectedStatus = value ?? 'all';
          });
        },
      ),
    );
  }

  Widget _buildWebView(double padding) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          // Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildStatItem('Total', _leaves.length.toString(), Icons.event_note),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    'Pending',
                    _leaves.where((l) => l['status'] == 'pending').length.toString(),
                    Icons.pending,
                    Colors.orange,
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    'Approved',
                    _leaves.where((l) => l['status'] == 'approved').length.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  _buildStatItem(
                    'Rejected',
                    _leaves.where((l) => l['status'] == 'rejected').length.toString(),
                    Icons.cancel,
                    Colors.red,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Table Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                Expanded(flex: 2, child: Text('Barber', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  flex: 1, 
                  child: Text(
                    'Status', 
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2, 
                  child: Text(
                    'Actions', 
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Table Rows
          ..._leaves.map((leave) {
            final barberId = leave['barber_id'] as String;
            final profile = _barberProfiles[barberId] ?? {};
            final barberName = profile['full_name'] ?? 'Unknown';
            final leaveDate = _formatDate(leave['leave_date']);
            final leaveType = leave['leave_type'] ?? 'full_day';
            final status = leave['status'] ?? 'pending';
            final reason = leave['reason'] ?? 'No reason provided';
            
            String timeDisplay = '';
            if (leaveType == 'full_day' || leaveType == 'emergency') {
              timeDisplay = 'All Day';
            } else if (leaveType == 'half_day') {
              timeDisplay = '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
            } else if (leaveType == 'short_leave') {
              timeDisplay = '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                          backgroundImage: profile['avatar_url'] != null
                              ? NetworkImage(profile['avatar_url'])
                              : null,
                          child: profile['avatar_url'] == null
                              ? Text(
                                  barberName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFFFF6B8B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            barberName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(leaveDate),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Text(
                          _getLeaveTypeIcon(leaveType),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getLeaveTypeName(leaveType),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      timeDisplay,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      reason,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: _buildStatusCell(leave, status),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _editLeave(leave),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteLeave(leave),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMobileView(double padding) {
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _leaves.length,
      itemBuilder: (context, index) {
        final leave = _leaves[index];
        final barberId = leave['barber_id'] as String;
        final profile = _barberProfiles[barberId] ?? {};
        final barberName = profile['full_name'] ?? 'Unknown';
        final leaveDate = _formatDate(leave['leave_date']);
        final leaveType = leave['leave_type'] ?? 'full_day';
        final status = leave['status'] ?? 'pending';
        final reason = leave['reason'] ?? 'No reason provided';
        
        String timeDisplay = '';
        if (leaveType == 'full_day' || leaveType == 'emergency') {
          timeDisplay = 'All Day';
        } else if (leaveType == 'half_day') {
          timeDisplay = '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
        } else if (leaveType == 'short_leave') {
          timeDisplay = '${_formatTime(leave['start_time'])} - ${_formatTime(leave['end_time'])}';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  backgroundImage: profile['avatar_url'] != null
                      ? NetworkImage(profile['avatar_url'])
                      : null,
                  child: profile['avatar_url'] == null
                      ? Text(
                          barberName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFFF6B8B),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        barberName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    _buildStatusCell(leave, status),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          leaveDate,
                          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _getLeaveTypeIcon(leaveType),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getLeaveTypeName(leaveType),
                          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                        ),
                        const SizedBox(width: 8),
                        if (timeDisplay.isNotEmpty)
                          Expanded(
                            child: Text(
                              '• $timeDisplay',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              
              // Action buttons row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editLeave(leave),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteLeave(leave),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, [Color? color]) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color ?? const Color(0xFFFF6B8B)),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== ADD/EDIT LEAVE DIALOG ====================
class _AddEditLeaveDialog extends StatefulWidget {
  final List<Map<String, dynamic>> barbers;
  final String salonId;
  final String? salonOpenTime;
  final String? salonCloseTime;
  final Map<String, dynamic>? leaveToEdit;

  const _AddEditLeaveDialog({
    required this.barbers,
    required this.salonId,
    this.salonOpenTime,
    this.salonCloseTime,
    this.leaveToEdit,
  });

  @override
  State<_AddEditLeaveDialog> createState() => _AddEditLeaveDialogState();
}

class _AddEditLeaveDialogState extends State<_AddEditLeaveDialog> {
  final supabase = Supabase.instance.client;
  
  String? _selectedBarberId;
  DateTime? _selectedDate;
  String _leaveType = 'full_day';
  final TextEditingController _reasonController = TextEditingController();
  
  // Time selection
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _isEditMode = false;
  int? _editLeaveId;

  // Working hours from salon
  TimeOfDay? _minTime;
  TimeOfDay? _maxTime;

  @override
  void initState() {
    super.initState();
    _parseSalonHours();
    
    if (widget.leaveToEdit != null) {
      _isEditMode = true;
      _loadLeaveData();
    }
  }

  void _parseSalonHours() {
    if (widget.salonOpenTime != null) {
      final openParts = widget.salonOpenTime!.split(':');
      _minTime = TimeOfDay(
        hour: int.parse(openParts[0]),
        minute: int.parse(openParts[1]),
      );
      _startTime = _minTime!;
    }

    if (widget.salonCloseTime != null) {
      final closeParts = widget.salonCloseTime!.split(':');
      _maxTime = TimeOfDay(
        hour: int.parse(closeParts[0]),
        minute: int.parse(closeParts[1]),
      );
      _endTime = _maxTime!;
    }
  }

  void _loadLeaveData() {
    final leave = widget.leaveToEdit!;
    
    _selectedBarberId = leave['barber_id'];
    _leaveType = leave['leave_type'] ?? 'full_day';
    _reasonController.text = leave['reason'] ?? '';
    _editLeaveId = leave['id'];
    
    if (leave['leave_date'] != null) {
      try {
        _selectedDate = DateTime.parse(leave['leave_date']);
      } catch (e) {}
    }
    
    if (leave['start_time'] != null && leave['end_time'] != null) {
      try {
        final startParts = leave['start_time'].split(':');
        final endParts = leave['end_time'].split(':');
        
        _startTime = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );
        
        _endTime = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );
      } catch (e) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isWeb ? 600 : screenWidth * 0.95,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(_isEditMode ? Icons.edit : Icons.beach_access, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _isEditMode ? 'Edit Leave' : 'Add Leave',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isWeb ? 24 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Text('Select Barber', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedBarberId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      hint: const Text('Choose barber'),
                      items: widget.barbers.map<DropdownMenuItem<String>>((b) {
                        return DropdownMenuItem<String>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String),
                        );
                      }).toList(),
                      onChanged: _isEditMode 
                          ? null
                          : (String? value) {
                              setState(() {
                                _selectedBarberId = value;
                                _errorMessage = null;
                              });
                            },
                    ),

                    const SizedBox(height: 16),

                    const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                            _errorMessage = null;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDate != null
                                    ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                                    : 'Select date',
                                style: TextStyle(
                                  color: _selectedDate != null ? Colors.black : Colors.grey[500],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text('Leave Type', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTypeChip('Full Day', 'full_day', Icons.calendar_month, Colors.purple),
                        _buildTypeChip('Half Day', 'half_day', Icons.access_time, Colors.blue),
                        _buildTypeChip('Emergency', 'emergency', Icons.warning, Colors.red),
                        _buildTypeChip('Short Leave', 'short_leave', Icons.timer, Colors.green),
                      ],
                    ),

                    if (_leaveType == 'half_day' || _leaveType == 'short_leave') ...[
                      const SizedBox(height: 16),
                      const Text('Select Time', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      
                      if (_minTime != null && _maxTime != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Salon hours: ${_formatTimeOfDay(_minTime!)} - ${_formatTimeOfDay(_maxTime!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTimePicker(
                                label: 'Start Time',
                                time: _startTime,
                                onTimeSelected: (TimeOfDay newTime) {
                                  setState(() => _startTime = newTime);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTimePicker(
                                label: 'End Time',
                                time: _endTime,
                                onTimeSelected: (TimeOfDay newTime) {
                                  setState(() => _endTime = newTime);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_leaveType == 'short_leave')
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer, size: 16, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Maximum 2 hours for short leave',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_leaveType == 'half_day')
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Half day should be approximately 4 hours',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 16),

                    const Text('Reason', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter reason for leave',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Footer with buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedBarberId != null && _selectedDate != null && !_isLoading
                        ? _saveLeave
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(_isEditMode ? 'Update' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, String value, IconData icon, Color color) {
    final isSelected = _leaveType == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon, 
            size: 14, 
            color: isSelected ? Colors.white : color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _leaveType = value;
          _errorMessage = null;
        });
      },
      backgroundColor: Colors.grey[100],
      selectedColor: color,
      checkmarkColor: Colors.white,
      showCheckmark: false,
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onTimeSelected,
  }) {
    return GestureDetector(
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onTimeSelected(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimeOfDay(time),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _saveLeave() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_leaveType == 'half_day' || _leaveType == 'short_leave') {
        final startMinutes = _startTime.hour * 60 + _startTime.minute;
        final endMinutes = _endTime.hour * 60 + _endTime.minute;
        
        if (_minTime != null) {
          final minMinutes = _minTime!.hour * 60 + _minTime!.minute;
          if (startMinutes < minMinutes) {
            setState(() {
              _errorMessage = 'Start time cannot be before salon opening time';
              _isLoading = false;
            });
            return;
          }
        }

        if (_maxTime != null) {
          final maxMinutes = _maxTime!.hour * 60 + _maxTime!.minute;
          if (endMinutes > maxMinutes) {
            setState(() {
              _errorMessage = 'End time cannot be after salon closing time';
              _isLoading = false;
            });
            return;
          }
        }

        if (startMinutes >= endMinutes) {
          setState(() {
            _errorMessage = 'Start time must be before end time';
            _isLoading = false;
          });
          return;
        }

        final durationMinutes = endMinutes - startMinutes;
        
        if (_leaveType == 'half_day') {
          if (durationMinutes < 180 || durationMinutes > 300) {
            setState(() {
              _errorMessage = 'Half day should be approximately 4 hours (3-5 hours range)';
              _isLoading = false;
            });
            return;
          }
        } else if (_leaveType == 'short_leave') {
          if (durationMinutes > 120) {
            setState(() {
              _errorMessage = 'Short leave cannot exceed 2 hours';
              _isLoading = false;
            });
            return;
          }
          if (durationMinutes < 15) {
            setState(() {
              _errorMessage = 'Short leave must be at least 15 minutes';
              _isLoading = false;
            });
            return;
          }
        }
      }

      final dateStr = '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      
      if (!_isEditMode) {
        final existingLeave = await supabase
            .from('barber_leaves')
            .select()
            .eq('barber_id', _selectedBarberId!)
            .eq('leave_date', dateStr)
            .maybeSingle();

        if (existingLeave != null) {
          setState(() {
            _errorMessage = 'This barber already has a leave on this date.';
            _isLoading = false;
          });
          return;
        }
      }

      Map<String, dynamic> leaveData = {
        'barber_id': _selectedBarberId!,
        'salon_id': int.parse(widget.salonId),
        'leave_date': dateStr,
        'leave_type': _leaveType,
        'reason': _reasonController.text.trim(),
        'status': _isEditMode ? widget.leaveToEdit!['status'] : 'pending',
      };

      if (_leaveType == 'half_day' || _leaveType == 'short_leave') {
        leaveData['start_time'] = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';
        leaveData['end_time'] = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00';
      } else {
        leaveData['start_time'] = null;
        leaveData['end_time'] = null;
      }

      if (_isEditMode) {
        await supabase
            .from('barber_leaves')
            .update(leaveData)
            .eq('id', _editLeaveId!);
      } else {
        await supabase.from('barber_leaves').insert(leaveData);
      }

      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'leave_id': _editLeaveId ?? leaveData['id'],
          'barber_id': _selectedBarberId,
          'barber_name': widget.barbers.firstWhere(
            (b) => b['id'] == _selectedBarberId,
            orElse: () => {'name': 'Unknown'},
          )['name'],
          'leave_date': dateStr,
          'leave_type': _leaveType,
          'reason': _reasonController.text.trim(),
          'start_time': leaveData['start_time'],
          'end_time': leaveData['end_time'],
        });
      }
    } catch (e) {
      debugPrint('❌ Error saving leave: $e');
      
      if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
        setState(() {
          _errorMessage = 'This barber already has a leave on this date.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Error saving leave: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }
}