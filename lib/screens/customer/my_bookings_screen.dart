// lib/screens/customer/my_bookings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/customer/booking_flow_screen.dart';
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
  List<Map<String, dynamic>> _overflowNotifications = [];
  bool _isLoading = true;
  String? _error;
  
  // Tab controller
  late TabController _tabController;
  
  // Colors
  final Color _primaryColor = const Color(0xFFFF6B8B);
  final Color _secondaryColor = const Color(0xFF4CAF50);
  final Color _textDark = const Color(0xFF333333);
  final Color _bgLight = const Color(0xFFF8F9FA);
  
  // Loading states
  bool _isCancelling = false;
  bool _isProcessingOverflow = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    await Future.wait([
      _loadBookings(),
      _loadOverflowNotifications(),
    ]);
    
    setState(() => _isLoading = false);
  }
  
  // =====================================================
  // LOAD BOOKINGS (SIMPLIFIED)
  // =====================================================
  Future<void> _loadBookings() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Please login to view your bookings';
          _isLoading = false;
        });
        return;
      }
      
      // Get all appointments for this customer
      final appointments = await supabase
          .from('appointments')
          .select('*')
          .eq('customer_id', user.id)
          .order('appointment_date', ascending: false);
      
      final now = DateTime.now();
      final List<Map<String, dynamic>> processedBookings = [];
      
      for (var booking in appointments) {
        // Get salon details
        final salon = await supabase
            .from('salons')
            .select('name, address')
            .eq('id', booking['salon_id'])
            .maybeSingle();
        
        // Get service name
        final service = await supabase
            .from('services')
            .select('name')
            .eq('id', booking['service_id'])
            .maybeSingle();
        
        // Get variant details
        Map<String, dynamic>? variant;
        if (booking['variant_id'] != null) {
          variant = await supabase
              .from('service_variants')
              .select('price, duration')
              .eq('id', booking['variant_id'])
              .maybeSingle();
        }
        
        // Get barber name
        String barberName = 'Barber';
        if (booking['barber_id'] != null) {
          final barber = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', booking['barber_id'])
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
      });
      
    } catch (e) {
      print('Error loading bookings: $e');
      setState(() {
        _error = 'Failed to load bookings: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // =====================================================
  // LOAD OVERFLOW NOTIFICATIONS (SIMPLIFIED - NO COMPLEX JOINS)
  // =====================================================
  Future<void> _loadOverflowNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      // Simple query without nested joins
      final result = await supabase
          .from('overflow_notifications')
          .select('*')
          .eq('customer_id', user.id)
          .eq('status', 'PENDING')
          .order('notified_at', ascending: false);
      
      final List<Map<String, dynamic>> notifications = [];
      
      for (var notice in result) {
        // Get appointment details separately
        final apt = await supabase
            .from('appointments')
            .select('*, salons!inner(name, address), services!inner(name)')
            .eq('id', notice['appointment_id'])
            .single();
        
        // Get barber name separately
        String barberName = 'Barber';
        if (apt['barber_id'] != null) {
          final barber = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', apt['barber_id'])
              .maybeSingle();
          if (barber != null) {
            barberName = barber['full_name'] ?? 'Barber';
          }
        }
        
        // Convert times
        final appointmentDate = DateTime.parse(apt['appointment_date']);
        final utcStartTime = apt['start_time'] as String;
        final utcEndTime = apt['end_time'] as String;
        
        final localStartTime = TimezoneService.utcToLocalTime(utcStartTime, appointmentDate);
        final localEndTime = TimezoneService.utcToLocalTime(utcEndTime, appointmentDate);
        
        notifications.add({
          'id': notice['id'],
          'excess_minutes': notice['excess_minutes'],
          'estimated_end': notice['estimated_end'],
          'salon_close': notice['salon_close'],
          'notified_at': notice['notified_at'],
          'appointment': {
            'id': apt['id'],
            'booking_number': apt['booking_number'],
            'appointment_date': apt['appointment_date'],
            'start_time': localStartTime,
            'end_time': localEndTime,
            'utc_start_time': utcStartTime,
            'utc_end_time': utcEndTime,
            'status': apt['status'],
            'queue_number': apt['queue_number'],
            'child_name': apt['child_name'],
            'travel_time_minutes': apt['travel_time_minutes'],
            'salon_name': apt['salons']?['name'] ?? 'Salon',
            'salon_address': apt['salons']?['address'],
            'salon_id': apt['salon_id'],
            'service_name': apt['services']?['name'] ?? 'Service',
            'barber_name': barberName,
          },
        });
      }
      
      setState(() => _overflowNotifications = notifications);
      
    } catch (e) {
      print('Error loading overflow notifications: $e');
      setState(() => _overflowNotifications = []);
    }
  }
  
  // =====================================================
  // OVERFLOW RESPONSE HANDLER (Type 2 Cancel)
  // =====================================================
  Future<void> _respondToOverflow(int notificationId, String response) async {
    setState(() => _isProcessingOverflow = true);
    
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final result = await supabase.rpc('handle_overflow_response', params: {
        'p_notification_id': notificationId,
        'p_customer_id': user.id,
        'p_response': response,
      });
      
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(response == 'MOVE' ? Icons.calendar_today : Icons.check_circle, 
                       color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(result['message'] ?? 'Success')),
                ],
              ),
              backgroundColor: response == 'MOVE' ? Colors.green : Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingOverflow = false);
    }
  }
  
  // =====================================================
  // OVERFLOW DECISION DIALOG
  // =====================================================
  void _showOverflowDecisionDialog(Map<String, dynamic> notification) {
    final apt = notification['appointment'];
    final excessMinutes = notification['excess_minutes'];
    final estimatedEnd = notification['estimated_end'];
    final salonClose = notification['salon_close'];
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Appointment Overflow', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚠️ Delay of $excessMinutes minutes detected', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                  const SizedBox(height: 8),
                  Text('Your appointment on ${apt['appointment_date']} at ${apt['start_time']} may be significantly delayed.', style: TextStyle(color: Colors.orange.shade700)),
                  const SizedBox(height: 8),
                  Text('Estimated end: $estimatedEnd | Salon closes: $salonClose', style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('What would you like to do?', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Move to Next Day', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    Text('Reschedule your appointment to tomorrow', style: TextStyle(fontSize: 12, color: Colors.green.shade600)),
                  ])),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.cancel, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Cancel Appointment', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                    Text('Cancel this appointment (no charges)', style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                  ])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('⚠️ If no response within 30 minutes, your appointment will be auto-cancelled.', style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('DECIDE LATER')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _showMoveCancelOptions(notification['id']);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('PROCEED'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _showMoveCancelOptions(int notificationId) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose Action'),
        content: const Text('What would you like to do?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'CANCEL'), child: const Text('CANCEL', style: TextStyle(color: Colors.red))),
          ElevatedButton(onPressed: () => Navigator.pop(context, 'MOVE'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('MOVE TO NEXT DAY')),
        ],
      ),
    );
    
    if (result != null) {
      await _respondToOverflow(notificationId, result);
    }
  }
  
  // =====================================================
  // CANCEL BOOKING (Type 1 Cancel - Customer Self Cancel)
  // =====================================================
  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final hasOverflow = _overflowNotifications.any((n) => n['appointment']['id'] == booking['id']);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Cancel Booking?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel this booking?', style: TextStyle(fontSize: 16, color: Colors.grey[800])),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(Icons.store, size: 16, color: _primaryColor), const SizedBox(width: 8), Text(booking['salon_name'], style: const TextStyle(fontWeight: FontWeight.w500))]),
                  const SizedBox(height: 4),
                  Row(children: [Icon(Icons.calendar_today, size: 16, color: _primaryColor), const SizedBox(width: 8), Text(DateFormat('EEEE, MMM dd, yyyy').format(DateTime.parse(booking['appointment_date'])))]),
                  const SizedBox(height: 4),
                  Row(children: [Icon(Icons.access_time, size: 16, color: _primaryColor), const SizedBox(width: 8), Text('${booking['local_start_time']} - ${booking['local_end_time']}')]),
                ],
              ),
            ),
            if (hasOverflow) Padding(padding: const EdgeInsets.only(top: 12), child: Text('⚠️ Cancelling now will resolve overflow.', style: TextStyle(fontSize: 12, color: Colors.orange.shade700))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KEEP BOOKING')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('YES, CANCEL')),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isCancelling = true);
    
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final result = await supabase.rpc('cancel_booking_and_reorder', params: {
        'p_appointment_id': booking['id'],
        'p_customer_id': user.id,
        'p_cancel_reason': 'Cancelled by customer',
      });
      
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 20), SizedBox(width: 8), Text('Booking cancelled successfully')]), backgroundColor: _secondaryColor),
        );
        await _loadData();
      } else {
        throw Exception(result['message'] ?? 'Cancellation failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }
  
  List<Map<String, dynamic>> get _upcomingBookings => _bookings.where((b) => b['status_category'] == 'upcoming').toList();
  List<Map<String, dynamic>> get _completedBookings => _bookings.where((b) => b['status_category'] == 'completed').toList();
  List<Map<String, dynamic>> get _cancelledBookings => _bookings.where((b) => b['status_category'] == 'cancelled').toList();
  
  // =====================================================
  // BUILD METHOD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: const Text('My Bookings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: _primaryColor,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'UPCOMING'), Tab(text: 'COMPLETED'), Tab(text: 'CANCELLED')],
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
                      ElevatedButton(onPressed: _loadData, style: ElevatedButton.styleFrom(backgroundColor: _primaryColor), child: const Text('TRY AGAIN')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: _primaryColor,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBookingList(_upcomingBookings, isUpcoming: true),
                      _buildBookingList(_completedBookings, isUpcoming: false),
                      _buildBookingList(_cancelledBookings, isUpcoming: false),
                    ],
                  ),
                ),
    );
  }
  
  Widget _buildBookingList(List<Map<String, dynamic>> bookings, {required bool isUpcoming}) {
    if (bookings.isEmpty && _overflowNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isUpcoming ? Icons.event_available : Icons.history, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(isUpcoming ? 'No upcoming bookings' : 'No bookings found', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            if (isUpcoming) const SizedBox(height: 16),
            if (isUpcoming) ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: _primaryColor), child: const Text('BOOK NOW')),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length + _overflowNotifications.length,
      itemBuilder: (context, index) {
        if (isUpcoming && index < _overflowNotifications.length) {
          return _buildOverflowCard(_overflowNotifications[index]);
        }
        final bookingIndex = isUpcoming ? index - _overflowNotifications.length : index;
        if (bookingIndex < 0 || bookingIndex >= bookings.length) return const SizedBox.shrink();
        return _buildBookingCard(bookings[bookingIndex], isUpcoming);
      },
    );
  }
  
  Widget _buildOverflowCard(Map<String, dynamic> notification) {
    final apt = notification['appointment'];
    final excessMinutes = notification['excess_minutes'];
    final estimatedEnd = notification['estimated_end'];
    final salonClose = notification['salon_close'];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.orange.shade50, border: Border.all(color: Colors.orange.shade300)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
              child: Row(
                children: [
                  Container(width: 45, height: 45, decoration: BoxDecoration(color: Colors.orange.shade200, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.warning_amber, color: Colors.orange, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('⚠️ ACTION REQUIRED', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange)), Text(apt['salon_name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(20)), child: Text('$excessMinutes min overflow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]), const SizedBox(width: 8), Text(apt['appointment_date'], style: TextStyle(fontSize: 14, color: Colors.grey[700]))]),
                  const SizedBox(height: 8),
                  Row(children: [Icon(Icons.access_time, size: 16, color: Colors.grey[600]), const SizedBox(width: 8), Text('${apt['start_time']} - ${apt['end_time']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('⚠️ Schedule Overflow Detected', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                        const SizedBox(height: 6),
                        Text('Your appointment may be delayed by approximately $excessMinutes minutes.', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Estimated end: $estimatedEnd | Salon closes: $salonClose', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isProcessingOverflow ? null : () => _showOverflowDecisionDialog(notification),
                    icon: _isProcessingOverflow ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle, size: 18),
                    label: const Text('RESPOND NOW'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange), padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                  const SizedBox(height: 8),
                  Text('⚠️ If no response within 30 minutes, this appointment will be auto-cancelled.', style: TextStyle(fontSize: 12, color: Colors.orange.shade600), textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
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
    case 'confirmed': statusColor = Colors.green; statusText = 'Confirmed'; break;
    case 'pending': statusColor = Colors.orange; statusText = 'Pending'; break;
    case 'in_progress': statusColor = Colors.blue; statusText = 'In Progress'; break;
    case 'completed': statusColor = Colors.purple; statusText = 'Completed'; break;
    case 'cancelled': statusColor = Colors.red; statusText = 'Cancelled'; break;
    default: statusColor = Colors.grey; statusText = status;
  }
  
  return Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                if (booking['queue_number'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.format_list_numbered, size: 16, color: _primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Queue #${booking['queue_number']}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _primaryColor),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryColor),
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
          
          // =====================================================
          // BUTTONS SECTION - ONLY FOR UPCOMING TAB
          // =====================================================
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
                  // CANCEL BUTTON
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isCancelling ? null : () => _cancelBooking(booking),
                      icon: _isCancelling
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.cancel_outlined, color: Colors.red),
                      label: Text(_isCancelling ? 'CANCELLING...' : 'CANCEL'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // INFO BUTTON (Small icon)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: IconButton(
                      onPressed: () => _showBookingDetails(booking),
                      icon: Icon(Icons.info_outline, color: _primaryColor, size: 22),
                      tooltip: 'View Details',
                    ),
                  ),
                ],
              ),
            ),
          
          // COMPLETED BOOKING ACTIONS
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
                      onPressed: () => _showLeaveReviewDialog(booking),
                      icon: Icon(Icons.star_outline, color: Colors.amber),
                      label: const Text('REVIEW'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber,
                        side: const BorderSide(color: Colors.amber),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rebookBooking(booking),
                      icon: Icon(Icons.refresh, color: _primaryColor),
                      label: Text('BOOK AGAIN', style: TextStyle(color: _primaryColor)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: BorderSide(color: _primaryColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.receipt_long, color: _primaryColor, size: 28)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Booking #${booking['booking_number']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(booking['appointment_date'])), style: TextStyle(fontSize: 12, color: Colors.grey[600]))])),
              ],
            ),
            const SizedBox(height: 20),
            _buildDetailRow('Salon', booking['salon_name']),
            _buildDetailRow('Address', booking['salon_address'] ?? 'N/A'),
            _buildDetailRow('Barber', booking['barber_name']),
            _buildDetailRow('Service', booking['service_name']),
            _buildDetailRow('Duration', '${booking['duration']} minutes'),
            _buildDetailRow('Price', 'Rs. ${(booking['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
            if (booking['child_name'] != null && booking['child_name'].toString().isNotEmpty) _buildDetailRow('Booked For', booking['child_name']),
            if (booking['queue_number'] != null) _buildDetailRow('Queue Number', '#${booking['queue_number']}'),
            if (booking['travel_time_minutes'] != null && booking['travel_time_minutes'] > 0) _buildDetailRow('Travel Time', '${booking['travel_time_minutes']} minutes'),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: _primaryColor), child: const Text('CLOSE'))),
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
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600]))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
  
  void _showLeaveReviewDialog(Map<String, dynamic> booking) {
    int selectedRating = 0;
    String reviewText = '';
    final TextEditingController reviewController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.star_rate_rounded, color: Colors.amber, size: 28),
                const SizedBox(width: 10),
                const Text('Leave a Review', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(booking['salon_name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Barber: ${booking['barber_name']}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        Text('Service: ${booking['service_name']}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Your Rating', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        onPressed: () => setStateDialog(() => selectedRating = index + 1),
                        icon: Icon(index < selectedRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 36),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Center(child: Text(selectedRating == 0 ? 'Tap to rate' : 'You rated: $selectedRating/5', style: TextStyle(fontSize: 13, color: selectedRating == 0 ? Colors.grey[500] : Colors.amber[700]))),
                  const SizedBox(height: 20),
                  const Text('Your Review (Optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reviewController,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Share your experience...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryColor, width: 2)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (value) => reviewText = value,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: selectedRating == 0 ? null : () async {
                  if (selectedRating > 0) {
                    await _submitReview(bookingId: booking['id'], rating: selectedRating, review: reviewText);
                    if (mounted) Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                child: const Text('SUBMIT REVIEW'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  void _rebookBooking(Map<String, dynamic> booking) {
    final salonData = {
      'id': booking['salon_id'],
      'name': booking['salon_name'],
    };
    
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookingFlowScreen(initialSalon: salonData)),
    );
  }
  
  Future<void> _submitReview({
    required int bookingId,
    required int rating,
    required String review,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final appointment = await supabase
          .from('appointments')
          .select('barber_id, salon_id')
          .eq('id', bookingId)
          .single();
      
      final existingReview = await supabase
          .from('reviews')
          .select('id')
          .eq('appointment_id', bookingId)
          .maybeSingle();
      
      if (existingReview != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already reviewed this appointment'), backgroundColor: Colors.orange),
        );
        return;
      }
      
      await supabase.from('reviews').insert({
        'appointment_id': bookingId,
        'customer_id': user.id,
        'barber_id': appointment['barber_id'],
        'salon_id': appointment['salon_id'],
        'overall_rating': rating,
        'comment': review,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 20), SizedBox(width: 8), Text('Thank you for your review!')]), backgroundColor: Colors.green),
      );
      
      await _loadData();
      
    } catch (e) {
      print('Error submitting review: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit review: $e'), backgroundColor: Colors.red));
    }
  }
}