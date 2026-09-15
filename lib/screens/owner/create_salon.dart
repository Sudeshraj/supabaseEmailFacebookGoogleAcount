import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/alertBox/time_picker_dialog.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../services/timezone_service.dart';
import '../../utils/image_compression.dart';

// ====================================================================
// CREATE SALON SCREEN — step-by-step wizard
//
// Steps:
//  0. Basic + Contact Info (+ logo/cover)
//  1. Business Hours + Currency
//  2. Age Categories
//  3. Genders
//  4. Service Categories
//  5. Services (add services under categories)
//  6. Pricing (add pricing variants to services — OPTIONAL step)
//  7. Review & Create
//
// NOTE: The Pricing step can be skipped. If skipped, services are still
// saved (without variants). Price can be left empty (saved as 0).
// ====================================================================
class CreateSalonScreen extends StatefulWidget {
  const CreateSalonScreen({super.key});

  @override
  State<CreateSalonScreen> createState() => _CreateSalonScreenState();
}

class _CreateSalonScreenState extends State<CreateSalonScreen> {
  // ==================== STEP MANAGEMENT ====================
  int _currentStep = 0;
  int _furthestStep = 0;
  static const int _totalSteps = 8;

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
    {'name': 'content_cut', 'icon': Icons.content_cut, 'label': 'Hair'},
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

  // ==================== SERVICES + PRICING ====================
  // Locally-held services, each referencing its category by display_name.
  final List<Map<String, dynamic>> _addedServices = [];

  // ---- Services step (step 5) ----
  final TextEditingController _newServiceNameController =
      TextEditingController();
  final TextEditingController _newServiceDescriptionController =
      TextEditingController();
  String? _newServiceIcon;
  String? _serviceFormCategoryRef;
  int _editingServiceIndex = -1;
  String? _serviceNameError;

  // ---- Pricing step (step 6) ----
  int? _variantTargetServiceIndex;
  String? _variantGenderRef;
  String? _variantAgeRef;
  final TextEditingController _variantPriceController = TextEditingController();
  final TextEditingController _variantDurationController =
      TextEditingController();
  String? _newVariantPriceError;
  String? _newVariantDurationError;

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

  // ==================== CURRENCY RELATED VARIABLES ====================
  String _salonCurrencyCode = 'LKR';
  String _salonCurrencySymbol = 'Rs.';

  static const List<Map<String, String>> _supportedCurrencies = [
    {'code': 'LKR', 'symbol': 'Rs.', 'name': 'Sri Lankan Rupee'},
    {'code': 'USD', 'symbol': '\$', 'name': 'US Dollar'},
    {'code': 'INR', 'symbol': '₹', 'name': 'Indian Rupee'},
    {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
    {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
    {'code': 'AUD', 'symbol': 'A\$', 'name': 'Australian Dollar'},
    {'code': 'CAD', 'symbol': 'C\$', 'name': 'Canadian Dollar'},
    {'code': 'SGD', 'symbol': 'S\$', 'name': 'Singapore Dollar'},
    {'code': 'AED', 'symbol': 'د.إ', 'name': 'UAE Dirham'},
    {'code': 'MYR', 'symbol': 'RM', 'name': 'Malaysian Ringgit'},
    {'code': 'THB', 'symbol': '฿', 'name': 'Thai Baht'},
    {'code': 'JPY', 'symbol': '¥', 'name': 'Japanese Yen'},
    {'code': 'CNY', 'symbol': '¥', 'name': 'Chinese Yuan'},
    {'code': 'NZD', 'symbol': 'NZ\$', 'name': 'New Zealand Dollar'},
    {'code': 'CHF', 'symbol': 'CHF', 'name': 'Swiss Franc'},
    {'code': 'PKR', 'symbol': '₨', 'name': 'Pakistani Rupee'},
    {'code': 'BDT', 'symbol': '৳', 'name': 'Bangladeshi Taka'},
    {'code': 'NPR', 'symbol': 'रू', 'name': 'Nepalese Rupee'},
  ];

  bool _isConfirmDialogOpen = false;

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
    _newServiceIcon = _iconList.first['name'] as String;
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

  Future<void> _initializeWithTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    String cachedUserTimezone =
        prefs.getString(TimezoneService.kUserTimezone) ?? '';

    if (cachedUserTimezone.isNotEmpty) {
      _userTimezone = cachedUserTimezone;
      await TimezoneService.setTimezone(_userTimezone);
      debugPrint('✅ Timezone from USER SETTING: $_userTimezone');
    } else {
      _userTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString(TimezoneService.kUserTimezone, _userTimezone);
      debugPrint('✅ Timezone from SERVICE (first time): $_userTimezone');
    }

    _salonTimezone = _userTimezone;

    _detectCurrencyFromTimezone();
    debugPrint('✅ Currency AUTO-DETECTED: $_salonCurrencyCode');

    _initializeBusinessHours();

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadGlobalData();
  }

  Future<void> _checkTimezoneChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString(TimezoneService.kUserTimezone) ?? '';

    if (_userTimezone.isNotEmpty && _userTimezone != currentTimezone) {
      debugPrint('🔄 Timezone changed: $_userTimezone → $currentTimezone');

      setState(() {
        _userTimezone = currentTimezone;
        _salonTimezone = currentTimezone;
        _detectCurrencyFromTimezone();
        debugPrint('✅ Currency AUTO-SYNCED: $_salonCurrencyCode');
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

    debugPrint('✅ Business hours initialized');
  }

  void _detectCurrencyFromTimezone() {
    _salonCurrencyCode = TimezoneService.getCurrencyForTimezone(_salonTimezone);
    _salonCurrencySymbol = _getSymbolForCode(_salonCurrencyCode);
  }

  String _getSymbolForCode(String code) {
    return TimezoneService.getSymbolForCurrency(code);
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
    _newServiceNameController.dispose();
    _newServiceDescriptionController.dispose();
    _variantPriceController.dispose();
    _variantDurationController.dispose();
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
    final removedName = _addedAgeCategories[index]['display_name'];
    setState(() {
      _addedAgeCategories.removeAt(index);
      for (int i = 0; i < _addedAgeCategories.length; i++) {
        _addedAgeCategories[i]['display_order'] = i;
      }
      for (var service in _addedServices) {
        (service['variants'] as List).removeWhere(
          (v) => v['age_ref'] == removedName,
        );
      }
    });
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
    final removedName = _addedServiceCategories[index]['display_name'];
    setState(() {
      _addedServiceCategories.removeAt(index);
      for (int i = 0; i < _addedServiceCategories.length; i++) {
        _addedServiceCategories[i]['display_order'] = i;
      }
      _addedServices.removeWhere((s) => s['category_ref'] == removedName);
      if (_serviceFormCategoryRef == removedName) {
        _serviceFormCategoryRef = null;
      }
      if (_variantTargetServiceIndex != null &&
          _variantTargetServiceIndex! >= _addedServices.length) {
        _variantTargetServiceIndex = null;
      }
    });
  }

  // ==================== SERVICES + PRICING LOGIC ====================

  List<String> _selectedGenderDisplayNames() {
    return _globalGenders
        .where((g) => _selectedGenderIds.contains(g['id']))
        .map((g) => g['display_name'] as String)
        .toList();
  }

  /// Price is OPTIONAL. Empty => no error. Non-empty => must be a valid number >= 0.
  void _validateNewVariantPrice() {
    final text = _variantPriceController.text.trim();
    if (text.isEmpty) {
      setState(() => _newVariantPriceError = null);
      return;
    }
    final price = double.tryParse(text);
    setState(() {
      if (price == null) {
        _newVariantPriceError = 'Enter a valid number';
      } else if (price < 0) {
        _newVariantPriceError = 'Price cannot be negative';
      } else {
        _newVariantPriceError = null;
      }
    });
  }

  /// Duration is REQUIRED (validated only when non-empty for live feedback).
  void _validateNewVariantDuration() {
    final text = _variantDurationController.text.trim();
    if (text.isEmpty) {
      setState(() => _newVariantDurationError = null);
      return;
    }
    final duration = int.tryParse(text);
    setState(() {
      if (duration == null) {
        _newVariantDurationError = 'Enter a valid number';
      } else if (duration <= 0) {
        _newVariantDurationError = 'Duration must be greater than 0';
      } else {
        _newVariantDurationError = null;
      }
    });
  }

  void _validateNewServiceName() {
    final name = _newServiceNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _serviceNameError = null);
      return;
    }
    final exists = _addedServices.asMap().entries.any(
      (e) =>
          e.value['name'].toString().toLowerCase() == name.toLowerCase() &&
          e.key != _editingServiceIndex,
    );
    setState(() {
      _serviceNameError = exists
          ? 'A service with this name already exists'
          : null;
    });
  }

  void _saveCurrentService() {
    _validateNewServiceName();

    if (_serviceFormCategoryRef == null) {
      _showSnackBar('Please select a category for this service', Colors.orange);
      return;
    }
    final name = _newServiceNameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Service name is required', Colors.orange);
      return;
    }
    if (_serviceNameError != null) {
      _showSnackBar(_serviceNameError!, Colors.orange);
      return;
    }

    final isEditing = _editingServiceIndex >= 0;

    final variants = isEditing
        ? List<Map<String, dynamic>>.from(
            (_addedServices[_editingServiceIndex]['variants'] as List).map(
              (v) => Map<String, dynamic>.from(v),
            ),
          )
        : <Map<String, dynamic>>[];

    final newService = {
      'name': name,
      'description': _newServiceDescriptionController.text.trim(),
      'icon_name': _newServiceIcon ?? _iconList.first['name'],
      'category_ref': _serviceFormCategoryRef,
      'variants': variants,
    };

    setState(() {
      if (isEditing) {
        _addedServices[_editingServiceIndex] = newService;
        _editingServiceIndex = -1;
      } else {
        _addedServices.add(newService);
      }
      _newServiceNameController.clear();
      _newServiceDescriptionController.clear();
      _newServiceIcon = _iconList.first['name'] as String;
      _serviceFormCategoryRef = null;
      _serviceNameError = null;
    });
  }

  void _editAddedService(int index) {
    final service = _addedServices[index];
    setState(() {
      _editingServiceIndex = index;
      _serviceFormCategoryRef = service['category_ref'] as String?;
      _newServiceNameController.text = service['name'] as String;
      _newServiceDescriptionController.text = service['description'] as String;
      _newServiceIcon = service['icon_name'] as String;
      _serviceNameError = null;
      _variantTargetServiceIndex = null;
    });
    _goToStep(5);
  }

  void _cancelEditingService() {
    setState(() {
      _editingServiceIndex = -1;
      _newServiceNameController.clear();
      _newServiceDescriptionController.clear();
      _newServiceIcon = _iconList.first['name'] as String;
      _serviceFormCategoryRef = null;
      _serviceNameError = null;
    });
  }

  void _removeAddedService(int index) {
    setState(() {
      _addedServices.removeAt(index);
      if (_editingServiceIndex == index) {
        _cancelEditingService();
      } else if (_editingServiceIndex > index) {
        _editingServiceIndex--;
      }
      if (_variantTargetServiceIndex == index) {
        _variantTargetServiceIndex = null;
      } else if (_variantTargetServiceIndex != null &&
          _variantTargetServiceIndex! > index) {
        _variantTargetServiceIndex = _variantTargetServiceIndex! - 1;
      }
    });
  }

  /// Adds a pricing variant. Gender + age + duration are REQUIRED. Price is
  /// optional (empty => 0).
  void _addVariantToService(int serviceIndex) {
    // Gender + age required
    if (_variantGenderRef == null) {
      _showSnackBar('Please select a gender', Colors.orange);
      return;
    }
    if (_variantAgeRef == null) {
      _showSnackBar('Please select an age category', Colors.orange);
      return;
    }

    // Live validation
    _validateNewVariantPrice();
    _validateNewVariantDuration();

    // Price: optional. Empty => 0.
    final priceText = _variantPriceController.text.trim();
    final double price;
    if (priceText.isEmpty) {
      price = 0;
    } else {
      final parsed = double.tryParse(priceText);
      if (parsed == null || parsed < 0) {
        _showSnackBar(
          'Please enter a valid price (or leave empty)',
          Colors.orange,
        );
        return;
      }
      price = parsed;
    }

    // Duration: required
    final durationText = _variantDurationController.text.trim();
    final duration = int.tryParse(durationText);
    if (durationText.isEmpty || duration == null || duration <= 0) {
      _showSnackBar('Please enter a valid duration', Colors.orange);
      return;
    }

    final service = _addedServices[serviceIndex];
    final variants = service['variants'] as List;

    final isDuplicate = variants.any(
      (v) =>
          v['gender_ref'] == _variantGenderRef &&
          v['age_ref'] == _variantAgeRef,
    );
    if (isDuplicate) {
      _showSnackBar(
        'This gender + age combination is already added',
        Colors.orange,
      );
      return;
    }

    setState(() {
      variants.add({
        'gender_ref': _variantGenderRef,
        'age_ref': _variantAgeRef,
        'price': price,
        'duration': duration,
      });
      _variantGenderRef = null;
      _variantAgeRef = null;
      _variantPriceController.clear();
      _variantDurationController.clear();
      _newVariantPriceError = null;
      _newVariantDurationError = null;
    });
  }

  // ==================== STEP VALIDATION ====================

  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _nameController.text.trim().isNotEmpty &&
            _isPhoneValid &&
            _isEmailValid;
      case 1:
        return true;
      case 2:
        return _addedAgeCategories.isNotEmpty;
      case 3:
        return _selectedGenderIds.isNotEmpty;
      case 4:
        return _addedServiceCategories.isNotEmpty;
      case 5:
        return _addedServices.isNotEmpty;
      case 6:
        // Pricing step is OPTIONAL — can always proceed.
        return true;
      default:
        return true;
    }
  }

  String _stepRequirementMessage(int step) {
    switch (step) {
      case 0:
        return 'Please enter a salon name (and a valid phone/email if provided)';
      case 2:
        return 'Add at least one age category (e.g., Adult, Child)';
      case 3:
        return 'Select at least one gender your salon serves';
      case 4:
        return 'Add at least one service category (e.g., Hair, Nails, Spa)';
      case 5:
        return 'Add at least one service';
      default:
        return '';
    }
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
      if (step > _furthestStep) _furthestStep = step;
    });
  }

  // ==================== WIDGETS: SHARED HELPERS ====================

  Widget _buildStepHeader(String title, String subtitle) {
    final isDark = _isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${_currentStep + 1} OF $_totalSteps',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String message, IconData icon, Color color) {
    final isDark = _isDark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ),
        ],
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

  // ==================== WIDGETS: GENDERS ====================
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
                    onPressed: () {
                      setState(() {
                        _selectedGenderIds.clear();
                        for (var service in _addedServices) {
                          (service['variants'] as List).clear();
                        }
                      });
                    },
                    child: Text(
                      'Clear All',
                      style: TextStyle(
                        color: isDark ? Colors.red[300] : Colors.red,
                      ),
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
                        for (var service in _addedServices) {
                          (service['variants'] as List).removeWhere(
                            (v) => v['gender_ref'] == displayName,
                          );
                        }
                      }
                    });
                  },
                  backgroundColor: isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
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

  // ==================== SHARED: AGE FIELD / SUGGESTIONS / TEXT ====================

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

    Widget addFormBox() => Container(
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
    );

    Widget listBox() => Container(
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
                  onPressed: () => setState(() => addedItems.clear()),
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
    );

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
                      color: color,
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
                  Expanded(child: addFormBox()),
                  const SizedBox(width: 16),
                  Expanded(child: listBox()),
                ],
              )
            else
              Column(
                children: [addFormBox(), const SizedBox(height: 16), listBox()],
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
            hint: 'e.g., Child, Adult',
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
                children: const [
                  Icon(Icons.error_outline, size: 14, color: Colors.red),
                  SizedBox(width: 4),
                  Text(
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
      return _buildLoadingCard(
        'Service Categories',
        Icons.category,
        Colors.orange,
      );
    }
    if (_hasErrorLoadingData && _globalCategories.isEmpty) {
      return _buildErrorCard(
        'Service Categories',
        Icons.category,
        Colors.orange,
        () {
          _loadGlobalData();
        },
      );
    }

    return _buildSplitViewSection(
      title: 'Service Categories',
      icon: Icons.category,
      color: Colors.orange,
      addedItems: _addedServiceCategories,
      onRemove: _removeServiceCategory,
      itemDisplayName: (item) => item['display_name'],
      formFields: Column(
        children: [
          _buildSuggestionField(
            controller: _serviceCategoryDisplayNameController,
            label: 'Service Category Name *',
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
          _buildIconSelectorGeneric(
            selectedIcon: _selectedIcon,
            onSelect: (v) => setState(() => _selectedIcon = v),
          ),
          const SizedBox(height: 8),
          _buildColorPicker(),
        ],
      ),
      onAdd: _addServiceCategory,
    );
  }

  Widget _buildIconSelectorGeneric({
    required String selectedIcon,
    required ValueChanged<String> onSelect,
  }) {
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
              final isSelected = selectedIcon == iconItem['name'];

              return GestureDetector(
                onTap: () => onSelect(iconItem['name'] as String),
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
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  prefixIcon: Icon(
                    icon,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppTheme.primary,
                      width: 2,
                    ),
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

  // ==================== CURRENCY CARD ====================
  Widget _buildCurrencyCard() {
    final isDark = _isDark;

    return Card(
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
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.currency_exchange,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Currency',
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
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: isDark ? Colors.teal[300] : Colors.teal[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.teal[300] : Colors.teal[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Auto-detected from your timezone: $_salonTimezone',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _salonCurrencyCode,
              isExpanded: true,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                prefixIcon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1.0,
                    child: Text(
                      _salonCurrencySymbol,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 60,
                  minHeight: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: _supportedCurrencies.map((currency) {
                return DropdownMenuItem<String>(
                  value: currency['code'],
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${currency['code']} - ${currency['name']}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  final selected = _supportedCurrencies.firstWhere(
                    (c) => c['code'] == value,
                  );
                  setState(() {
                    _salonCurrencyCode = value;
                    _salonCurrencySymbol = selected['symbol']!;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark ? Colors.teal[300] : Colors.teal[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All prices will be in $_salonCurrencyCode ($_salonCurrencySymbol).',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.teal[300] : Colors.teal[700],
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
                    children: const [
                      Icon(Icons.edit, size: 14, color: Colors.white),
                      SizedBox(width: 4),
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
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
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
                  style: TextStyle(
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
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
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
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
                  style: TextStyle(
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
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
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppTheme.primary,
                  ),
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
                        _openTimeUtc =
                            TimezoneService.timeOfDayToUtcWithTimezone(
                              time,
                              _salonTimezone,
                            );
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
                        _closeTimeUtc =
                            TimezoneService.timeOfDayToUtcWithTimezone(
                              time,
                              _salonTimezone,
                            );
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
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
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

  // ==================== STEP 5: SERVICES ====================

  Widget _buildServicesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Add Services',
          'Add services under your categories. You can add pricing in the next step (optional).',
        ),
        if (_addedServiceCategories.isEmpty)
          _buildInfoBanner(
            'You need at least one service category before you can add services. Go back to the "Service Categories" step.',
            Icons.warning_amber,
            Colors.orange,
          )
        else
          _buildAddServiceCard(),
      ],
    );
  }

  Widget _buildAddServiceCard() {
    final isDark = _isDark;
    final isDesktop = _isWeb;
    final categorySelected = _serviceFormCategoryRef != null;

    Widget formBox() => Container(
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
                _editingServiceIndex >= 0 ? 'Edit Service' : 'Add New Service',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
              const Spacer(),
              if (_editingServiceIndex >= 0)
                TextButton(
                  onPressed: _cancelEditingService,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            initialValue: _serviceFormCategoryRef,
            isExpanded: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Select Category *',
              hintText: 'Choose a category...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              prefixIcon: Icon(
                Icons.category,
                size: 20,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: _addedServiceCategories
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c['display_name'] as String,
                    child: Text(c['display_name'] as String),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _serviceFormCategoryRef = v;
            }),
          ),

          if (categorySelected) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _newServiceNameController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Service Name *',
                hintText: 'e.g., Hair Cut, Facial',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                prefixIcon: Icon(
                  Icons.build,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                errorText: _serviceNameError,
                errorMaxLines: 2,
              ),
              onChanged: (_) => _validateNewServiceName(),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newServiceDescriptionController,
              maxLines: 2,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Describe this service...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                prefixIcon: Icon(
                  Icons.description,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildIconSelectorGeneric(
              selectedIcon:
                  _newServiceIcon ?? _iconList.first['name'] as String,
              onSelect: (v) => setState(() => _newServiceIcon = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveCurrentService,
                icon: Icon(
                  _editingServiceIndex >= 0 ? Icons.save : Icons.add,
                  size: 18,
                ),
                label: Text(
                  _editingServiceIndex >= 0 ? 'Update Service' : 'Add Service',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a category to continue',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    Widget listBox() => Container(
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
              const Icon(Icons.list, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Added Services',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
              const Spacer(),
              if (_addedServices.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _addedServices.clear()),
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
          if (_addedServices.isEmpty)
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
                      'No services added yet',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[500],
                        fontSize: 12,
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
              itemCount: _addedServices.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final service = _addedServices[index];
                final variants = service['variants'] as List;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    child: Icon(
                      _iconList.firstWhere(
                            (i) => i['name'] == service['icon_name'],
                            orElse: () => _iconList.first,
                          )['icon']
                          as IconData,
                      size: 18,
                      color: Colors.orange,
                    ),
                  ),
                  title: Text(
                    service['name'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    '${service['category_ref']} • ${variants.length} pricing${variants.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.blue,
                        ),
                        onPressed: () => _editAddedService(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: isDark ? Colors.red[300] : Colors.red,
                        ),
                        onPressed: () => _removeAddedService(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
        ],
      ),
    );

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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.build, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Text(
                  'Services',
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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_addedServices.length} items',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
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
                  Expanded(child: formBox()),
                  const SizedBox(width: 16),
                  Expanded(child: listBox()),
                ],
              )
            else
              Column(
                children: [formBox(), const SizedBox(height: 16), listBox()],
              ),
          ],
        ),
      ),
    );
  }

  // ==================== STEP 6: PRICING ====================

  Widget _buildPricingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Add Pricing (Optional)',
          'Optionally pick a service and add a price + duration for each gender/age combination. You can skip this step.',
        ),
        _buildInfoBanner(
          'This step is optional. If you skip it, your services will be saved without any pricing. You can add pricing later.',
          Icons.info_outline,
          Colors.blue,
        ),
        if (_addedServices.isEmpty)
          _buildInfoBanner(
            'You need at least one service first. Go back to the "Services" step.',
            Icons.warning_amber,
            Colors.orange,
          )
        else if (_addedAgeCategories.isEmpty || _selectedGenderIds.isEmpty)
          _buildInfoBanner(
            'You need age categories and genders before you can price a service.',
            Icons.warning_amber,
            Colors.orange,
          )
        else
          _buildAddPricingCard(),
      ],
    );
  }

  Widget _buildAddPricingCard() {
    final isDark = _isDark;
    final isDesktop = _isWeb;
    final genderOptions = _selectedGenderDisplayNames();

    final selectedService = _variantTargetServiceIndex != null
        ? _addedServices[_variantTargetServiceIndex!]
        : null;
    final variants = selectedService != null
        ? (selectedService['variants'] as List)
        : <dynamic>[];

    // ===== FORM BOX =====
    Widget addFormBox() => Container(
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
              const Text(
                'Add New Pricing',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Step 1: Service dropdown (always visible)
          DropdownButtonFormField<int>(
            initialValue: _variantTargetServiceIndex,
            isExpanded: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Select Service *',
              hintText: 'Choose a service...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              prefixIcon: Icon(
                Icons.build,
                size: 20,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: _addedServices.asMap().entries.map((entry) {
              final idx = entry.key;
              final svc = entry.value;
              final vCount = (svc['variants'] as List).length;
              return DropdownMenuItem<int>(
                value: idx,
                child: Text(
                  '${svc['name']} (${svc['category_ref']}) • $vCount pricing${vCount == 1 ? '' : 's'}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (v) => setState(() {
              _variantTargetServiceIndex = v;
              _variantGenderRef = null;
              _variantAgeRef = null;
              _variantPriceController.clear();
              _variantDurationController.clear();
              _newVariantPriceError = null;
              _newVariantDurationError = null;
            }),
          ),

          // Step 2: Only show the rest when a service is picked
          if (selectedService != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _variantGenderRef,
                    isExpanded: true,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Gender *',
                      hintText: 'Select',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      prefixIcon: Icon(
                        Icons.wc,
                        size: 20,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: genderOptions
                        .map(
                          (g) => DropdownMenuItem<String>(
                            value: g,
                            child: Text(g),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _variantGenderRef = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _variantAgeRef,
                    isExpanded: true,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Age Category *',
                      hintText: 'Select',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      prefixIcon: Icon(
                        Icons.timeline,
                        size: 20,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: _addedAgeCategories
                        .map(
                          (a) => DropdownMenuItem<String>(
                            value: a['display_name'] as String,
                            child: Text(
                              '${a['display_name']} (${a['min_age']}-${a['max_age']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _variantAgeRef = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _variantPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Price (optional)',
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          widthFactor: 1.0,
                          child: Text(
                            _salonCurrencySymbol,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 50,
                        minHeight: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      errorText: _newVariantPriceError,
                    ),
                    onChanged: (_) => _validateNewVariantPrice(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _variantDurationController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Duration (mins) *',
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      prefixIcon: Icon(
                        Icons.timer,
                        size: 20,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      errorText: _newVariantDurationError,
                    ),
                    onChanged: (_) => _validateNewVariantDuration(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _addVariantToService(_variantTargetServiceIndex!),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Pricing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a service to add pricing',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    // ===== LIST BOX =====
    Widget listBox() => Container(
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
              const Icon(Icons.list, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedService != null
                      ? 'Pricing — ${selectedService['name']}'
                      : 'Added Pricing',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (variants.isNotEmpty && selectedService != null)
                TextButton(
                  onPressed: () => setState(
                    () => (selectedService['variants'] as List).clear(),
                  ),
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
          if (selectedService == null)
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
                      Icons.tune,
                      size: 40,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a service to view its pricing',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (variants.isEmpty)
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
                      'No pricing added yet',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[500],
                        fontSize: 12,
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
              itemCount: variants.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final v = variants[index];
                final gender = v['gender_ref'] as String;
                final age = v['age_ref'] as String;
                final price = v['price'] as double;
                final duration = v['duration'] as int;
                final priceDisplay = price == 0
                    ? 'Free'
                    : '$_salonCurrencySymbol${price.toStringAsFixed(0)}';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  title: Text(
                    '$gender • $age',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    '$priceDisplay • $duration min',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: isDark ? Colors.red[300] : Colors.red,
                    ),
                    onPressed: () => setState(() {
                      (selectedService['variants'] as List).removeAt(index);
                    }),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
        ],
      ),
    );

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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Text(
                  'Pricing',
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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${variants.length} items',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
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
                  Expanded(child: addFormBox()),
                  const SizedBox(width: 16),
                  Expanded(child: listBox()),
                ],
              )
            else
              Column(
                children: [addFormBox(), const SizedBox(height: 16), listBox()],
              ),
          ],
        ),
      ),
    );
  }

  // ==================== STEP 7: REVIEW ====================

  Widget _buildReviewTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onEdit,
  }) {
    final isDark = _isDark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final totalVariants = _addedServices.fold<int>(
      0,
      (sum, s) => sum + (s['variants'] as List).length,
    );
    final servicesWithVariants = _addedServices
        .where((s) => (s['variants'] as List).isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Review & Create',
          'Check everything below, then tap "Create Salon" to finish.',
        ),
        _buildReviewTile(
          icon: Icons.store,
          title: 'Salon Name',
          value: _nameController.text.trim().isEmpty
              ? 'Not set'
              : _nameController.text.trim(),
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.access_time,
          title: 'Business Hours & Currency',
          value:
              '${_openTimeLocal.format(context)} - ${_closeTimeLocal.format(context)} · $_salonCurrencyCode ($_salonCurrencySymbol)',
          onEdit: () => _goToStep(1),
        ),
        _buildReviewTile(
          icon: Icons.calendar_today,
          title: 'Age Categories',
          value: '${_addedAgeCategories.length} added',
          onEdit: () => _goToStep(2),
        ),
        _buildReviewTile(
          icon: Icons.people,
          title: 'Genders',
          value: '${_selectedGenderIds.length} selected',
          onEdit: () => _goToStep(3),
        ),
        _buildReviewTile(
          icon: Icons.category,
          title: 'Service Categories',
          value: '${_addedServiceCategories.length} added',
          onEdit: () => _goToStep(4),
        ),
        _buildReviewTile(
          icon: Icons.build,
          title: 'Services',
          value: '${_addedServices.length} services',
          onEdit: () => _goToStep(5),
        ),
        _buildReviewTile(
          icon: Icons.tune,
          title: 'Pricing (optional)',
          value: totalVariants == 0
              ? 'None — services will be saved without pricing'
              : '$totalVariants pricing entries across $servicesWithVariants service${servicesWithVariants == 1 ? '' : 's'}',
          onEdit: () => _goToStep(6),
        ),
        const SizedBox(height: 8),
        _buildInfoBanner(
          'Tapping "Create Salon" will save the salon, its categories, ages, genders, and all services${totalVariants > 0 ? ' with their pricing' : ' (no pricing)'}.',
          Icons.info_outline,
          AppTheme.primary,
        ),
      ],
    );
  }

  // ==================== CREATE SALON ====================
  Future<void> _onCreateSalonPressed() async {
    // Only validate required steps (skip step 6 — pricing is optional)
    for (int step = 0; step <= 7; step++) {
      if (step == 6) continue; // Pricing step is optional
      if (!_canProceedFromStep(step)) {
        _goToStep(step);
        _showSnackBar(_stepRequirementMessage(step), Colors.orange);
        return;
      }
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please login first', Colors.red);
      return;
    }

    if (_isConfirmDialogOpen) return;
    _isConfirmDialogOpen = true;

    final totalVariants = _addedServices.fold<int>(
      0,
      (sum, s) => sum + (s['variants'] as List).length,
    );

    final confirmed = await showCustomAlert(
      context: context,
      title: "Create Salon?",
      message:
          'Do you want to create "${_nameController.text.trim()}"?\n\n'
          'Service Categories: ${_addedServiceCategories.length}\n'
          'Services: ${_addedServices.length}\n'
          'Pricing entries: $totalVariants\n'
          'Currency: $_salonCurrencyCode ($_salonCurrencySymbol)\n'
          'Timezone: $_salonTimezone\n\n'
          'This will save the salon with everything you\'ve set up.',
      isError: false,
      buttonText: "Create",
      buttonIcon: Icons.add_business,
      showCancelButton: true,
      cancelButtonText: "Cancel",
    );

    _isConfirmDialogOpen = false;

    if (!mounted) return;
    if (confirmed != true) return;

    await _performCreateSalon();
  }

  Future<void> _performCreateSalon() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        _showSnackBar('Please login first', Colors.red);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userTimezone =
          prefs.getString(TimezoneService.kUserTimezone) ??
          TimezoneService.getCurrentTimezone();

      final extraData = {
        'created_from': _isWeb ? 'web' : 'mobile',
        'platform': _getPlatformName(),
        'user_timezone': userTimezone,
      };

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
        'currency_code': _salonCurrencyCode,
        'currency_symbol': _salonCurrencySymbol,
        'extra_data': extraData,
        'is_active': true,
      };

      final response = await supabase
          .from('salons')
          .insert(salonData)
          .select('id, name')
          .single();
      final salonId = response['id'] as int;
      debugPrint('✅ Salon created with ID: $salonId');

      String? logoUrl = (_logoFile != null || _logoWebBytes != null)
          ? await _uploadLogo(salonId)
          : null;
      String? coverUrl = (_coverFile != null || _coverWebBytes != null)
          ? await _uploadCover(salonId)
          : null;

      if (logoUrl != null || coverUrl != null) {
        final imageUpdate = <String, dynamic>{};
        if (logoUrl != null) imageUpdate['logo_url'] = logoUrl;
        if (coverUrl != null) imageUpdate['cover_url'] = coverUrl;
        await supabase.from('salons').update(imageUpdate).eq('id', salonId);
      }

      // ---- Genders ----
      final Map<String, int> genderIdMap = {};
      for (int i = 0; i < _selectedGenderIds.length; i++) {
        final genderId = _selectedGenderIds[i];
        final gender = _globalGenders.firstWhere((g) => g['id'] == genderId);
        final displayName = gender['display_name'] as String;
        final inserted = await supabase
            .from('salon_genders')
            .insert({
              'salon_id': salonId,
              'display_name': displayName,
              'display_order': i,
              'is_active': true,
            })
            .select('id')
            .single();
        genderIdMap[displayName] = inserted['id'] as int;
      }

      // ---- Age categories ----
      final Map<String, int> ageIdMap = {};
      for (var ageCat in _addedAgeCategories) {
        final inserted = await supabase
            .from('salon_age_categories')
            .insert({
              'salon_id': salonId,
              'display_name': ageCat['display_name'],
              'min_age': ageCat['min_age'],
              'max_age': ageCat['max_age'],
              'display_order': ageCat['display_order'],
              'is_active': ageCat['is_active'],
            })
            .select('id')
            .single();
        ageIdMap[ageCat['display_name'] as String] = inserted['id'] as int;
      }

      // ---- Service categories ----
      final Map<String, int> categoryIdMap = {};
      for (var serviceCat in _addedServiceCategories) {
        final inserted = await supabase
            .from('salon_categories')
            .insert({
              'salon_id': salonId,
              'display_name': serviceCat['display_name'],
              'description': serviceCat['description'],
              'icon_name': serviceCat['icon_name'],
              'color': serviceCat['color'],
              'display_order': serviceCat['display_order'],
              'is_active': serviceCat['is_active'],
            })
            .select('id')
            .single();
        categoryIdMap[serviceCat['display_name'] as String] =
            inserted['id'] as int;
      }

      // ---- Services + pricing ----
      for (var svc in _addedServices) {
        final categoryId = categoryIdMap[svc['category_ref']];
        final description = (svc['description'] as String).isNotEmpty
            ? svc['description']
            : null;

        final serviceInserted = await supabase
            .from('services')
            .insert({
              'salon_id': salonId,
              'name': svc['name'],
              'description': description,
              'category_id': categoryId,
              'icon_name': svc['icon_name'],
              'is_active': true,
              'created_by': userId,
            })
            .select('id')
            .single();
        final serviceId = serviceInserted['id'] as int;

        // Pricing is optional — skip if none
        for (var v in (svc['variants'] as List)) {
          final genderId = genderIdMap[v['gender_ref']];
          final ageId = ageIdMap[v['age_ref']];
          await supabase.from('service_variants').insert({
            'service_id': serviceId,
            'salon_gender_id': genderId,
            'salon_age_category_id': ageId,
            'price': v['price'], // 0 if empty was passed
            'duration': v['duration'],
            'is_active': true,
          });
        }
      }

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

  // ==================== STEP CONTENT SWITCH ====================

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Basic & Contact Information',
          'Add your salon\'s core details and how customers can reach you.',
        ),
        _buildCoverSection(),
        Transform.translate(
          offset: const Offset(16, -40),
          child: Align(
            alignment: Alignment.topLeft,
            child: _buildLogoSeparate(),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                    color: _isDark ? Colors.white : Colors.black87,
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
        Card(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                    color: _isDark ? Colors.white : Colors.black87,
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
                  hint: 'Enter email address (e.g., salon@example.com)',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  isEmail: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'Phone and email are optional but recommended',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Business Hours & Currency',
          'Set your working hours; the currency is auto-detected but you can change it.',
        ),
        _buildBusinessHoursCard(),
        const SizedBox(height: 16),
        _buildCurrencyCard(),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Age Categories',
          'Define the age groups your salon prices differently, e.g. Child, Adult, Senior.',
        ),
        _buildAgeCategorySection(),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Genders',
          'Select which genders your salon serves. This is combined with age categories to price each service.',
        ),
        _buildGenderSelection(),
      ],
    );
  }

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Service Categories',
          'Group your services under categories like Hair, Nails, or Spa. You\'ll add individual services under these in a later step.',
        ),
        _buildServiceCategorySection(),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2(); // Ages
      case 3:
        return _buildStep3(); // Genders
      case 4:
        return _buildStep4(); // Service Categories
      case 5:
        return _buildServicesStep(); // Services
      case 6:
        return _buildPricingStep(); // Pricing (optional)
      case 7:
        return _buildReviewStep(); // Review
      default:
        return const SizedBox();
    }
  }

  // ==================== STEP INDICATOR ====================

  static const List<Map<String, dynamic>> _stepMeta = [
    {'label': 'Basic', 'icon': Icons.store},
    {'label': 'Hours', 'icon': Icons.access_time},
    {'label': 'Ages', 'icon': Icons.calendar_today},
    {'label': 'Genders', 'icon': Icons.people},
    {'label': 'Categories', 'icon': Icons.category},
    {'label': 'Services', 'icon': Icons.build},
    {'label': 'Pricing', 'icon': Icons.tune},
    {'label': 'Review', 'icon': Icons.check_circle},
  ];

  Widget _buildStepIndicatorRow() {
    final isMobile = !_isWeb;

    return Container(
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 20,
          vertical: isMobile ? 12 : 16,
        ),
        child: Row(
          children: [
            for (int i = 0; i < _stepMeta.length; i++) ...[
              _buildStepCircle(
                i,
                _stepMeta[i]['label'] as String,
                _stepMeta[i]['icon'] as IconData,
                isMobile,
              ),
              if (i != _stepMeta.length - 1)
                Container(
                  width: isMobile ? 18 : 30,
                  height: 2,
                  color: _furthestStep > i
                      ? AppTheme.primary
                      : Colors.grey[300],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepCircle(
    int step,
    String label,
    IconData icon,
    bool isMobile,
  ) {
    final isActive = _currentStep == step;
    final isCompleted = _furthestStep > step;
    final isDark = _isDark;
    final size = isMobile ? 34.0 : 42.0;
    final iconSize = isMobile ? 16.0 : 20.0;
    final canTap = step <= _furthestStep;

    return GestureDetector(
      onTap: canTap ? () => _goToStep(step) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? AppTheme.primary
                  : (isActive
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : (isDark ? Colors.grey[800] : Colors.grey[200])),
              border: Border.all(
                color: isActive
                    ? AppTheme.primary
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
                width: isActive ? 2 : 1.5,
              ),
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check, size: iconSize, color: Colors.white)
                  : Icon(
                      icon,
                      size: iconSize,
                      color: isActive ? AppTheme.primary : Colors.grey[500],
                    ),
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? AppTheme.primary
                    : (isDark ? Colors.white60 : Colors.grey[500]),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== BOTTOM NAVIGATION ====================

  Widget _buildBottomNavBar() {
    final isDark = _isDark;
    final isLastStep = _currentStep == 7;
    final canProceed = _canProceedFromStep(_currentStep);
    final busy = _isLoading || _isUploadingLogo || _isUploadingCover;
    final isPricingStep = _currentStep == 6;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => setState(() => _currentStep--),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: busy
                    ? null
                    : () {
                        if (!canProceed) {
                          _showSnackBar(
                            _stepRequirementMessage(_currentStep),
                            Colors.orange,
                          );
                          return;
                        }
                        if (isLastStep) {
                          _onCreateSalonPressed();
                        } else {
                          setState(() {
                            _currentStep++;
                            if (_currentStep > _furthestStep) {
                              _furthestStep = _currentStep;
                            }
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: canProceed
                      ? AppTheme.primary
                      : (isDark ? Colors.grey[800] : Colors.grey[300]),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isUploadingLogo || _isUploadingCover
                                ? 'Uploading...'
                                : 'Creating...',
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLastStep
                                ? 'Create Salon'
                                : (isPricingStep
                                      ? 'Skip / Continue'
                                      : 'Continue'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isLastStep
                                ? Icons.check_circle
                                : Icons.arrow_forward,
                            size: 20,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;
    _isWeb = isWeb;
    _isDark = isDark;

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
        title: const Text(
          'Create New Salon',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
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
                maxWidth: isWeb ? 1000 : double.infinity,
              ),
              child: Column(
                children: [
                  _buildStepIndicatorRow(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isWeb ? 32 : 16),
                      child: _buildStepContent(),
                    ),
                  ),
                  _buildBottomNavBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
