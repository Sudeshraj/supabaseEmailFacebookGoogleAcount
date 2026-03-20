// screens/barber/queue_management_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QueueManagementScreen extends StatefulWidget {
  final String barberId;

  const QueueManagementScreen({super.key, required this.barberId});

  @override
  State<QueueManagementScreen> createState() => _QueueManagementScreenState();
}

class _QueueManagementScreenState extends State<QueueManagementScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _queue = [];
  Map<String, dynamic>? _currentAppointment;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _subscribeToQueue();
  }

  Future<void> _loadQueue() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // 🔥 FIX 1: Remove .in_() and use multiple status conditions
      final response = await supabase
          .from('appointments')
          .select('''
          id,
          queue_number,
          queue_token,
          status,
          start_time,
          end_time,
          customer_id,
          service_id,
          variant_id,
          services (
            name
          ),
          service_variants (
            price,
            duration,
            genders (
              display_name
            ),
            age_categories (
              display_name
            )
          ),
          profiles!customer_id (
            full_name,
            avatar_url
          )
        ''')
          .eq('barber_id', widget.barberId)
          .eq('appointment_date', today)
          .or('status.eq.pending,status.eq.in_progress')
          .order('queue_number');

      _queue = List<Map<String, dynamic>>.from(response);

      // 🔥 FIX 2: Fix firstWhere orElse return type
      _currentAppointment = _queue.firstWhere(
        (a) => a['status'] == 'in_progress',
        orElse: () => <String, dynamic>{}, // Return empty map instead of null
      );

      // If empty map, set to null
      if (_currentAppointment?.isEmpty ?? true) {
        _currentAppointment = null;
      }
    } catch (e) {
      debugPrint('❌ Error loading queue: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToQueue() {
    supabase
        .channel('queue_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          callback: (payload) {
            _loadQueue();
          },
        )
        .subscribe();
  }

  Future<void> _confirmAppointment(int appointmentId, String queueToken) async {
    try {
      await supabase
          .from('appointments')
          .update({
            'status': 'in_progress',
            'actual_start_time': DateTime.now().toIso8601String(),
          })
          .eq('id', appointmentId)
          .eq('queue_token', queueToken);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service started'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error confirming appointment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _completeAppointment(int appointmentId) async {
    try {
      await supabase
          .from('appointments')
          .update({
            'status': 'completed',
            'actual_end_time': DateTime.now().toIso8601String(),
          })
          .eq('id', appointmentId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service completed'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error completing appointment: $e');
    }
  }

  Future<void> _showConfirmDialog(Map<String, dynamic> appointment) async {
    final tokenController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Appointment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Queue #${appointment['queue_number']}'),
            const SizedBox(height: 8),
            Text(
              appointment['profiles']['full_name'] ?? 'Customer',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: tokenController,
              decoration: InputDecoration(
                labelText: 'Enter Queue Token',
                hintText: appointment['queue_token'],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
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
              if (tokenController.text == appointment['queue_token']) {
                Navigator.pop(context);
                _confirmAppointment(
                  appointment['id'],
                  appointment['queue_token'],
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid token'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue Management'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : _queue.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.queue, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No appointments in queue',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_currentAppointment != null) _buildCurrentAppointment(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _queue.length,
                    itemBuilder: (context, index) {
                      final appointment = _queue[index];
                      if (appointment['status'] == 'in_progress') {
                        return const SizedBox.shrink();
                      }
                      return _buildQueueItem(appointment);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCurrentAppointment() {
    final appointment = _currentAppointment!;
    final variant = appointment['service_variants'];

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'CURRENT SERVICE',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.green.shade100,
                backgroundImage: appointment['profiles']['avatar_url'] != null
                    ? NetworkImage(appointment['profiles']['avatar_url'])
                    : null,
                child: appointment['profiles']['avatar_url'] == null
                    ? Text(
                        appointment['profiles']['full_name'][0].toUpperCase(),
                        style: const TextStyle(color: Colors.green),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment['profiles']['full_name'] ?? 'Customer',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${appointment['services']['name']} - ${variant['genders']['display_name']} ${variant['age_categories']['display_name']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _completeAppointment(appointment['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Complete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueItem(Map<String, dynamic> appointment) {
    final variant = appointment['service_variants'];
    final isNext =
        _queue.indexOf(appointment) == 0 && _currentAppointment == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isNext ? const Color(0xFFFF6B8B) : Colors.transparent,
          width: isNext ? 2 : 0,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isNext
                ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '#${appointment['queue_number']}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isNext ? const Color(0xFFFF6B8B) : Colors.grey,
              ),
            ),
          ),
        ),
        title: Text(appointment['profiles']['full_name'] ?? 'Customer'),
        subtitle: Text(
          '${appointment['services']['name']} • ${variant['genders']['display_name']} ${variant['age_categories']['display_name']}',
        ),
        trailing: isNext
            ? ElevatedButton(
                onPressed: () => _showConfirmDialog(appointment),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Start'),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Waiting',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
      ),
    );
  }
}
