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

  final ScrollController _scrollController = ScrollController();

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
  // ✅ LOAD DATA
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
          .select(
            'id, full_name, email, phone, avatar_url, created_at, is_active, is_blocked',
          )
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
        if (roleStatus != 'active') actualStatus = roleStatus;
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
        });
      }

      if (mounted) {
        setState(() {
          _barbers = combinedList;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading barbers: $e');
      if (mounted) context.showErrorSnackBar('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ✅ BARBER ACTIONS
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
      if (mounted) context.showSuccessSnackBar('✅ $barberName activated');
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) context.showErrorSnackBar('Error: $e');
    }
  }

  Future<void> _deactivateBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final confirm = await _showConfirmDialog(
      title: 'Deactivate Barber',
      message: 'Temporarily deactivate $barberName?',
      confirmText: 'Deactivate',
      confirmColor: AppTheme.warning,
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
        if (mounted) context.showWarningSnackBar('⏸️ $barberName deactivated');
      } catch (e) {
        debugPrint('❌ Error: $e');
        if (mounted) context.showErrorSnackBar('Error: $e');
      }
    }
  }

  Future<void> _deleteBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final confirm = await _showConfirmDialog(
      title: 'Delete Barber',
      message:
          'Permanently delete $barberName from this salon?\n\n• They will be hidden from all lists\n• All their data will be kept\n• This action can be reversed',
      confirmText: 'Delete',
      confirmColor: AppTheme.error,
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
        if (mounted) context.showErrorSnackBar('🗑️ $barberName deleted');
      } catch (e) {
        debugPrint('❌ Error: $e');
        if (mounted) context.showErrorSnackBar('Error: $e');
      }
    }
  }

  Future<void> _restoreBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    final confirm = await _showConfirmDialog(
      title: 'Restore Barber',
      message: 'Restore $barberName to inactive status?',
      confirmText: 'Restore',
      confirmColor: AppTheme.info,
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
        if (mounted) context.showSnackBar('🔄 $barberName restored');
      } catch (e) {
        debugPrint('❌ Error: $e');
        if (mounted) context.showErrorSnackBar('Error: $e');
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: context.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.secondaryTextColor),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
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
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  // ============================================================
  // ✅ STATUS HELPERS
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
        return AppTheme.success;
      case 'inactive':
        return AppTheme.warning;
      case 'deleted':
        return AppTheme.error;
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
  // ✅ BUILD METHOD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isWeb = context.isWeb;
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Barber List',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isWeb ? 22 : 20,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        centerTitle: !isWeb,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
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
            ? _buildEmptyState()
            : isWeb
            ? _buildDesktopView()
            : RefreshIndicator(
                onRefresh: _loadData,
                color: AppTheme.primary,
                child: isTablet ? _buildTabletView() : _buildMobileView(),
              ),
      ),
    );
  }

  // ============================================================
  // ✅ EMPTY STATE
  // ============================================================
  Widget _buildEmptyState() {
    final isWeb = context.isWeb;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: isWeb ? 80 : 64,
                color: AppTheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Barbers Found',
              style: TextStyle(
                fontSize: isWeb ? 22 : 20,
                fontWeight: FontWeight.bold,
                color: context.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add barbers to get started',
              style: TextStyle(
                fontSize: 14,
                color: context.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  context.push('/owner/add-barber?salonId=${widget.salonId}'),
              icon: const Icon(Icons.person_add),
              label: const Text('Add First Barber'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ DESKTOP VIEW - With Scrollbar + Proper Spacing
  // ============================================================
  Widget _buildDesktopView() {
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Stats Cards
                Row(
                  children: [
                    _buildStatCard(
                      'Total Barbers',
                      _barbers.length.toString(),
                      Icons.people,
                      Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      'Active',
                      activeCount.toString(),
                      Icons.check_circle,
                      AppTheme.success,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      'Inactive',
                      inactiveCount.toString(),
                      Icons.pause_circle,
                      AppTheme.warning,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      'Deleted',
                      deletedCount.toString(),
                      Icons.delete,
                      AppTheme.error,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      'Blocked',
                      blockedCount.toString(),
                      Icons.block,
                      Colors.purple,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ✅ Section Title
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'All Barbers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_barbers.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ✅ Table Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'BARBER',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: context.textColor,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'CONTACT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: context.textColor,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'JOINED',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: context.textColor,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'SERVICES',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: context.textColor,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'STATUS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: context.textColor,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'ACTIONS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                            color: context.textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ✅ Table Rows
                ..._barbers.asMap().entries.map(
                  (entry) => _buildDesktopBarberRow(entry.value, entry.key),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ DESKTOP BARBER ROW - Proper Design
  // ============================================================
  Widget _buildDesktopBarberRow(Map<String, dynamic> barber, int index) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ✅ Barber info
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: statusColor.withValues(alpha: 0.15),
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
                            border: Border.all(
                              color: context.cardColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            statusIcon,
                            color: Colors.white,
                            size: 10,
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
                          fontSize: 15,
                          color: context.textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        barber['email'],
                        style: TextStyle(
                          fontSize: 12,
                          color: context.secondaryTextColor,
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

          // ✅ Contact
          Expanded(
            flex: 3,
            child: Text(
              barber['phone'] ?? 'No phone',
              style: TextStyle(
                fontSize: 13,
                color: barber['phone'] == 'No phone'
                    ? context.secondaryTextColor
                    : context.textColor,
              ),
            ),
          ),

          // ✅ Joined date
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(barber['joined_at']),
              style: TextStyle(
                fontSize: 13,
                color: context.textColor,
              ),
            ),
          ),

          // ✅ Service count
          Expanded(
            flex: 2,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${barber['service_count']}',
                  style: TextStyle(
                    color: context.isDarkMode
                        ? Colors.blue[300]
                        : Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),

          // ✅ Status
          Expanded(
            flex: 2,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ✅ Actions
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDesktopActionButton(
                  icon: Icons.edit,
                  color: Colors.blue,
                  tooltip: 'Services',
                  onTap: () => _editBarberServices(barber),
                ),
                _buildDesktopActionButton(
                  icon: Icons.schedule,
                  color: Colors.teal,
                  tooltip: 'Schedule',
                  onTap: () => _viewSchedule(barber),
                ),
                _buildDesktopActionButton(
                  icon: Icons.beach_access,
                  color: Colors.orange,
                  tooltip: 'Leaves',
                  onTap: () => _viewLeaves(barber),
                ),
                if (status == 'active')
                  _buildDesktopActionButton(
                    icon: Icons.pause_circle,
                    color: AppTheme.warning,
                    tooltip: 'Deactivate',
                    onTap: () => _deactivateBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
                    ),
                  ),
                if (status == 'inactive') ...[
                  _buildDesktopActionButton(
                    icon: Icons.play_circle,
                    color: AppTheme.success,
                    tooltip: 'Activate',
                    onTap: () => _activateBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
                    ),
                  ),
                  _buildDesktopActionButton(
                    icon: Icons.delete,
                    color: AppTheme.error,
                    tooltip: 'Delete',
                    onTap: () => _deleteBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
                    ),
                  ),
                ],
                if (status == 'deleted')
                  _buildDesktopActionButton(
                    icon: Icons.restore,
                    color: Colors.blue,
                    tooltip: 'Restore',
                    onTap: () => _restoreBarber(
                      barber['salon_barber_id'],
                      barber['name'],
                      barber['id'],
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
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.purple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Contact Support',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.isDarkMode
                            ? Colors.purple[300]
                            : Colors.purple,
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

  Widget _buildDesktopActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        onPressed: onTap,
        tooltip: tooltip,
        splashRadius: 20,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  // ============================================================
  // ✅ TABLET VIEW
  // ============================================================
  Widget _buildTabletView() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        return _buildBarberCard(_barbers[index]);
      },
    );
  }

  // ============================================================
  // ✅ MOBILE VIEW
  // ============================================================
  Widget _buildMobileView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        return _buildBarberCard(_barbers[index]);
      },
    );
  }

  // ============================================================
  // ✅ BARBER CARD - Proper Design
  // ============================================================
  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.dividerColor),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: statusColor, width: 4)),
        ),
        child: Column(
          children: [
            // ✅ Header - Avatar + Name + Status
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        backgroundImage: barber['avatar'] != null
                            ? NetworkImage(barber['avatar'])
                            : null,
                        child: barber['avatar'] == null
                            ? Text(
                                barber['name'][0].toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                      if (status != 'active')
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.cardColor,
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          barber['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: context.textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          barber['email'],
                          style: TextStyle(
                            fontSize: 13,
                            color: context.secondaryTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildStatusChip(
                              statusColor,
                              statusIcon,
                              statusText,
                            ),
                            const SizedBox(width: 8),
                            _buildServiceChip(barber['service_count']),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ✅ Divider
            Divider(height: 1, color: context.dividerColor),

            // ✅ Info Row - Phone + Joined
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.phone,
                          size: 14,
                          color: context.secondaryTextColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            barber['phone'] ?? 'No phone',
                            style: TextStyle(
                              fontSize: 12,
                              color: barber['phone'] == 'No phone'
                                  ? context.secondaryTextColor
                                  : context.textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: context.dividerColor,
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 12,
                        color: context.secondaryTextColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(barber['joined_at']),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ✅ Divider
            Divider(height: 1, color: context.dividerColor),

            // ✅ Action Buttons - Grid Layout
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildActionChip(
                    icon: Icons.edit,
                    label: 'Services',
                    color: Colors.blue,
                    onTap: () => _editBarberServices(barber),
                  ),
                  _buildActionChip(
                    icon: Icons.schedule,
                    label: 'Schedule',
                    color: Colors.teal,
                    onTap: () => _viewSchedule(barber),
                  ),
                  _buildActionChip(
                    icon: Icons.beach_access,
                    label: 'Leaves',
                    color: Colors.orange,
                    onTap: () => _viewLeaves(barber),
                  ),
                  if (status == 'active')
                    _buildActionChip(
                      icon: Icons.pause_circle,
                      label: 'Deactivate',
                      color: AppTheme.warning,
                      onTap: () => _deactivateBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                    ),
                  if (status == 'inactive') ...[
                    _buildActionChip(
                      icon: Icons.play_circle,
                      label: 'Activate',
                      color: AppTheme.success,
                      onTap: () => _activateBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                    ),
                    _buildActionChip(
                      icon: Icons.delete,
                      label: 'Delete',
                      color: AppTheme.error,
                      onTap: () => _deleteBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                    ),
                  ],
                  if (status == 'deleted')
                    _buildActionChip(
                      icon: Icons.restore,
                      label: 'Restore',
                      color: Colors.blue,
                      onTap: () => _restoreBarber(
                        barber['salon_barber_id'],
                        barber['name'],
                        barber['id'],
                      ),
                    ),
                  if (status == 'blocked')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block,
                            size: 14,
                            color: context.isDarkMode
                                ? Colors.purple[300]
                                : Colors.purple,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Blocked',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.isDarkMode
                                  ? Colors.purple[300]
                                  : Colors.purple,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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

  Widget _buildStatusChip(Color color, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$count services',
        style: TextStyle(
          color: context.isDarkMode ? Colors.blue[300] : Colors.blue[700],
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: context.isDarkMode ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: context.isDarkMode ? 0.3 : 0.2),
            ),
          ),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.secondaryTextColor,
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
    );
  }

  // ============================================================
  // ✅ FILTER DIALOG
  // ============================================================
  void _showFilterDialog() {
    String tempFilter = _selectedFilter!;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: context.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.filter_list, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Filter Barbers',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
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
                ),
                _buildFilterOption(
                  title: 'Active Only',
                  value: 'active',
                  currentFilter: tempFilter,
                  icon: Icons.check_circle,
                  color: AppTheme.success,
                  onTap: () => setDialogState(() => tempFilter = 'active'),
                ),
                _buildFilterOption(
                  title: 'Inactive Only',
                  value: 'inactive',
                  currentFilter: tempFilter,
                  icon: Icons.pause_circle,
                  color: AppTheme.warning,
                  onTap: () => setDialogState(() => tempFilter = 'inactive'),
                ),
                _buildFilterOption(
                  title: 'Deleted Only',
                  value: 'deleted',
                  currentFilter: tempFilter,
                  icon: Icons.delete,
                  color: AppTheme.error,
                  onTap: () => setDialogState(() => tempFilter = 'deleted'),
                ),
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
                child: Text(
                  'Cancel',
                  style: TextStyle(color: context.secondaryTextColor),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    final isSelected = currentFilter == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: context.textColor,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: color, size: 20)
              else
                Icon(
                  Icons.circle_outlined,
                  color: context.secondaryTextColor,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}