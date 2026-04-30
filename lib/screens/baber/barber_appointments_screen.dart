// lib/screens/barber/barber_appointments_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  
  bool _isLoading = true;
  String? _error;
  String? _barberName;
  String? _barberAvatar;
  
  // Tab controller
  late TabController _tabController;
  
  // Date selection
  DateTime _selectedDate = DateTime.now();
  bool _showDatePicker = false;
  
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
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      
      if (profile != null && mounted) {
        setState(() {
          _barberName = profile['full_name'] ?? 'Barber';
          _barberAvatar = profile['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint('Error loading barber data: $e');
    }
  }
  
// Replace your existing _loadAppointments function with this
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
    
    // Query with proper foreign key relationships
    final response = await supabase
        .from('appointments')
        .select('''
          *,
          customers:profiles!appointments_customer_id_fkey (
            id,
            full_name,
            avatar_url,
            phone
          ),
          services (
            id,
            name
          ),
          service_variants (
            id,
            price,
            duration,
            salon_genders!left (
              display_name
            ),
            salon_age_categories!left (
              display_name
            )
          ),
          salons (
            id,
            name,
            address,
            phone
          )
        ''')
        .eq('barber_id', user.id)
        .order('appointment_date', ascending: true)
        .order('start_time', ascending: true);
    
    final List<Map<String, dynamic>> allAppointments = List<Map<String, dynamic>>.from(response);
    final List<Map<String, dynamic>> processedAppointments = [];
    
    for (var apt in allAppointments) {
      final customer = apt['customers'] as Map<String, dynamic>?;
      final service = apt['services'] as Map<String, dynamic>?;
      final variant = apt['service_variants'] as Map<String, dynamic>?;
      final salon = apt['salons'] as Map<String, dynamic>?;
      
      // Build service name
      String serviceName = service?['name'] ?? 'Service';
      if (variant != null) {
        final gender = variant['salon_genders'] as Map<String, dynamic>?;
        final age = variant['salon_age_categories'] as Map<String, dynamic>?;
        if (gender?['display_name'] != null) serviceName = '${gender!['display_name']} $serviceName';
        if (age?['display_name'] != null) serviceName = '$serviceName (${age!['display_name']})';
      }
      
      final appointmentDate = DateTime.parse(apt['appointment_date']);
      final utcStart = apt['start_time'] as String;
      final utcEnd = apt['end_time'] as String;
      
      processedAppointments.add({
        ...apt,
        'customers': customer,
        'services': service,
        'service_variants': variant,
        'salons': salon,
        'service_name': serviceName,
        'customer_name': customer?['full_name'] ?? 'Customer',
        'customer_avatar': customer?['avatar_url'],
        'customer_phone': customer?['phone'],
        'salon_name': salon?['name'] ?? 'Salon',
        'local_start_time': _formatTime(utcStart),
        'local_end_time': _formatTime(utcEnd),
        'date_display': DateFormat('MMM dd, yyyy').format(appointmentDate),
        'day_display': DateFormat('EEEE').format(appointmentDate),
      });
    }
    
    // Categorize by date
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayList = <Map<String, dynamic>>[];
    final upcomingList = <Map<String, dynamic>>[];
    final pastList = <Map<String, dynamic>>[];
    
    for (var apt in processedAppointments) {
      final aptDate = DateTime.parse(apt['appointment_date']);
      final aptDateOnly = DateTime(aptDate.year, aptDate.month, aptDate.day);
      
      if (apt['status'] == 'cancelled') {
        pastList.add(apt);
      } else if (aptDateOnly.isAtSameMomentAs(today)) {
        todayList.add(apt);
      } else if (aptDateOnly.isAfter(today)) {
        upcomingList.add(apt);
      } else {
        pastList.add(apt);
      }
    }
    
    todayList.sort((a, b) => a['local_start_time'].compareTo(b['local_start_time']));
    
    if (mounted) {
      setState(() {
        _todayAppointments = todayList;
        _upcomingAppointments = upcomingList;
        _pastAppointments = pastList;
        _isLoading = false;
      });
    }
    
  } catch (e) {
    debugPrint('Error loading appointments: $e');
    if (mounted) {
      setState(() {
        _error = 'Failed to load appointments: $e';
        _isLoading = false;
      });
    }
  }
}

String _formatTime(String time) {
  if (time.isEmpty) return '--:--';
  final parts = time.split(':');
  if (parts.length >= 2) {
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }
  return time;
}


  
  
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
      final now = DateTime.now();
      final result = await supabase
          .from('appointments')
          .update({
            'status': 'in_progress',
            'actual_start_time': now.toIso8601String(),
            'is_started': true,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', appointment['id'])
          .select();
      
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Appointment started!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        await _loadAppointments();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
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
                      Text('Started: ${appointment['local_start_time']}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.timer, size: 16, color: _primaryColor),
                      const SizedBox(width: 8),
                      Text('Duration: ${appointment['service_variants']?['duration'] ?? 30} min'),
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
      final now = DateTime.now();
      final result = await supabase
          .from('appointments')
          .update({
            'status': 'completed',
            'actual_end_time': now.toIso8601String(),
            'is_completed': true,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', appointment['id'])
          .select();
      
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Appointment completed!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        await _loadAppointments();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
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
      final result = await supabase
          .from('appointments')
          .update({
            'status': 'cancelled',
            'cancel_reason': 'Cancelled by barber',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appointment['id'])
          .select();
      
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Appointment cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadAppointments();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
  Future<void> _showCustomerInfo(Map<String, dynamic> appointment) async {
    final customer = appointment['customers'] as Map<String, dynamic>?;
    if (customer == null) return;
    
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
                  backgroundImage: customer['avatar_url'] != null 
                      ? NetworkImage(customer['avatar_url']) 
                      : null,
                  child: customer['avatar_url'] == null
                      ? Text(
                          (customer['full_name'] ?? 'C')[0].toUpperCase(),
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
                        customer['full_name'] ?? 'Customer',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (customer['phone'] != null)
                        Text(
                          customer['phone'],
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
            _buildInfoTile('Duration', '${appointment['service_variants']?['duration'] ?? 30} minutes'),
            _buildInfoTile('Price', 'Rs. ${(appointment['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
            if (appointment['child_name'] != null && appointment['child_name'].toString().isNotEmpty)
              _buildInfoTile('Booked For', appointment['child_name']),
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
          // Date picker button
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
                    Container(
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
                // Time
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