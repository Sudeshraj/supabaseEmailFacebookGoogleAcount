import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

// ==================== ENHANCED TIME PICKER ====================
class EnhancedTimePicker extends StatefulWidget {
  final TimeOfDay? initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;

  const EnhancedTimePicker({
    super.key,
    required this.initialTime,
    required this.onTimeSelected,
  });

  @override
  State<EnhancedTimePicker> createState() => _EnhancedTimePickerState();
}

class _EnhancedTimePickerState extends State<EnhancedTimePicker> {
  late int _selectedHour;
  late int _selectedMinute;
  late String _selectedPeriod;

  final List<int> hours12 = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  final List<int> minutes = List.generate(60, (i) => i);
  final List<String> periods = ['AM', 'PM'];

  @override
  void initState() {
    super.initState();
    _initializeTime();
  }

  void _initializeTime() {
    if (widget.initialTime != null) {
      final hour24 = widget.initialTime!.hour;
      final minute = widget.initialTime!.minute;

      if (hour24 == 0) {
        _selectedHour = 12;
        _selectedPeriod = 'AM';
      } else if (hour24 == 12) {
        _selectedHour = 12;
        _selectedPeriod = 'PM';
      } else if (hour24 > 12) {
        _selectedHour = hour24 - 12;
        _selectedPeriod = 'PM';
      } else {
        _selectedHour = hour24;
        _selectedPeriod = 'AM';
      }
      _selectedMinute = minute;
    } else {
      final now = TimeOfDay.now();
      final hour24 = now.hour;
      if (hour24 == 0) {
        _selectedHour = 12;
        _selectedPeriod = 'AM';
      } else if (hour24 == 12) {
        _selectedHour = 12;
        _selectedPeriod = 'PM';
      } else if (hour24 > 12) {
        _selectedHour = hour24 - 12;
        _selectedPeriod = 'PM';
      } else {
        _selectedHour = hour24;
        _selectedPeriod = 'AM';
      }
      _selectedMinute = now.minute;
    }
  }

  void _confirmTime() {
    int hour24;
    if (_selectedPeriod == 'AM') {
      hour24 = _selectedHour == 12 ? 0 : _selectedHour;
    } else {
      hour24 = _selectedHour == 12 ? 12 : _selectedHour + 12;
    }

    final selectedTime = TimeOfDay(hour: hour24, minute: _selectedMinute);
    widget.onTimeSelected(selectedTime);
    Navigator.of(context).pop(selectedTime);
  }

  void _cancelTime() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isMobile = context.isMobile;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 320,
          // ✅ Cap the dialog height to a fraction of the screen. This is
          // just an upper bound now - the content below is fully
          // scrollable, so however small the *actual* available height
          // ends up being (even down to a few dozen pixels, as can happen
          // in some embedded/preview hosts), the dialog scrolls instead of
          // tripping a RenderFlex overflow assertion.
          maxHeight: screenHeight * 0.85,
        ),
        // ✅ The ENTIRE dialog body - title, time display, scroll wheels,
        // AND the Cancel/OK buttons - now lives inside one
        // SingleChildScrollView. Previously only the middle section
        // scrolled while the title/buttons stayed fixed outside it, which
        // still overflowed when the host gave the dialog very little
        // height (e.g. constraints h<=62). Making the whole thing
        // scrollable means there is no fixed-size Column being forced
        // into a space smaller than its natural size, so it can never
        // overflow - worst case the user scrolls a little to see the
        // buttons.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Time',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _selectedHour.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      ':',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.primary,
                      ),
                    ),
                    Text(
                      _selectedMinute.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _selectedPeriod,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  _buildScrollPicker(
                    title: 'HOUR',
                    items: hours12,
                    selectedValue: _selectedHour,
                    onChanged: (value) => setState(() => _selectedHour = value),
                  ),
                  const SizedBox(width: 12),
                  _buildScrollPicker(
                    title: 'MINUTE',
                    items: minutes,
                    selectedValue: _selectedMinute,
                    onChanged: (value) => setState(() => _selectedMinute = value),
                  ),
                  const SizedBox(width: 12),
                  _buildScrollPicker(
                    title: 'PERIOD',
                    items: periods,
                    selectedValue: _selectedPeriod,
                    onChanged: (value) => setState(() => _selectedPeriod = value),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _cancelTime,
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.white60 : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmTime,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollPicker<T>({
    required String title,
    required List<T> items,
    required T selectedValue,
    required ValueChanged<T> onChanged,
  }) {
    final isDark = context.isDarkMode;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListWheelScrollView.useDelegate(
              itemExtent: 40,
              onSelectedItemChanged: (newIndex) {
                if (newIndex >= 0 && newIndex < items.length) {
                  onChanged(items[newIndex]);
                }
              },
              childDelegate: ListWheelChildBuilderDelegate(
                builder: (context, i) {
                  final item = items[i];
                  final isSelected = item == selectedValue;
                  return Container(
                    alignment: Alignment.center,
                    child: Text(
                      item.toString(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.white70 : Colors.grey[800]),
                      ),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== TIME PICKER FIELD ====================
class TimePickerField extends StatefulWidget {
  final String label;
  final TimeOfDay? initialTime;
  final ValueChanged<TimeOfDay> onTimeSelected;
  final bool isRequired;

  const TimePickerField({
    super.key,
    required this.label,
    this.initialTime,
    required this.onTimeSelected,
    this.isRequired = true,
  });

  @override
  State<TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<TimePickerField> {
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  String _formatTimeForDisplay(TimeOfDay time) {
    final hour = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Future<void> _showTimePicker() async {
    final result = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) => EnhancedTimePicker(
        initialTime: _selectedTime,
        onTimeSelected: (time) {},
      ),
    );

    if (result != null) {
      setState(() {
        _selectedTime = result;
      });
      widget.onTimeSelected(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final accentColor = AppTheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showTimePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: _selectedTime != null ? accentColor : Colors.grey[400],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedTime != null
                        ? _formatTimeForDisplay(_selectedTime!)
                        : 'Select time',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _selectedTime != null
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark ? Colors.white70 : Colors.grey[500]),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: isDark ? Colors.white70 : Colors.grey,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}