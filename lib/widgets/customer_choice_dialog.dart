// lib/widgets/customer_choice_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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

  // ✅ Static show method
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
    return context.colorScheme.surface;
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    final isDesktop = context.isDesktop;
    final isSmall = context.isMobile && context.screenWidth < 400;
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    final dialogWidth = isDesktop ? 500.0 : (isTablet ? 450.0 : 400.0);
    final padding = isTablet ? 24.0 : 20.0;
    final titleSize = isTablet ? 22.0 : 20.0;
    final bodySize = isTablet ? 15.0 : 14.0;
    final optionTitleSize = isTablet ? 17.0 : 16.0;
    final optionSubSize = isTablet ? 13.0 : 12.0;
    final iconSize = isTablet ? 28.0 : 24.0;
    final minCardHeight = isTablet ? 70.0 : 60.0;
    final screenHeight = context.screenHeight;

    final dialogBgColor = _getDialogBackgroundColor(context);

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
        textColor,
        secondaryTextColor,
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
                  color: isDark 
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.orange.shade50,
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
                  color: textColor,
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
                  color: textColor,
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
                  color: secondaryTextColor,
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
                  isDark: isDark,
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
                isDark: isDark,
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
                isDark: isDark,
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
                  border: isDark
                      ? Border.all(color: Colors.grey[800]!, width: 0.5)
                      : null,
                ),
                child: Text(
                  'You will be notified once your choice is processed',
                  style: TextStyle(
                    fontSize: isTablet ? 13 : 12,
                    color: secondaryTextColor,
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
    Color textColor,
    Color secondaryTextColor,
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
            border: isDark
                ? Border.all(color: Colors.grey[800]!, width: 0.5)
                : null,
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
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Warning Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.orange.shade50,
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
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Message
                Text(
                  'Dear ${widget.customerName},',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
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
                    color: secondaryTextColor,
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
                    isDark: isDark,
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
                  isDark: isDark,
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
                  isDark: isDark,
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
                    border: isDark
                        ? Border.all(color: Colors.grey[800]!, width: 0.5)
                        : null,
                  ),
                  child: Text(
                    'You will be notified once your choice is processed',
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                    ),
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
    required bool isDark,
    required double optionTitleSize,
    required double optionSubSize,
    required double iconSize,
    required double minHeight,
  }) {
    final secondaryTextColor = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6) ?? Colors.grey[600];

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
            color: isDark 
                ? color.withValues(alpha: 0.08)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
            border: Border.all(
              color: isDark 
                  ? color.withValues(alpha: 0.4)
                  : color.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isTablet ? 10 : 8),
                decoration: BoxDecoration(
                  color: isDark 
                      ? color.withValues(alpha: 0.15)
                      : color.withValues(alpha: 0.1),
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
                        color: isDark ? Colors.white : color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: optionSubSize,
                        color: isDark ? Colors.white60 : secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: isTablet ? 18 : 16,
                color: isDark ? color.withValues(alpha: 0.5) : color.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}