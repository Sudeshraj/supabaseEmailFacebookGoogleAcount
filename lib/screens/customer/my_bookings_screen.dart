// lib/screens/customer/my_bookings_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/timezone_service.dart';

class MyBookingsScreen extends StatefulWidget {
  final int? highlightId;
  
  const MyBookingsScreen({super.key, this.highlightId});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  String? _error;
  
  // Tab controller
  late TabController _tabController;
  
  // Colors (same as booking screen)
  final Color _primaryColor = const Color(0xFFFF6B8B);
  final Color _secondaryColor = const Color(0xFF4CAF50);
  final Color _textDark = const Color(0xFF333333);
  final Color _bgLight = const Color(0xFFF8F9FA);
  
  // Cancel dialog loading
  bool _isCancelling = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBookings();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
Future<void> _loadBookings() async {
  setState(() {
    _isLoading = true;
    _error = null;
  });
  
  try {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please login to view your bookings';
        _isLoading = false;
      });
      return;
    }
    
    // 🔥 SIMPLE QUERY - Get all appointments first
    final appointments = await supabase
        .from('appointments')
        .select('*')
        .eq('customer_id', user.id)
        .order('appointment_date', ascending: false);
    
    final now = DateTime.now();
    final List<Map<String, dynamic>> processedBookings = [];
    
    for (var booking in appointments) {
      // Get salon details
      final salonId = booking['salon_id'];
      final salon = await supabase
          .from('salons')
          .select('name, address')
          .eq('id', salonId)
          .maybeSingle();
      
      // Get service details
      final serviceId = booking['service_id'];
      final service = await supabase
          .from('services')
          .select('name')
          .eq('id', serviceId)
          .maybeSingle();
      
      // Get variant details
      final variantId = booking['variant_id'];
      Map<String, dynamic>? variant;
      if (variantId != null) {
        variant = await supabase
            .from('service_variants')
            .select('price, duration')
            .eq('id', variantId)
            .maybeSingle();
      }
      
      // Get barber name
      final barberId = booking['barber_id'];
      String barberName = 'Barber';
      if (barberId != null) {
        final barber = await supabase
            .from('profiles')
            .select('full_name')
            .eq('id', barberId)
            .maybeSingle();
        if (barber != null) {
          barberName = barber['full_name'] ?? 'Barber';
        }
      }
      
      // Convert times
      final appointmentDate = DateTime.parse(booking['appointment_date']);
      final utcStartTime = booking['start_time'] as String;
      final utcEndTime = booking['end_time'] as String;
      
      final localStartTime = TimezoneService.utcToLocalTime(utcStartTime, appointmentDate);
      final localEndTime = TimezoneService.utcToLocalTime(utcEndTime, appointmentDate);
      
      // Determine status category
      String statusCategory = 'upcoming';
      final status = booking['status'];
      if (status == 'cancelled' || status == 'no_show') {
        statusCategory = 'cancelled';
      } else if (status == 'completed') {
        statusCategory = 'completed';
      } else if (appointmentDate.isBefore(DateTime(now.year, now.month, now.day))) {
        statusCategory = 'completed';
      } else {
        statusCategory = 'upcoming';
      }
      
      processedBookings.add({
        ...booking,
        'local_start_time': localStartTime,
        'local_end_time': localEndTime,
        'status_category': statusCategory,
        'salon_name': salon?['name'] ?? 'Salon',
        'salon_address': salon?['address'],
        'barber_name': barberName,
        'service_name': service?['name'] ?? 'Service',
        'price': variant?['price'] ?? booking['price'] ?? 0.0,
        'duration': variant?['duration'] ?? 30,
      });
    }
    
    setState(() {
      _bookings = processedBookings;
      _isLoading = false;
    });
    
  } catch (e) {
    print('Error loading bookings: $e');
    setState(() {
      _error = 'Failed to load bookings: $e';
      _isLoading = false;
    });
  }
}
  
  
  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Cancel Booking?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel this booking?',
              style: TextStyle(fontSize: 16, color: Colors.grey[800]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text(booking['salon_name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text(DateFormat('EEEE, MMM dd, yyyy').format(DateTime.parse(booking['appointment_date']))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text('${booking['local_start_time']} - ${booking['local_end_time']}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Cancelling may affect your loyalty points and booking limits.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP BOOKING'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isCancelling = true);
    
    try {
      await supabase
          .from('appointments')
          .update({
            'status': 'cancelled',
            'cancel_reason': 'Cancelled by customer',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', booking['id'])
          .select();
      
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Booking cancelled successfully'),
                ],
              ),
              backgroundColor: _secondaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          
          // Reload bookings
          await _loadBookings();
        }
      
    } catch (e) {
      print('Error cancelling booking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }
  
  List<Map<String, dynamic>> get _upcomingBookings {
    return _bookings.where((b) => b['status_category'] == 'upcoming').toList();
  }
  
  List<Map<String, dynamic>> get _completedBookings {
    return _bookings.where((b) => b['status_category'] == 'completed').toList();
  }
  
  List<Map<String, dynamic>> get _cancelledBookings {
    return _bookings.where((b) => b['status_category'] == 'cancelled').toList();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: const Text(
          'My Bookings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'UPCOMING'),
            Tab(text: 'COMPLETED'),
            Tab(text: 'CANCELLED'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBookings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('TRY AGAIN'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBookingList(_upcomingBookings, isUpcoming: true),
                    _buildBookingList(_completedBookings, isUpcoming: false),
                    _buildBookingList(_cancelledBookings, isUpcoming: false),
                  ],
                ),
    );
  }
  
  Widget _buildBookingList(List<Map<String, dynamic>> bookings, {required bool isUpcoming}) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUpcoming ? Icons.event_available : Icons.history,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              isUpcoming 
                  ? 'No upcoming bookings'
                  : 'No bookings found',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
            if (isUpcoming)
              const SizedBox(height: 16),
            if (isUpcoming)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to booking flow
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('BOOK NOW'),
              ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadBookings,
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (context, index) => _buildBookingCard(bookings[index], isUpcoming),
      ),
    );
  }
  
  Widget _buildBookingCard(Map<String, dynamic> booking, bool isUpcoming) {
    final appointmentDate = DateTime.parse(booking['appointment_date']);
    final isPast = appointmentDate.isBefore(DateTime.now());
    final canCancel = isUpcoming && !isPast && booking['status'] != 'cancelled';
    final status = booking['status'];
    
    Color statusColor;
    String statusText;
    
    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusText = 'Confirmed';
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Pending';
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        statusText = 'In Progress';
        break;
      case 'completed':
        statusColor = Colors.purple;
        statusText = 'Completed';
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelled';
        break;
      default:
        statusColor = Colors.grey;
        statusText = status;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with salon name and status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.store, color: _primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['salon_name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (booking['salon_address'] != null)
                          Text(
                            booking['salon_address'],
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Booking details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date and Time
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMM dd, yyyy').format(appointmentDate),
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        '${booking['local_start_time']} - ${booking['local_end_time']}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  
                  // Queue Number
                  if (booking['queue_number'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.format_list_numbered, size: 16, color: _primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Queue Number - ${booking['queue_number']}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const Divider(height: 24),
                  
                  // Service and Barber
                  Row(
                    children: [
                      Icon(Icons.content_cut, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          booking['service_name'],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          booking['barber_name'],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  
                  // Booking for child if any
                  if (booking['child_name'] != null && booking['child_name'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(
                            'Booking for: ${booking['child_name']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  
                  const Divider(height: 24),
                  
                  // Price and Duration
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer, size: 16, color: _primaryColor),
                          const SizedBox(width: 4),
                          Text(
                            '${booking['duration']} min',
                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      Text(
                        'Rs. ${(booking['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                  
                  if (booking['travel_time_minutes'] != null && booking['travel_time_minutes'] > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.directions_car, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Travel time: ${booking['travel_time_minutes']} min',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            
            // Action buttons
            if (isUpcoming && canCancel)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isCancelling ? null : () => _cancelBooking(booking),
                        icon: _isCancelling
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.cancel_outlined, color: Colors.red),
                        label: Text(
                          _isCancelling ? 'CANCELLING...' : 'CANCEL BOOKING',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Navigate to rebook or view details
                          _showBookingDetails(booking);
                        },
                        icon: Icon(Icons.info_outline, color: Colors.white, size: 18),
                        label: const Text('VIEW DETAILS'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            if (!isUpcoming && status == 'completed')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Navigate to review
                          _showLeaveReviewDialog(booking);
                        },
                        icon: Icon(Icons.star_outline, color: Colors.amber),
                        label: const Text('LEAVE REVIEW'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: BorderSide(color: Colors.amber),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Navigate to rebook
                          _rebookBooking(booking);
                        },
                        icon: Icon(Icons.refresh, color: _primaryColor),
                        label: Text('BOOK AGAIN', style: TextStyle(color: _primaryColor)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: BorderSide(color: _primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
  
  void _showBookingDetails(Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt_long, color: _primaryColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking #${booking['booking_number']}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(booking['appointment_date'])),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildDetailRow('Salon', booking['salon_name']),
            _buildDetailRow('Address', booking['salon_address'] ?? 'N/A'),
            _buildDetailRow('Barber', booking['barber_name']),
            _buildDetailRow('Service', booking['service_name']),
            _buildDetailRow('Duration', '${booking['duration']} minutes'),
            _buildDetailRow('Price', 'Rs. ${(booking['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
            if (booking['child_name'] != null && booking['child_name'].toString().isNotEmpty)
              _buildDetailRow('Booked For', booking['child_name']),
            if (booking['queue_number'] != null)
              _buildDetailRow('Queue Number', '#${booking['queue_number']}'),
            if (booking['travel_time_minutes'] != null && booking['travel_time_minutes'] > 0)
              _buildDetailRow('Travel Time', '${booking['travel_time_minutes']} minutes'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('CLOSE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showLeaveReviewDialog(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave a Review'),
        content: const Text('Review feature coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
  
  void _rebookBooking(Map<String, dynamic> booking) {
    // Navigate back to booking flow with salon pre-selected
    Navigator.pop(context);
    // You can pass the salon data to booking flow
    // Navigator.push(context, MaterialPageRoute(builder: (_) => BookingFlowScreen(initialSalon: {...})));
  }
}