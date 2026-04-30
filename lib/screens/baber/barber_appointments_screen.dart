// lib/screens/barber/barber_appointments_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/timezone_service.dart';

class BarberAppointmentsScreen extends StatefulWidget {
  const BarberAppointmentsScreen({super.key});

  @override
  State<BarberAppointmentsScreen> createState() => _BarberAppointmentsScreenState();
}

class _BarberAppointmentsScreenState extends State<BarberAppointmentsScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  
  // Colors
  final Color _primaryColor = const Color(0xFFFF6B8B);
  final Color _secondaryColor = const Color(0xFF4CAF50);
  final Color _warningColor = const Color(0xFFFF9800);
  final Color _dangerColor = const Color(0xFFF44336);
  
  // Data
  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  
  bool _isLoading = true;
  String? _error;
  String? _barberName;
  
  // Tab controller
  late TabController _tabController;
  
  // Date selection
  DateTime _selectedDate = DateTime.now();
  
  // Action states
  bool _isProcessing = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBarberData();
    _loadAppointments();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadBarberData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final profile = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      
      if (profile != null && mounted) {
        setState(() {
          _barberName = profile['full_name'] ?? 'Barber';
        });
      }
    } catch (e) {
      debugPrint('Error loading barber data: $e');
    }
  }
  
  // =====================================================
  // LOAD APPOINTMENTS WITH TIMEZONE SERVICE
  // =====================================================
  Future<void> _loadAppointments() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }
      
      // Step 1: Get all appointments for this barber
      final appointments = await supabase
          .from('appointments')
          .select('*')
          .eq('barber_id', user.id)
          .order('appointment_date', ascending: true);
      
      if (appointments.isEmpty) {
        setState(() {
          _todayAppointments = [];
          _upcomingAppointments = [];
          _pastAppointments = [];
          _isLoading = false;
        });
        return;
      }
      
      // Step 2: Get all unique customer IDs
      final customerIds = appointments
          .map((a) => a['customer_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();
      
      // Step 3: Fetch all customers in one query
      Map<String, Map<String, dynamic>> customersMap = {};
      if (customerIds.isNotEmpty) {
        final customers = await supabase
            .from('profiles')
            .select('id, full_name, avatar_url, phone')
            .inFilter('id', customerIds);
        
        for (var customer in customers) {
          customersMap[customer['id']] = customer as Map<String, dynamic>;
        }
      }
      
      // Step 4: Get all unique service IDs
      final serviceIds = appointments
          .map((a) => a['service_id'] as int?)
          .where((id) => id != null)
          .toSet()
          .toList();
      
      Map<int, String> servicesMap = {};
      if (serviceIds.isNotEmpty) {
        final services = await supabase
            .from('services')
            .select('id, name')
            .inFilter('id', serviceIds);
        
        for (var service in services) {
          servicesMap[service['id']] = service['name'];
        }
      }
      
      // Step 5: Get all unique salon IDs
      final salonIds = appointments
          .map((a) => a['salon_id'] as int?)
          .where((id) => id != null)
          .toSet()
          .toList();
      
      Map<int, String> salonsMap = {};
      if (salonIds.isNotEmpty) {
        final salons = await supabase
            .from('salons')
            .select('id, name')
            .inFilter('id', salonIds);
        
        for (var salon in salons) {
          salonsMap[salon['id']] = salon['name'];
        }
      }
      
      // Step 6: Process appointments with TIMEZONE SERVICE
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final List<Map<String, dynamic>> todayList = [];
      final List<Map<String, dynamic>> upcomingList = [];
      final List<Map<String, dynamic>> pastList = [];
      
      for (var apt in appointments) {
        final customer = customersMap[apt['customer_id']];
        final serviceName = servicesMap[apt['service_id']] ?? 'Service';
        final salonName = salonsMap[apt['salon_id']] ?? 'Salon';
        
        final appointmentDate = DateTime.parse(apt['appointment_date']);
        final appointmentDateOnly = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day);
        
        // 🔥 TIMEZONE FIX: Convert UTC to Local time using TimezoneService
        final utcStart = apt['start_time'] as String;
        final utcEnd = apt['end_time'] as String;
        final localStart = TimezoneService.utcToLocalTime(utcStart, appointmentDate);
        final localEnd = TimezoneService.utcToLocalTime(utcEnd, appointmentDate);
        
        final appointmentData = {
          'id': apt['id'],
          'booking_number': apt['booking_number'],
          'appointment_date': apt['appointment_date'],
          'start_time': apt['start_time'],
          'end_time': apt['end_time'],
          'status': apt['status'],
          'is_vip': apt['is_vip'] ?? false,
          'price': apt['price'] ?? 0.0,
          'queue_number': apt['queue_number'],
          'child_name': apt['child_name'],
          'customer_name': customer?['full_name'] ?? 'Customer',
          'customer_avatar': customer?['avatar_url'],
          'customer_phone': customer?['phone'],
          'service_name': serviceName,
          'salon_name': salonName,
          'local_start_time': localStart,
          'local_end_time': localEnd,
          'date_display': DateFormat('MMM dd, yyyy').format(appointmentDate),
          'day_display': DateFormat('EEEE').format(appointmentDate),
          'time_display': '$localStart - $localEnd',
        };
        
        // Categorize
        if (apt['status'] == 'cancelled' || apt['status'] == 'no_show') {
          pastList.add(appointmentData);
        } else if (appointmentDateOnly.isAtSameMomentAs(today)) {
          todayList.add(appointmentData);
        } else if (appointmentDateOnly.isAfter(today)) {
          upcomingList.add(appointmentData);
        } else {
          pastList.add(appointmentData);
        }
      }
      
      // Sort today's appointments by time
      todayList.sort((a, b) => a['local_start_time'].compareTo(b['local_start_time']));
      upcomingList.sort((a, b) => a['appointment_date'].compareTo(b['appointment_date']));
      pastList.sort((a, b) => b['appointment_date'].compareTo(a['appointment_date']));
      
      if (mounted) {
        setState(() {
          _todayAppointments = todayList;
          _upcomingAppointments = upcomingList;
          _pastAppointments = pastList;
          _isLoading = false;
        });
      }
      
      debugPrint('✅ Loaded ${todayList.length} today, ${upcomingList.length} upcoming, ${pastList.length} past');
      
    } catch (e) {
      debugPrint('❌ Error loading appointments: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load appointments: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  // =====================================================
  // START APPOINTMENT
  // =====================================================
Future<void> _startAppointment(Map<String, dynamic> appointment) async {
  if (_isProcessing) return;
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Start Appointment?'),
      content: Text('Are you ready to start ${appointment['customer_name']}\'s appointment?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
          child: const Text('START NOW'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isProcessing = true);
  
  try {
    // 🔥 Get current UTC time (not local)
    final nowUtc = DateTime.now().toUtc();
    
    await supabase
        .from('appointments')
        .update({
          'status': 'in_progress',
          'actual_start_time': nowUtc.toIso8601String(),  // ✅ UTC time
          'is_started': true,
          'updated_at': nowUtc.toIso8601String(),        // ✅ UTC time
        })
        .eq('id', appointment['id']);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Appointment started!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      await _loadAppointments();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _isProcessing = false);
  }
}
  
  // =====================================================
  // COMPLETE APPOINTMENT
  // =====================================================
Future<void> _completeAppointment(Map<String, dynamic> appointment) async {
  if (_isProcessing) return;
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Complete Appointment?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mark ${appointment['customer_name']}\'s appointment as completed?'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: _primaryColor),
                    const SizedBox(width: 8),
                    Text('Time: ${appointment['local_start_time']}'),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: _primaryColor),
                    const SizedBox(width: 8),
                    Text('Customer: ${appointment['customer_name']}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: _secondaryColor),
          child: const Text('COMPLETE'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isProcessing = true);
  
  try {
    // 🔥 Get current UTC time (not local)
    final nowUtc = DateTime.now().toUtc();
    
    await supabase
        .from('appointments')
        .update({
          'status': 'completed',
          'actual_end_time': nowUtc.toIso8601String(),  // ✅ UTC time
          'is_completed': true,
          'updated_at': nowUtc.toIso8601String(),      // ✅ UTC time
        })
        .eq('id', appointment['id']);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Appointment completed!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      await _loadAppointments();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _isProcessing = false);
  }
}
  
  // =====================================================
  // CANCEL APPOINTMENT
  // =====================================================
  Future<void> _cancelAppointment(Map<String, dynamic> appointment) async {
    if (_isProcessing) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Appointment?'),
        content: Text('Are you sure you want to cancel ${appointment['customer_name']}\'s appointment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('NO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _dangerColor),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isProcessing = true);
    
    try {
      await supabase
          .from('appointments')
          .update({
            'status': 'cancelled',
            'cancel_reason': 'Cancelled by barber',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appointment['id']);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Appointment cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadAppointments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
  // =====================================================
  // SHOW CUSTOMER INFO
  // =====================================================
  Future<void> _showCustomerInfo(Map<String, dynamic> appointment) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _primaryColor.withOpacity(0.1),
                  backgroundImage: appointment['customer_avatar'] != null 
                      ? NetworkImage(appointment['customer_avatar']) 
                      : null,
                  child: appointment['customer_avatar'] == null
                      ? Text(
                          (appointment['customer_name'][0]).toUpperCase(),
                          style: TextStyle(fontSize: 24, color: _primaryColor),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment['customer_name'],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (appointment['customer_phone'] != null)
                        Text(
                          appointment['customer_phone'],
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoTile('Service', appointment['service_name']),
            _buildInfoTile('Time', appointment['time_display']),
            _buildInfoTile('Salon', appointment['salon_name']),
            _buildInfoTile('Price', 'Rs. ${(appointment['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
            if (appointment['child_name'] != null && appointment['child_name'].toString().isNotEmpty)
              _buildInfoTile('Booked For', appointment['child_name']),
            if (appointment['queue_number'] != null)
              _buildInfoTile('Queue Number', '#${appointment['queue_number']}'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('CLOSE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
  
  void _showDatePickerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Select Date'),
        content: SizedBox(
          width: 300,
          height: 350,
          child: CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime.now().subtract(const Duration(days: 30)),
            lastDate: DateTime.now().add(const Duration(days: 60)),
            onDateChanged: (date) {
              Navigator.pop(context);
              setState(() {
                _selectedDate = date;
              });
              _loadAppointments();
            },
          ),
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Appointments'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _showDatePickerDialog,
            tooltip: 'Select Date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAppointments,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.today, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                        onPressed: _loadAppointments,
                        style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Stats summary
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _buildStatCard('Today', _todayAppointments.length, Icons.today, _primaryColor),
                          const SizedBox(width: 12),
                          _buildStatCard('Upcoming', _upcomingAppointments.length, Icons.calendar_month, _warningColor),
                          const SizedBox(width: 12),
                          _buildStatCard('Completed', _pastAppointments.where((a) => a['status'] == 'completed').length, Icons.check_circle, _secondaryColor),
                        ],
                      ),
                    ),
                    // Tab bar
                    TabBar(
                      controller: _tabController,
                      labelColor: _primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: _primaryColor,
                      tabs: const [
                        Tab(text: 'TODAY'),
                        Tab(text: 'UPCOMING'),
                        Tab(text: 'PAST'),
                      ],
                    ),
                    // Tab views
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAppointmentList(_todayAppointments, isToday: true),
                          _buildAppointmentList(_upcomingAppointments, isToday: false),
                          _buildAppointmentList(_pastAppointments, isToday: false),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
  
  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAppointmentList(List<Map<String, dynamic>> appointments, {required bool isToday}) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              isToday ? 'No appointments today' : 'No appointments found',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadAppointments,
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: appointments.length,
        itemBuilder: (context, index) => _buildAppointmentCard(appointments[index], isToday),
      ),
    );
  }
  
  Widget _buildAppointmentCard(Map<String, dynamic> appointment, bool isToday) {
    final status = appointment['status'];
    final isInProgress = status == 'in_progress';
    final isConfirmed = status == 'confirmed' || status == 'pending';
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusText = 'Confirmed';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Pending';
        statusIcon = Icons.pending_outlined;
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        statusText = 'In Progress';
        statusIcon = Icons.play_circle_outline;
        break;
      case 'completed':
        statusColor = Colors.purple;
        statusText = 'Completed';
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Cancelled';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.grey;
        statusText = status;
        statusIcon = Icons.circle_outlined;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isInProgress ? BorderSide(color: Colors.blue, width: 2) : BorderSide.none,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                // Time (Local time already converted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    appointment['local_start_time'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusText, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const Spacer(),
                // Queue number
                if (appointment['queue_number'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Q#${appointment['queue_number']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Customer info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _primaryColor.withOpacity(0.1),
                  backgroundImage: appointment['customer_avatar'] != null
                      ? NetworkImage(appointment['customer_avatar'])
                      : null,
                  child: appointment['customer_avatar'] == null
                      ? Text(
                          (appointment['customer_name'][0]).toUpperCase(),
                          style: TextStyle(fontSize: 16, color: _primaryColor),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment['customer_name'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (appointment['child_name'] != null && appointment['child_name'].toString().isNotEmpty)
                        Text(
                          'Booked for: ${appointment['child_name']}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
                // Customer info button
                IconButton(
                  icon: Icon(Icons.info_outline, color: Colors.grey[500], size: 20),
                  onPressed: () => _showCustomerInfo(appointment),
                  tooltip: 'Customer Info',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Service info
            Row(
              children: [
                Icon(Icons.content_cut, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    appointment['service_name'],
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
                Text(
                  'Rs. ${(appointment['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _primaryColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action buttons
            if (isToday && isConfirmed && !isCancelled && !isCompleted)
              Row(
                children: [
                  if (!isInProgress)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : () => _startAppointment(appointment),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('START'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  if (!isInProgress) const SizedBox(width: 12),
                  if (isInProgress)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : () => _completeAppointment(appointment),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('COMPLETE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  if (!isInProgress && !isCompleted)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : () => _cancelAppointment(appointment),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('CANCEL'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _dangerColor,
                          side: BorderSide(color: _dangerColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                ],
              ),
            if (!isToday && isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _secondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: _secondaryColor),
                      const SizedBox(width: 8),
                      Text('Completed on ${appointment['date_display']}', style: TextStyle(fontSize: 12, color: _secondaryColor)),
                    ],
                  ),
                ),
              ),
            if (!isToday && isCancelled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _dangerColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cancel, size: 16, color: _dangerColor),
                      const SizedBox(width: 8),
                      Text('Cancelled', style: TextStyle(fontSize: 12, color: _dangerColor)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}