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

  // ✅ Static show method - මෙතනට ගෙනියන්න
  static Future<void> show(
    BuildContext context, {
    required String customerName,
    required String appointmentDate,
    required String appointmentTime,
    required String serviceName,
    Map<String, dynamic>? availableBarber,
    required VoidCallback onAcceptNewBarber,
    required VoidCallback onMoveToNextDay,
    required VoidCallback onCancel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomerChoiceDialog(
        customerName: customerName,
        appointmentDate: appointmentDate,
        appointmentTime: appointmentTime,
        serviceName: serviceName,
        availableBarber: availableBarber,
        onAcceptNewBarber: onAcceptNewBarber,
        onMoveToNextDay: onMoveToNextDay,
        onCancel: onCancel,
      ),
    );
  }

  @override
  State<CustomerChoiceDialog> createState() => _CustomerChoiceDialogState();
}

class _CustomerChoiceDialogState extends State<CustomerChoiceDialog> {
  // ✅ Helper method for dialog background color
  Color _getDialogBackgroundColor(BuildContext context) {
    final dialogTheme = DialogTheme.of(context);
    if (dialogTheme.backgroundColor != null) {
      return dialogTheme.backgroundColor!;
    }
    return Theme.of(context).colorScheme.surface;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final isDesktop = screenWidth >= 1200;
    final isSmall = screenWidth < 400;

    final dialogWidth = isDesktop ? 500.0 : (isTablet ? 450.0 : 400.0);
    final padding = isTablet ? 24.0 : 20.0;
    final titleSize = isTablet ? 22.0 : 20.0;
    final bodySize = isTablet ? 15.0 : 14.0;
    final optionTitleSize = isTablet ? 17.0 : 16.0;
    final optionSubSize = isTablet ? 13.0 : 12.0;
    final iconSize = isTablet ? 28.0 : 24.0;
    final minCardHeight = isTablet ? 70.0 : 60.0;
    final screenHeight = MediaQuery.of(context).size.height;

    final dialogBgColor = _getDialogBackgroundColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isSmall) {
      return _buildBottomSheet(
        context,
        padding,
        titleSize,
        bodySize,
        optionTitleSize,
        optionSubSize,
        iconSize,
        minCardHeight,
        dialogBgColor,
        isDark,
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
      ),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
        ),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: dialogBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon
              Container(
                padding: EdgeInsets.all(isTablet ? 20 : 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: isTablet ? 56 : 48,
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),

              // Title
              Text(
                'Appointment Update Required',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isTablet ? 10 : 8),

              // Message
              Text(
                'Dear ${widget.customerName},',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: bodySize,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isTablet ? 10 : 8),
              Text(
                'Your appointment for ${widget.serviceName} on '
                '${widget.appointmentDate} at ${widget.appointmentTime} '
                'has been affected due to barber unavailability.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: bodySize,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),

              // Options
              if (widget.availableBarber != null) ...[
                _buildOptionCard(
                  icon: Icons.person_add,
                  color: Colors.green,
                  title: 'Accept Alternative Barber',
                  subtitle: '${widget.availableBarber!['name']} will serve you',
                  onTap: widget.onAcceptNewBarber,
                  isTablet: isTablet,
                  optionTitleSize: optionTitleSize,
                  optionSubSize: optionSubSize,
                  iconSize: iconSize,
                  minHeight: minCardHeight,
                ),
                SizedBox(height: isTablet ? 10 : 8),
              ],

              _buildOptionCard(
                icon: Icons.today,
                color: Colors.blue,
                title: 'Move to Tomorrow',
                subtitle: 'Get Queue #1 priority tomorrow morning',
                onTap: widget.onMoveToNextDay,
                isTablet: isTablet,
                optionTitleSize: optionTitleSize,
                optionSubSize: optionSubSize,
                iconSize: iconSize,
                minHeight: minCardHeight,
              ),
              SizedBox(height: isTablet ? 10 : 8),

              _buildOptionCard(
                icon: Icons.cancel,
                color: Colors.red,
                title: 'Cancel Appointment',
                subtitle: 'No penalty, book again later',
                onTap: widget.onCancel,
                isTablet: isTablet,
                optionTitleSize: optionTitleSize,
                optionSubSize: optionSubSize,
                iconSize: iconSize,
                minHeight: minCardHeight,
              ),
              SizedBox(height: isTablet ? 20 : 16),

              // Note
              Container(
                padding: EdgeInsets.all(isTablet ? 14 : 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.withValues(alpha: 0.1)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                ),
                child: Text(
                  'You will be notified once your choice is processed',
                  style: TextStyle(
                    fontSize: isTablet ? 13 : 12,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet(
    BuildContext context,
    double padding,
    double titleSize,
    double bodySize,
    double optionTitleSize,
    double optionSubSize,
    double iconSize,
    double minHeight,
    Color dialogBgColor,
    bool isDark,
  ) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: dialogBgColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
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
                Text(
                  'Appointment Update Required',
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Message
                Text(
                  'Dear ${widget.customerName},',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your appointment for ${widget.serviceName} on '
                  '${widget.appointmentDate} at ${widget.appointmentTime} '
                  'has been affected due to barber unavailability.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: bodySize,
                    color: Colors.grey[600],
                  ),
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
                    isTablet: false,
                    optionTitleSize: optionTitleSize,
                    optionSubSize: optionSubSize,
                    iconSize: iconSize,
                    minHeight: minHeight,
                  ),
                  const SizedBox(height: 8),
                ],

                _buildOptionCard(
                  icon: Icons.today,
                  color: Colors.blue,
                  title: 'Move to Tomorrow',
                  subtitle: 'Get Queue #1 priority tomorrow morning',
                  onTap: widget.onMoveToNextDay,
                  isTablet: false,
                  optionTitleSize: optionTitleSize,
                  optionSubSize: optionSubSize,
                  iconSize: iconSize,
                  minHeight: minHeight,
                ),
                const SizedBox(height: 8),

                _buildOptionCard(
                  icon: Icons.cancel,
                  color: Colors.red,
                  title: 'Cancel Appointment',
                  subtitle: 'No penalty, book again later',
                  onTap: widget.onCancel,
                  isTablet: false,
                  optionTitleSize: optionTitleSize,
                  optionSubSize: optionSubSize,
                  iconSize: iconSize,
                  minHeight: minHeight,
                ),
                const SizedBox(height: 16),

                // Note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey.withValues(alpha: 0.1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'You will be notified once your choice is processed',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isTablet,
    required double optionTitleSize,
    required double optionSubSize,
    required double iconSize,
    required double minHeight,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
          constraints: BoxConstraints(
            minHeight: minHeight,
          ),
          padding: EdgeInsets.all(isTablet ? 18 : 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isTablet ? 10 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: iconSize,
                ),
              ),
              SizedBox(width: isTablet ? 18 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: optionTitleSize,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: optionSubSize,
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: isTablet ? 18 : 16,
                color: color.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}