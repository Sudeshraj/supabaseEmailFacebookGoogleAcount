// Dashboard screen for owners to view appointments of their salon

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AppointmentsScreen extends StatefulWidget {
  final String? salonId;
  final String? filter;

  const AppointmentsScreen({super.key, this.salonId, this.filter});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'today';
  String _selectedSalonName = '';
  int _totalCount = 0;
  int _completedCount = 0;
  int _pendingCount = 0;
  int _cancelledCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.filter ?? 'today';
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please login to view appointments';
          _isLoading = false;
        });
        return;
      }

      if (widget.salonId != null) {
        final salonResponse = await supabase
            .from('salons')
            .select('name')
            .eq('id', int.parse(widget.salonId!))
            .maybeSingle();

        if (salonResponse != null) {
          _selectedSalonName = salonResponse['name'] ?? 'Salon';
        }
      }

      await _loadAppointments();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading appointments: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ✅ FIXED: _loadAppointments() function
  Future<void> _loadAppointments() async {
    try {
      final salonIdInt = widget.salonId != null
          ? int.parse(widget.salonId!)
          : null;
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Build query
      var query = supabase.from('appointments').select('''
            id,
            booking_number,
            customer_id,
            barber_id,
            appointment_date,
            start_time,
            end_time,
            status,
            price,
            service_id,
            variant_id,
            salon_id,
            queue_number,
            queue_token,
            is_vip,
            child_name,
            created_at,
            profiles!appointments_customer_id_fkey (
              id,
              full_name,
              email,
              phone,
              avatar_url
            ),
            barber_profiles:profiles!appointments_barber_id_fkey (
              id,
              full_name,
              avatar_url
            ),
            services!inner (
              name,
              description
            ),
            service_variants!left (
              price,
              duration
            ),
            salons!inner (
              id,
              name
            )
          ''');

      if (salonIdInt != null) {
        query = query.eq('salon_id', salonIdInt);
      }

      if (_selectedFilter == 'today') {
        query = query.eq('appointment_date', today);
      } else if (_selectedFilter == 'pending') {
        query = query.inFilter('status', [
          'pending',
          'confirmed',
          'in_progress',
        ]);
      }

      final response = await query
          .order('appointment_date', ascending: true)
          .order('start_time', ascending: true);

      // Process appointments
      final List<Map<String, dynamic>> appointments = [];
      int total = 0;
      int completed = 0;
      int pending = 0;
      int cancelled = 0;

      for (var apt in response) {
        final customer = apt['profiles'] as Map?;
        final barber = apt['barber_profiles'] as Map?;
        final service = apt['services'] as Map?;
        final variant = apt['service_variants'] as Map?;
        final salon = apt['salons'] as Map?;

        final status = apt['status'] as String? ?? 'pending';
        final aptDate = apt['appointment_date'] as String;
        final isToday = aptDate == today;
        final isVip = apt['is_vip'] as bool? ?? false;

        total++;
        if (status == 'completed') {
          completed++;
        } else if (status == 'pending' ||
            status == 'confirmed' ||
            status == 'in_progress') {
          pending++;
        } else if (status == 'cancelled' || status == 'no_show') {
          cancelled++;
        }
        appointments.add({
          'id': apt['id'],
          'booking_number': apt['booking_number'] ?? 'N/A',
          'customer_name': customer?['full_name'] ?? 'Unknown Customer',
          'customer_phone': customer?['phone'] ?? '',
          'customer_email': customer?['email'] ?? '',
          'customer_avatar': customer?['avatar_url'],
          'barber_name': barber?['full_name'] ?? 'Unknown Barber',
          'barber_avatar': barber?['avatar_url'],
          'service_name': service?['name'] ?? 'Unknown Service',
          'service_description': service?['description'],
          'duration': variant?['duration'] ?? 30,
          'price':
              (apt['price'] as num?)?.toDouble() ??
              (variant?['price'] as num?)?.toDouble() ??
              0.0,
          'salon_name': salon?['name'] ?? 'Unknown Salon',
          'appointment_date': aptDate,
          'is_today': isToday,
          'display_date': _formatDate(aptDate),
          'start_time': apt['start_time'],
          'end_time': apt['end_time'],
          'status': status,
          'is_vip': isVip,
          'queue_number': apt['queue_number'],
          'queue_token': apt['queue_token'],
          'child_name': apt['child_name'],
          'created_at': apt['created_at'],
        });
      }

      setState(() {
        _appointments = appointments;
        _totalCount = total;
        _completedCount = completed;
        _pendingCount = pending;
        _cancelledCount = cancelled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading appointments: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ... rest of the methods (same as before)
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      if (date.isAtSameMomentAs(today)) {
        return 'Today';
      } else if (date.isAtSameMomentAs(tomorrow)) {
        return 'Tomorrow';
      } else {
        return DateFormat('EEEE, MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'confirmed':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'no_show':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'confirmed':
        return 'Confirmed';
      case 'in_progress':
        return 'In Progress';
      case 'pending':
        return 'Pending';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No Show';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.hourglass_top;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'no_show':
        return Icons.person_off;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedFilter == 'today'
                  ? "Today's Appointments"
                  : _selectedFilter == 'pending'
                  ? 'Pending Appointments'
                  : 'All Appointments',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_selectedSalonName.isNotEmpty)
              Text(
                _selectedSalonName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
              _loadAppointments();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'today', child: Text('Today')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(value: 'all', child: Text('All')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading appointments...'),
                ],
              ),
            )
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loadData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Stats summary
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Total', '$_totalCount', Colors.blue),
                      Container(width: 1, height: 30, color: Colors.grey[300]),
                      _buildStatItem(
                        'Completed',
                        '$_completedCount',
                        Colors.green,
                      ),
                      Container(width: 1, height: 30, color: Colors.grey[300]),
                      _buildStatItem(
                        'Pending',
                        '$_pendingCount',
                        Colors.orange,
                      ),
                      Container(width: 1, height: 30, color: Colors.grey[300]),
                      _buildStatItem(
                        'Cancelled',
                        '$_cancelledCount',
                        Colors.red,
                      ),
                    ],
                  ),
                ),

                // Appointments list
                Expanded(
                  child: _appointments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.event_busy,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedFilter == 'today'
                                    ? 'No appointments today'
                                    : _selectedFilter == 'pending'
                                    ? 'No pending appointments'
                                    : 'No appointments found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() => _selectedFilter = 'today');
                                  _loadAppointments();
                                },
                                icon: const Icon(Icons.calendar_today),
                                label: const Text('View Today'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6B8B),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _appointments.length,
                          itemBuilder: (context, index) {
                            return _buildAppointmentCard(_appointments[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> apt) {
    final status = apt['status'] as String;
    final statusColor = _getStatusColor(status);
    final isVip = apt['is_vip'] as bool? ?? false;
    final customerName = apt['customer_name'] as String;
    final customerAvatar = apt['customer_avatar'] as String?;
    final barberName = apt['barber_name'] as String;
    final serviceName = apt['service_name'] as String;
    final price = apt['price'] as double;
    final startTime = _formatTime(apt['start_time']);
    final endTime = _formatTime(apt['end_time']);
    final displayDate = apt['display_date'] as String;
    final isToday = apt['is_today'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isVip
            ? BorderSide(color: Colors.amber.shade400, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _viewAppointmentDetails(apt),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    apt['booking_number'] ?? 'BK-XXXX',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  if (isVip)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'VIP',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(status),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusDisplay(status),
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Customer & Barber
              Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                    ),
                    child: customerAvatar != null && customerAvatar.isNotEmpty
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: customerAvatar,
                              fit: BoxFit.cover,
                              width: 45,
                              height: 45,
                              errorWidget: (context, url, error) => Center(
                                child: Text(
                                  customerName.isNotEmpty
                                      ? customerName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              customerName.isNotEmpty
                                  ? customerName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 12,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Barber: $barberName',
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
                ],
              ),
              const SizedBox(height: 12),

              // Service & Time
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${apt['duration']} min • Rs. ${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isToday ? 'Today' : displayDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$startTime - $endTime',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewAppointmentDetails(Map<String, dynamic> apt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AppointmentDetailsSheet(appointment: apt),
    );
  }
}

// ============================================================
// APPOINTMENT DETAILS SHEET
// ============================================================
class AppointmentDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const AppointmentDetailsSheet({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    final customerName = appointment['customer_name'] as String;
    final customerPhone = appointment['customer_phone'] as String? ?? '';
    final customerEmail = appointment['customer_email'] as String? ?? '';
    final customerAvatar = appointment['customer_avatar'] as String?;
    final barberName = appointment['barber_name'] as String;
    final serviceName = appointment['service_name'] as String;
    final price = appointment['price'] as double;
    final duration = appointment['duration'] as int;
    final status = appointment['status'] as String;
    final statusColor = _getStatusColor(status);
    final isVip = appointment['is_vip'] as bool? ?? false;
    final displayDate = appointment['display_date'] as String;
    final startTime = appointment['start_time'] as String;
    final endTime = appointment['end_time'] as String;
    final bookingNumber = appointment['booking_number'] as String? ?? 'N/A';
    final childName = appointment['child_name'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Booking #$bookingNumber',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getStatusIcon(status),
                                    size: 14,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getStatusDisplay(status),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isVip) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.amber.shade400,
                                  ),
                                ),
                                child: const Text(
                                  '⭐ VIP',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[200],
                  ),
                  child: customerAvatar != null && customerAvatar.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: customerAvatar,
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                            errorWidget: (context, url, error) => Center(
                              child: Text(
                                customerName.isNotEmpty
                                    ? customerName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            customerName.isNotEmpty
                                ? customerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                ),
                title: Text(
                  customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (customerPhone.isNotEmpty) Text(customerPhone),
                    if (customerEmail.isNotEmpty) Text(customerEmail),
                    if (childName != null && childName.isNotEmpty)
                      Text(
                        'Child: $childName',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('Barber', barberName),
              _buildDetailRow('Service', serviceName),
              _buildDetailRow('Duration', '$duration minutes'),
              _buildDetailRow('Price', 'Rs. ${price.toStringAsFixed(2)}'),
              _buildDetailRow('Date', displayDate),
              _buildDetailRow(
                'Time',
                '${_formatTime(startTime)} - ${_formatTime(endTime)}',
              ),
              if (appointment['queue_number'] != null)
                _buildDetailRow('Queue', '#${appointment['queue_number']}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'confirmed':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'no_show':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'confirmed':
        return 'Confirmed';
      case 'in_progress':
        return 'In Progress';
      case 'pending':
        return 'Pending';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No Show';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.hourglass_top;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'no_show':
        return Icons.person_off;
      default:
        return Icons.info;
    }
  }

  String _formatTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }
}
