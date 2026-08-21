import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

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

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // Alternating card colors - Dark mode aware
  final List<Color> _cardColorsLight = [
    const Color(0xFFE3F2FD),
    const Color(0xFFFCE4EC),
    const Color(0xFFE8F5E9),
    const Color(0xFFFFF3E0),
    const Color(0xFFF3E5F5),
    const Color(0xFFE0F7FA),
    const Color(0xFFFFEBEE),
    const Color(0xFFE8EAF6),
  ];

  final List<Color> _cardColorsDark = [
    const Color(0xFF1A237E),
    const Color(0xFF4A148C),
    const Color(0xFF1B5E20),
    const Color(0xFFE65100),
    const Color(0xFF4A148C),
    const Color(0xFF004D40),
    const Color(0xFFB71C1C),
    const Color(0xFF1A237E),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ LOAD DATA WITH user_roles.status CHECK
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

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('user_id, status, role_id')
          .inFilter('user_id', barberIds)
          .eq('role_id', 2);

      final Map<String, Map<String, dynamic>> profileMap = {};
      for (var profile in profilesResponse) {
        profileMap[profile['id']] = profile;
      }

      final Map<String, String> roleStatusMap = {};
      for (var role in userRolesResponse) {
        roleStatusMap[role['user_id']] = role['status'] ?? 'active';
      }

      Map<String, int> serviceCountMap = {};
      for (var sb in salonBarbersResponse) {
        final salonBarberId = sb['id'] as int;
        final count = await supabase
            .from('barber_services')
            .select('id')
            .eq('salon_barber_id', salonBarberId);

        serviceCountMap[sb['barber_id']] = count.length;
      }

      List<Map<String, dynamic>> combinedList = [];

      for (var sb in salonBarbersResponse) {
        final barberId = sb['barber_id'] as String;
        final profile = profileMap[barberId] ?? {};
        final roleStatus = roleStatusMap[barberId] ?? 'active';

        final isProfileActive = profile['is_active'] ?? true;
        final isProfileBlocked = profile['is_blocked'] ?? false;

        String actualStatus = sb['status'] ?? 'active';

        if (roleStatus != 'active') {
          actualStatus = roleStatus;
        }

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
  // ✅ ACTIVATE BARBER
  // ============================================================
  Future<void> _activateBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    try {
      await supabase
          .from('salon_barbers')
          .update({'status': 'active'})
          .eq('id', salonBarberId);

      await supabase
          .from('user_roles')
          .update({
            'status': 'active',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', barberId)
          .eq('role_id', 2);

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
  // ✅ DEACTIVATE BARBER
  // ============================================================
  Future<void> _deactivateBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final isDark = context.isDarkMode;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Deactivate Barber',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Temporarily deactivate $barberName? They can be reactivated later.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('salon_barbers')
            .update({'status': 'inactive'})
            .eq('id', salonBarberId);

        await supabase
            .from('user_roles')
            .update({
              'status': 'inactive',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', barberId)
            .eq('role_id', 2);

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
  // ✅ DELETE BARBER
  // ============================================================
  Future<void> _deleteBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final isDark = context.isDarkMode;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Barber',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permanently delete $barberName from this salon?',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              '• They will be hidden from all lists',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            Text(
              '• All their data (appointments, leaves) will be kept',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            Text(
              '• This action can be reversed by restoring',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('salon_barbers')
            .update({'status': 'deleted'})
            .eq('id', salonBarberId);

        await supabase
            .from('user_roles')
            .update({
              'status': 'deleted',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', barberId)
            .eq('role_id', 2);

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
  // ✅ RESTORE BARBER
  // ============================================================
  Future<void> _restoreBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final isDark = context.isDarkMode;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Restore Barber',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Restore $barberName to inactive status?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('salon_barbers')
            .update({'status': 'inactive'})
            .eq('id', salonBarberId);

        await supabase
            .from('user_roles')
            .update({
              'status': 'inactive',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', barberId)
            .eq('role_id', 2);

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
  // ✅ STATUS HELPER METHODS
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

  // ============================================================
  // ✅ BUILD METHOD - Edge-to-Edge + Responsive
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;
    final isTablet = context.isTablet;
    final double padding = isWeb ? 24.0 : (isTablet ? 20.0 : 16.0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Barber List',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        centerTitle: !isWeb,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list, color: Colors.white),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(Icons.person_add, color: Colors.white),
            onPressed: () =>
                context.push('/owner/add-barber?salonId=${widget.salonId}'),
            tooltip: 'Add Barber',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _barbers.isEmpty
            ? _buildEmptyState(isWeb, padding, isDark)
            : isWeb
            ? _buildDesktopView(padding, isDark)
            : RefreshIndicator(
                onRefresh: _loadData,
                color: AppTheme.primary,
                child: isTablet
                    ? _buildTabletView(padding, isDark)
                    : _buildMobileView(padding, isDark),
              ),
      ),
    );
  }

  Widget _buildEmptyState(bool isWeb, double padding, bool isDark) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: isWeb ? 80 : 64,
              color: isDark ? Colors.white30 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No barbers found',
              style: TextStyle(
                fontSize: isWeb ? 20 : 18,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add barbers to get started',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  context.push('/owner/add-barber?salonId=${widget.salonId}'),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Barber'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ DESKTOP VIEW - With Scrollbar
  // ============================================================
  Widget _buildDesktopView(double padding, bool isDark) {
    final activeCount = _barbers.where((b) => b['status'] == 'active').length;
    final inactiveCount = _barbers
        .where((b) => b['status'] == 'inactive')
        .length;
    final deletedCount = _barbers.where((b) => b['status'] == 'deleted').length;
    final blockedCount = _barbers.where((b) => b['status'] == 'blocked').length;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.right,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
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
                      isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'Active',
                      activeCount.toString(),
                      Icons.check_circle,
                      Colors.green,
                      isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'Inactive',
                      inactiveCount.toString(),
                      Icons.pause_circle,
                      Colors.orange,
                      isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'Deleted',
                      deletedCount.toString(),
                      Icons.delete,
                      Colors.red,
                      isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'Blocked',
                      blockedCount.toString(),
                      Icons.block,
                      Colors.purple,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Table Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(
                      alpha: isDark ? 0.2 : 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(
                        alpha: isDark ? 0.3 : 0.3,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Barber',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Contact',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Joined',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Services',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Status',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Actions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Table Rows
                ..._barbers.asMap().entries.map(
                  (entry) =>
                      _buildDesktopBarberRow(entry.value, entry.key, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ DESKTOP BARBER ROW
  // ============================================================
  Widget _buildDesktopBarberRow(
    Map<String, dynamic> barber,
    int index,
    bool isDark,
  ) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);
    final cardColor = isDark
        ? _cardColorsDark[index % _cardColorsDark.length]
        : _cardColorsLight[index % _cardColorsLight.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        barber['email'],
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
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
                    ? (isDark ? Colors.white70 : Colors.grey[400])
                    : (isDark ? Colors.white70 : Colors.grey[800]),
              ),
            ),
          ),

          // Joined date
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(barber['joined_at']),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
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
                    color: isDark ? Colors.blue[300] : Colors.blue[700],
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
                  icon: Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _editBarberServices(barber),
                  tooltip: 'Edit Services',
                ),
                IconButton(
                  icon: Icon(Icons.schedule, color: Colors.teal),
                  onPressed: () => _viewSchedule(barber),
                  tooltip: 'View Schedule',
                ),
                IconButton(
                  icon: Icon(Icons.beach_access, color: Colors.orange),
                  onPressed: () => _viewLeaves(barber),
                  tooltip: 'View Leaves',
                ),
                if (status == 'active')
                  IconButton(
                    icon: const Icon(Icons.pause_circle, color: Colors.orange),
                    onPressed: () => _deactivateBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
                    ),
                    tooltip: 'Deactivate',
                  ),
                if (status == 'inactive') ...[
                  IconButton(
                    icon: const Icon(Icons.play_circle, color: Colors.green),
                    onPressed: () => _activateBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
                    ),
                    tooltip: 'Activate',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
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
                      barber['id'],
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
                    child: Text(
                      'Contact Support',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.purple[300] : Colors.purple,
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

  // ============================================================
  // ✅ TABLET VIEW
  // ============================================================
  Widget _buildTabletView(double padding, bool isDark) {
    return GridView.builder(
      padding: EdgeInsets.all(padding),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        final barber = _barbers[index];
        return _buildMobileCard(barber, index, isDark);
      },
    );
  }

  // ============================================================
  // ✅ MOBILE VIEW
  // ============================================================
  Widget _buildMobileView(double padding, bool isDark) {
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        final barber = _barbers[index];
        return _buildMobileCard(barber, index, isDark);
      },
    );
  }

  // ============================================================
  // ✅ MOBILE CARD
  // ============================================================
  Widget _buildMobileCard(Map<String, dynamic> barber, int index, bool isDark) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);
    final cardColor = isDark
        ? _cardColorsDark[index % _cardColorsDark.length]
        : _cardColorsLight[index % _cardColorsLight.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          barber['email'],
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey[600],
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
                                  color: isDark
                                      ? Colors.blue[300]
                                      : Colors.blue[700],
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
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.5),
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
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              barber['phone'] ?? 'No phone',
                              style: TextStyle(
                                fontSize: 12,
                                color: barber['phone'] == 'No phone'
                                    ? (isDark
                                          ? Colors.white70
                                          : Colors.grey[400])
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.grey[800]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(barber['joined_at']),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.grey[600],
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
                    isDark: isDark,
                  ),
                  _buildMobileActionChip(
                    icon: Icons.schedule,
                    label: 'Schedule',
                    color: Colors.teal,
                    onTap: () => _viewSchedule(barber),
                    isDark: isDark,
                  ),
                  _buildMobileActionChip(
                    icon: Icons.beach_access,
                    label: 'Leaves',
                    color: Colors.orange,
                    onTap: () => _viewLeaves(barber),
                    isDark: isDark,
                  ),
                  if (status == 'active')
                    _buildMobileActionChip(
                      icon: Icons.pause_circle,
                      label: 'Deactivate',
                      color: Colors.orange,
                      onTap: () => _deactivateBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                      isDark: isDark,
                    ),
                  if (status == 'inactive') ...[
                    _buildMobileActionChip(
                      icon: Icons.play_circle,
                      label: 'Activate',
                      color: Colors.green,
                      onTap: () => _activateBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                      isDark: isDark,
                    ),
                    _buildMobileActionChip(
                      icon: Icons.delete,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: () => _deleteBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                      isDark: isDark,
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
                        barber['id'],
                      ),
                      isDark: isDark,
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
                      child: Text(
                        'Blocked',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.purple[300] : Colors.purple,
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
  }

  Widget _buildMobileActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
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
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? color.withValues(alpha: 0.3)
                : color.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : color.withValues(alpha: 0.1),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ FILTER DIALOG
  // ============================================================
  void _showFilterDialog() {
    final isDark = context.isDarkMode;
    String tempFilter = _selectedFilter!;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Filter Barbers',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
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
                  isDark: isDark,
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Active Only',
                  value: 'active',
                  currentFilter: tempFilter,
                  icon: Icons.check_circle,
                  color: Colors.green,
                  onTap: () => setDialogState(() => tempFilter = 'active'),
                  isDark: isDark,
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Inactive Only',
                  value: 'inactive',
                  currentFilter: tempFilter,
                  icon: Icons.pause_circle,
                  color: Colors.orange,
                  onTap: () => setDialogState(() => tempFilter = 'inactive'),
                  isDark: isDark,
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Deleted Only',
                  value: 'deleted',
                  currentFilter: tempFilter,
                  icon: Icons.delete,
                  color: Colors.red,
                  onTap: () => setDialogState(() => tempFilter = 'deleted'),
                  isDark: isDark,
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Blocked Only',
                  value: 'blocked',
                  currentFilter: tempFilter,
                  icon: Icons.block,
                  color: Colors.purple,
                  onTap: () => setDialogState(() => tempFilter = 'blocked'),
                  isDark: isDark,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
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
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
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
    required bool isDark,
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
                  color: currentFilter == value
                      ? color
                      : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
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
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
