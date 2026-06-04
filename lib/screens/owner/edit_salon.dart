import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../services/timezone_service.dart';

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
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isMobile ? double.infinity : 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedHour.toString().padLeft(2, '0'),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B)),
                  ),
                  const Text(
                    ':',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B)),
                  ),
                  Text(
                    _selectedMinute.toString().padLeft(2, '0'),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B)),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedPeriod,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    return Expanded(
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
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
                        color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[800],
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
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showTimePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!, width: 1),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: _selectedTime != null ? const Color(0xFFFF6B8B) : Colors.grey[400],
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
                      color: _selectedTime != null ? Colors.black : Colors.grey[500],
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== EDIT SALON SCREEN ====================
class EditSalonScreen extends StatefulWidget {
  final int salonId;

  const EditSalonScreen({super.key, required this.salonId});

  @override
  State<EditSalonScreen> createState() => _EditSalonScreenState();
}

class _EditSalonScreenState extends State<EditSalonScreen> {
  // ============================================
  // BASIC INFO CONTROLLERS
  // ============================================
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

  // ============================================
  // GENDER SECTION
  // ============================================
  List<Map<String, dynamic>> _globalGenders = [];
  final List<int> _selectedGenderIds = [];

  // ============================================
  // AGE CATEGORY SECTION
  // ============================================
  final List<Map<String, dynamic>> _addedAgeCategories = [];
  final TextEditingController _ageCategoryDisplayNameController = TextEditingController();
  final TextEditingController _ageCategoryMinAgeController = TextEditingController();
  final TextEditingController _ageCategoryMaxAgeController = TextEditingController();
  List<Map<String, dynamic>> _globalAgeCategories = [];

  // ============================================
  // SERVICE CATEGORY SECTION
  // ============================================
  final List<Map<String, dynamic>> _addedServiceCategories = [];
  final TextEditingController _serviceCategoryDisplayNameController = TextEditingController();
  final TextEditingController _serviceCategoryDescriptionController = TextEditingController();
  String _selectedIcon = 'content_cut';
  Color _selectedColor = const Color(0xFFFF6B8B);
  List<Map<String, dynamic>> _globalCategories = [];

  final List<Map<String, dynamic>> _iconList = [  
    {'name': 'face', 'icon': Icons.face, 'label': 'Face'},
    {'name': 'face_retouching_natural', 'icon': Icons.face_retouching_natural, 'label': 'Beard'},
    {'name': 'spa', 'icon': Icons.spa, 'label': 'Spa'},
    {'name': 'handshake', 'icon': Icons.handshake, 'label': 'Nails'},
    {'name': 'palette', 'icon': Icons.palette, 'label': 'Makeup'},   
    {'name': 'shower', 'icon': Icons.shower, 'label': 'Shower'},
    {'name': 'masks', 'icon': Icons.masks, 'label': 'Masks'},   
    {'name': 'spa_outlined', 'icon': Icons.spa_outlined, 'label': 'Wellness'},
  ];

  // ============================================
  // IMAGES
  // ============================================
  File? _logoFile;
  Uint8List? _logoWebBytes;
  File? _coverFile;
  Uint8List? _coverWebBytes;
  String? _currentLogoUrl;
  String? _currentCoverUrl;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  // ============================================
  // TIMEZONE VARIABLES (CRITICAL - DON'T MISS!)
  // ============================================
  String _userTimezone = '';
  String _salonTimezone = '';
  
  // Business hours - UTC for database
  String _openTimeUtc = '';
  String _closeTimeUtc = '';
  
  // Business hours - Local for display
  TimeOfDay? _openTimeLocal;
  TimeOfDay? _closeTimeLocal;
  
  bool _isTimezoneLoaded = false;
  bool _isLoadingGlobalData = false;
  bool _hasErrorLoadingData = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;

  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _ageCategoryMinAgeController.text = '0';
    _ageCategoryMaxAgeController.text = '100';
    _initializeWithTimezone();
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

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================
  
  Future<void> _initializeWithTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    
    // Get user's timezone
    _userTimezone = prefs.getString('user_timezone') ?? TimezoneService.getCurrentTimezone();
    
    // Ensure TimezoneService uses this timezone
    await TimezoneService.setTimezone(_userTimezone);

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadAllData();
  }

  // ============================================
  // CORRECT TIMEZONE CONVERSIONS
  // ============================================
  
  /// Convert UTC time string (from database) to LOCAL TimeOfDay for display
  TimeOfDay _utcToLocalTime(String utcTimeStr, String salonTimezone) {
    try {
      final parts = utcTimeStr.split(':');
      final utcHour = int.parse(parts[0]);
      final utcMinute = int.parse(parts[1]);
      
      final now = DateTime.now();
      final utcDateTime = DateTime.utc(now.year, now.month, now.day, utcHour, utcMinute);
      
      // Use salon's timezone for conversion
      final location = tz.getLocation(salonTimezone);
      final localDateTime = tz.TZDateTime.from(utcDateTime, location);
      
      debugPrint('🔄 UTC to Local: $utcTimeStr UTC → ${localDateTime.hour}:${localDateTime.minute} ($salonTimezone)');
      
      return TimeOfDay(hour: localDateTime.hour, minute: localDateTime.minute);
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      // Fallback: simple conversion
      final parts = utcTimeStr.split(':');
      final utcHour = int.parse(parts[0]);
      final utcMinute = int.parse(parts[1]);
      final offsetHours = TimezoneService.getUtcOffsetHours();
      int localHour = utcHour + offsetHours;
      if (localHour >= 24) localHour -= 24;
      if (localHour < 0) localHour += 24;
      return TimeOfDay(hour: localHour, minute: utcMinute);
    }
  }

  /// Convert LOCAL TimeOfDay to UTC time string for database
  String _localTimeToUtc(TimeOfDay localTime, String salonTimezone) {
    try {
      final now = DateTime.now();
      final location = tz.getLocation(salonTimezone);
      
      final localTZDateTime = tz.TZDateTime(
        location,
        now.year, now.month, now.day,
        localTime.hour, localTime.minute,
      );
      
      final utcDateTime = localTZDateTime.toUtc();
      
      debugPrint('🔄 Local to UTC: ${localTime.hour}:${localTime.minute} ($salonTimezone) → ${utcDateTime.hour}:${utcDateTime.minute} UTC');
      
      return '${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}:00';
    } catch (e) {
      debugPrint('Error converting local to UTC: $e');
      // Fallback: simple conversion
      final offsetHours = TimezoneService.getUtcOffsetHours();
      int utcHour = localTime.hour - offsetHours;
      if (utcHour < 0) utcHour += 24;
      if (utcHour >= 24) utcHour -= 24;
      return '${utcHour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:00';
    }
  }

  /// Get timezone display string with flag
  String _getTimezoneDisplay() {
    return '${TimezoneService.getCurrentFlag()} ${TimezoneService.getTimezoneDisplayName()} (${TimezoneService.getUtcOffsetString()})';
  }

  // ============================================
  // LOAD ALL DATA
  // ============================================
  
  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _isLoadingGlobalData = true;
      _hasErrorLoadingData = false;
    });
    
    try {
      await _loadGlobalData();
      await _loadSalonData();
      await _loadSalonSelections();
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() {
        _hasErrorLoadingData = true;
      });
      if (mounted) {
        _showSnackBar('Error loading data. Please check your connection.', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingGlobalData = false;
        });
      }
    }
  }

  Future<void> _loadGlobalData() async {
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
          .select('id, display_name, description, icon_name, color, display_order')
          .eq('is_active', true)
          .order('display_order')
          .timeout(const Duration(seconds: 15));
          
      setState(() {
        _globalGenders = List<Map<String, dynamic>>.from(genders);
        _globalAgeCategories = List<Map<String, dynamic>>.from(ageCategories);
        _globalCategories = List<Map<String, dynamic>>.from(categories);
        _hasErrorLoadingData = false;
      });
      
      debugPrint('✅ Global data loaded');
    } catch (e) {
      debugPrint('Error loading global data: $e');
      rethrow;
    }
  }

  Future<void> _loadSalonData() async {
    try {
      final response = await supabase
          .from('salons')
          .select()
          .eq('id', widget.salonId)
          .single();

      _nameController.text = response['name'] ?? '';
      _addressController.text = response['address'] ?? '';
      _phoneController.text = response['phone'] ?? '';
      _emailController.text = response['email'] ?? '';
      _descriptionController.text = response['description'] ?? '';

      _currentLogoUrl = response['logo_url'];
      _currentCoverUrl = response['cover_url'];
      
      // ✅ IMPORTANT: Get salon's timezone from database
      _salonTimezone = response['timezone'] ?? TimezoneService.getCurrentTimezone();

      // ✅ Load and convert times using salon's timezone
      if (response['open_time'] != null) {
        _openTimeUtc = response['open_time'] as String;
        _openTimeLocal = _utcToLocalTime(_openTimeUtc, _salonTimezone);
      } else {
        _openTimeLocal = const TimeOfDay(hour: 9, minute: 0);
        _openTimeUtc = _localTimeToUtc(_openTimeLocal!, _salonTimezone);
      }

      if (response['close_time'] != null) {
        _closeTimeUtc = response['close_time'] as String;
        _closeTimeLocal = _utcToLocalTime(_closeTimeUtc, _salonTimezone);
      } else {
        _closeTimeLocal = const TimeOfDay(hour: 18, minute: 0);
        _closeTimeUtc = _localTimeToUtc(_closeTimeLocal!, _salonTimezone);
      }
      
      debugPrint('✅ Salon data loaded. Salon timezone: $_salonTimezone, User timezone: $_userTimezone');
      debugPrint('✅ Open time: UTC=$_openTimeUtc, Local=${_openTimeLocal?.hour}:${_openTimeLocal?.minute}');
      debugPrint('✅ Close time: UTC=$_closeTimeUtc, Local=${_closeTimeLocal?.hour}:${_closeTimeLocal?.minute}');
      
    } catch (e) {
      debugPrint('Error loading salon: $e');
      rethrow;
    }
  }

  Future<void> _loadSalonSelections() async {
    try {
      // Load genders
      final genderResponse = await supabase
          .from('salon_genders')
          .select('display_name')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      setState(() {
        _selectedGenderIds.clear();
        for (var gender in genderResponse) {
          final displayName = gender['display_name'] as String;
          final matchedGender = _globalGenders.firstWhere(
            (g) => g['display_name'] == displayName,
            orElse: () => {},
          );
          if (matchedGender.isNotEmpty) {
            _selectedGenderIds.add(matchedGender['id'] as int);
          }
        }
      });

      // Load age categories
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('display_name, min_age, max_age')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      setState(() {
        _addedAgeCategories.clear();
        for (var age in ageResponse) {
          _addedAgeCategories.add({
            'display_name': age['display_name'],
            'min_age': age['min_age'],
            'max_age': age['max_age'],
            'display_order': _addedAgeCategories.length,
            'is_active': true,
          });
        }
      });

      // Load service categories
      final categoryResponse = await supabase
          .from('salon_categories')
          .select('display_name, description, icon_name, color')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      setState(() {
        _addedServiceCategories.clear();
        for (var cat in categoryResponse) {
          _addedServiceCategories.add({
            'display_name': cat['display_name'],
            'description': cat['description'] ?? '',
            'icon_name': cat['icon_name'] ?? 'content_cut',
            'color': cat['color'] ?? '#FF6B8B',
            'display_order': _addedServiceCategories.length,
            'is_active': true,
          });
        }
      });

      debugPrint('✅ Selections loaded');
    } catch (e) {
      debugPrint('Error loading salon selections: $e');
    }
  }

  // ============================================
  // VALIDATION FUNCTIONS
  // ============================================
  
  void _validatePhone(String value) {
    setState(() {
      if (value.isEmpty) {
        _isPhoneValid = true;
      } else {
        final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned.length >= 9 && cleaned.length <= 10 && cleaned.startsWith('0')) {
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
        final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
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

  // ============================================
  // AGE CATEGORY FUNCTIONS
  // ============================================
  
  void _autoFillAgeCategory(Map<String, dynamic> selected) {
    setState(() {
      _ageCategoryDisplayNameController.text = selected['display_name']?.toString() ?? '';
      _ageCategoryMinAgeController.text = (selected['min_age'] ?? 0).toString();
      _ageCategoryMaxAgeController.text = (selected['max_age'] ?? 100).toString();
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
      _showSnackBar('Valid age range is required', Colors.orange);
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
    _showSnackBar('Age category added', Colors.green);
  }

  void _removeAgeCategory(int index) {
    setState(() => _addedAgeCategories.removeAt(index));
    for (int i = 0; i < _addedAgeCategories.length; i++) {
      _addedAgeCategories[i]['display_order'] = i;
    }
  }

  // ============================================
  // SERVICE CATEGORY FUNCTIONS
  // ============================================
  
  void _autoFillServiceCategory(Map<String, dynamic> selected) {
    setState(() {
      _serviceCategoryDisplayNameController.text = selected['display_name']?.toString() ?? '';
      _serviceCategoryDescriptionController.text = selected['description']?.toString() ?? '';
      _selectedIcon = selected['icon_name']?.toString() ?? 'content_cut';
      
      String colorStr = selected['color']?.toString() ?? '#FF6B8B';
      if (colorStr.startsWith('#')) {
        _selectedColor = Color(int.parse('0xFF${colorStr.substring(1)}'));
      } else {
        _selectedColor = const Color(0xFFFF6B8B);
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
    _showSnackBar('Service category added', Colors.green);
  }

  void _removeServiceCategory(int index) {
    setState(() => _addedServiceCategories.removeAt(index));
    for (int i = 0; i < _addedServiceCategories.length; i++) {
      _addedServiceCategories[i]['display_order'] = i;
    }
  }

  // ============================================
  // IMAGE FUNCTIONS
  // ============================================
  
  Future<void> _pickLogo() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _logoWebBytes = bytes;
            _logoFile = null;
          });
          _showSnackBar('Logo selected', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true,
              ),
              IOSUiSettings(
                title: 'Crop Logo',
                aspectRatioLockEnabled: true,
              ),
            ],
          );
          
          if (croppedFile != null) {
            setState(() {
              _logoFile = File(croppedFile.path);
              _logoWebBytes = null;
            });
            _showSnackBar('Logo cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking logo: $e');
      _showSnackBar('Error picking logo', Colors.red);
    }
  }

  Future<void> _takeLogoPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _logoWebBytes = bytes;
            _logoFile = null;
          });
          _showSnackBar('Logo captured', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(
                title: 'Crop Logo',
                aspectRatioLockEnabled: true,
              ),
            ],
          );
          
          if (croppedFile != null) {
            setState(() {
              _logoFile = File(croppedFile.path);
              _logoWebBytes = null;
            });
            _showSnackBar('Logo captured and cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoWebBytes = null;
      _currentLogoUrl = null;
    });
    _showSnackBar('Logo removed', Colors.red);
  }

  Future<void> _pickCover() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _coverWebBytes = bytes;
            _coverFile = null;
          });
          _showSnackBar('Cover selected', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.ratio16x9,
                lockAspectRatio: true,
              ),
              IOSUiSettings(
                title: 'Crop Cover',
                aspectRatioLockEnabled: true,
              ),
            ],
          );
          
          if (croppedFile != null) {
            setState(() {
              _coverFile = File(croppedFile.path);
              _coverWebBytes = null;
            });
            _showSnackBar('Cover cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking cover: $e');
      _showSnackBar('Error picking cover', Colors.red);
    }
  }

  Future<void> _takeCoverPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _coverWebBytes = bytes;
            _coverFile = null;
          });
          _showSnackBar('Cover captured', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(
                title: 'Crop Cover',
                aspectRatioLockEnabled: true,
              ),
            ],
          );
          
          if (croppedFile != null) {
            setState(() {
              _coverFile = File(croppedFile.path);
              _coverWebBytes = null;
            });
            _showSnackBar('Cover captured and cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeCover() {
    setState(() {
      _coverFile = null;
      _coverWebBytes = null;
      _currentCoverUrl = null;
    });
    _showSnackBar('Cover removed', Colors.red);
  }

  Future<String?> _uploadLogo() async {
    if (_logoFile == null && _logoWebBytes == null) return _currentLogoUrl;
    setState(() => _isUploadingLogo = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      String fileName;
      if (kIsWeb && _logoWebBytes != null) {
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage.from('salon-images').uploadBinary(filePath, _logoWebBytes!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      } else if (_logoFile != null) {
        final fileExt = path.extension(_logoFile!.path);
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage.from('salon-images').upload(filePath, _logoFile!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      }
      return _currentLogoUrl;
    } catch (e) {
      return _currentLogoUrl;
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<String?> _uploadCover() async {
    if (_coverFile == null && _coverWebBytes == null) return _currentCoverUrl;
    setState(() => _isUploadingCover = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      String fileName;
      if (kIsWeb && _coverWebBytes != null) {
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage.from('salon-images').uploadBinary(filePath, _coverWebBytes!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      } else if (_coverFile != null) {
        final fileExt = path.extension(_coverFile!.path);
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage.from('salon-images').upload(filePath, _coverFile!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      }
      return _currentCoverUrl;
    } catch (e) {
      return _currentCoverUrl;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  // ============================================
  // UPDATE SALON
  // ============================================
  
  Future<void> _updateSalon() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleaned.length < 9 || cleaned.length > 10 || !cleaned.startsWith('0')) {
        _showSnackBar('Please enter a valid phone number', Colors.orange);
        return;
      }
    }
    
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
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

    if (_openTimeLocal == null || _closeTimeLocal == null) {
      _showSnackBar('Please set business hours', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final logoUrl = await _uploadLogo();
      final coverUrl = await _uploadCover();

      // ✅ IMPORTANT: Convert local times to UTC using salon's timezone
      final openTimeUtc = _localTimeToUtc(_openTimeLocal!, _salonTimezone);
      final closeTimeUtc = _localTimeToUtc(_closeTimeLocal!, _salonTimezone);

      final updateData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'logo_url': logoUrl,
        'cover_url': coverUrl,
        'open_time': openTimeUtc,
        'close_time': closeTimeUtc,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('salons').update(updateData).eq('id', widget.salonId);

      // Update genders
      await supabase.from('salon_genders').delete().eq('salon_id', widget.salonId);
      
      for (int i = 0; i < _selectedGenderIds.length; i++) {
        final genderId = _selectedGenderIds[i];
        final gender = _globalGenders.firstWhere((g) => g['id'] == genderId);
        
        await supabase.from('salon_genders').insert({
          'salon_id': widget.salonId,
          'display_name': gender['display_name'],
          'display_order': i,
          'is_active': true,
        });
      }

      // Update age categories
      await supabase.from('salon_age_categories').delete().eq('salon_id', widget.salonId);
      
      for (var ageCat in _addedAgeCategories) {
        await supabase.from('salon_age_categories').insert({
          'salon_id': widget.salonId,
          'display_name': ageCat['display_name'],
          'min_age': ageCat['min_age'],
          'max_age': ageCat['max_age'],
          'display_order': ageCat['display_order'],
          'is_active': ageCat['is_active'],
        });
      }

      // Update service categories
      await supabase.from('salon_categories').delete().eq('salon_id', widget.salonId);
      
      for (var serviceCat in _addedServiceCategories) {
        await supabase.from('salon_categories').insert({
          'salon_id': widget.salonId,
          'display_name': serviceCat['display_name'],
          'description': serviceCat['description'],
          'icon_name': serviceCat['icon_name'],
          'color': serviceCat['color'],
          'display_order': serviceCat['display_order'],
          'is_active': serviceCat['is_active'],
        });
      }

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "✅ Salon Updated!",
        message: "${_nameController.text.trim()} has been updated successfully.\n\n"
            "📍 Salon Timezone: ${_getTimezoneDisplay()}\n"
            "🕐 UTC Time: $openTimeUtc - $closeTimeUtc\n"
            "🕐 Local Time: ${_openTimeLocal!.format(context)} - ${_closeTimeLocal!.format(context)}\n\n"
            "✅ ${_selectedGenderIds.length} genders\n"
            "✅ ${_addedAgeCategories.length} age categories\n"
            "✅ ${_addedServiceCategories.length} service categories\n\n"
            "💡 Times are saved in UTC and will be displayed in your local timezone",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ============================================
  // DELETE SALON
  // ============================================
  
  Future<void> _deleteSalon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Salon', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete '${_nameController.text.trim()}'?",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚠️ This will also delete:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                  SizedBox(height: 8),
                  Text('• All appointments', style: TextStyle(fontSize: 13)),
                  Text('• All services', style: TextStyle(fontSize: 13)),
                  Text('• All barbers', style: TextStyle(fontSize: 13)),
                  Text('• All reviews', style: TextStyle(fontSize: 13)),
                  Text('• All service variants', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('This action cannot be undone!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Delete Permanently', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isDeleting = true);

      try {
        await supabase.from('salons').delete().eq('id', widget.salonId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Salon deleted successfully'), backgroundColor: Colors.green),
          );
          if (mounted) Navigator.pop(context, true);
        }
      } catch (e) {
        debugPrint('Error deleting salon: $e');
        if (mounted) _showSnackBar('Error deleting salon', Colors.red);
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  // ============================================
  // WIDGETS
  // ============================================
  
  Widget _buildTimezoneInfoCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _getTimezoneDisplay(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Salon timezone: $_salonTimezone',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              'Your timezone: $_userTimezone',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String title, IconData icon, Color color, VoidCallback onRetry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
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
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                const Icon(Icons.error_outline, color: Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Failed to load data', style: TextStyle(color: Colors.red)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard(String title, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
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
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (value) => onChanged(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey),
          errorText: !isValid && controller.text.isNotEmpty ? 'Enter a valid number (0-150)' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${addedItems.length} items',
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
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
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.add_circle_outline, size: 20, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Add New $title',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: color,
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
                  ),
                  const SizedBox(width: 16),
                  
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.list, size: 20, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'Added $title',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                              const Spacer(),
                              if (addedItems.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      addedItems.clear();
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text(
                                    'Clear All',
                                    style: TextStyle(fontSize: 12, color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (addedItems.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.inbox, size: 40, color: Colors.grey[400]),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No $title added yet',
                                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                    ),
                                    Text(
                                      'Use the form on the left to add',
                                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
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
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = addedItems[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.1),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(fontSize: 12, color: color),
                                    ),
                                  ),
                                  title: Text(
                                    itemDisplayName(item),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
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
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.add_circle_outline, size: 20, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Add New $title',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.list, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Added $title',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                            ),
                            const Spacer(),
                            if (addedItems.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    addedItems.clear();
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                ),
                                child: const Text(
                                  'Clear All',
                                  style: TextStyle(fontSize: 12, color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (addedItems.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inbox, size: 40, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text('No $title added yet', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                  Text('Tap + button to add', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: addedItems.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = addedItems[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.1),
                                  child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: color)),
                                ),
                                title: Text(itemDisplayName(item), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
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

  Widget _buildGenderSelection() {
    if (_isLoadingGlobalData) {
      return _buildLoadingCard('Genders', Icons.people, Colors.blue);
    }
    
    if (_hasErrorLoadingData && _globalGenders.isEmpty) {
      return _buildErrorCard('Genders', Icons.people, Colors.blue, () {
        _loadAllData();
      });
    }
    
    if (_globalGenders.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
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
                const Text(
                  'Gender Categories',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectedGenderIds.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedGenderIds.clear()),
                    child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Select the genders your salon serves',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
                  label: Text(displayName),
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
                  backgroundColor: Colors.white,
                  selectedColor: Colors.blue.withValues(alpha: 0.2),
                  checkmarkColor: Colors.blue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.blue : Colors.grey[700],
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                  shape: StadiumBorder(
                    side: BorderSide(color: isSelected ? Colors.blue : Colors.grey[300]!),
                  ),
                );
              }).toList(),
            ),
            if (_selectedGenderIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedGenderIds.length} gender${_selectedGenderIds.length > 1 ? 's' : ''} selected',
                    style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeCategorySection() {
    if (_isLoadingGlobalData) {
      return _buildLoadingCard('Age Categories', Icons.calendar_today, Colors.green);
    }
    
    if (_hasErrorLoadingData && _globalAgeCategories.isEmpty) {
      return _buildErrorCard('Age Categories', Icons.calendar_today, Colors.green, () {
        _loadAllData();
      });
    }
    
    return _buildSplitViewSection(
      title: 'Age Categories',
      icon: Icons.calendar_today,
      color: Colors.green,
      addedItems: _addedAgeCategories,
      onRemove: _removeAgeCategory,
      itemDisplayName: (item) => '${item['display_name']} (${item['min_age']}-${item['max_age']})',
      formFields: Column(
        children: [
          _buildSuggestionField(
            controller: _ageCategoryDisplayNameController,
            label: 'Display Name *',
            hint: 'e.g., Child, Teen, Adult, Senior',
            icon: Icons.visibility,
            suggestions: _globalAgeCategories.map((a) => a['display_name'] as String).toList(),
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
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
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
      return _buildErrorCard('Main Services', Icons.category, Colors.orange, () {
        _loadAllData();
      });
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
            suggestions: _globalCategories.map((c) => c['display_name'] as String).toList(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Icon', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                onTap: () => setState(() => _selectedIcon = iconItem['name'] as String),
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFF6B8B).withValues(alpha: 0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        iconItem['icon'] as IconData,
                        size: 24,
                        color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        iconItem['label'] as String,
                        style: TextStyle(
                          fontSize: 9,
                          color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
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
    final List<Color> colorOptions = [
      const Color(0xFFFF6B8B), const Color(0xFF4CAF50), const Color(0xFF2196F3),
      const Color(0xFFFF9800), const Color(0xFF9C27B0), const Color(0xFFF44336),
      const Color(0xFF00BCD4), const Color(0xFF795548), const Color(0xFF607D8B),
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Color', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                  border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                  boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)] : null,
                ),
                child: isSelected ? const Center(child: Icon(Icons.check, color: Colors.white, size: 14)) : null,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
          return suggestions.where((option) =>
              option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
        },
        onSelected: (String selection) {
          onSelected(selection);
          controller.text = selection;
        },
        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
          if (textController.text != controller.text) textController.text = controller.text;
          controller.addListener(() {
            if (textController.text != controller.text) textController.text = controller.text;
          });
          
          return TextFormField(
            controller: textController,
            focusNode: focusNode,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(icon, color: Colors.grey),
              suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
              ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (value) {
          if (isPhone) _validatePhone(value);
          if (isEmail) _validateEmail(value);
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey),
          errorText: isPhone && !_isPhoneValid && controller.text.isNotEmpty
              ? 'Enter valid phone number (e.g., 0771234567)'
              : isEmail && !_isEmailValid && controller.text.isNotEmpty
                  ? 'Enter valid email address'
                  : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
        ),
      ),
    );
  }

  // ============================================
  // IMAGE SECTION WIDGETS
  // ============================================
  
  Widget _buildCoverSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
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
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                image: (_coverFile != null || _coverWebBytes != null || _currentCoverUrl != null)
                    ? DecorationImage(image: _getCoverImageProvider(), fit: BoxFit.cover)
                    : null,
              ),
              child: (_coverFile == null && _coverWebBytes == null && _currentCoverUrl == null)
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: isDesktop ? 48 : 36, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text('Tap to add cover photo', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          if (_coverFile != null || _coverWebBytes != null || _currentCoverUrl != null)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => _showCoverSourceDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('Edit', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ImageProvider _getCoverImageProvider() {
    if (kIsWeb && _coverWebBytes != null) {
      return MemoryImage(_coverWebBytes!);
    } else if (_coverFile != null) {
      return FileImage(_coverFile!);
    } else if (_currentCoverUrl != null) {
      return NetworkImage(_currentCoverUrl!);
    }
    return const AssetImage('placeholder.png');
  }

  Widget _buildLogoSeparate() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 0, bottom: 16),
      child: GestureDetector(
        onTap: () => _showLogoSourceDialog(),
        child: Container(
          width: isDesktop ? 100 : 80,
          height: isDesktop ? 100 : 80,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2)),
            ],
            image: (_logoFile != null || _logoWebBytes != null || _currentLogoUrl != null)
                ? DecorationImage(image: _getLogoImageProvider(), fit: BoxFit.cover)
                : null,
          ),
          child: (_logoFile == null && _logoWebBytes == null && _currentLogoUrl == null)
              ? Container(
                  decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, size: isDesktop ? 30 : 24, color: Colors.grey[600]),
                      SizedBox(height: isDesktop ? 4 : 2),
                      Text('Add Logo', style: TextStyle(fontSize: isDesktop ? 10 : 8, color: Colors.grey[600])),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    const CircleAvatar(backgroundColor: Colors.transparent, radius: 50),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFFFF6B8B), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  ImageProvider _getLogoImageProvider() {
    if (kIsWeb && _logoWebBytes != null) {
      return MemoryImage(_logoWebBytes!);
    } else if (_logoFile != null) {
      return FileImage(_logoFile!);
    } else if (_currentLogoUrl != null) {
      return NetworkImage(_currentLogoUrl!);
    }
    return const AssetImage('placeholder.png');
  }

  void _showLogoSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Add Logo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(context); _pickLogo(); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () { Navigator.pop(context); _takeLogoPhoto(); },
            ),
            if (_logoFile != null || _logoWebBytes != null || _currentLogoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Logo', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); _removeLogo(); },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showCoverSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Add Cover Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(context); _pickCover(); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () { Navigator.pop(context); _takeCoverPhoto(); },
            ),
            if (_coverFile != null || _coverWebBytes != null || _currentCoverUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Cover', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); _removeCover(); },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ============================================
  // BUSINESS HOURS CARD (UPDATED WITH UTC DISPLAY)
  // ============================================
  
  Widget _buildBusinessHoursCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Business Hours',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _getTimezoneDisplay(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
                        // Update UTC when local changes
                        _openTimeUtc = _localTimeToUtc(time, _salonTimezone);
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
                        // Update UTC when local changes
                        _closeTimeUtc = _localTimeToUtc(time, _salonTimezone);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Times are saved in UTC and will be displayed in your local timezone',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.cloud_queue, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'UTC Time (Database): $_openTimeUtc - $_closeTimeUtc',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    if (!_isTimezoneLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Salon'),
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 40, height: 40, child: CircularProgressIndicator()),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Salon'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isDesktop,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _isDeleting ? null : _deleteSalon,
            tooltip: 'Delete Salon',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : Container(
              color: Colors.grey[50],
              child: Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isDesktop ? 32 : 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildCoverSection(),
                          Transform.translate(
                            offset: const Offset(16, -40),
                            child: Align(alignment: Alignment.topLeft, child: _buildLogoSeparate()),
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTimezoneInfoCard(),
                          const SizedBox(height: 16),
                          
                          // Basic Info Card
                          Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Basic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 16),
                                  _buildTextField(controller: _nameController, label: 'Salon Name *', hint: 'Enter salon name', icon: Icons.store),
                                  const SizedBox(height: 12),
                                  _buildTextField(controller: _addressController, label: 'Address', hint: 'Enter address', icon: Icons.location_on, maxLines: 2),
                                  const SizedBox(height: 12),
                                  _buildTextField(controller: _descriptionController, label: 'Description', hint: 'Tell about your salon', icon: Icons.description, maxLines: 3),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Contact Info Card
                          Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Contact Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 16),
                                  _buildTextField(controller: _phoneController, label: 'Phone Number', hint: 'Enter phone number (e.g., 0771234567)', icon: Icons.phone, keyboardType: TextInputType.phone, isPhone: true),
                                  const SizedBox(height: 12),
                                  _buildTextField(controller: _emailController, label: 'Email Address', hint: 'Enter email address (e.g., salon@example.com)', icon: Icons.email, keyboardType: TextInputType.emailAddress, isEmail: true),
                                  const SizedBox(height: 8),
                                  Text('Phone and email are optional but recommended', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                          
                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey[700],
                                    side: BorderSide(color: Colors.grey[300]!),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: (_isSaving || _isUploadingLogo || _isUploadingCover) ? null : _updateSalon,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B8B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: _isSaving || _isUploadingLogo || _isUploadingCover
                                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                          SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                          SizedBox(width: 8),
                                          Text('Saving...'),
                                        ])
                                      : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}