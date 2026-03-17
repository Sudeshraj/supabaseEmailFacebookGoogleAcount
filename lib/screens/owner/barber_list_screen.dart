// screens/owner/barber_list_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart' show kIsWeb;

class BarberListScreen extends StatefulWidget {
  final String? salonId;

  const BarberListScreen({super.key, this.salonId});

  @override
  State<BarberListScreen> createState() => _BarberListScreenState();
}

class _BarberListScreenState extends State<BarberListScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _barbers = [];
  String? _selectedFilter = 'all'; // all, active, inactive, deleted

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Step 1: Get barber data from salon_barbers with filters
      var query = supabase
          .from('salon_barbers')
          .select('id, barber_id, status, joined_at')
          .eq('salon_id', int.parse(widget.salonId!));

      // Apply filter
      if (_selectedFilter == 'active') {
        query = query.eq('status', 'active');
      } else if (_selectedFilter == 'inactive') {
        query = query.eq('status', 'inactive');
      } else if (_selectedFilter == 'deleted') {
        query = query.eq('status', 'deleted');
      }

      final salonBarbersResponse = await query.order('joined_at', ascending: false);

      if (salonBarbersResponse.isEmpty) {
        setState(() {
          _barbers = [];
          _isLoading = false;
        });
        return;
      }

      // Step 2: Get all barber IDs
      final barberIds = salonBarbersResponse.map((sb) => sb['barber_id'] as String).toList();

      // Step 3: Get profiles for these barbers
      List<Map<String, dynamic>> allProfiles = [];
      for (String barberId in barberIds) {
        final profile = await supabase
            .from('profiles')
            .select('id, full_name, email, phone, avatar_url, created_at')
            .eq('id', barberId)
            .maybeSingle();

        if (profile != null) {
          allProfiles.add(profile);
        }
      }

      // Step 4: Create a map for quick lookup
      final Map<String, Map<String, dynamic>> profileMap = {};
      for (var profile in allProfiles) {
        profileMap[profile['id']] = profile;
      }

      // Step 5: Get service counts for each barber
      Map<String, int> serviceCountMap = {};
      for (String barberId in barberIds) {
        // First get salon_barber_id
        final salonBarber = await supabase
            .from('salon_barbers')
            .select('id')
            .eq('barber_id', barberId)
            .eq('salon_id', int.parse(widget.salonId!))
            .maybeSingle();

        if (salonBarber != null) {
          final count = await supabase
              .from('barber_services')
              .select('id')
              .eq('salon_barber_id', salonBarber['id'])
              .eq('is_active', true);

          serviceCountMap[barberId] = count.length;
        } else {
          serviceCountMap[barberId] = 0;
        }
      }

      // Step 6: Combine all data
      List<Map<String, dynamic>> combinedList = [];

      for (var sb in salonBarbersResponse) {
        final barberId = sb['barber_id'] as String;
        final profile = profileMap[barberId] ?? {};

        combinedList.add({
          'id': barberId,
          'salon_barber_id': sb['id'],
          'status': sb['status'] ?? 'active',
          'joined_at': sb['joined_at'],
          'name': profile['full_name'] ?? 'Unknown',
          'email': profile['email'] ?? '',
          'phone': profile['phone'] ?? 'No phone',
          'avatar': profile['avatar_url'],
          'created_at': profile['created_at'],
          'service_count': serviceCountMap[barberId] ?? 0,
        });
      }

      setState(() {
        _barbers = combinedList;
      });

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

  // ==================== ACTIONS ====================

  Future<void> _activateBarber(int salonBarberId, String barberName) async {
    try {
      await supabase
          .from('salon_barbers')
          .update({'status': 'active'})
          .eq('id', salonBarberId);

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
    }
  }

  Future<void> _deactivateBarber(int salonBarberId, String barberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deactivate Barber'),
        content: Text('Temporarily deactivate $barberName? They can be reactivated later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
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
      }
    }
  }

  Future<void> _deleteBarber(int salonBarberId, String barberName) async {
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
      }
    }
  }

  Future<void> _restoreBarber(int salonBarberId, String barberName) async {
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
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
      }
    }
  }

  void _editBarberServices(Map<String, dynamic> barber) {
    context.push(
      '/owner/edit-barber-services?barberId=${barber['id']}&salonId=${widget.salonId}',
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

  String _getStatusText(String status) {
    switch (status) {
      case 'active': return 'Active';
      case 'inactive': return 'Inactive';
      case 'deleted': return 'Deleted';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active': return Colors.green;
      case 'inactive': return Colors.orange;
      case 'deleted': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active': return Icons.check_circle;
      case 'inactive': return Icons.pause_circle;
      case 'deleted': return Icons.delete;
      default: return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800 || kIsWeb;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barber List'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
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
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: isWeb ? 80 : 64,
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
                      onPressed: () => context.push(
                        '/owner/add-barber?salonId=${widget.salonId}',
                      ),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add Barber'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B8B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : isWeb
          ? _buildWebView(padding)
          : _buildMobileView(padding),
    );
  }

  Widget _buildWebView(double padding) {
    final activeCount = _barbers.where((b) => b['status'] == 'active').length;
    final inactiveCount = _barbers.where((b) => b['status'] == 'inactive').length;
    final deletedCount = _barbers.where((b) => b['status'] == 'deleted').length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          // Stats Cards
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
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
              ],
            ),
          ),

          // Table Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF6B8B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Expanded(flex: 3, child: Text('Barber', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Contact', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Joined', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 1, child: Text('Services', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 3, child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Table Rows
          ..._barbers.map((barber) {
            final status = barber['status'] ?? 'active';
            final statusColor = _getStatusColor(status);
            final statusText = _getStatusText(status);
            final statusIcon = _getStatusIcon(status);

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
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
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
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
                        color: barber['phone'] == 'No phone' ? Colors.grey[400] : Colors.grey[800],
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
                            Icon(
                              statusIcon,
                              color: statusColor,
                              size: 14,
                            ),
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
                        // Edit Services
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _editBarberServices(barber),
                          tooltip: 'Edit Services',
                        ),

                        // Schedule
                        IconButton(
                          icon: const Icon(Icons.schedule, color: Colors.teal),
                          onPressed: () => context.push('/owner/barber-schedule?barberId=${barber['id']}'),
                          tooltip: 'View Schedule',
                        ),

                        // Leaves
                        IconButton(
                          icon: const Icon(Icons.beach_access, color: Colors.orange),
                          onPressed: () => context.push('/owner/barber-leaves?barberId=${barber['id']}'),
                          tooltip: 'View Leaves',
                        ),

                        // Status actions
                        if (status == 'active')
                          IconButton(
                            icon: const Icon(Icons.pause_circle, color: Colors.orange),
                            onPressed: () => _deactivateBarber(barber['salon_barber_id'], barber['name']),
                            tooltip: 'Deactivate',
                          ),
                        if (status == 'inactive') ...[
                          IconButton(
                            icon: const Icon(Icons.play_circle, color: Colors.green),
                            onPressed: () => _activateBarber(barber['salon_barber_id'], barber['name']),
                            tooltip: 'Activate',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteBarber(barber['salon_barber_id'], barber['name']),
                            tooltip: 'Delete',
                          ),
                        ],
                        if (status == 'deleted')
                          IconButton(
                            icon: const Icon(Icons.restore, color: Colors.blue),
                            onPressed: () => _restoreBarber(barber['salon_barber_id'], barber['name']),
                            tooltip: 'Restore',
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
      itemCount: _barbers.length,
      itemBuilder: (context, index) {
        final barber = _barbers[index];
        final status = barber['status'] ?? 'active';
        final statusColor = _getStatusColor(status);
        final statusText = _getStatusText(status);
        final statusIcon = _getStatusIcon(status);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: statusColor,
                  width: 4,
                ),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with avatar and name
                  Row(
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              barber['email'],
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                      const SizedBox(width: 2),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

                  const SizedBox(height: 12),

                  // Contact and joined info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  barber['phone'] ?? 'No phone',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: barber['phone'] == 'No phone' ? Colors.grey[400] : Colors.grey[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 20, color: Colors.grey[300]),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(barber['joined_at']),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Action buttons
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildActionChip(
                          icon: Icons.edit,
                          label: 'Edit Services',
                          color: Colors.blue,
                          onTap: () => _editBarberServices(barber),
                        ),
                        const SizedBox(width: 8),
                        _buildActionChip(
                          icon: Icons.schedule,
                          label: 'Schedule',
                          color: Colors.teal,
                          onTap: () => context.push('/owner/barber-schedule?barberId=${barber['id']}'),
                        ),
                        const SizedBox(width: 8),
                        _buildActionChip(
                          icon: Icons.beach_access,
                          label: 'Leaves',
                          color: Colors.orange,
                          onTap: () => context.push('/owner/barber-leaves?barberId=${barber['id']}'),
                        ),
                        if (status == 'active') ...[
                          const SizedBox(width: 8),
                          _buildActionChip(
                            icon: Icons.pause_circle,
                            label: 'Deactivate',
                            color: Colors.orange,
                            onTap: () => _deactivateBarber(barber['salon_barber_id'], barber['name']),
                          ),
                        ],
                        if (status == 'inactive') ...[
                          const SizedBox(width: 8),
                          _buildActionChip(
                            icon: Icons.play_circle,
                            label: 'Activate',
                            color: Colors.green,
                            onTap: () => _activateBarber(barber['salon_barber_id'], barber['name']),
                          ),
                          const SizedBox(width: 8),
                          _buildActionChip(
                            icon: Icons.delete,
                            label: 'Delete',
                            color: Colors.red,
                            onTap: () => _deleteBarber(barber['salon_barber_id'], barber['name']),
                          ),
                        ],
                        if (status == 'deleted') ...[
                          const SizedBox(width: 8),
                          _buildActionChip(
                            icon: Icons.restore,
                            label: 'Restore',
                            color: Colors.blue,
                            onTap: () => _restoreBarber(barber['salon_barber_id'], barber['name']),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, color: color, size: 16),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, [Color? color]) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: color ?? const Color(0xFFFF6B8B)),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== FILTER DIALOG ====================
  void _showFilterDialog() {
    String tempFilter = _selectedFilter!;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  onTap: () => setState(() => tempFilter = 'all'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Active Only',
                  value: 'active',
                  currentFilter: tempFilter,
                  icon: Icons.check_circle,
                  color: Colors.green,
                  onTap: () => setState(() => tempFilter = 'active'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Inactive Only',
                  value: 'inactive',
                  currentFilter: tempFilter,
                  icon: Icons.pause_circle,
                  color: Colors.orange,
                  onTap: () => setState(() => tempFilter = 'inactive'),
                ),
                const Divider(),
                _buildFilterOption(
                  title: 'Deleted Only',
                  value: 'deleted',
                  currentFilter: tempFilter,
                  icon: Icons.delete,
                  color: Colors.red,
                  onTap: () => setState(() => tempFilter = 'deleted'),
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
                  this.setState(() {
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
                  ? Center(
                      child: Icon(
                        Icons.circle,
                        color: color,
                        size: 12,
                      ),
                    )
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
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}