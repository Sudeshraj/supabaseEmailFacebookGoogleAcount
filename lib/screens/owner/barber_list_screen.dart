import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  // ✅ Two separate lists: all barbers (for stats) + filtered (for display)
  List<Map<String, dynamic>> _allBarbers = [];
  List<Map<String, dynamic>> _filteredBarbers = [];

  final ScrollController _scrollController = ScrollController();

  // ✅ NEW: Dynamic barber role id (loaded once, cached)
  int? _barberRoleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadRoleIds();
      if (mounted) await _loadData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ NEW: Load role ids once (barber = ?)
  // ============================================================
  Future<void> _loadRoleIds() async {
    try {
      final roles = await supabase.from('roles').select('id, name');
      for (var r in roles) {
        if (r['name'] == 'barber') {
          _barberRoleId = r['id'] as int;
          break;
        }
      }
      // Safe fallback (matches seed order in migration)
      _barberRoleId ??= 2;
      debugPrint('✅ Barber role id: $_barberRoleId');
    } catch (e) {
      debugPrint('❌ Error loading role ids: $e');
      _barberRoleId = 2;
    }
  }

  // ============================================================
  // ✅ SMALL HELPERS (safe avatar / initial)
  // ============================================================
  String _initial(String? name) {
    final n = (name ?? '').trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  String? _avatarUrl(Map<String, dynamic> barber) {
    final a = barber['avatar'];
    if (a is String && a.trim().isNotEmpty) return a;
    return null;
  }

  // ============================================================
  // ✅ STATUS MAPPING (NEW: single source of truth)
  // ============================================================
  /// Map raw (salon_barbers.status, user_roles.status, profile flags)
  /// into a stable, filterable status.
  String _resolveStatus({
    required String salonBarberStatus,
    required String roleStatus,
    required bool isProfileActive,
    required bool isProfileBlocked,
  }) {
    // 1. Blocked wins (support-level)
    if (isProfileBlocked) return 'blocked';

    // 2. Role status: map unknown values → known filterable values
    //    scheduled_for_deletion → inactive (barber still visible, not bookable)
    String status = salonBarberStatus;
    switch (roleStatus) {
      case 'active':
        break;
      case 'inactive':
      case 'deleted':
        status = roleStatus;
        break;
      case 'scheduled_for_deletion':
        // Treat as inactive for UI/filter purposes
        if (status == 'active') status = 'inactive';
        break;
      default:
        // Unknown role status → keep salon status (defensive)
        break;
    }

    // 3. Profile inactive → inactive (only if currently 'active')
    if (!isProfileActive && status == 'active') {
      status = 'inactive';
    }

    return status;
  }

  // ============================================================
  // ✅ LOAD DATA
  // ============================================================
  Future<void> _loadData() async {
    // Guard: no salon id
    if (widget.salonId == null) {
      if (mounted) {
        setState(() {
          _allBarbers = [];
          _filteredBarbers = [];
          _isLoading = false;
        });
      }
      return;
    }

    final salonIdInt = int.tryParse(widget.salonId!);
    if (salonIdInt == null) {
      if (mounted) {
        setState(() {
          _allBarbers = [];
          _filteredBarbers = [];
          _isLoading = false;
        });
      }
      return;
    }

    // ✅ Ensure role id is loaded (safety net for refresh button)
    if (_barberRoleId == null) {
      await _loadRoleIds();
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final salonBarbersResponse = await supabase
          .from('salon_barbers')
          .select('id, barber_id, status, joined_at')
          .eq('salon_id', salonIdInt)
          .order('joined_at', ascending: false);

      if (salonBarbersResponse.isEmpty) {
        if (mounted) {
          setState(() {
            _allBarbers = [];
            _filteredBarbers = [];
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
          .eq('role_id', _barberRoleId!);

      final Map<String, Map<String, dynamic>> profileMap = {};
      for (var profile in profilesResponse) {
        profileMap[profile['id']] = profile;
      }

      final Map<String, String> roleStatusMap = {};
      for (var role in userRolesResponse) {
        roleStatusMap[role['user_id']] = role['status'] ?? 'active';
      }

      // ✅ Single query for all service counts (no N+1)
      final salonBarberIds = salonBarbersResponse
          .map((sb) => sb['id'] as int)
          .toList();

      final Map<int, int> countBySalonBarberId = {};
      if (salonBarberIds.isNotEmpty) {
        final allServices = await supabase
            .from('barber_services')
            .select('salon_barber_id')
            .inFilter('salon_barber_id', salonBarberIds);

        for (var svc in allServices) {
          final sbId = svc['salon_barber_id'] as int;
          countBySalonBarberId[sbId] = (countBySalonBarberId[sbId] ?? 0) + 1;
        }
      }

      final Map<String, int> serviceCountMap = {};
      for (var sb in salonBarbersResponse) {
        serviceCountMap[sb['barber_id']] =
            countBySalonBarberId[sb['id']] ?? 0;
      }

      final List<Map<String, dynamic>> combinedList = [];

      for (var sb in salonBarbersResponse) {
        final barberId = sb['barber_id'] as String;
        final profile = profileMap[barberId] ?? {};
        final roleStatus = roleStatusMap[barberId] ?? 'active';
        final isProfileActive = profile['is_active'] ?? true;
        final isProfileBlocked = profile['is_blocked'] ?? false;

        // ✅ Use centralized status resolver
        final actualStatus = _resolveStatus(
          salonBarberStatus: sb['status'] ?? 'active',
          roleStatus: roleStatus,
          isProfileActive: isProfileActive,
          isProfileBlocked: isProfileBlocked,
        );

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

      // ✅ Apply filter
      final filteredList = _applyFilterToList(combinedList, _selectedFilter);

      if (mounted) {
        setState(() {
          _allBarbers = combinedList; // ✅ All (for stats)
          _filteredBarbers = filteredList; // ✅ Filtered (for display)
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
  // ✅ FILTER HELPER (pure function)
  // ============================================================
  List<Map<String, dynamic>> _applyFilterToList(
    List<Map<String, dynamic>> source,
    String? filter,
  ) {
    if (filter == 'all' || filter == null) return source;
    return source.where((b) => b['status'] == filter).toList();
  }

  // ============================================================
  // ✅ APPLY FILTER (without reloading from server)
  // ============================================================
  void _applyFilter() {
    setState(() {
      _filteredBarbers = _applyFilterToList(_allBarbers, _selectedFilter);
    });
  }

  // ============================================================
  // ✅ LOCAL UPDATE HELPER (avoid full reload)
  // ============================================================
  void _updateLocalBarberStatus(int salonBarberId, String newStatus) {
    if (!mounted) return;

    setState(() {
      final idx = _allBarbers.indexWhere(
        (b) => b['salon_barber_id'] == salonBarberId,
      );
      if (idx != -1) {
        _allBarbers[idx]['status'] = newStatus;
      }
      // ✅ Apply filter in same setState (no double rebuild)
      _filteredBarbers = _applyFilterToList(_allBarbers, _selectedFilter);
    });
  }

  // ============================================================
  // ✅ BARBER ACTIONS
  // ============================================================

  /// ✅ Activate barber (blocked check: client-side fast, server-side safe)
  Future<void> _activateBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    try {
      // ✅ Fast client-side check (uses cached data, no round trip)
      final cached = _allBarbers.firstWhere(
        (b) => b['salon_barber_id'] == salonBarberId,
        orElse: () => <String, dynamic>{},
      );
      if (cached['status'] == 'blocked') {
        if (mounted) {
          context.showErrorSnackBar(
            '⚠️ Cannot activate $barberName — account is blocked by support.',
          );
        }
        return;
      }

      // ✅ Server-side safety check (in case block happened mid-session)
      final profileCheck = await supabase
          .from('profiles')
          .select('is_blocked')
          .eq('id', barberId)
          .maybeSingle();

      if (profileCheck != null && profileCheck['is_blocked'] == true) {
        if (mounted) {
          context.showErrorSnackBar(
            '⚠️ Cannot activate $barberName — account is blocked by support.',
          );
        }
        return;
      }

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
          .eq('role_id', _barberRoleId!);

      _updateLocalBarberStatus(salonBarberId, 'active');
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
            .eq('role_id', _barberRoleId!);

        _updateLocalBarberStatus(salonBarberId, 'inactive');
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
            .eq('role_id', _barberRoleId!);

        _updateLocalBarberStatus(salonBarberId, 'deleted');
        if (mounted) context.showErrorSnackBar('🗑️ $barberName deleted');
      } catch (e) {
        debugPrint('❌ Error: $e');
        if (mounted) context.showErrorSnackBar('Error: $e');
      }
    }
  }

  /// ✅ Restore barber to inactive (blocked check first)
  Future<void> _restoreBarber(
    int salonBarberId,
    String barberName,
    String barberId,
  ) async {
    try {
      // ✅ Fast client-side check
      final cached = _allBarbers.firstWhere(
        (b) => b['salon_barber_id'] == salonBarberId,
        orElse: () => <String, dynamic>{},
      );
      if (cached['status'] == 'blocked') {
        if (mounted) {
          context.showErrorSnackBar(
            '⚠️ Cannot restore $barberName — account is blocked by support.',
          );
        }
        return;
      }

      // ✅ Server-side safety check
      final profileCheck = await supabase
          .from('profiles')
          .select('is_blocked')
          .eq('id', barberId)
          .maybeSingle();

      if (profileCheck != null && profileCheck['is_blocked'] == true) {
        if (mounted) {
          context.showErrorSnackBar(
            '⚠️ Cannot restore $barberName — account is blocked by support.',
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('❌ Error checking blocked status: $e');
    }

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
            .eq('role_id', _barberRoleId!);

        _updateLocalBarberStatus(salonBarberId, 'inactive');
        if (mounted) context.showSnackBar('🔄 $barberName restored');
      } catch (e) {
        debugPrint('❌ Error: $e');
        if (mounted) context.showErrorSnackBar('Error: $e');
      }
    }
  }

  // ============================================================
  // ✅ CONFIRM DIALOG
  // ============================================================
  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        backgroundColor: dialogContext.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: dialogContext.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: dialogContext.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: dialogContext.secondaryTextColor),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
        // ✅ Safe fallback (shouldn't hit anymore with _resolveStatus)
        return status
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
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
  // ✅ BUILD
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
            : _allBarbers.isEmpty
                ? _buildEmptyState()
                : isWeb
                    ? _buildDesktopView()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppTheme.primary,
                        child: isTablet
                            ? _buildTabletView()
                            : _buildMobileView(),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
  // ✅ DESKTOP VIEW
  // ============================================================
  Widget _buildDesktopView() {
    final activeCount = _allBarbers.where((b) => b['status'] == 'active').length;
    final inactiveCount =
        _allBarbers.where((b) => b['status'] == 'inactive').length;
    final deletedCount =
        _allBarbers.where((b) => b['status'] == 'deleted').length;
    final blockedCount =
        _allBarbers.where((b) => b['status'] == 'blocked').length;

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
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Barbers',
                        _allBarbers.length.toString(),
                        Icons.people,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Active',
                        activeCount.toString(),
                        Icons.check_circle,
                        AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Inactive',
                        inactiveCount.toString(),
                        Icons.pause_circle,
                        AppTheme.warning,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Deleted',
                        deletedCount.toString(),
                        Icons.delete,
                        AppTheme.error,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Blocked',
                        blockedCount.toString(),
                        Icons.block,
                        Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
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
                        '${_filteredBarbers.length}',
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
                if (_filteredBarbers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.filter_alt_off,
                            size: 48,
                            color: context.secondaryTextColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No barbers match this filter',
                            style: TextStyle(
                              fontSize: 14,
                              color: context.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _selectedFilter = 'all');
                              _applyFilter();
                            },
                            icon: const Icon(Icons.clear, size: 18),
                            label: const Text('Clear Filter'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: BorderSide(color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._filteredBarbers.asMap().entries.map(
                        (entry) =>
                            _buildDesktopBarberRow(entry.value, entry.key),
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
  Widget _buildDesktopBarberRow(Map<String, dynamic> barber, int index) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);
    final avatarUrl = _avatarUrl(barber);

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
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? Text(
                              _initial(barber['name']),
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
          Expanded(
            flex: 3,
            child: Text(
              barber['phone'] ?? 'No phone',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: barber['phone'] == 'No phone'
                    ? context.secondaryTextColor
                    : context.textColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(barber['joined_at']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.textColor),
            ),
          ),
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
                    Flexible(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
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
    return IconButton(
      icon: Icon(icon, size: 20),
      color: color,
      onPressed: onTap,
      tooltip: tooltip,
      splashRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  // ============================================================
  // ✅ TABLET VIEW
  // ============================================================
  Widget _buildTabletView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double pagePadding = 20;
        const double spacing = 16;
        const double maxCardWidth = 400;

        final available = (constraints.maxWidth - pagePadding * 2).clamp(
          1.0,
          double.infinity,
        );
        final columns = (available / maxCardWidth).ceil().clamp(1, 4).toInt();
        final cardWidth = (available - spacing * (columns - 1)) / columns;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(pagePadding),
          child: _filteredBarbers.isEmpty
              ? _buildEmptyFilterState()
              : Wrap(
                  spacing: spacing,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: _filteredBarbers
                      .map(
                        (barber) => SizedBox(
                          width: cardWidth,
                          child: _buildBarberCard(barber),
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }

  // ============================================================
  // ✅ MOBILE VIEW
  // ============================================================
  Widget _buildMobileView() {
    if (_filteredBarbers.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: _buildEmptyFilterState(),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _filteredBarbers.length,
      itemBuilder: (context, index) {
        return _buildBarberCard(_filteredBarbers[index]);
      },
    );
  }

  Widget _buildEmptyFilterState() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off,
              size: 64,
              color: context.secondaryTextColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No barbers match this filter',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different filter or clear it',
              style: TextStyle(
                fontSize: 13,
                color: context.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedFilter = 'all';
                });
                _applyFilter();
              },
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Clear Filter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ BARBER CARD
  // ============================================================
  Widget _buildBarberCard(Map<String, dynamic> barber) {
    final status = barber['status'] ?? 'active';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final statusIcon = _getStatusIcon(status);
    final avatarUrl = _avatarUrl(barber);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.dividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: statusColor),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: statusColor.withValues(
                                alpha: 0.15,
                              ),
                              backgroundImage: avatarUrl != null
                                  ? CachedNetworkImageProvider(avatarUrl)
                                  : null,
                              child: avatarUrl == null
                                  ? Text(
                                      _initial(barber['name']),
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _buildStatusChip(
                                    statusColor,
                                    statusIcon,
                                    statusText,
                                  ),
                                  _buildServiceChip(barber['service_count']),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.dividerColor),
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
                          mainAxisSize: MainAxisSize.min,
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
                  Divider(height: 1, color: context.dividerColor),
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(Color color, IconData icon, String text) {
    final isDark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
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
    final isDark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$count services',
        style: TextStyle(
          color: isDark ? Colors.blue[300] : Colors.blue[700],
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
    final isDark = context.isDarkMode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.3 : 0.2),
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
    return Container(
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
    );
  }

  // ============================================================
  // ✅ FILTER DIALOG
  // ============================================================
  void _showFilterDialog() {
    String tempFilter = _selectedFilter ?? 'all';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setDialogState) {
          return AlertDialog(
            scrollable: true,
            backgroundColor: dialogContext.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.filter_list, color: AppTheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Filter Barbers',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dialogContext.textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterOption(
                  dialogContext: dialogContext,
                  title: 'All Barbers',
                  value: 'all',
                  currentFilter: tempFilter,
                  icon: Icons.people,
                  color: Colors.blue,
                  onTap: () => setDialogState(() => tempFilter = 'all'),
                ),
                _buildFilterOption(
                  dialogContext: dialogContext,
                  title: 'Active Only',
                  value: 'active',
                  currentFilter: tempFilter,
                  icon: Icons.check_circle,
                  color: AppTheme.success,
                  onTap: () => setDialogState(() => tempFilter = 'active'),
                ),
                _buildFilterOption(
                  dialogContext: dialogContext,
                  title: 'Inactive Only',
                  value: 'inactive',
                  currentFilter: tempFilter,
                  icon: Icons.pause_circle,
                  color: AppTheme.warning,
                  onTap: () => setDialogState(() => tempFilter = 'inactive'),
                ),
                _buildFilterOption(
                  dialogContext: dialogContext,
                  title: 'Deleted Only',
                  value: 'deleted',
                  currentFilter: tempFilter,
                  icon: Icons.delete,
                  color: AppTheme.error,
                  onTap: () => setDialogState(() => tempFilter = 'deleted'),
                ),
                _buildFilterOption(
                  dialogContext: dialogContext,
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
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: dialogContext.secondaryTextColor),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // ✅ Single setState: update filter + apply (no double rebuild)
                  setState(() {
                    _selectedFilter = tempFilter;
                    _filteredBarbers =
                        _applyFilterToList(_allBarbers, tempFilter);
                  });
                  Navigator.pop(dialogContext);
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
    required BuildContext dialogContext,
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
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: dialogContext.textColor,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: color, size: 20)
              else
                Icon(
                  Icons.circle_outlined,
                  color: dialogContext.secondaryTextColor,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}