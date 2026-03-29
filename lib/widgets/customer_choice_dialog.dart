// lib/widgets/customer_choice_dialog.dart
import 'package:flutter/material.dart';

class CustomerChoiceDialog extends StatefulWidget {
  final String customerName;
  final String appointmentDate;
  final String appointmentTime;
  final String serviceName;
  final Map<String, dynamic>? availableBarber;
  final VoidCallback onAcceptNewBarber;
  final VoidCallback onMoveToNextDay;
  final VoidCallback onCancel;

  const CustomerChoiceDialog({
    super.key,
    required this.customerName,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.serviceName,
    this.availableBarber,
    required this.onAcceptNewBarber,
    required this.onMoveToNextDay,
    required this.onCancel,
  });

  @override
  State<CustomerChoiceDialog> createState() => _CustomerChoiceDialogState();
}

class _CustomerChoiceDialogState extends State<CustomerChoiceDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Appointment Update Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Message
            Text(
              'Dear ${widget.customerName},',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment for ${widget.serviceName} on '
              '${widget.appointmentDate} at ${widget.appointmentTime} '
              'has been affected due to barber unavailability.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Options
            if (widget.availableBarber != null) ...[
              _buildOptionCard(
                icon: Icons.person_add,
                color: Colors.green,
                title: 'Accept Alternative Barber',
                subtitle: '${widget.availableBarber!['name']} will serve you',
                onTap: widget.onAcceptNewBarber,
              ),
              const SizedBox(height: 8),
            ],

            _buildOptionCard(
              icon: Icons.today,
              color: Colors.blue,
              title: 'Move to Tomorrow',
              subtitle: 'Get Queue #1 priority tomorrow morning',
              onTap: widget.onMoveToNextDay,
            ),
            const SizedBox(height: 8),

            _buildOptionCard(
              icon: Icons.cancel,
              color: Colors.red,
              title: 'Cancel Appointment',
              subtitle: 'No penalty, book again later',
              onTap: widget.onCancel,
            ),
            const SizedBox(height: 16),

            // Note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'You will be notified once your choice is processed',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}