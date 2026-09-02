import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../services/timezone_service.dart';
import '../../utils/image_compression.dart';

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

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isMobile ? double.infinity : 320,
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
            const SizedBox(height: 20),

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
            const SizedBox(height: 20),

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

            const SizedBox(height: 24),

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

// ==================== MAIN CREATE SALON SCREEN ====================
class CreateSalonScreen extends StatefulWidget {
  const CreateSalonScreen({super.key});

  @override
  State<CreateSalonScreen> createState() => _CreateSalonScreenState();
}

class _CreateSalonScreenState extends State<CreateSalonScreen> {
  // Basic info controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Validation flags
  bool _isPhoneValid = true;
  bool _isEmailValid = true;
  bool _isMinAgeValid = true;
  bool _isMaxAgeValid = true;
  bool _isAgeRangeValid = true;

  // Genders
  List<Map<String, dynamic>> _globalGenders = [];
  final List<int> _selectedGenderIds = [];

  // Age Categories
  final List<Map<String, dynamic>> _addedAgeCategories = [];
  final TextEditingController _ageCategoryDisplayNameController =
      TextEditingController();
  final TextEditingController _ageCategoryMinAgeController =
      TextEditingController();
  final TextEditingController _ageCategoryMaxAgeController =
      TextEditingController();
  List<Map<String, dynamic>> _globalAgeCategories = [];

  // Service Categories
  final List<Map<String, dynamic>> _addedServiceCategories = [];
  final TextEditingController _serviceCategoryDisplayNameController =
      TextEditingController();
  final TextEditingController _serviceCategoryDescriptionController =
      TextEditingController();
  String _selectedIcon = 'content_cut';
  Color _selectedColor = AppTheme.primary;
  List<Map<String, dynamic>> _globalCategories = [];

  final List<Map<String, dynamic>> _iconList = [
    {'name': 'face', 'icon': Icons.face, 'label': 'Face'},
    {
      'name': 'face_retouching_natural',
      'icon': Icons.face_retouching_natural,
      'label': 'Beard',
    },
    {'name': 'spa', 'icon': Icons.spa, 'label': 'Spa'},
    {'name': 'handshake', 'icon': Icons.handshake, 'label': 'Nails'},
    {'name': 'palette', 'icon': Icons.palette, 'label': 'Makeup'},
    {'name': 'shower', 'icon': Icons.shower, 'label': 'Shower'},
    {'name': 'masks', 'icon': Icons.masks, 'label': 'Masks'},
    {'name': 'spa_outlined', 'icon': Icons.spa_outlined, 'label': 'Wellness'},
  ];

  // Images
  File? _logoFile;
  Uint8List? _logoWebBytes;
  File? _coverFile;
  Uint8List? _coverWebBytes;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  // ==================== TIMEZONE RELATED VARIABLES ====================
  String _openTimeUtc = '';
  String _closeTimeUtc = '';
  TimeOfDay _openTimeLocal = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closeTimeLocal = const TimeOfDay(hour: 18, minute: 0);
  String _userTimezone = '';
  String _salonTimezone = '';
  bool _isTimezoneLoaded = false;
  bool _isLoadingGlobalData = false;
  bool _hasErrorLoadingData = false;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  late bool _isWeb;
  late bool _isDark;

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  String _getTimezoneDisplay() {
    if (_salonTimezone.isEmpty) {
      return 'Loading timezone...';
    }
    return TimezoneService.getFullTimezoneDisplay();
  }

  @override
  void initState() {
    super.initState();
    _ageCategoryMinAgeController.text = '0';
    _ageCategoryMaxAgeController.text = '100';
    _initializeWithTimezone();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTimezoneChanges();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;
  }

  Future<void> _checkTimezoneChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString('user_timezone') ??
        TimezoneService.getCurrentTimezone();

    if (_userTimezone.isNotEmpty && _userTimezone != currentTimezone) {
      setState(() {
        _userTimezone = currentTimezone;
        _refreshDisplayTimes();
      });
    }
  }

  void _refreshDisplayTimes() {
    if (_openTimeUtc.isNotEmpty) {
      _openTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _openTimeUtc,
        _salonTimezone,
      );
      _closeTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _closeTimeUtc,
        _salonTimezone,
      );
    }
    setState(() {});
  }

  Future<void> _initializeWithTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    String cachedUserTimezone = prefs.getString('user_timezone') ?? '';

    if (cachedUserTimezone.isEmpty) {
      _userTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString('user_timezone', _userTimezone);
    } else {
      _userTimezone = cachedUserTimezone;
      await TimezoneService.setTimezone(_userTimezone);
    }

    _salonTimezone = _userTimezone;
    _initializeBusinessHours();

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadGlobalData();
  }

  void _initializeBusinessHours() {
    const defaultOpenLocal = TimeOfDay(hour: 9, minute: 0);
    const defaultCloseLocal = TimeOfDay(hour: 18, minute: 0);

    _openTimeLocal = defaultOpenLocal;
    _closeTimeLocal = defaultCloseLocal;

    _openTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
      defaultOpenLocal,
      _salonTimezone,
    );
    _closeTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
      defaultCloseLocal,
      _salonTimezone,
    );

    debugPrint('✅ Business hours initialized: Local=${_openTimeLocal.format(context)} - ${_closeTimeLocal.format(context)}');
    debugPrint('✅ UTC hours for DB: $_openTimeUtc - $_closeTimeUtc');
    debugPrint('✅ Salon timezone: $_salonTimezone');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    _ageCategoryDisplayNameController.dispose();
    _ageCategoryMinAgeController.dispose();
    _ageCategoryMaxAgeController.dispose();
    _serviceCategoryDisplayNameController.dispose();
    _serviceCategoryDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalData() async {
    setState(() {
      _isLoadingGlobalData = true;
      _hasErrorLoadingData = false;
    });

    try {
      final genders = await supabase
          .from('genders')
          .select('id, display_name, display_order')
          .eq('is_active', true)
          .order('display_order')
          .timeout(const Duration(seconds: 15));

      final ageCategories = await supabase
          .from('age_categories')
          .select('id, display_name, min_age, max_age, display_order')
          .eq('is_active', true)
          .order('display_order')
          .timeout(const Duration(seconds: 15));

      final categories = await supabase
          .from('categories')
          .select(
            'id, display_name, description, icon_name, color, display_order',
          )
          .eq('is_active', true)
          .order('display_order')
          .timeout(const Duration(seconds: 15));

      setState(() {
        _globalGenders = List<Map<String, dynamic>>.from(genders);
        _globalAgeCategories = List<Map<String, dynamic>>.from(ageCategories);
        _globalCategories = List<Map<String, dynamic>>.from(categories);
        _hasErrorLoadingData = false;
      });
    } catch (e) {
      setState(() {
        _hasErrorLoadingData = true;
      });
      if (mounted) {
        _showSnackBar(
          'Failed to load data. Please check your internet connection.',
          Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGlobalData = false;
        });
      }
    }
  }

  // ==================== VALIDATION ====================
  void _validatePhone(String value) {
    setState(() {
      if (value.isEmpty) {
        _isPhoneValid = true;
      } else {
        final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned.length >= 9 &&
            cleaned.length <= 10 &&
            cleaned.startsWith('0')) {
          _isPhoneValid = true;
        } else {
          _isPhoneValid = false;
        }
      }
    });
  }

  void _validateEmail(String value) {
    setState(() {
      if (value.isEmpty) {
        _isEmailValid = true;
      } else {
        final emailRegex = RegExp(
          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        );
        _isEmailValid = emailRegex.hasMatch(value);
      }
    });
  }

  void _validateAgeFields() {
    setState(() {
      final minAgeStr = _ageCategoryMinAgeController.text.trim();
      if (minAgeStr.isEmpty) {
        _isMinAgeValid = true;
      } else {
        final minAge = int.tryParse(minAgeStr);
        _isMinAgeValid = minAge != null && minAge >= 0 && minAge <= 150;
      }

      final maxAgeStr = _ageCategoryMaxAgeController.text.trim();
      if (maxAgeStr.isEmpty) {
        _isMaxAgeValid = true;
      } else {
        final maxAge = int.tryParse(maxAgeStr);
        _isMaxAgeValid = maxAge != null && maxAge >= 0 && maxAge <= 150;
      }

      final minAge = int.tryParse(_ageCategoryMinAgeController.text.trim());
      final maxAge = int.tryParse(_ageCategoryMaxAgeController.text.trim());

      if (minAge != null && maxAge != null) {
        _isAgeRangeValid = minAge <= maxAge;
      } else {
        _isAgeRangeValid = true;
      }
    });
  }

  // ==================== AGE CATEGORY ====================
  void _autoFillAgeCategory(Map<String, dynamic> selected) {
    setState(() {
      _ageCategoryDisplayNameController.text =
          selected['display_name']?.toString() ?? '';
      _ageCategoryMinAgeController.text = (selected['min_age'] ?? 0).toString();
      _ageCategoryMaxAgeController.text = (selected['max_age'] ?? 100)
          .toString();
      _validateAgeFields();
    });
  }

  void _addAgeCategory() {
    _validateAgeFields();

    final displayName = _ageCategoryDisplayNameController.text.trim();
    final minAgeStr = _ageCategoryMinAgeController.text.trim();
    final maxAgeStr = _ageCategoryMaxAgeController.text.trim();
    final minAge = int.tryParse(minAgeStr);
    final maxAge = int.tryParse(maxAgeStr);

    if (displayName.isEmpty) {
      _showSnackBar('Age category display name is required', Colors.orange);
      return;
    }

    if (minAgeStr.isEmpty || maxAgeStr.isEmpty) {
      _showSnackBar('Both min age and max age are required', Colors.orange);
      return;
    }

    if (minAge == null || maxAge == null) {
      _showSnackBar('Please enter valid numbers for age range', Colors.orange);
      return;
    }

    if (minAge < 0 || minAge > 150 || maxAge < 0 || maxAge > 150) {
      _showSnackBar('Age must be between 0 and 150', Colors.orange);
      return;
    }

    if (minAge > maxAge) {
      _showSnackBar('Min age cannot be greater than max age', Colors.orange);
      return;
    }

    if (_addedAgeCategories.any((a) => a['display_name'] == displayName)) {
      _showSnackBar('This age category is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedAgeCategories.add({
        'display_name': displayName,
        'min_age': minAge,
        'max_age': maxAge,
        'display_order': _addedAgeCategories.length,
        'is_active': true,
      });
      _ageCategoryDisplayNameController.clear();
      _ageCategoryMinAgeController.text = '0';
      _ageCategoryMaxAgeController.text = '100';
      _isMinAgeValid = true;
      _isMaxAgeValid = true;
      _isAgeRangeValid = true;
    });
  }

  void _removeAgeCategory(int index) {
    setState(() => _addedAgeCategories.removeAt(index));
    for (int i = 0; i < _addedAgeCategories.length; i++) {
      _addedAgeCategories[i]['display_order'] = i;
    }
  }

  // ==================== SERVICE CATEGORY ====================
  void _autoFillServiceCategory(Map<String, dynamic> selected) {
    setState(() {
      _serviceCategoryDisplayNameController.text =
          selected['display_name']?.toString() ?? '';
      _serviceCategoryDescriptionController.text =
          selected['description']?.toString() ?? '';
      _selectedIcon = selected['icon_name']?.toString() ?? 'content_cut';

      String colorStr = selected['color']?.toString() ?? '#FF6B8B';
      if (colorStr.startsWith('#')) {
        _selectedColor = Color(int.parse('0xFF${colorStr.substring(1)}'));
      } else {
        _selectedColor = AppTheme.primary;
      }
    });
  }

  void _addServiceCategory() {
    final displayName = _serviceCategoryDisplayNameController.text.trim();
    if (displayName.isEmpty) {
      _showSnackBar('Service category display name is required', Colors.orange);
      return;
    }
    if (_addedServiceCategories.any((c) => c['display_name'] == displayName)) {
      _showSnackBar('This service category is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedServiceCategories.add({
        'display_name': displayName,
        'description': _serviceCategoryDescriptionController.text.trim(),
        'icon_name': _selectedIcon,
        'color': '#${_selectedColor.toARGB32().toRadixString(16).substring(2)}',
        'display_order': _addedServiceCategories.length,
        'is_active': true,
      });
      _serviceCategoryDisplayNameController.clear();
      _serviceCategoryDescriptionController.clear();
    });
  }

  void _removeServiceCategory(int index) {
    setState(() => _addedServiceCategories.removeAt(index));
    for (int i = 0; i < _addedServiceCategories.length; i++) {
      _addedServiceCategories[i]['display_order'] = i;
    }
  }

  // ==================== WIDGETS ====================
  Widget _buildGenderSelection() {
    final isDark = _isDark;

    if (_isLoadingGlobalData) {
      return _buildLoadingCard('Genders', Icons.people, Colors.blue);
    }

    if (_hasErrorLoadingData && _globalGenders.isEmpty) {
      return _buildErrorCard('Genders', Icons.people, Colors.blue, () {
        _loadGlobalData();
      });
    }

    if (_globalGenders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.people, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Text(
                  'Gender Categories',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                if (_selectedGenderIds.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedGenderIds.clear()),
                    child: Text(
                      'Clear All',
                      style: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Select the genders your salon serves',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _globalGenders.map((gender) {
                final id = gender['id'] as int;
                final isSelected = _selectedGenderIds.contains(id);
                final displayName = gender['display_name'] as String;

                return FilterChip(
                  label: Text(
                    displayName,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.blue
                          : (isDark ? Colors.white70 : Colors.grey[700]),
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (!_selectedGenderIds.contains(id)) {
                          _selectedGenderIds.add(id);
                        }
                      } else {
                        _selectedGenderIds.remove(id);
                      }
                    });
                  },
                  backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  selectedColor: Colors.blue.withValues(alpha: 0.2),
                  checkmarkColor: Colors.blue,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: isSelected
                          ? Colors.blue
                          : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_selectedGenderIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedGenderIds.length} gender${_selectedGenderIds.length > 1 ? 's' : ''} selected',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.blue[300] : Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onRetry,
  ) {
    final isDark = _isDark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.error_outline, color: Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load data',
              style: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard(String title, IconData icon, Color color) {
    final isDark = _isDark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const Spacer(),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    required bool isValid,
    required VoidCallback onChanged,
  }) {
    final isDark = _isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        onChanged: (value) => onChanged(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
          prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.grey),
          errorText: !isValid && controller.text.isNotEmpty
              ? 'Enter a valid number (0-150)'
              : null,
          errorStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          filled: true,
        ),
      ),
    );
  }

  Widget _buildSplitViewSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> addedItems,
    required Function(int) onRemove,
    required String Function(Map<String, dynamic>) itemDisplayName,
    required Widget formFields,
    required VoidCallback onAdd,
  }) {
    final isDark = _isDark;
    final isDesktop = _isWeb;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${addedItems.length} items',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? color : color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Add New $title',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? color : color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          formFields,
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: onAdd,
                              icon: const Icon(Icons.add, size: 18),
                              label: Text('Add $title'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.list,
                                size: 20,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Added $title',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? color : color,
                                ),
                              ),
                              const Spacer(),
                              if (addedItems.isNotEmpty)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => addedItems.clear()),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                  ),
                                  child: Text(
                                    'Clear All',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.red[300] : Colors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (addedItems.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inbox,
                                      size: 40,
                                      color: isDark ? Colors.white30 : Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No $title added yet',
                                      style: TextStyle(
                                        color: isDark ? Colors.white70 : Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      'Use the form on the left to add',
                                      style: TextStyle(
                                        color: isDark ? Colors.white30 : Colors.grey[400],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: addedItems.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = addedItems[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(
                                      alpha: 0.1,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? color : color,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    itemDisplayName(item),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: isDark ? Colors.red[300] : Colors.red,
                                    ),
                                    onPressed: () => onRemove(index),
                                  ),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.add_circle_outline,
                              size: 20,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add New $title',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? color : color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        formFields,
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text('Add $title'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.list,
                              size: 20,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Added $title',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? color : color,
                              ),
                            ),
                            const Spacer(),
                            if (addedItems.isNotEmpty)
                              TextButton(
                                onPressed: () =>
                                    setState(() => addedItems.clear()),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                ),
                                child: Text(
                                  'Clear All',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.red[300] : Colors.red,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (addedItems.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.inbox,
                                    size: 40,
                                    color: isDark ? Colors.white30 : Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No $title added yet',
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Tap + button to add',
                                    style: TextStyle(
                                      color: isDark ? Colors.white30 : Colors.grey[400],
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: addedItems.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = addedItems[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.1),
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? color : color,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  itemDisplayName(item),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: isDark ? Colors.red[300] : Colors.red,
                                  ),
                                  onPressed: () => onRemove(index),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeCategorySection() {
    if (_isLoadingGlobalData) {
      return _buildLoadingCard(
        'Age Categories',
        Icons.calendar_today,
        Colors.green,
      );
    }

    if (_hasErrorLoadingData && _globalAgeCategories.isEmpty) {
      return _buildErrorCard(
        'Age Categories',
        Icons.calendar_today,
        Colors.green,
        () {
          _loadGlobalData();
        },
      );
    }

    return _buildSplitViewSection(
      title: 'Age Categories',
      icon: Icons.calendar_today,
      color: Colors.green,
      addedItems: _addedAgeCategories,
      onRemove: _removeAgeCategory,
      itemDisplayName: (item) =>
          '${item['display_name']} (${item['min_age']}-${item['max_age']})',
      formFields: Column(
        children: [
          _buildSuggestionField(
            controller: _ageCategoryDisplayNameController,
            label: 'Display Name *',
            hint: 'e.g., Child, Teen, Adult, Senior',
            icon: Icons.visibility,
            suggestions: _globalAgeCategories
                .map((a) => a['display_name'] as String)
                .toList(),
            onSelected: (String value) {
              final selected = _globalAgeCategories.firstWhere(
                (a) => a['display_name'] == value,
                orElse: () => {},
              );
              if (selected.isNotEmpty) _autoFillAgeCategory(selected);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildAgeTextField(
                  controller: _ageCategoryMinAgeController,
                  label: 'Min Age',
                  hint: '0',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  isValid: _isMinAgeValid,
                  onChanged: _validateAgeFields,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAgeTextField(
                  controller: _ageCategoryMaxAgeController,
                  label: 'Max Age',
                  hint: '100',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  isValid: _isMaxAgeValid,
                  onChanged: _validateAgeFields,
                ),
              ),
            ],
          ),
          if (!_isAgeRangeValid)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  const Text(
                    'Min age cannot be greater than max age',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
        ],
      ),
      onAdd: _addAgeCategory,
    );
  }

  Widget _buildServiceCategorySection() {
    if (_isLoadingGlobalData) {
      return _buildLoadingCard('Main Services', Icons.category, Colors.orange);
    }

    if (_hasErrorLoadingData && _globalCategories.isEmpty) {
      return _buildErrorCard(
        'Main Services',
        Icons.category,
        Colors.orange,
        () {
          _loadGlobalData();
        },
      );
    }

    return _buildSplitViewSection(
      title: 'Main Services',
      icon: Icons.category,
      color: Colors.orange,
      addedItems: _addedServiceCategories,
      onRemove: _removeServiceCategory,
      itemDisplayName: (item) => item['display_name'],
      formFields: Column(
        children: [
          _buildSuggestionField(
            controller: _serviceCategoryDisplayNameController,
            label: 'Service Name *',
            hint: 'e.g., Hair, Skin, Nails, Grooming',
            icon: Icons.category,
            suggestions: _globalCategories
                .map((c) => c['display_name'] as String)
                .toList(),
            onSelected: (String value) {
              final selected = _globalCategories.firstWhere(
                (c) => c['display_name'] == value,
                orElse: () => {},
              );
              if (selected.isNotEmpty) _autoFillServiceCategory(selected);
            },
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _serviceCategoryDescriptionController,
            label: 'Description',
            hint: 'e.g., Hair cutting and styling services',
            icon: Icons.description,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          _buildIconSelector(),
          const SizedBox(height: 8),
          _buildColorPicker(),
        ],
      ),
      onAdd: _addServiceCategory,
    );
  }

  Widget _buildIconSelector() {
    final isDark = _isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Icon',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _iconList.length,
            itemBuilder: (context, index) {
              final iconItem = _iconList[index];
              final isSelected = _selectedIcon == iconItem['name'];

              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedIcon = iconItem['name'] as String),
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : (isDark ? const Color(0xFF2A2A2A) : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        iconItem['icon'] as IconData,
                        size: 24,
                        color: isSelected
                            ? AppTheme.primary
                            : (isDark ? Colors.white60 : Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        iconItem['label'] as String,
                        style: TextStyle(
                          fontSize: 9,
                          color: isSelected
                              ? AppTheme.primary
                              : (isDark ? Colors.white60 : Colors.grey[600]),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorPicker() {
    final isDark = _isDark;
    final List<Color> colorOptions = [
      AppTheme.primary,
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFFF44336),
      const Color(0xFF00BCD4),
      const Color(0xFF795548),
      const Color(0xFF607D8B),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colorOptions.map((color) {
            final isSelected = _selectedColor == color;
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = color),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Center(
                        child: Icon(Icons.check, color: Colors.white, size: 14),
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSuggestionField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required List<String> suggestions,
    required Function(String) onSelected,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    final isDark = _isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<String>.empty();
          }
          return suggestions.where(
            (option) => option.toLowerCase().contains(
              textEditingValue.text.toLowerCase(),
            ),
          );
        },
        onSelected: (String selection) {
          onSelected(selection);
          controller.text = selection;
        },
        fieldViewBuilder:
            (context, textController, focusNode, onFieldSubmitted) {
              if (textController.text != controller.text) {
                textController.text = controller.text;
              }
              controller.addListener(() {
                if (textController.text != controller.text) {
                  textController.text = controller.text;
                }
              });
              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                keyboardType: keyboardType,
                maxLines: maxLines,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
                  prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.grey),
                  suffixIcon: Icon(
                    Icons.arrow_drop_down,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                  fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  filled: true,
                ),
                onChanged: (value) => controller.text = value,
              );
            },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool isPhone = false,
    bool isEmail = false,
  }) {
    final isDark = _isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (value) {
          if (isPhone) _validatePhone(value);
          if (isEmail) _validateEmail(value);
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
          prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.grey),
          errorText: isPhone && !_isPhoneValid && controller.text.isNotEmpty
              ? 'Enter valid phone number (e.g., 0771234567)'
              : isEmail && !_isEmailValid && controller.text.isNotEmpty
              ? 'Enter valid email address'
              : null,
          errorStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          filled: true,
        ),
      ),
    );
  }

  // ==================== IMAGE SECTION ====================
  Widget _buildCoverSection() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    return Container(
      height: isDesktop ? 250 : 180,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _showCoverSourceDialog(),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                image: (_coverFile != null || _coverWebBytes != null)
                    ? DecorationImage(
                        image: _coverWebBytes != null
                            ? MemoryImage(_coverWebBytes!)
                            : FileImage(_coverFile!) as ImageProvider,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (_coverFile == null && _coverWebBytes == null)
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: isDesktop ? 48 : 36,
                            color: isDark ? Colors.white30 : Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add cover photo',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          if (_coverFile != null || _coverWebBytes != null)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => _showCoverSourceDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogoSeparate() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    return Container(
      margin: const EdgeInsets.only(left: 16, top: 0, bottom: 16),
      child: GestureDetector(
        onTap: () => _showLogoSourceDialog(),
        child: Container(
          width: isDesktop ? 100 : 80,
          height: isDesktop ? 100 : 80,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            image: (_logoFile != null || _logoWebBytes != null)
                ? DecorationImage(
                    image: _logoWebBytes != null
                        ? MemoryImage(_logoWebBytes!)
                        : FileImage(_logoFile!) as ImageProvider,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: (_logoFile == null && _logoWebBytes == null)
              ? Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo,
                        size: isDesktop ? 30 : 24,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                      SizedBox(height: isDesktop ? 4 : 2),
                      Text(
                        'Add Logo',
                        style: TextStyle(
                          fontSize: isDesktop ? 10 : 8,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.transparent,
                      radius: 50,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _showLogoSourceDialog() {
    final isDark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add Logo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppTheme.primary,
              ),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickLogo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
              title: Text(
                'Take a Photo',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _takeLogoPhoto();
              },
            ),
            if (_logoFile != null || _logoWebBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Remove Logo',
                  style: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeLogo();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showCoverSourceDialog() {
    final isDark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add Cover Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppTheme.primary,
              ),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickCover();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
              title: Text(
                'Take a Photo',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _takeCoverPhoto();
              },
            ),
            if (_coverFile != null || _coverWebBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Remove Cover',
                  style: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeCover();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressAvatarBytes(rawBytes);
          setState(() {
            _logoWebBytes = compressed;
            _logoFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Logo', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            // ✅ Compress the cropped file's bytes before storing - same
            // path as web, so both platforms end up with a small,
            // upload-ready Uint8List regardless of the original photo size.
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressAvatarBytes(rawBytes);
            setState(() {
              _logoWebBytes = compressed;
              _logoFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error picking logo', Colors.red);
    }
  }

  Future<void> _takeLogoPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressAvatarBytes(rawBytes);
          setState(() {
            _logoWebBytes = compressed;
            _logoFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Logo', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressAvatarBytes(rawBytes);
            setState(() {
              _logoWebBytes = compressed;
              _logoFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoWebBytes = null;
    });
  }

  Future<void> _pickCover() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 1350,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressCoverBytes(rawBytes);
          setState(() {
            _coverWebBytes = compressed;
            _coverFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.ratio16x9,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Cover', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressCoverBytes(rawBytes);
            setState(() {
              _coverWebBytes = compressed;
              _coverFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error picking cover', Colors.red);
    }
  }

  Future<void> _takeCoverPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 1350,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressCoverBytes(rawBytes);
          setState(() {
            _coverWebBytes = compressed;
            _coverFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Cover', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressCoverBytes(rawBytes);
            setState(() {
              _coverWebBytes = compressed;
              _coverFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeCover() {
    setState(() {
      _coverFile = null;
      _coverWebBytes = null;
    });
  }

  // ✅ Fixed path per SALON: 'salons/{userId}/{salonId}/logo.jpg'. This is the
  // EXACT SAME path scheme EditSalonScreen uses, so a logo uploaded here at
  // creation time is the same storage object that a later edit will replace
  // via upsert:true - never a separate orphan file. Requires the salon row
  // to already exist (see _createSalon(), which inserts the row first to
  // obtain a real salonId before calling this).
  Future<String?> _uploadLogo(int salonId) async {
    if (_logoFile == null && _logoWebBytes == null) return null;
    setState(() => _isUploadingLogo = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final filePath = 'salons/$userId/$salonId/logo.jpg';

      if (_logoWebBytes != null) {
        await supabase.storage
            .from('salon-images')
            .uploadBinary(
              filePath,
              _logoWebBytes!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else if (_logoFile != null) {
        await supabase.storage
            .from('salon-images')
            .upload(
              filePath,
              _logoFile!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else {
        return null;
      }

      final baseUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading logo: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  // ✅ Same fixed-path-per-salon + upsert pattern as _uploadLogo() above.
  Future<String?> _uploadCover(int salonId) async {
    if (_coverFile == null && _coverWebBytes == null) return null;
    setState(() => _isUploadingCover = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final filePath = 'salons/$userId/$salonId/cover.jpg';

      if (_coverWebBytes != null) {
        await supabase.storage
            .from('salon-images')
            .uploadBinary(
              filePath,
              _coverWebBytes!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else if (_coverFile != null) {
        await supabase.storage
            .from('salon-images')
            .upload(
              filePath,
              _coverFile!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else {
        return null;
      }

      final baseUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading cover: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  // ==================== BUSINESS HOURS CARD ====================
  Widget _buildBusinessHoursCard() {
    final isDark = _isDark;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Business Hours',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getTimezoneDisplay(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.access_time, size: 14, color: AppTheme.primary),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TimePickerField(
                    label: 'Open Time',
                    initialTime: _openTimeLocal,
                    isRequired: true,
                    onTimeSelected: (time) {
                      setState(() {
                        _openTimeLocal = time;
                        _openTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
                          time,
                          _salonTimezone,
                        );
                        debugPrint('✅ Open time updated: Local=${_openTimeLocal.format(context)}, UTC=$_openTimeUtc');
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TimePickerField(
                    label: 'Close Time',
                    initialTime: _closeTimeLocal,
                    isRequired: true,
                    onTimeSelected: (time) {
                      setState(() {
                        _closeTimeLocal = time;
                        _closeTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
                          time,
                          _salonTimezone,
                        );
                        debugPrint('✅ Close time updated: Local=${_closeTimeLocal.format(context)}, UTC=$_closeTimeUtc');
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: isDark ? Colors.white70 : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Times are stored in UTC. Your local time: ${_openTimeLocal.format(context)} - ${_closeTimeLocal.format(context)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white70 : Colors.grey,
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

  // ==================== CREATE SALON ====================
  Future<void> _createSalon() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleaned.length < 9 ||
          cleaned.length > 10 ||
          !cleaned.startsWith('0')) {
        _showSnackBar('Please enter a valid phone number', Colors.orange);
        return;
      }
    }

    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      final emailRegex = RegExp(
        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      );
      if (!emailRegex.hasMatch(email)) {
        _showSnackBar('Please enter a valid email address', Colors.orange);
        return;
      }
    }

    if (_selectedGenderIds.isEmpty) {
      _showSnackBar('Please select at least one gender', Colors.orange);
      return;
    }
    if (_addedAgeCategories.isEmpty) {
      _showSnackBar('Please add at least one age category', Colors.orange);
      return;
    }
    if (_addedServiceCategories.isEmpty) {
      _showSnackBar('Please add at least one service category', Colors.orange);
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please login first', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userTimezone =
          prefs.getString('user_timezone') ??
          TimezoneService.getCurrentTimezone();

      final extraData = {
        'created_from': _isWeb ? 'web' : 'mobile',
        'platform': _getPlatformName(),
        'user_timezone': userTimezone,
      };

      // ✅ Step 1: insert the salon row WITHOUT logo/cover first, so we get
      // a real salonId. Images are uploaded to a path keyed by that salonId
      // (see below) - the EXACT SAME path scheme EditSalonScreen uses, so a
      // later edit's upsert replaces this same file instead of creating a
      // separate orphan.
      final salonData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'owner_id': userId,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'logo_url': null,
        'cover_url': null,
        'open_time': _openTimeUtc,
        'close_time': _closeTimeUtc,
        'timezone': _salonTimezone,
        'extra_data': extraData,
        'is_active': true,
      };

      debugPrint('📝 Creating salon with data:');
      debugPrint('   Name: ${salonData['name']}');
      debugPrint('   Timezone: ${salonData['timezone']}');
      debugPrint('   Open Time UTC: ${salonData['open_time']}');
      debugPrint('   Close Time UTC: ${salonData['close_time']}');

      final response = await supabase
          .from('salons')
          .insert(salonData)
          .select('id, name')
          .single();
      final salonId = response['id'] as int;

      debugPrint('✅ Salon created with ID: $salonId');

      // ✅ Step 2: now that salonId exists, upload logo/cover to
      // 'salons/{userId}/{salonId}/logo.jpg' (and cover.jpg) - same path
      // EditSalonScreen will reuse for this salon going forward.
      String? logoUrl = (_logoFile != null || _logoWebBytes != null)
          ? await _uploadLogo(salonId)
          : null;
      String? coverUrl = (_coverFile != null || _coverWebBytes != null)
          ? await _uploadCover(salonId)
          : null;

      // ✅ Step 3: patch the row with the uploaded URLs, if any.
      if (logoUrl != null || coverUrl != null) {
        final imageUpdate = <String, dynamic>{};
        if (logoUrl != null) imageUpdate['logo_url'] = logoUrl;
        if (coverUrl != null) imageUpdate['cover_url'] = coverUrl;
        await supabase.from('salons').update(imageUpdate).eq('id', salonId);
        debugPrint('✅ Salon images saved: logo=$logoUrl, cover=$coverUrl');
      }

      for (int i = 0; i < _selectedGenderIds.length; i++) {
        final genderId = _selectedGenderIds[i];
        final gender = _globalGenders.firstWhere((g) => g['id'] == genderId);
        await supabase.from('salon_genders').insert({
          'salon_id': salonId,
          'display_name': gender['display_name'],
          'display_order': i,
          'is_active': true,
        });
      }
      debugPrint('✅ Added ${_selectedGenderIds.length} genders');

      for (var ageCat in _addedAgeCategories) {
        await supabase.from('salon_age_categories').insert({
          'salon_id': salonId,
          'display_name': ageCat['display_name'],
          'min_age': ageCat['min_age'],
          'max_age': ageCat['max_age'],
          'display_order': ageCat['display_order'],
          'is_active': ageCat['is_active'],
        });
      }
      debugPrint('✅ Added ${_addedAgeCategories.length} age categories');

      for (var serviceCat in _addedServiceCategories) {
        await supabase.from('salon_categories').insert({
          'salon_id': salonId,
          'display_name': serviceCat['display_name'],
          'description': serviceCat['description'],
          'icon_name': serviceCat['icon_name'],
          'color': serviceCat['color'],
          'display_order': serviceCat['display_order'],
          'is_active': serviceCat['is_active'],
        });
      }
      debugPrint('✅ Added ${_addedServiceCategories.length} service categories');

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "🎉 Salon Created!",
        message:
            "${_nameController.text.trim()} created successfully.\n\n"
            "📍 Salon Timezone: ${_getTimezoneDisplay()}\n"
            "🕐 Business Hours (Local): ${_openTimeLocal.format(context)} - ${_closeTimeLocal.format(context)}\n"
            "🕐 Business Hours (UTC): $_openTimeUtc - $_closeTimeUtc\n"
            "✅ ${_selectedGenderIds.length} genders selected\n"
            "✅ ${_addedAgeCategories.length} age categories added\n"
            "✅ ${_addedServiceCategories.length} service categories added\n\n"
            "💡 Tip: All times are stored in UTC. When you view them, they will automatically adjust to your local timezone.",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('❌ Error creating salon: $e');
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getPlatformName() => kIsWeb
      ? 'web'
      : Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
      ? 'android'
      : 'mobile';

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;
    final isDesktop = isWeb;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: const Text('Create New Salon'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              ),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Create New Salon',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isDesktop,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: Container(
          color: isDark ? const Color(0xFF121212) : Colors.grey[50],
          child: Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 1200 : double.infinity,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isDesktop ? 32 : 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildCoverSection(),
                      Transform.translate(
                        offset: const Offset(16, -40),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _buildLogoSeparate(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Basic Information
                      Card(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Basic Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _nameController,
                                label: 'Salon Name *',
                                hint: 'Enter salon name',
                                icon: Icons.store,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _addressController,
                                label: 'Address',
                                hint: 'Enter address',
                                icon: Icons.location_on,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _descriptionController,
                                label: 'Description',
                                hint: 'Tell about your salon',
                                icon: Icons.description,
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Contact Information
                      Card(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contact Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _phoneController,
                                label: 'Phone Number',
                                hint: 'Enter phone number (e.g., 0771234567)',
                                icon: Icons.phone,
                                keyboardType: TextInputType.phone,
                                isPhone: true,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                controller: _emailController,
                                label: 'Email Address',
                                hint:
                                    'Enter email address (e.g., salon@example.com)',
                                icon: Icons.email,
                                keyboardType: TextInputType.emailAddress,
                                isEmail: true,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Phone and email are optional but recommended',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white70 : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildBusinessHoursCard(),
                      const SizedBox(height: 16),

                      _buildServiceCategorySection(),
                      _buildAgeCategorySection(),
                      _buildGenderSelection(),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed:
                              (_isLoading ||
                                  _isUploadingLogo ||
                                  _isUploadingCover)
                              ? null
                              : _createSalon,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child:
                              (_isLoading ||
                                  _isUploadingLogo ||
                                  _isUploadingCover)
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _isUploadingLogo || _isUploadingCover
                                          ? 'Uploading...'
                                          : 'Creating...',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_business, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Create Salon',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
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
          ),
        ),
      ),
    );
  }
}