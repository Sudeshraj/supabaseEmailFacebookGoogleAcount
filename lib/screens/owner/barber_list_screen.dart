import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BarberListScreen extends StatefulWidget {
  final String? salonId;

  const BarberListScreen({super.key, this.salonId});

  @override
  State<BarberListScreen> createState() => _BarberListScreenState();
}

class _BarberListScreenState extends State<BarberListScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _selectedFilter = 'all';
  List<Map<String, dynamic>> _barbers = [];

  // Alternating card colors
  final List<Color> _cardColors = [
    const Color(0xFFE3F2FD), // Light Blue
    const Color(0xFFFCE4EC), // Light Pink
    const Color(0xFFE8F5E9), // Light Green
    const Color(0xFFFFF3E0), // Light Orange
    const Color(0xFFF3E5F5), // Light Purple
    const Color(0xFFE0F7FA), // Light Cyan
    const Color(0xFFFFEBEE), // Light Red
    const Color(0xFFE8EAF6), // Light Indigo
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ============================================================
  // ✅ UPDATED: LOAD DATA WITH user_roles.status CHECK
  // ============================================================
  Future<void> _loadData() async {
    if (widget.salonId == null) {
      if (mounted) {
        setState(() {
          _barbers = [];
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId!);

      // ✅ Step 1: Get salon barbers
      var query = supabase
          .from('salon_barbers')
          .select('id, barber_id, status, joined_at')
          .eq('salon_id', salonIdInt);

      if (_selectedFilter == 'active') {
        query = query.eq('status', 'active');
      } else if (_selectedFilter == 'inactive') {
        query = query.eq('status', 'inactive');
      } else if (_selectedFilter == 'deleted') {
        query = query.eq('status', 'deleted');
      }

      final salonBarbersResponse = await query.order(
        'joined_at',
        ascending: false,
      );

      if (salonBarbersResponse.isEmpty) {
        if (mounted) {
          setState(() {
            _barbers = [];
            _isLoading = false;
          });
        }
        return;
      }

      final barberIds = salonBarbersResponse
          .map((sb) => sb['barber_id'] as String)
          .toList();

      // ✅ Step 2: Get profiles for these barbers (NO join with user_roles)
      final profilesResponse = await supabase
          .from('profiles')
          .select('''
          id,
          full_name,
          email,
          phone,
          avatar_url,
          created_at,
          is_active,
          is_blocked
        ''')
          .inFilter('id', barberIds);

      // ✅ Step 3: Get user_roles for these barbers (separate query)
      final userRolesResponse = await supabase
          .from('user_roles')
          .select('user_id, status, role_id')
          .inFilter('user_id', barberIds)
          .eq('role_id', 2); // barber role ID

      // Create maps for quick lookup
      final Map<String, Map<String, dynamic>> profileMap = {};
      for (var profile in profilesResponse) {
        profileMap[profile['id']] = profile;
      }

      // Create user_roles status map
      final Map<String, String> roleStatusMap = {};
      for (var role in userRolesResponse) {
        roleStatusMap[role['user_id']] = role['status'] ?? 'active';
      }

      // ✅ Step 4: Get service counts for each barber
      Map<String, int> serviceCountMap = {};
      for (var sb in salonBarbersResponse) {
        final salonBarberId = sb['id'] as int;
        final count = await supabase
            .from('barber_services')
            .select('id')
            .eq('salon_barber_id', salonBarberId);

        serviceCountMap[sb['barber_id']] = count.length;
      }

      // ✅ Step 5: Combine all data
      List<Map<String, dynamic>> combinedList = [];

      for (var sb in salonBarbersResponse) {
        final barberId = sb['barber_id'] as String;
        final profile = profileMap[barberId] ?? {};
        final roleStatus = roleStatusMap[barberId] ?? 'active';

        // Check profile status
        final isProfileActive = profile['is_active'] ?? true;
        final isProfileBlocked = profile['is_blocked'] ?? false;

        // Determine actual status (combine all statuses)
        String actualStatus = sb['status'] ?? 'active';

        // If user_roles status is not active, override
        if (roleStatus != 'active') {
          actualStatus = roleStatus;
        }

        // If profile is blocked, override
        if (isProfileBlocked) {
          actualStatus = 'blocked';
        } else if (!isProfileActive && actualStatus == 'active') {
          actualStatus = 'inactive';
        }

        combinedList.add({
          'id': barberId,
          'salon_barber_id': sb['id'],
          'status': actualStatus,
          'joined_at': sb['joined_at'],
          'name': profile['full_name'] ?? 'Unknown',
          'email': profile['email'] ?? '',
          'phone': profile['phone'] ?? 'No phone',
          'avatar': profile['avatar_url'],
          'created_at': profile['created_at'],
          'service_count': serviceCountMap[barberId] ?? 0,
          'user_roles_status': roleStatus,
          'profile_active': isProfileActive,
          'profile_blocked': isProfileBlocked,
        });
      }

      if (mounted) {
        setState(() {
          _barbers = combinedList;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading barbers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ✅ UPDATED: ACTIVATE BARBER (Update user_roles.status)
  // ============================================================
  Future<void> _activateBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    try {
      // ✅ Update salon_barbers status
      await supabase
          .from('salon_barbers')
          .update({'status': 'active'})
          .eq('id', salonBarberId);

      // ✅ Update user_roles status to active
      await supabase
          .from('user_roles')
          .update({
            'status': 'active',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', barberId)
          .eq('role_id', 2); // barber role ID

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $barberName activated'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error activating barber: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ============================================================
  // ✅ UPDATED: DEACTIVATE BARBER (Update user_roles.status)
  // ============================================================
  Future<void> _deactivateBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deactivate Barber'),
        content: Text(
          'Temporarily deactivate $barberName? They can be reactivated later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // ✅ Update salon_barbers status
        await supabase
            .from('salon_barbers')
            .update({'status': 'inactive'})
            .eq('id', salonBarberId);

        // ✅ Update user_roles status to inactive
        await supabase
            .from('user_roles')
            .update({
              'status': 'inactive',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', barberId)
            .eq('role_id', 2); // barber role ID

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⏸️ $barberName deactivated'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error deactivating barber: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ============================================================
  // ✅ UPDATED: DELETE BARBER (Update user_roles.status)
  // ============================================================
  Future<void> _deleteBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Barber'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Permanently delete $barberName from this salon?'),
            const SizedBox(height: 8),
            const Text(
              '• They will be hidden from all lists',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const Text(
              '• All their data (appointments, leaves) will be kept',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const Text(
              '• This action can be reversed by restoring',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // ✅ Update salon_barbers status
        await supabase
            .from('salon_barbers')
            .update({'status': 'deleted'})
            .eq('id', salonBarberId);

        // ✅ Update user_roles status to deleted
        await supabase
            .from('user_roles')
            .update({
              'status': 'deleted',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', barberId)
            .eq('role_id', 2); // barber role ID

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ $barberName deleted'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error deleting barber: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ============================================================
  // ✅ UPDATED: RESTORE BARBER (Update user_roles.status)
  // ============================================================
  Future<void> _restoreBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restore Barber'),
        content: Text('Restore $barberName to inactive status?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // ✅ Update salon_barbers status
        await supabase
            .from('salon_barbers')
            .update({'status': 'inactive'})
            .eq('id', salonBarberId);

        // ✅ Update user_roles status to inactive
        await supabase
            .from('user_roles')
            .update({
              'status': 'inactive',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', barberId)
            .eq('role_id', 2); // barber role ID

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🔄 $barberName restored'),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error restoring barber: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _editBarberServices(Map<String, dynamic> barber) {
    context.push(
      '/owner/edit-barber-services?barberId=${barber['id']}&salonId=${widget.salonId}',
    );
  }

  void _viewSchedule(Map<String, dynamic> barber) {
    context.push(
      '/owner/barber-schedule?barberId=${barber['id']}&salonId=${widget.salonId}',
    );
  }

  void _viewLeaves(Map<String, dynamic> barber) {
    context.push(
      '/owner/barber-leaves?barberId=${barber['id']}&salonId=${widget.salonId}',
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final months = [
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
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  // ============================================================
  // ✅ UPDATED: STATUS HELPER METHODS WITH 'blocked'
  // ============================================================
  String _getStatusText(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'inactive':
        return 'Inactive';
      case 'deleted':
        return 'Deleted';
      case 'blocked':
        return 'Blocked';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.orange;
      case 'deleted':
        return Colors.red;
      case 'blocked':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'inactive':
        return Icons.pause_circle;
      case 'deleted':
        return Icons.delete;
      case 'blocked':
        return Icons.block;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 800;
    final double padding = isDesktop ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barber List'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: !isDesktop,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () =>
                context.push('/owner/add-barber?salonId=${widget.salonId}'),
            tooltip: 'Add Barber',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : _barbers.isEmpty
          ? _buildEmptyState(isDesktop, padding)
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFFFF6B8B),
              child: isDesktop
                  ? _buildDesktopView(padding)
                  : _buildMobileView(padding),
            ),
    );
  }

  Widget _buildEmptyState(bool isDesktop, double padding) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: isDesktop ? 80 : 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No barbers found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Add barbers to get started',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  context.push('/owner/add-barber?salonId=${widget.salonId}'),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Barber'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 237, 231, 233),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DESKTOP VIEW ====================

  Widget _buildDesktopView(double padding) {
    final activeCount = _barbers.where((b) => b['status'] == 'active').length;
    final inactiveCount = _barbers
        .where((b) => b['status'] == 'inactive')
        .length;
    final deletedCount = _barbers.where((b) => b['status'] == 'deleted').length;
    final blockedCount = _barbers.where((b) => b['status'] == 'blocked').length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          // Stats Cards
          Row(
            children: [
              _buildStatCard(
                'Total',
                _barbers.length.toString(),
                Icons.people,
                Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Active',
                activeCount.toString(),
                Icons.check_circle,
                Colors.green,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Inactive',
                inactiveCount.toString(),
                Icons.pause_circle,
                Colors.orange,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Deleted',
                deletedCount.toString(),
                Icons.delete,
                Colors.red,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Blocked',
                blockedCount.toString(),
                Icons.block,
                Colors.purple,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Table Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Barber',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Contact',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Joined',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Services',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 3,
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
          ..._barbers.asMap().entries.map(
            (entry) => _buildDesktopBarberRow(entry.value, entry.key),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ UPDATED: DESKTOP BARBER ROW WITH barberId PASS
  // ============================================================
  Widget _buildDesktopBarberRow(Map<String, dynamic> barber, int index) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);
    final cardColor = _cardColors[index % _cardColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Barber info
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: statusColor.withValues(alpha: 0.1),
                      backgroundImage: barber['avatar'] != null
                          ? NetworkImage(barber['avatar'])
                          : null,
                      child: barber['avatar'] == null
                          ? Text(
                              barber['name'][0].toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    if (status != 'active')
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            statusIcon,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        barber['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        barber['email'],
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Contact
          Expanded(
            flex: 2,
            child: Text(
              barber['phone'] ?? 'No phone',
              style: TextStyle(
                color: barber['phone'] == 'No phone'
                    ? Colors.grey[400]
                    : Colors.grey[800],
              ),
            ),
          ),

          // Joined date
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(barber['joined_at']),
              style: const TextStyle(fontSize: 14),
            ),
          ),

          // Service count
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${barber['service_count']}',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),

          // Status
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Actions
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _editBarberServices(barber),
                  tooltip: 'Edit Services',
                ),
                IconButton(
                  icon: const Icon(Icons.schedule, color: Colors.teal),
                  onPressed: () => _viewSchedule(barber),
                  tooltip: 'View Schedule',
                ),
                IconButton(
                  icon: const Icon(Icons.beach_access, color: Colors.orange),
                  onPressed: () => _viewLeaves(barber),
                  tooltip: 'View Leaves',
                ),
                if (status == 'active')
                  IconButton(
                    icon: const Icon(Icons.pause_circle, color: Colors.orange),
                    onPressed: () => _deactivateBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'], // ✅ Pass barber ID
                    ),
                    tooltip: 'Deactivate',
                  ),
                if (status == 'inactive') ...[
                  IconButton(
                    icon: const Icon(Icons.play_circle, color: Colors.green),
                    onPressed: () => _activateBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'], // ✅ Pass barber ID
                    ),
                    tooltip: 'Activate',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'], // ✅ Pass barber ID
                    ),
                    tooltip: 'Delete',
                  ),
                ],
                if (status == 'deleted')
                  IconButton(
                    icon: const Icon(Icons.restore, color: Colors.blue),
                    onPressed: () => _restoreBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'], // ✅ Pass barber ID
                    ),
                    tooltip: 'Restore',
                  ),
                if (status == 'blocked')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.purple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'Contact Support',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.purple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MOBILE VIEW ====================

  Widget _buildMobileView(double padding) {
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        final barber = _barbers[index];
        final status = barber['status'] ?? 'active';
        final statusColor = _getStatusColor(status);
        final statusText = _getStatusText(status);
        final statusIcon = _getStatusIcon(status);
        final cardColor = _cardColors[index % _cardColors.length];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: statusColor, width: 4)),
            ),
            child: Column(
              children: [
                // Header with avatar and name
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: statusColor.withValues(alpha: 0.1),
                            backgroundImage: barber['avatar'] != null
                                ? NetworkImage(barber['avatar'])
                                : null,
                            child: barber['avatar'] == null
                                ? Text(
                                    barber['name'][0].toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  )
                                : null,
                          ),
                          if (status != 'active')
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  statusIcon,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              barber['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              barber['email'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        statusIcon,
                                        color: statusColor,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${barber['service_count']} services',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Contact and joined info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.phone,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  barber['phone'] ?? 'No phone',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: barber['phone'] == 'No phone'
                                        ? Colors.grey[400]
                                        : Colors.grey[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 20,
                          color: Colors.grey[300],
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 12,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(barber['joined_at']),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildMobileActionChip(
                        icon: Icons.edit,
                        label: 'Services',
                        color: Colors.blue,
                        onTap: () => _editBarberServices(barber),
                      ),
                      _buildMobileActionChip(
                        icon: Icons.schedule,
                        label: 'Schedule',
                        color: Colors.teal,
                        onTap: () => _viewSchedule(barber),
                      ),
                      _buildMobileActionChip(
                        icon: Icons.beach_access,
                        label: 'Leaves',
                        color: Colors.orange,
                        onTap: () => _viewLeaves(barber),
                      ),
                      if (status == 'active')
                        _buildMobileActionChip(
                          icon: Icons.pause_circle,
                          label: 'Deactivate',
                          color: Colors.orange,
                          onTap: () => _deactivateBarber(
                            barber['salon_barber_id'],
                            barber['name'],
                            barber['id'], // ✅ Pass barber ID
                          ),
                        ),
                      if (status == 'inactive') ...[
                        _buildMobileActionChip(
                          icon: Icons.play_circle,
                          label: 'Activate',
                          color: Colors.green,
                          onTap: () => _activateBarber(
                            barber['salon_barber_id'],
                            barber['name'],
                            barber['id'], // ✅ Pass barber ID
                          ),
                        ),
                        _buildMobileActionChip(
                          icon: Icons.delete,
                          label: 'Delete',
                          color: Colors.red,
                          onTap: () => _deleteBarber(
                            barber['salon_barber_id'],
                            barber['name'],
                            barber['id'], // ✅ Pass barber ID
                          ),
                        ),
                      ],
                      if (status == 'deleted')
                        _buildMobileActionChip(
                          icon: Icons.restore,
                          label: 'Restore',
                          color: Colors.blue,
                          onTap: () => _restoreBarber(
                            barber['salon_barber_id'],
                            barber['name'],
                            barber['id'], // ✅ Pass barber ID
                          ),
                        ),
                      if (status == 'blocked')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.purple.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'Blocked',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.purple,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== FILTER DIALOG ====================

  void _showFilterDialog() {
    String tempFilter = _selectedFilter!;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Filter Barbers'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterOption(
                  title: 'All Barbers',
                  value: 'all',
                  currentFilter: tempFilter,
                  icon: Icons.people,
                  color: Colors.blue,
                  onTap: () => setDialogState(() => tempFilter = 'all'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Active Only',
                  value: 'active',
                  currentFilter: tempFilter,
                  icon: Icons.check_circle,
                  color: Colors.green,
                  onTap: () => setDialogState(() => tempFilter = 'active'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Inactive Only',
                  value: 'inactive',
                  currentFilter: tempFilter,
                  icon: Icons.pause_circle,
                  color: Colors.orange,
                  onTap: () => setDialogState(() => tempFilter = 'inactive'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Deleted Only',
                  value: 'deleted',
                  currentFilter: tempFilter,
                  icon: Icons.delete,
                  color: Colors.red,
                  onTap: () => setDialogState(() => tempFilter = 'deleted'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Blocked Only',
                  value: 'blocked',
                  currentFilter: tempFilter,
                  icon: Icons.block,
                  color: Colors.purple,
                  onTap: () => setDialogState(() => tempFilter = 'blocked'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedFilter = tempFilter;
                  });
                  Navigator.pop(context);
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                ),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterOption({
    required String title,
    required String value,
    required String currentFilter,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: currentFilter == value ? color : Colors.grey[400]!,
                  width: 2,
                ),
                color: currentFilter == value
                    ? color.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              child: currentFilter == value
                  ? Center(child: Icon(Icons.circle, color: color, size: 12))
                  : null,
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
