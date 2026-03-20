// screens/owner/vip_booking_requests_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class VIPBookingRequestsScreen extends StatefulWidget {
  final String salonId;

  const VIPBookingRequestsScreen({super.key, required this.salonId});

  @override
  State<VIPBookingRequestsScreen> createState() => _VIPBookingRequestsScreenState();
}

class _VIPBookingRequestsScreenState extends State<VIPBookingRequestsScreen> {
  final supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];
  Map<int, Map<String, dynamic>> _vipTypes = {};
  Map<String, Map<String, dynamic>> _customerProfiles = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load VIP types
      final vipTypesResponse = await supabase
          .from('vip_booking_types')
          .select();

      for (var type in vipTypesResponse) {
        _vipTypes[type['id']] = type;
      }

      // Load VIP bookings
      final requestsResponse = await supabase
          .from('vip_bookings')
          .select()
          .eq('salon_id', int.parse(widget.salonId))
          .order('created_at', ascending: false);

      _requests = List<Map<String, dynamic>>.from(requestsResponse);

      // Load customer profiles
      final customerIds = _requests.map((r) => r['customer_id'] as String).toSet();
      for (String customerId in customerIds) {
        final profile = await supabase
            .from('profiles')
            .select('full_name, email, avatar_url')
            .eq('id', customerId)
            .maybeSingle();

        if (profile != null) {
          _customerProfiles[customerId] = profile;
        }
      }

    } catch (e) {
      debugPrint('❌ Error loading VIP requests: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );

      // Get buffer minutes
      final vipType = _vipTypes[request['vip_type_id']];
      final bufferMinutes = vipType?['buffer_minutes'] ?? 15;

      // Calculate scheduled times
      final scheduledStart = request['preferred_start_time'];
      final totalDuration = request['total_duration_minutes'] ?? 0;
      
      // Update VIP booking
      await supabase
          .from('vip_bookings')
          .update({
            'status': 'approved',
            'approved_by': supabase.auth.currentUser?.id,
            'approved_at': DateTime.now().toIso8601String(),
            'scheduled_start_time': scheduledStart,
            'scheduled_end_time': _calculateEndTime(scheduledStart, totalDuration),
          })
          .eq('id', request['id']);

      // Load VIP services
      final services = await supabase
          .from('vip_booking_services')
          .select()
          .eq('vip_booking_id', request['id']);

      // Create appointments with buffer time
      DateTime currentTime = DateTime.parse('${request['event_date']}T$scheduledStart');
      
      for (var service in services) {
        // Add buffer before first service
        if (service == services.first) {
          currentTime = currentTime.add(Duration(minutes: bufferMinutes));
        }

        final endTime = currentTime.add(Duration(minutes: service['duration_minutes']));

        await supabase.from('appointments').insert({
          'booking_number': 'VIP-${request['booking_number']}-${service['id']}',
          'customer_id': request['customer_id'],
          'barber_id': service['barber_id'], // You'll need to assign barbers
          'salon_id': int.parse(widget.salonId),
          'service_id': service['service_id'],
          'variant_id': service['variant_id'],
          'appointment_date': request['event_date'],
          'start_time': DateFormat('HH:mm:ss').format(currentTime),
          'end_time': DateFormat('HH:mm:ss').format(endTime),
          'status': 'confirmed',
          'is_vip': true,
          'vip_booking_id': request['id'],
          'notes': 'VIP Booking - ${vipType?['name']}',
        });

        currentTime = endTime;
      }

      // Close loading
      if (context.mounted) Navigator.pop(context);

      // Show success
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VIP booking approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadData();

    } catch (e) {
      debugPrint('❌ Error approving VIP request: $e');
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(int requestId) async {
    try {
      await supabase
          .from('vip_bookings')
          .update({'status': 'rejected'})
          .eq('id', requestId);

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VIP booking rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error rejecting VIP request: $e');
    }
  }

  String _calculateEndTime(String startTime, int durationMinutes) {
    try {
      final parts = startTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      
      final totalMinutes = hour * 60 + minute + durationMinutes;
      final newHour = (totalMinutes ~/ 60) % 24;
      final newMinute = totalMinutes % 60;
      
      return '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      return startTime;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
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
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final double padding = isWeb ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VIP Booking Requests'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        centerTitle: isWeb,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'No VIP booking requests',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : isWeb
                  ? _buildWebView(padding)
                  : _buildMobileView(padding),
    );
  }

  Widget _buildWebView(double padding) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                Expanded(flex: 2, child: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Event Type', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Date/Time', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 1, child: Text('Guests', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 3, child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Table Rows
          ..._requests.map((request) {
            final customer = _customerProfiles[request['customer_id']] ?? {};
            final vipType = _vipTypes[request['vip_type_id']] ?? {};
            final statusColor = _getStatusColor(request['status']);
            
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
                          backgroundColor: Colors.amber.shade100,
                          backgroundImage: customer['avatar_url'] != null
                              ? NetworkImage(customer['avatar_url'])
                              : null,
                          child: customer['avatar_url'] == null
                              ? Text(
                                  (customer['full_name']?[0] ?? '?').toUpperCase(),
                                  style: const TextStyle(color: Colors.amber),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer['full_name'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                customer['email'] ?? '',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vipType['name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (vipType['priority_level'] == 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'High Priority',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(request['event_date'])),
                        Text(
                          _formatTime(request['preferred_start_time']),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${request['number_of_guests']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          request['status'].toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (request['status'] == 'pending') ...[
                          ElevatedButton.icon(
                            onPressed: () => _approveRequest(request),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(80, 36),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _rejectRequest(request['id']),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(80, 36),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              request['status'].toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        final customer = _customerProfiles[request['customer_id']] ?? {};
        final vipType = _vipTypes[request['vip_type_id']] ?? {};
        final statusColor = _getStatusColor(request['status']);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.amber.shade100,
                  backgroundImage: customer['avatar_url'] != null
                      ? NetworkImage(customer['avatar_url'])
                      : null,
                  child: customer['avatar_url'] == null
                      ? Text(
                          (customer['full_name']?[0] ?? '?').toUpperCase(),
                          style: const TextStyle(color: Colors.amber),
                        )
                      : null,
                ),
                title: Text(customer['full_name'] ?? 'Unknown'),
                subtitle: Text(customer['email'] ?? ''),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    request['status'].toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          '${_formatDate(request['event_date'])} at ${_formatTime(request['preferred_start_time'])}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          vipType['name'] ?? 'Unknown',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${request['number_of_guests']} guests',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (request['status'] == 'pending')
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _approveRequest(request),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _rejectRequest(request['id']),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Reject'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
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
}