import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/currency_prefix.dart';
import 'package:flutter_application_1/services/currency_service.dart';

class AddServiceScreen extends StatefulWidget {
  final int salonId;
  final int? salonBarberId;
  final String? barberName;
  final bool isEditing;
  final int? serviceId;

  const AddServiceScreen({
    super.key,
    required this.salonId,
    this.salonBarberId,
    this.barberName,
    this.isEditing = false,
    this.serviceId,
  });

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  // ==================== CONTROLLERS ====================
  final TextEditingController _serviceNameController = TextEditingController();
  final TextEditingController _serviceDescriptionController =
      TextEditingController();
  final TextEditingController _variantPriceController = TextEditingController();
  final TextEditingController _variantDurationController =
      TextEditingController();
  final TextEditingController _ageDisplayNameController =
      TextEditingController();
  final TextEditingController _ageMinController = TextEditingController();
  final TextEditingController _ageMaxController = TextEditingController();
  final TextEditingController _newCategoryNameController =
      TextEditingController();
  final TextEditingController _newCategoryDescriptionController =
      TextEditingController();

  // ==================== SERVICES ====================
  final CurrencyService _currencyService = CurrencyService.instance;

  // ==================== SELECTED ====================
  int? _selectedCategoryId;
  String? _selectedIcon;
  String _selectedCategoryColor = '#FF6B8B';
  int? _editingCategoryId;

  int? _variantTargetServiceIndex;
  int? _selectedGenderId;
  int? _selectedAgeCategoryId;

  // ==================== DATA ====================
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _genders = [];
  List<Map<String, dynamic>> _ageCategories = [];
  List<Map<String, dynamic>> _globalAgeCategories = [];

  final List<Map<String, dynamic>> _addedServices = [];
  final Set<int> _dbServiceIds = {};

  int _editingServiceIndex = -1;
  int _editingVariantIndex = -1;

  // ==================== LOADING ====================
  bool _isLoadingData = true;
  bool _isLoading = false;
  bool _isAddingAgeCategory = false;
  bool _isLoadingVariants = false;

  // ==================== VALIDATION ====================
  String? _priceError;
  String? _durationError;
  String? _serviceNameError;
  String? _categoryNameError;
  String? _ageNameError;
  String? _ageMinError;
  String? _ageMaxError;

  // ==================== CURRENCY ====================
  String _salonCurrencyCode = 'LKR';

  // ==================== RESPONSIVE ====================
  bool _isWeb = false;
  bool _isDark = false;

  // ==================== EXPANDABLE ARROWS ====================
  bool _variantsSectionExpanded = false;
  bool _genderExpanded = false;
  bool _ageExpanded = false;
  bool _durationExpanded = false;
  bool _priceExpanded = false;

  // ✅ NEW: "Add New Age Category" arrow inside the age typing form
  bool _addAgeCategoryFormExpanded = false;

  // ==================== ICON SUGGESTIONS ====================
  final List<Map<String, dynamic>> _iconSuggestions = [
    {
      'icon': Icons.content_cut,
      'name': 'content_cut',
      'label': 'Hair Cut',
      'color': 0xFFFF6B8B,
    },
    {'icon': Icons.face, 'name': 'face', 'label': 'Face', 'color': 0xFF4CAF50},
    {
      'icon': Icons.face_retouching_natural,
      'name': 'face_retouching_natural',
      'label': 'Grooming',
      'color': 0xFF2196F3,
    },
    {'icon': Icons.spa, 'name': 'spa', 'label': 'Spa', 'color': 0xFF9C27B0},
    {
      'icon': Icons.handshake,
      'name': 'handshake',
      'label': 'Nails',
      'color': 0xFFFF9800,
    },
    {
      'icon': Icons.build,
      'name': 'build',
      'label': 'Service',
      'color': 0xFF795548,
    },
    {
      'icon': Icons.brush,
      'name': 'brush',
      'label': 'Makeup',
      'color': 0xFFE91E63,
    },
    {
      'icon': Icons.cut,
      'name': 'cut',
      'label': 'Hair Cut',
      'color': 0xFFFF6B8B,
    },
    {
      'icon': Icons.shower,
      'name': 'shower',
      'label': 'Shower',
      'color': 0xFF00BCD4,
    },
    {
      'icon': Icons.masks,
      'name': 'masks',
      'label': 'Masks',
      'color': 0xFF607D8B,
    },
    {
      'icon': Icons.palette,
      'name': 'palette',
      'label': 'Makeup',
      'color': 0xFFE91E63,
    },
    {
      'icon': Icons.spa_outlined,
      'name': 'spa_outlined',
      'label': 'Wellness',
      'color': 0xFF9C27B0,
    },
  ];

  // ==================== CATEGORY COLOR OPTIONS ====================
  final List<Map<String, dynamic>> _categoryColorOptions = [
    {'hex': '#FF6B8B', 'color': const Color(0xFFFF6B8B)},
    {'hex': '#4CAF50', 'color': const Color(0xFF4CAF50)},
    {'hex': '#2196F3', 'color': const Color(0xFF2196F3)},
    {'hex': '#FF9800', 'color': const Color(0xFFFF9800)},
    {'hex': '#9C27B0', 'color': const Color(0xFF9C27B0)},
    {'hex': '#F44336', 'color': const Color(0xFFF44336)},
    {'hex': '#00BCD4', 'color': const Color(0xFF00BCD4)},
    {'hex': '#795548', 'color': const Color(0xFF795548)},
    {'hex': '#607D8B', 'color': const Color(0xFF607D8B)},
  ];

  final supabase = Supabase.instance.client;

  // ==================== CURRENCY GETTERS ====================
  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_salonCurrencyCode);

  bool get _currencyUsesDecimals =>
      _currencyService.getInfo(_salonCurrencyCode).decimals > 0;

  bool get _hasAtLeastOneVariantField =>
      _selectedGenderId != null ||
      _selectedAgeCategoryId != null ||
      _variantDurationController.text.trim().isNotEmpty ||
      _variantPriceController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ageMinController.text = '0';
    _ageMaxController.text = '100';
    _loadData();
    _loadSalonCurrency();
    _selectedIcon = _iconSuggestions.first['name'];
    _selectedCategoryColor = _categoryColorOptions.first['hex'];

    _variantPriceController.addListener(_onVariantFieldChanged);
    _variantDurationController.addListener(_onVariantFieldChanged);
    _serviceNameController.addListener(_validateServiceName);
    _newCategoryNameController.addListener(_validateCategoryName);
    _ageDisplayNameController.addListener(_validateAgeFields);
    _ageMinController.addListener(_validateAgeFields);
    _ageMaxController.addListener(_validateAgeFields);
  }

  void _onVariantFieldChanged() {
    _validatePrice();
    _validateDuration();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _serviceNameController.dispose();
    _serviceDescriptionController.dispose();
    _variantPriceController.dispose();
    _variantDurationController.dispose();
    _newCategoryNameController.dispose();
    _newCategoryDescriptionController.dispose();
    _ageDisplayNameController.dispose();
    _ageMinController.dispose();
    _ageMaxController.dispose();
    super.dispose();
  }

  // ============================================
  // CURRENCY LOADING
  // ============================================
  Future<void> _loadSalonCurrency() async {
    try {
      final response = await supabase
          .from('salons')
          .select('currency_code')
          .eq('id', widget.salonId)
          .single();

      if (!mounted) return;
      setState(() {
        _salonCurrencyCode = response['currency_code'] as String? ?? 'LKR';
      });
    } catch (e) {
      debugPrint('Error loading salon currency: $e');
    }
  }

  // ============================================
  // VALIDATION
  // ============================================
  void _validateServiceName() {
    final String name = _serviceNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _serviceNameError = null);
      return;
    }
    if (widget.isEditing && widget.serviceId != null) {
      setState(() => _serviceNameError = null);
      return;
    }
    final bool exists = _addedServices.asMap().entries.any(
          (e) =>
              e.value['name'].toString().toLowerCase() == name.toLowerCase() &&
              e.key != _editingServiceIndex,
        );
    setState(() {
      _serviceNameError =
          exists ? 'A service with this name already exists' : null;
    });
  }

  void _validateCategoryName() {
    final String name = _newCategoryNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _categoryNameError = null);
      return;
    }
    final bool exists = _categories.any(
      (c) =>
          c['display_name'].toString().toLowerCase() == name.toLowerCase() &&
          c['id'] != _editingCategoryId,
    );
    setState(() {
      _categoryNameError =
          exists ? 'A category with this name already exists' : null;
    });
  }

  void _validateAgeFields() {
    setState(() {
      final name = _ageDisplayNameController.text.trim();
      if (name.isEmpty) {
        _ageNameError = null;
      } else {
        final exists = _ageCategories.any(
          (a) =>
              a['display_name'].toString().toLowerCase() == name.toLowerCase(),
        );
        _ageNameError =
            exists ? 'This age category already exists' : null;
      }

      final minStr = _ageMinController.text.trim();
      final maxStr = _ageMaxController.text.trim();
      final min = int.tryParse(minStr);
      final max = int.tryParse(maxStr);

      if (minStr.isEmpty) {
        _ageMinError = null;
      } else if (min == null) {
        _ageMinError = 'Enter a valid number';
      } else if (min < 0 || min > 150) {
        _ageMinError = 'Age must be 0-150';
      } else {
        _ageMinError = null;
      }

      if (maxStr.isEmpty) {
        _ageMaxError = null;
      } else if (max == null) {
        _ageMaxError = 'Enter a valid number';
      } else if (max < 0 || max > 150) {
        _ageMaxError = 'Age must be 0-150';
      } else if (min != null && max < min) {
        _ageMaxError = 'Max must be >= min';
      } else {
        _ageMaxError = null;
      }
    });
  }

  void _validatePrice() {
    final String priceText = _variantPriceController.text.trim();
    if (priceText.isEmpty) {
      setState(() => _priceError = null);
      return;
    }

    final double? price = double.tryParse(priceText);
    if (price == null) {
      setState(() => _priceError = 'Please enter a valid number');
      return;
    }
    if (price < 0) {
      setState(() => _priceError = 'Price cannot be negative');
      return;
    }

    if (!_currencyUsesDecimals && priceText.contains('.')) {
      final decimalPart = priceText.split('.').last;
      if (decimalPart.isNotEmpty && int.tryParse(decimalPart) != 0) {
        setState(() {
          _priceError = '$_salonCurrencyCode does not use decimals';
        });
        return;
      }
    }

    setState(() => _priceError = null);
  }

  void _validateDuration() {
    final String durationText = _variantDurationController.text.trim();
    if (durationText.isEmpty) {
      setState(() => _durationError = null);
      return;
    }

    final int? duration = int.tryParse(durationText);
    if (duration == null) {
      setState(() => _durationError = 'Please enter a valid number');
    } else if (duration <= 0) {
      setState(() => _durationError = 'Duration must be greater than 0');
    } else {
      setState(() => _durationError = null);
    }
  }

  // ============================================
  // DATA LOADING
  // ============================================
  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);

    try {
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select(
            'id, display_name, description, icon_name, color, display_order, is_active',
          )
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name, display_order, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      final ageResponse = await supabase
          .from('salon_age_categories')
          .select(
            'id, display_name, min_age, max_age, display_order, is_active',
          )
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      List<dynamic> globalAgeResponse = [];
      try {
        globalAgeResponse = await supabase
            .from('age_categories')
            .select('id, display_name, min_age, max_age, display_order')
            .eq('is_active', true)
            .order('display_order');
      } catch (e) {
        debugPrint('Could not load global age categories: $e');
      }

      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _genders = List<Map<String, dynamic>>.from(gendersResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
        _globalAgeCategories =
            List<Map<String, dynamic>>.from(globalAgeResponse);

        if (_categories.isNotEmpty && _selectedCategoryId == null) {
          _selectedCategoryId = _categories.first['id'] as int;
        }

        // ✅ Auto-expand the "Add New Age Category" form ONLY IF there are
        // no existing age categories. Otherwise, keep it collapsed.
        _addAgeCategoryFormExpanded = _ageCategories.isEmpty;
      });

      await _loadExistingServicesFromDb();

      if (widget.isEditing && widget.serviceId != null) {
        await _loadServiceForEdit();
      }

      setState(() => _isLoadingData = false);
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        _showSnackBar('Error loading data: $e', Colors.red);
      }
    }
  }

  Future<void> _loadExistingServicesFromDb() async {
    try {
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('name');

      if (servicesResponse.isEmpty) return;

      final Map<String, Map<String, dynamic>> uniqueByName = {};
      for (var s in servicesResponse) {
        final name = (s['name'] as String).trim().toLowerCase();
        if (!uniqueByName.containsKey(name)) {
          uniqueByName[name] = Map<String, dynamic>.from(s);
        }
      }
      final uniqueServices = uniqueByName.values.toList();

      final serviceIds =
          uniqueServices.map<int>((s) => s['id'] as int).toList();

      final variantsResponse = await supabase
          .from('service_variants')
          .select(
              'id, service_id, price, duration, salon_gender_id, salon_age_category_id')
          .inFilter('service_id', serviceIds)
          .eq('is_active', true);

      final genderIdToName = <int, String>{};
      for (var g in _genders) {
        genderIdToName[g['id'] as int] = _getGenderDisplayName(g);
      }
      final ageIdToName = <int, String>{};
      for (var a in _ageCategories) {
        ageIdToName[a['id'] as int] = _getAgeCategoryDisplayName(a);
      }

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var v in variantsResponse) {
        final sid = v['service_id'] as int;
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final genderName = genderId != null
            ? (genderIdToName[genderId] ?? 'Any')
            : 'Any';
        final ageName =
            ageId != null ? (ageIdToName[ageId] ?? 'Any') : 'Any';

        final priceNum = (v['price'] as num?)?.toDouble();

        variantsByService.putIfAbsent(sid, () => []).add({
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_category_name': ageName,
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'variant_id': v['id'],
          'from_db': true,
        });
      }

      setState(() {
        for (var s in uniqueServices) {
          final sid = s['id'] as int;
          if (_addedServices.any((existing) => existing['id'] == sid)) {
            continue;
          }
          _addedServices.add({
            'id': sid,
            'name': s['name'] ?? '',
            'description': s['description'] ?? '',
            'icon_name': s['icon_name'] ?? 'content_cut',
            'category_id': s['category_id'],
            'variants': variantsByService[sid] ?? <Map<String, dynamic>>[],
            'from_db': true,
          });
          _dbServiceIds.add(sid);
        }
      });
    } catch (e) {
      debugPrint('Error loading existing services: $e');
    }
  }

  Future<void> _loadServiceForEdit() async {
    try {
      final serviceResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id')
          .eq('id', widget.serviceId!)
          .single();

      final variantsResponse = await supabase
          .from('service_variants')
          .select('id, price, duration, salon_gender_id, salon_age_category_id')
          .eq('service_id', widget.serviceId!)
          .eq('is_active', true);

      final variants = <Map<String, dynamic>>[];
      for (var v in variantsResponse) {
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final gender = genderId != null
            ? _genders.firstWhere(
                (g) => g['id'] == genderId,
                orElse: () => {'display_name': 'Any'},
              )
            : {'display_name': 'Any'};
        final ageCat = ageId != null
            ? _ageCategories.firstWhere(
                (a) => a['id'] == ageId,
                orElse: () => {
                  'display_name': 'Any',
                  'min_age': 0,
                  'max_age': 0,
                },
              )
            : {
                'display_name': 'Any',
                'min_age': 0,
                'max_age': 0,
              };

        final priceNum = (v['price'] as num?)?.toDouble();

        variants.add({
          'gender_id': genderId,
          'gender_name': _getGenderDisplayName(gender),
          'age_category_id': ageId,
          'age_category_name': _getAgeCategoryDisplayName(ageCat),
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'variant_id': v['id'],
          'from_db': true,
        });
      }

      setState(() {
        _addedServices.removeWhere((s) => s['id'] == widget.serviceId);
        _addedServices.insert(0, {
          'id': serviceResponse['id'],
          'name': serviceResponse['name'] ?? '',
          'description': serviceResponse['description'] ?? '',
          'icon_name': serviceResponse['icon_name'] ?? 'content_cut',
          'category_id': serviceResponse['category_id'],
          'variants': variants,
          'from_db': true,
        });
        _dbServiceIds.add(serviceResponse['id'] as int);
        _editingServiceIndex = 0;

        _selectedCategoryId = serviceResponse['category_id'];
        _serviceNameController.text = serviceResponse['name'] ?? '';
        _serviceDescriptionController.text =
            serviceResponse['description'] ?? '';
        _selectedIcon =
            serviceResponse['icon_name'] ?? _iconSuggestions.first['name'];
      });
    } catch (e) {
      debugPrint('Error loading service for edit: $e');
    }
  }

  Future<void> _loadVariantsForService(int serviceIndex) async {
    final service = _addedServices[serviceIndex];
    final serviceId = service['id'];
    if (serviceId == null) return;

    setState(() => _isLoadingVariants = true);
    try {
      final variantsResponse = await supabase
          .from('service_variants')
          .select('id, price, duration, salon_gender_id, salon_age_category_id')
          .eq('service_id', serviceId)
          .eq('is_active', true);

      final genderIdToName = <int, String>{};
      for (var g in _genders) {
        genderIdToName[g['id'] as int] = _getGenderDisplayName(g);
      }
      final ageIdToName = <int, String>{};
      for (var a in _ageCategories) {
        ageIdToName[a['id'] as int] = _getAgeCategoryDisplayName(a);
      }

      final loaded = <Map<String, dynamic>>[];
      for (var v in variantsResponse) {
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final genderName = genderId != null
            ? (genderIdToName[genderId] ?? 'Any')
            : 'Any';
        final ageName =
            ageId != null ? (ageIdToName[ageId] ?? 'Any') : 'Any';

        final priceNum = (v['price'] as num?)?.toDouble();

        loaded.add({
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_category_name': ageName,
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'variant_id': v['id'],
          'from_db': true,
        });
      }

      setState(() {
        service['variants'] = loaded;
      });
    } catch (e) {
      debugPrint('Error loading variants: $e');
    } finally {
      if (mounted) setState(() => _isLoadingVariants = false);
    }
  }

  // ============================================
  // HELPERS
  // ============================================
  String _getCategoryDisplayName(Map<String, dynamic> category) {
    return category['display_name'] ?? 'Unknown';
  }

  String _getGenderDisplayName(Map<String, dynamic> gender) {
    return gender['display_name'] ?? 'Unknown';
  }

  String _getAgeCategoryDisplayName(Map<String, dynamic> ageCat) {
    String name = ageCat['display_name'] ?? 'Unknown';
    if (ageCat['min_age'] != null && ageCat['max_age'] != null) {
      name = '$name (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
    }
    return name;
  }

  Map<String, dynamic>? _getCategoryById(int? id) {
    if (id == null) return null;
    try {
      return _categories.firstWhere((c) => c['id'] == id);
    } catch (_) {
      return null;
    }
  }

  bool _isVariantDuplicate(int serviceIndex) {
    final service = _addedServices[serviceIndex];
    final variants = service['variants'] as List;

    final newGenderId = _selectedGenderId;
    final newAgeId = _selectedAgeCategoryId;
    final newDuration =
        int.tryParse(_variantDurationController.text.trim()) ?? 0;

    return variants.any((v) {
      if (_editingVariantIndex >= 0 &&
          variants.indexOf(v) == _editingVariantIndex) {
        return false;
      }

      final sameGender = (v['gender_id'] as int?) == newGenderId;
      final sameAge = (v['age_category_id'] as int?) == newAgeId;
      final sameDuration =
          ((v['duration'] as num?)?.toInt() ?? 0) == newDuration;

      return sameGender && sameAge && sameDuration;
    });
  }

  String _formatPriceDisplay(Map<String, dynamic> v) {
    final priceSet = v['price_set'] == true;
    final price = (v['price'] as num?)?.toDouble() ?? 0.0;

    if (!priceSet) {
      return 'Not set';
    }
    if (price == 0) {
      return 'Free';
    }
    return _currencyService.format(
      price: price,
      currencyCode: _salonCurrencyCode,
    );
  }

  bool _isPriceNotSet(Map<String, dynamic> v) {
    return v['price_set'] != true;
  }

  // ============================================
  // CATEGORY MANAGEMENT
  // ============================================
  Future<void> _addOrUpdateCategory() async {
    final displayName = _newCategoryNameController.text.trim();
    if (displayName.isEmpty) {
      _showSnackBar('Category name is required', Colors.orange);
      return;
    }
    if (_categoryNameError != null) {
      _showSnackBar(_categoryNameError!, Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final data = {
        'salon_id': widget.salonId,
        'display_name': displayName,
        'description': _newCategoryDescriptionController.text.trim().isEmpty
            ? null
            : _newCategoryDescriptionController.text.trim(),
        'icon_name': _selectedIcon,
        'color': _selectedCategoryColor,
        'is_active': true,
      };

      if (_editingCategoryId != null) {
        await supabase
            .from('salon_categories')
            .update(data)
            .eq('id', _editingCategoryId!);

        setState(() {
          final idx =
              _categories.indexWhere((c) => c['id'] == _editingCategoryId);
          if (idx >= 0) {
            _categories[idx] = {
              ..._categories[idx],
              ...data,
            };
          }
          _editingCategoryId = null;
          _newCategoryNameController.clear();
          _newCategoryDescriptionController.clear();
          _selectedIcon = _iconSuggestions.first['name'];
          _selectedCategoryColor = _categoryColorOptions.first['hex'];
          _categoryNameError = null;
        });

        _showSnackBar('Category "$displayName" updated', AppTheme.primary);
      } else {
        data['display_order'] = _categories.length;

        final inserted = await supabase
            .from('salon_categories')
            .insert(data)
            .select()
            .single();

        setState(() {
          _categories.add(Map<String, dynamic>.from(inserted));
          _selectedCategoryId = inserted['id'] as int;
          _newCategoryNameController.clear();
          _newCategoryDescriptionController.clear();
          _selectedIcon = _iconSuggestions.first['name'];
          _selectedCategoryColor = _categoryColorOptions.first['hex'];
          _categoryNameError = null;
        });

        _showSnackBar('Category "$displayName" added', AppTheme.primary);
      }
    } catch (e) {
      _showSnackBar('Error saving category: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editCategory(int index) {
    final cat = _categories[index];
    setState(() {
      _editingCategoryId = cat['id'] as int?;
      _newCategoryNameController.text = cat['display_name'] ?? '';
      _newCategoryDescriptionController.text = cat['description'] ?? '';
      _selectedIcon = cat['icon_name'] ?? _iconSuggestions.first['name'];
      _selectedCategoryColor =
          cat['color'] ?? _categoryColorOptions.first['hex'];
      _categoryNameError = null;
    });
  }

  void _cancelEditCategory() {
    setState(() {
      _editingCategoryId = null;
      _newCategoryNameController.clear();
      _newCategoryDescriptionController.clear();
      _selectedIcon = _iconSuggestions.first['name'];
      _selectedCategoryColor = _categoryColorOptions.first['hex'];
      _categoryNameError = null;
    });
  }

  Future<void> _deleteCategory(int index) async {
    final cat = _categories[index];
    final catId = cat['id'] as int?;
    final catName = cat['display_name'] ?? '';

    final confirmed = await _showConfirmDialog(
      title: 'Delete Category?',
      message:
          'This will permanently remove "$catName" and all services under it (with their variants) from the salon.',
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      if (catId != null) {
        final servicesToDelete = _addedServices
            .where((s) => s['category_id'] == catId)
            .toList();

        for (final svc in servicesToDelete) {
          final svcId = svc['id'] as int?;
          if (svcId != null) {
            try {
              await supabase
                  .from('service_variants')
                  .delete()
                  .eq('service_id', svcId);
            } catch (_) {}
            try {
              await supabase
                  .from('barber_services')
                  .delete()
                  .eq('service_id', svcId);
            } catch (_) {}
            try {
              await supabase.from('services').delete().eq('id', svcId);
            } catch (_) {}
          }
        }

        await supabase.from('salon_categories').delete().eq('id', catId);

        setState(() {
          _categories.removeAt(index);
          _addedServices.removeWhere((s) => s['category_id'] == catId);
          if (_selectedCategoryId == catId) {
            _selectedCategoryId = _categories.isNotEmpty
                ? _categories.first['id'] as int
                : null;
          }
          if (_editingCategoryId == catId) _cancelEditCategory();
          if (_variantTargetServiceIndex != null &&
              _variantTargetServiceIndex! >= _addedServices.length) {
            _variantTargetServiceIndex = null;
          }
        });

        _showSnackBar('Category removed', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error deleting category: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================
  // AGE CATEGORY MANAGEMENT
  // ============================================
  void _autoFillAgeCategory(Map<String, dynamic> selected) {
    setState(() {
      _ageDisplayNameController.text =
          selected['display_name']?.toString() ?? '';
      _ageMinController.text = (selected['min_age'] ?? 0).toString();
      _ageMaxController.text = (selected['max_age'] ?? 100).toString();
      _validateAgeFields();
    });
  }

  Future<void> _addAgeCategoryDirect() async {
    _validateAgeFields();

    final displayName = _ageDisplayNameController.text.trim();
    final min = int.tryParse(_ageMinController.text.trim());
    final max = int.tryParse(_ageMaxController.text.trim());

    if (displayName.isEmpty) {
      _showSnackBar('Age category name is required', Colors.orange);
      return;
    }
    if (_ageNameError != null) {
      _showSnackBar(_ageNameError!, Colors.orange);
      return;
    }
    if (min == null || max == null) {
      _showSnackBar('Please enter a valid age range', Colors.orange);
      return;
    }
    if (min < 0 || min > 150 || max < 0 || max > 150) {
      _showSnackBar('Age must be between 0 and 150', Colors.orange);
      return;
    }
    if (min > max) {
      _showSnackBar('Min age cannot be greater than max age', Colors.orange);
      return;
    }

    setState(() => _isAddingAgeCategory = true);

    try {
      final insertData = {
        'salon_id': widget.salonId,
        'display_name': displayName,
        'min_age': min,
        'max_age': max,
        'display_order': _ageCategories.length,
        'is_active': true,
      };

      final inserted = await supabase
          .from('salon_age_categories')
          .insert(insertData)
          .select()
          .single();

      setState(() {
        _ageCategories.add(Map<String, dynamic>.from(inserted));
        _selectedAgeCategoryId = inserted['id'] as int;

        _ageDisplayNameController.clear();
        _ageMinController.text = '0';
        _ageMaxController.text = '100';
        _ageNameError = null;
        _ageMinError = null;
        _ageMaxError = null;
      });

      _showSnackBar(
        'Age category "$displayName" added to salon',
        Colors.green,
      );
    } catch (e) {
      _showSnackBar('Error adding age category: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isAddingAgeCategory = false);
    }
  }

  // ============================================
  // SERVICE MANAGEMENT
  // ============================================
  void _saveCurrentService() {
    _validateServiceName();

    if (_selectedCategoryId == null) {
      _showSnackBar('Please select a category for this service', Colors.orange);
      return;
    }
    final name = _serviceNameController.text.trim();
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
            (_addedServices[_editingServiceIndex]['variants'] as List)
                .map((v) => Map<String, dynamic>.from(v)),
          )
        : <Map<String, dynamic>>[];

    final newService = {
      'name': name,
      'description': _serviceDescriptionController.text.trim(),
      'icon_name': _selectedIcon ?? _iconSuggestions.first['name'],
      'category_id': _selectedCategoryId,
      'variants': variants,
    };

    setState(() {
      if (isEditing) {
        final existingId = _addedServices[_editingServiceIndex]['id'];
        if (existingId != null) newService['id'] = existingId;
        final wasFromDb = _addedServices[_editingServiceIndex]['from_db'];
        if (wasFromDb == true) newService['from_db'] = true;
        _addedServices[_editingServiceIndex] = newService;
        _editingServiceIndex = -1;
      } else {
        _addedServices.add(newService);
      }
      _serviceNameController.clear();
      _serviceDescriptionController.clear();
      _selectedIcon = _iconSuggestions.first['name'];
      _serviceNameError = null;
      _variantTargetServiceIndex = null;
    });

    _showSnackBar(
      'Service ${isEditing ? 'updated' : 'added'}. You can add variants next (optional).',
      AppTheme.primary,
    );
  }

  void _editAddedService(int index) {
    final service = _addedServices[index];
    setState(() {
      _editingServiceIndex = index;
      _selectedCategoryId = service['category_id'] as int?;
      _serviceNameController.text = service['name'] as String;
      _serviceDescriptionController.text = service['description'] as String;
      _selectedIcon = service['icon_name'] as String;
      _serviceNameError = null;
    });
  }

  void _cancelEditingService() {
    setState(() {
      _editingServiceIndex = -1;
      _serviceNameController.clear();
      _serviceDescriptionController.clear();
      _selectedIcon = _iconSuggestions.first['name'];
      _serviceNameError = null;
    });
  }

  void _removeAddedService(int index) {
    final wasFromDb = _addedServices[index]['from_db'] == true;
    final serviceId = _addedServices[index]['id'];
    final serviceName = _addedServices[index]['name'];

    if (wasFromDb && serviceId != null) {
      _confirmDeleteServiceFromDb(serviceId as int, index, serviceName);
    } else {
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
  }

  Future<void> _confirmDeleteServiceFromDb(
      int serviceId, int localIndex, String serviceName) async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete Service?',
      message:
          'This will permanently remove "$serviceName" and all its variants from the salon.',
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await supabase
          .from('service_variants')
          .delete()
          .eq('service_id', serviceId);

      try {
        await supabase
            .from('barber_services')
            .delete()
            .eq('service_id', serviceId);
      } catch (_) {}

      await supabase.from('services').delete().eq('id', serviceId);

      setState(() {
        _addedServices.removeAt(localIndex);
        _dbServiceIds.remove(serviceId);
        if (_variantTargetServiceIndex != null &&
            _variantTargetServiceIndex! >= _addedServices.length) {
          _variantTargetServiceIndex = null;
        }
      });

      _showSnackBar('Service removed from salon', Colors.orange);
    } catch (e) {
      _showSnackBar('Error removing service: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================
  // VARIANT MANAGEMENT
  // ============================================
  void _saveVariant() {
    if (_variantTargetServiceIndex == null) {
      _showSnackBar('Please select a service first', Colors.orange);
      return;
    }

    if (!_hasAtLeastOneVariantField) {
      _showSnackBar(
        'Please fill at least one field (gender, age, duration, or price)',
        Colors.orange,
      );
      return;
    }

    _validatePrice();
    _validateDuration();

    if (_priceError != null || _durationError != null) {
      _showSnackBar('Please fix the errors before adding', Colors.orange);
      return;
    }

    final priceText = _variantPriceController.text.trim();
    final bool priceSet = priceText.isNotEmpty;
    final double price;
    if (!priceSet) {
      price = 0;
    } else {
      final parsed = double.tryParse(priceText);
      if (parsed == null || parsed < 0) {
        _showSnackBar('Please enter a valid price', Colors.orange);
        return;
      }
      price = parsed;
    }

    final durationText = _variantDurationController.text.trim();
    final int duration;
    if (durationText.isEmpty) {
      duration = 0;
    } else {
      final parsed = int.tryParse(durationText);
      if (parsed == null || parsed <= 0) {
        _showSnackBar('Please enter a valid duration', Colors.orange);
        return;
      }
      duration = parsed;
    }

    if (_isVariantDuplicate(_variantTargetServiceIndex!)) {
      _showSnackBar(
        'This gender + age + duration combination is already added',
        Colors.orange,
      );
      return;
    }

    final genderName = _selectedGenderId != null
        ? _getGenderDisplayName(
            _genders.firstWhere((g) => g['id'] == _selectedGenderId))
        : 'Any';
    final ageName = _selectedAgeCategoryId != null
        ? _getAgeCategoryDisplayName(
            _ageCategories.firstWhere((a) => a['id'] == _selectedAgeCategoryId))
        : 'Any';

    final service = _addedServices[_variantTargetServiceIndex!];
    final isEditingExistingVariant = _editingVariantIndex >= 0;

    setState(() {
      if (isEditingExistingVariant) {
        final existing = (service['variants'] as List)[_editingVariantIndex];
        (service['variants'] as List)[_editingVariantIndex] = {
          ...existing,
          'gender_id': _selectedGenderId,
          'gender_name': genderName,
          'age_category_id': _selectedAgeCategoryId,
          'age_category_name': ageName,
          'price': price,
          'price_set': priceSet,
          'duration': duration,
          'edited': true,
        };
        _editingVariantIndex = -1;
      } else {
        (service['variants'] as List).add({
          'gender_id': _selectedGenderId,
          'gender_name': genderName,
          'age_category_id': _selectedAgeCategoryId,
          'age_category_name': ageName,
          'price': price,
          'price_set': priceSet,
          'duration': duration,
        });
      }

      _selectedGenderId = null;
      _selectedAgeCategoryId = null;
      _variantPriceController.clear();
      _variantDurationController.clear();
      _priceError = null;
      _durationError = null;

      _genderExpanded = false;
      _ageExpanded = false;
      _durationExpanded = false;
      _priceExpanded = false;
    });

    _showSnackBar(
      isEditingExistingVariant ? 'Variant updated' : 'Variant added',
      AppTheme.primary,
    );
  }

  void _editVariant(int serviceIndex, int variantIndex) {
    final service = _addedServices[serviceIndex];
    final v = (service['variants'] as List)[variantIndex];

    setState(() {
      _variantTargetServiceIndex = serviceIndex;
      _editingVariantIndex = variantIndex;
      _variantsSectionExpanded = true;

      _selectedGenderId = v['gender_id'] as int?;
      _selectedAgeCategoryId = v['age_category_id'] as int?;

      final price = (v['price'] as num).toDouble();
      final priceSet = v['price_set'] == true;
      _variantPriceController.text = (!priceSet || price == 0)
          ? ''
          : (_currencyUsesDecimals
              ? price.toString()
              : price.toInt().toString());

      final duration = (v['duration'] as num).toInt();
      _variantDurationController.text =
          duration == 0 ? '' : duration.toString();

      _genderExpanded = true;
      _ageExpanded = true;
      _durationExpanded = true;
      _priceExpanded = true;
    });
  }

  void _cancelEditVariant() {
    setState(() {
      _editingVariantIndex = -1;
      _selectedGenderId = null;
      _selectedAgeCategoryId = null;
      _variantPriceController.clear();
      _variantDurationController.clear();
      _priceError = null;
      _durationError = null;
      _genderExpanded = false;
      _ageExpanded = false;
      _durationExpanded = false;
      _priceExpanded = false;
    });
  }

  void _removeVariant(int serviceIndex, int variantIndex) {
    final service = _addedServices[serviceIndex];
    final variant = (service['variants'] as List)[variantIndex];

    if (variant['from_db'] == true && variant['variant_id'] != null) {
      _confirmRemoveDbVariant(
          serviceIndex, variantIndex, variant['variant_id'] as int);
    } else {
      setState(() {
        (service['variants'] as List).removeAt(variantIndex);
      });
    }
  }

  Future<void> _confirmRemoveDbVariant(
      int serviceIndex, int variantIndex, int variantId) async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete Variant?',
      message: 'This will permanently remove this variant from the salon.',
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await supabase
            .from('service_variants')
            .delete()
            .eq('id', variantId);

        setState(() {
          final service = _addedServices[serviceIndex];
          (service['variants'] as List).removeAt(variantIndex);
        });
        _showSnackBar('Variant removed', Colors.orange);
      } catch (e) {
        _showSnackBar('Error removing variant: $e', Colors.red);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: _isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: _isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // SAVE ALL SERVICES TO DB
  // ============================================

  /// ✅ Entry point for the Save button.
  /// Shows a confirm dialog FIRST. The actual DB save (and the screen
  /// refresh that follows it) only happens if the user taps "Save" on
  /// the confirm dialog. If they cancel/close it, nothing is saved and
  /// nothing is refreshed — the screen stays exactly as it was.
  Future<void> _saveAllServices() async {
    if (_addedServices.isEmpty) {
      _showSnackBar('Please add at least one service', Colors.orange);
      return;
    }

    final totalVariantsPreview = _addedServices.fold<int>(
        0, (sum, s) => sum + (s['variants'] as List).length);

    final confirmed = await _showSaveConfirmDialog(
      title: widget.isEditing ? 'Update Service?' : 'Save Services?',
      message: widget.isEditing
          ? 'This will save your changes to "${_addedServices.isNotEmpty ? _addedServices.first['name'] : ''}" to the database.'
          : 'This will save ${_addedServices.length} service${_addedServices.length == 1 ? '' : 's'} '
              'and $totalVariantsPreview variant${totalVariantsPreview == 1 ? '' : 's'} to the database.',
    );

    // ❌ User cancelled/closed the dialog — do NOT save, do NOT refresh.
    if (confirmed != true) return;

    // ✅ User confirmed — perform the actual save, then refresh.
    await _performSaveAllServices();
  }

  /// A dedicated confirm dialog for the save action (separate from the
  /// destructive-delete dialog styling of [_showConfirmDialog]).
  Future<bool?> _showSaveConfirmDialog({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: _isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: _isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(widget.isEditing ? 'Update' : 'Save'),
          ),
        ],
      ),
    );
  }

  /// Actually writes everything to the database. Only ever called after
  /// the user has confirmed via [_showSaveConfirmDialog].
  Future<void> _performSaveAllServices() async {
    setState(() => _isLoading = true);

    try {
      if (widget.salonBarberId != null) {
        final barberStatusCheck = await supabase
            .from('user_roles')
            .select('status')
            .eq('user_id', widget.salonBarberId!)
            .eq('role_id', 2)
            .maybeSingle();

        if (barberStatusCheck == null ||
            barberStatusCheck['status'] != 'active') {
          _showSnackBar(
            'This barber account is not active. Please reactivate the barber first.',
            Colors.orange,
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      final existingServicesResponse = await supabase
          .from('services')
          .select('id, name')
          .eq('salon_id', widget.salonId);

      final Map<String, int> existingServiceIdByName = {};
      for (var s in existingServicesResponse) {
        existingServiceIdByName[
                (s['name'] as String).trim().toLowerCase()] =
            s['id'] as int;
      }

      final Set<int> usedServiceIds = {};

      for (final service in _addedServices) {
        final fromDb = service['from_db'] == true;
        final localId = service['id'] as int?;
        final svcName = (service['name'] as String).trim();
        final svcNameLower = svcName.toLowerCase();

        int serviceId;

        if (fromDb && localId != null) {
          serviceId = localId;
          usedServiceIds.add(serviceId);

          await supabase.from('services').update({
            'name': svcName,
            'description': (service['description'] as String).isEmpty
                ? null
                : service['description'],
            'category_id': service['category_id'],
            'icon_name': service['icon_name'],
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', serviceId);

          await supabase
              .from('service_variants')
              .delete()
              .eq('service_id', serviceId);
        } else if (widget.isEditing &&
            widget.serviceId != null &&
            localId == widget.serviceId) {
          serviceId = widget.serviceId!;
          usedServiceIds.add(serviceId);

          await supabase.from('services').update({
            'name': svcName,
            'description': (service['description'] as String).isEmpty
                ? null
                : service['description'],
            'category_id': service['category_id'],
            'icon_name': service['icon_name'],
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', serviceId);
        } else {
          final existingId = existingServiceIdByName[svcNameLower];

          if (existingId != null && !usedServiceIds.contains(existingId)) {
            serviceId = existingId;
            usedServiceIds.add(serviceId);

            await supabase.from('services').update({
              'name': svcName,
              'description': (service['description'] as String).isEmpty
                  ? null
                  : service['description'],
              'category_id': service['category_id'],
              'icon_name': service['icon_name'],
              'is_active': true,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', serviceId);

            await supabase
                .from('service_variants')
                .delete()
                .eq('service_id', serviceId);
          } else {
            final serviceData = {
              'salon_id': widget.salonId,
              'name': svcName,
              'description': (service['description'] as String).isEmpty
                  ? null
                  : service['description'],
              'category_id': service['category_id'],
              'icon_name': service['icon_name'],
              'is_active': true,
              'created_by': supabase.auth.currentUser?.id,
            };

            final serviceResponse = await supabase
                .from('services')
                .insert(serviceData)
                .select()
                .single();
            serviceId = serviceResponse['id'] as int;
            usedServiceIds.add(serviceId);
            existingServiceIdByName[svcNameLower] = serviceId;
          }
        }

        final variants = service['variants'] as List;
        for (final v in variants) {
          final variantData = {
            'service_id': serviceId,
            'salon_gender_id': v['gender_id'],
            'salon_age_category_id': v['age_category_id'],
            'price': v['price_set'] == true ? v['price'] : null,
            'duration': ((v['duration'] as num?)?.toInt() ?? 0) == 0
                ? null
                : v['duration'],
            'is_active': true,
          };

          final variantResponse = await supabase
              .from('service_variants')
              .insert(variantData)
              .select()
              .single();
          final variantId = variantResponse['id'];

          if (widget.salonBarberId != null) {
            final existing = await supabase
                .from('barber_services')
                .select()
                .eq('salon_barber_id', widget.salonBarberId!)
                .eq('service_id', serviceId)
                .eq('variant_id', variantId)
                .maybeSingle();

            if (existing == null) {
              await supabase.from('barber_services').insert({
                'salon_barber_id': widget.salonBarberId!,
                'service_id': serviceId,
                'variant_id': variantId,
                'custom_price': v['price'],
              });
            }
          }
        }

        if (variants.isEmpty && widget.salonBarberId != null) {
          final existing = await supabase
              .from('barber_services')
              .select()
              .eq('salon_barber_id', widget.salonBarberId!)
              .eq('service_id', serviceId)
              .maybeSingle();

          if (existing == null) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': widget.salonBarberId!,
              'service_id': serviceId,
            });
          }
        }
      }

      if (!mounted) return;

      final totalVariants = _addedServices.fold<int>(
          0, (sum, s) => sum + (s['variants'] as List).length);

      await showCustomAlert(
        context: context,
        title: widget.isEditing ? "✅ Service Updated!" : "🎉 Services Saved!",
        message: widget.isEditing
            ? "${_addedServices.first['name']} has been updated successfully.\n\n"
                "✅ $totalVariants variant${totalVariants == 1 ? '' : 's'} saved"
            : "${_addedServices.length} service${_addedServices.length == 1 ? '' : 's'} added/updated successfully.\n\n"
                "✅ $totalVariants variant${totalVariants == 1 ? '' : 's'} saved",
        isError: false,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _addedServices.clear();
        _dbServiceIds.clear();
        _variantTargetServiceIndex = null;
        _editingServiceIndex = -1;
        _editingVariantIndex = -1;
        _selectedGenderId = null;
        _selectedAgeCategoryId = null;
        _variantPriceController.clear();
        _variantDurationController.clear();
        _serviceNameController.clear();
        _serviceDescriptionController.clear();
        _variantsSectionExpanded = false;
        _genderExpanded = false;
        _ageExpanded = false;
        _durationExpanded = false;
        _priceExpanded = false;
      });

      await _loadData();

      if (!mounted) return;
      _showSnackBar(
        'Saved successfully. You can continue adding more services.',
        Colors.green,
      );
    } catch (e) {
      if (mounted) {
        if (e.toString().contains(
          'duplicate key value violates unique constraint',
        )) {
          _showSnackBar(
            'A service with this name already exists. Please use a different name.',
            Colors.orange,
          );
        } else {
          _showSnackBar('Error: $e', Colors.red);
        }
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    final isDark = _isDark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        backgroundColor: isDark ? color.withValues(alpha: 0.8) : color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================
  // EXPANDABLE HEADER
  // ============================================
  Widget _buildExpandableHeader({
    required String title,
    required IconData icon,
    required Color color,
    required bool isExpanded,
    required VoidCallback onTap,
    String? subtitle,
    bool isRequired = false,
    bool isMainHeader = false,
  }) {
    final isDark = _isDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isMainHeader ? 14 : 12),
        decoration: BoxDecoration(
          color: isMainHeader
              ? color.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF2A2A2A) : Colors.grey[50]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExpanded
                ? color.withValues(alpha: 0.5)
                : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
            width: isExpanded ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMainHeader ? 10 : 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: color, size: isMainHeader ? 22 : 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: isMainHeader ? 15 : 13,
                          fontWeight: isMainHeader
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (isRequired)
                        Text(
                          ' *',
                          style: TextStyle(
                            fontSize: isMainHeader ? 15 : 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[300],
                          ),
                        ),
                    ],
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isMainHeader ? 12 : 11,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: isDark ? Colors.white70 : Colors.grey[600],
                size: isMainHeader ? 28 : 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // HIERARCHY GUIDE (explains Category → Service → Variant)
  // ============================================
  Widget _buildHierarchyGuideCard() {
    final isDark = _isDark;

    Widget levelLabel(String text, Color color) => Container(
          width: 66,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        );

    Widget arrow(Color color) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward, size: 12, color: color),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppTheme.primary.withValues(alpha: 0.25),
        ),
      ),
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
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_tree,
                      color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'How this works',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Each category can hold many services, and each service can '
              'have many variants (by gender, age, price and duration).',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category
                  Row(
                    children: [
                      levelLabel('Category', Colors.orange),
                      arrow(Colors.orange),
                      const Icon(Icons.folder,
                          size: 15, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'Hair',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Service 1
                  Row(
                    children: [
                      levelLabel('Service', Colors.blue),
                      arrow(Colors.blue),
                      Text(
                        '①  ├─',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white38 : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.content_cut,
                          size: 13, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                        'Hair Cut',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  // Variant 1a
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 3),
                    child: Row(
                      children: [
                        levelLabel('Variant', Colors.purple),
                        arrow(Colors.purple),
                        Text(
                          '│  ├─ ①',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Male • Adult   Rs.1500 • 30 min',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Variant 1b
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 2),
                    child: Row(
                      children: [
                        const SizedBox(width: 72),
                        Text(
                          '│  └─ ②',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Female • Adult  Rs.1800 • 45 min',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Service 2
                  Row(
                    children: [
                      const SizedBox(width: 72),
                      Text(
                        '②  └─',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white38 : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.water_drop,
                          size: 13, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                        'Hair Wash',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  // Variant 2a
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 3),
                    child: Row(
                      children: [
                        const SizedBox(width: 72),
                        Text(
                          '   ├─ ①',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Any • Any   Free • —',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Variant 2b
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 2),
                    child: Row(
                      children: [
                        const SizedBox(width: 72),
                        Text(
                          '   └─ ②',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Male • Child  Rs.400 • 10 min',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 13,
                    color: isDark ? Colors.white38 : Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'The live "Summary" section below shows this same tree with your actual data.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.grey[500],
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

  // ============================================
  // CATEGORIES SECTION
  // ============================================
  Widget _buildCategoriesSection() {
    final isDark = _isDark;
    final isDesktop = _isWeb;
    final isEditingCat = _editingCategoryId != null;

    Widget addCategoryForm() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEditingCat
                  ? Colors.orange.withValues(alpha: 0.5)
                  : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
              width: isEditingCat ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isEditingCat ? Icons.edit : Icons.add_circle_outline,
                    size: 18,
                    color: isEditingCat ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEditingCat ? 'Edit Category' : 'Add New Category',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (isEditingCat)
                    TextButton(
                      onPressed: _cancelEditCategory,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                      ),
                      child: const Text(
                        'Cancel',
                        style:
                            TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCategoryNameController,
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
                onChanged: (_) => _validateCategoryName(),
                decoration: InputDecoration(
                  labelText: 'Category Name *',
                  hintText: 'e.g., Hair, Nails, Spa',
                  prefixIcon: Icon(Icons.category,
                      size: 18,
                      color: isDark ? Colors.white70 : Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color:
                            isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  errorText: _categoryNameError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newCategoryDescriptionController,
                maxLines: 2,
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g., Hair cutting and styling',
                  prefixIcon: Icon(Icons.description,
                      size: 18,
                      color: isDark ? Colors.white70 : Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color:
                            isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              _buildIconPicker(),
              const SizedBox(height: 8),
              _buildColorPicker(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _addOrUpdateCategory,
                  icon: Icon(
                      isEditingCat ? Icons.save : Icons.add,
                      size: 18),
                  label:
                      Text(isEditingCat ? 'Update Category' : 'Add Category'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isEditingCat ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );

    Widget categoriesList() => Container(
          padding: const EdgeInsets.all(14),
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
                  const Icon(Icons.list, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Categories (${_categories.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_categories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox,
                            size: 36,
                            color:
                                isDark ? Colors.white30 : Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No categories yet',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white70 : Colors.grey[500],
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
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final catId = cat['id'];
                    final isSelected = _selectedCategoryId == catId;
                    final isBeingEdited = _editingCategoryId == catId;

                    return Material(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              _hexToColor(cat['color'] ?? '#FF6B8B')
                                  .withValues(alpha: 0.15),
                          child: Icon(
                            _iconFromName(cat['icon_name']),
                            size: 14,
                            color: _hexToColor(cat['color'] ?? '#FF6B8B'),
                          ),
                        ),
                        title: Text(
                          _getCategoryDisplayName(cat),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected || isBeingEdited
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isBeingEdited
                                ? Colors.orange
                                : (isSelected
                                    ? AppTheme.primary
                                    : (isDark
                                        ? Colors.white
                                        : Colors.black87)),
                          ),
                        ),
                        subtitle: (cat['description'] ?? '')
                                .toString()
                                .isNotEmpty
                            ? Text(
                                cat['description'],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onTap: () => setState(
                            () => _selectedCategoryId = catId),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  size: 16, color: Colors.blue),
                              onPressed: () => _editCategory(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Edit',
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 16,
                                  color: isDark
                                      ? Colors.red[300]
                                      : Colors.red),
                              onPressed: () => _deleteCategory(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete',
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle,
                                  color: AppTheme.primary, size: 18),
                            ],
                          ],
                        ),
                      ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.category,
                      color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Service Categories',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_categories.length} items',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: addCategoryForm()),
                  const SizedBox(width: 12),
                  Expanded(child: categoriesList()),
                ],
              )
            else
              Column(
                children: [
                  addCategoryForm(),
                  const SizedBox(height: 12),
                  categoriesList(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconPicker() {
    final isDark = _isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Icon',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _iconSuggestions.length,
            itemBuilder: (context, index) {
              final item = _iconSuggestions[index];
              final isSelected = _selectedIcon == item['name'];
              final color = Color(item['color']);
              return GestureDetector(
                onTap: () => setState(() => _selectedIcon = item['name']),
                child: Container(
                  width: 52,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.15)
                        : (isDark
                            ? const Color(0xFF1E1E1E)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item['icon'],
                        size: 20,
                        color: isSelected
                            ? color
                            : (isDark ? Colors.white60 : Colors.grey[600]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['label'],
                        style: TextStyle(
                          fontSize: 8,
                          color: isSelected
                              ? color
                              : (isDark ? Colors.white60 : Colors.grey[600]),
                        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _categoryColorOptions.map((opt) {
            final isSelected = _selectedCategoryColor == opt['hex'];
            return GestureDetector(
              onTap: () =>
                  setState(() => _selectedCategoryColor = opt['hex']),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: opt['color'],
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: (opt['color'] as Color)
                                .withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _hexToColor(String hex) {
    if (hex.startsWith('#')) {
      return Color(int.parse('0xFF${hex.substring(1)}'));
    }
    return AppTheme.primary;
  }

  IconData _iconFromName(String? name) {
    final found = _iconSuggestions.firstWhere(
      (i) => i['name'] == name,
      orElse: () => _iconSuggestions.first,
    );
    return found['icon'] as IconData;
  }

  // ============================================
  // SERVICES SECTION
  // ============================================
  Widget _buildServicesSection() {
    final isDark = _isDark;
    final isDesktop = _isWeb;
    final categorySelected = _selectedCategoryId != null;

    Widget serviceForm() => Container(
          padding: const EdgeInsets.all(14),
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
                  const Icon(Icons.add_circle_outline,
                      size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    _editingServiceIndex >= 0
                        ? 'Edit Service'
                        : 'Add New Service',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
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
                        style: TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Select Category *',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              if (_categories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Add at least one category above first',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _selectedCategoryId,
                  isExpanded: true,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.category,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.grey),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 2),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: _categories.map((cat) {
                    return DropdownMenuItem<int>(
                      value: cat['id'] as int,
                      child: Text(
                        _getCategoryDisplayName(cat),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color:
                                isDark ? Colors.white : Colors.black87),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) =>
                      setState(() => _selectedCategoryId = v),
                ),
              if (categorySelected) ...[
                const SizedBox(height: 12),
                Text(
                  'Service Name *',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _serviceNameController,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'e.g., Hair Cut, Facial',
                    prefixIcon: Icon(Icons.build,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.grey),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 2),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    errorText: _serviceNameError,
                    errorMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _serviceDescriptionController,
                  maxLines: 2,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Describe this service...',
                    prefixIcon: Icon(Icons.description,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.grey),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 2),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                _buildIconPicker(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveCurrentService,
                    icon: Icon(
                        _editingServiceIndex >= 0 ? Icons.save : Icons.add,
                        size: 18),
                    label: Text(_editingServiceIndex >= 0
                        ? 'Update Service'
                        : 'Add Service'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14,
                          color:
                              isDark ? Colors.white60 : Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Select a category to continue',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
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

    Widget servicesList() => Container(
          padding: const EdgeInsets.all(14),
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
                  const Icon(Icons.list, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Services (${_addedServices.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_addedServices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox,
                            size: 36,
                            color:
                                isDark ? Colors.white30 : Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No services yet',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white70 : Colors.grey[500],
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
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final service = _addedServices[index];
                    final variants = service['variants'] as List;
                    final isFromDb = service['from_db'] == true;
                    final isSelected = _variantTargetServiceIndex == index;
                    final isBeingEdited = _editingServiceIndex == index;

                    final pricedCount = variants
                        .where((v) => v['price_set'] == true)
                        .length;

                    return Material(
                      color: isSelected
                          ? Colors.purple.withValues(alpha: 0.08)
                          : (isBeingEdited
                              ? Colors.orange.withValues(alpha: 0.08)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        dense: true,
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: isSelected
                                  ? Colors.purple.withValues(alpha: 0.15)
                                  : Colors.orange.withValues(alpha: 0.15),
                              child: Icon(
                                _iconFromName(service['icon_name']),
                                size: 14,
                                color: isSelected
                                    ? Colors.purple
                                    : Colors.orange,
                              ),
                            ),
                            if (isFromDb)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                service['name'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected || isBeingEdited
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.purple
                                      : (isBeingEdited
                                          ? Colors.orange
                                          : (isDark
                                              ? Colors.white
                                              : Colors.black87)),
                                ),
                              ),
                            ),
                            if (isFromDb)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'SAVED',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${_getCategoryById(service['category_id'] as int?)?['display_name'] ?? '—'} • ${variants.length} variant${variants.length == 1 ? '' : 's'}'
                          '${variants.isNotEmpty ? ' • $pricedCount priced' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  size: 16, color: Colors.blue),
                              onPressed: () => _editAddedService(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Edit',
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 16,
                                  color:
                                      isDark ? Colors.red[300] : Colors.red),
                              onPressed: () => _removeAddedService(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete',
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle,
                                  color: Colors.purple, size: 18),
                            ],
                          ],
                        ),
                      ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.build,
                      color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Services',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_addedServices.length} items',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: serviceForm()),
                  const SizedBox(width: 12),
                  Expanded(child: servicesList()),
                ],
              )
            else
              Column(
                children: [
                  serviceForm(),
                  const SizedBox(height: 12),
                  servicesList(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // VARIANTS SECTION
  // ============================================
  Widget _buildVariantsSection() {
    final isDark = _isDark;
    final isDesktop = _isWeb;

    if (_addedServices.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.info_outline,
                  color: isDark ? Colors.white60 : Colors.grey, size: 32),
              const SizedBox(height: 8),
              Text(
                'Add a service first',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You need at least one service before you can add variants.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final selectedService = _variantTargetServiceIndex != null
        ? _addedServices[_variantTargetServiceIndex!]
        : null;
    final variants = selectedService != null
        ? (selectedService['variants'] as List)
        : <dynamic>[];

    final canAddVariant = selectedService != null && _hasAtLeastOneVariantField;
    final isEditingVariant = _editingVariantIndex >= 0;

    Widget variantForm() => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEditingVariant
                  ? Colors.orange.withValues(alpha: 0.5)
                  : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
              width: isEditingVariant ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isEditingVariant ? Icons.edit : Icons.add_circle_outline,
                    size: 18,
                    color: isEditingVariant ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEditingVariant ? 'Edit Variant' : 'Add New Variant',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (isEditingVariant)
                    TextButton(
                      onPressed: _cancelEditVariant,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                      ),
                      child: const Text(
                        'Cancel',
                        style:
                            TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isEditingVariant
                    ? 'Update the fields below'
                    : 'All fields optional — fill at least one to add',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'Select Service *',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _variantTargetServiceIndex,
                isExpanded: true,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Choose a service...',
                  prefixIcon: Icon(Icons.build,
                      size: 18,
                      color: isDark ? Colors.white70 : Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color:
                            isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: _addedServices.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final svc = entry.value;
                  final vCount = (svc['variants'] as List).length;
                  return DropdownMenuItem<int>(
                    value: idx,
                    child: Text(
                      '${svc['name']} • $vCount variant${vCount == 1 ? '' : 's'}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                  );
                }).toList(),
                onChanged: (v) async {
                  setState(() {
                    _variantTargetServiceIndex = v;
                    _editingVariantIndex = -1;
                    _selectedGenderId = null;
                    _selectedAgeCategoryId = null;
                    _variantPriceController.clear();
                    _variantDurationController.clear();
                    _priceError = null;
                    _durationError = null;
                    _genderExpanded = false;
                    _ageExpanded = false;
                    _durationExpanded = false;
                    _priceExpanded = false;
                  });

                  if (v != null) {
                    final svc = _addedServices[v];
                    if (svc['from_db'] == true && svc['id'] != null) {
                      await _loadVariantsForService(v);
                    }
                  }
                },
              ),

              if (selectedService != null) ...[
                const SizedBox(height: 12),

                _buildExpandableHeader(
                  title: 'Gender',
                  icon: Icons.wc,
                  color: Colors.blue,
                  isExpanded: _genderExpanded,
                  subtitle: _selectedGenderId != null
                      ? _genders.firstWhere(
                          (g) => g['id'] == _selectedGenderId,
                          orElse: () => {'display_name': 'Selected'},
                        )['display_name']
                      : 'Tap to select gender (optional)',
                  onTap: () => setState(
                      () => _genderExpanded = !_genderExpanded),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _genderExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildGenderChips(),
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 8),

                _buildExpandableHeader(
                  title: 'Age Category',
                  icon: Icons.timeline,
                  color: Colors.green,
                  isExpanded: _ageExpanded,
                  subtitle: _selectedAgeCategoryId != null
                      ? _getAgeCategoryDisplayName(
                          _ageCategories.firstWhere(
                            (a) => a['id'] == _selectedAgeCategoryId,
                            orElse: () => {
                              'display_name': 'Selected',
                              'min_age': 0,
                              'max_age': 0,
                            },
                          ),
                        )
                      : 'Tap to type or pick an age category (optional)',
                  onTap: () =>
                      setState(() => _ageExpanded = !_ageExpanded),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _ageExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildAgeTypingForm(),
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 8),

                _buildExpandableHeader(
                  title: 'Duration',
                  icon: Icons.timer,
                  color: Colors.orange,
                  isExpanded: _durationExpanded,
                  subtitle: _variantDurationController.text.isNotEmpty
                      ? '${_variantDurationController.text} mins'
                      : 'Tap to enter duration (optional)',
                  onTap: () => setState(
                      () => _durationExpanded = !_durationExpanded),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _durationExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildDurationField(),
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 8),

                _buildExpandableHeader(
                  title: 'Price',
                  icon: Icons.attach_money,
                  color: Colors.teal,
                  isExpanded: _priceExpanded,
                  subtitle: _variantPriceController.text.isNotEmpty
                      ? '$_salonCurrencySymbol${_variantPriceController.text}'
                      : 'Tap to enter price (optional — add later)',
                  onTap: () =>
                      setState(() => _priceExpanded = !_priceExpanded),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _priceExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildPriceField(),
                  ),
                  secondChild: const SizedBox(width: double.infinity),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (canAddVariant || isEditingVariant)
                        ? _saveVariant
                        : null,
                    icon: Icon(
                        isEditingVariant ? Icons.save : Icons.add,
                        size: 18),
                    label: Text(isEditingVariant
                        ? 'Update Variant'
                        : 'Add Variant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEditingVariant
                          ? Colors.orange
                          : (canAddVariant
                              ? Colors.purple
                              : (isDark
                                  ? Colors.grey[800]
                                  : Colors.grey[300])),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (!canAddVariant && !isEditingVariant) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Fill at least one field to enable',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14,
                          color:
                              isDark ? Colors.white60 : Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Select a service to add variants',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
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

    Widget variantsList() => Container(
          padding: const EdgeInsets.all(14),
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
                  const Icon(Icons.list, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedService != null
                          ? 'Variants — ${selectedService['name']}'
                          : 'Added Variants',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isLoadingVariants)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (variants.isNotEmpty && selectedService != null)
                    TextButton(
                      onPressed: () => setState(() =>
                          (selectedService['variants'] as List).clear()),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                      ),
                      child: Text(
                        'Clear All',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.red[300] : Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (selectedService == null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.tune,
                            size: 36,
                            color:
                                isDark ? Colors.white30 : Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'Select a service to view its variants',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white70 : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isLoadingVariants)
                Container(
                  padding: const EdgeInsets.all(20),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (variants.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox,
                            size: 36,
                            color:
                                isDark ? Colors.white30 : Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No variants added yet',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white70 : Colors.grey[500],
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
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final v = variants[index];
                    final duration = (v['duration'] as num).toInt();
                    final priceDisplay = _formatPriceDisplay(v);
                    final priceNotSet = _isPriceNotSet(v);
                    final durationDisplay =
                        duration == 0 ? '—' : '$duration min';
                    final isFromDb = v['from_db'] == true;
                    final isBeingEdited = _editingVariantIndex == index;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: isBeingEdited
                                ? Colors.orange.withValues(alpha: 0.15)
                                : Colors.purple.withValues(alpha: 0.15),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isBeingEdited
                                    ? Colors.orange
                                    : Colors.purple,
                              ),
                            ),
                          ),
                          if (isFromDb)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        '${v['gender_name']} • ${v['age_category_name']}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isBeingEdited
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isBeingEdited
                              ? Colors.orange
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            priceDisplay,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: priceNotSet
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: priceNotSet
                                  ? (isDark
                                      ? Colors.white38
                                      : Colors.grey[500])
                                  : (isDark
                                      ? Colors.white60
                                      : Colors.grey[600]),
                              fontWeight: priceNotSet
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' • $durationDisplay',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit,
                                size: 16, color: Colors.blue),
                            onPressed: () => _editVariant(
                                _variantTargetServiceIndex!, index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Edit',
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 16,
                                color:
                                    isDark ? Colors.red[300] : Colors.red),
                            onPressed: () => _removeVariant(
                                _variantTargetServiceIndex!, index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
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
            _buildExpandableHeader(
              title: 'Variants (Optional)',
              icon: Icons.tune,
              color: Colors.purple,
              isExpanded: _variantsSectionExpanded,
              isMainHeader: true,
              subtitle: _variantsSectionExpanded
                  ? 'Tap to collapse'
                  : 'Tap to expand and manage variants',
              onTap: () => setState(
                  () => _variantsSectionExpanded = !_variantsSectionExpanded),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _variantsSectionExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: variantForm()),
                          const SizedBox(width: 12),
                          Expanded(child: variantsList()),
                        ],
                      )
                    : Column(
                        children: [
                          variantForm(),
                          const SizedBox(height: 12),
                          variantsList(),
                        ],
                      ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // SUMMARY SECTION
  // ============================================
  Widget _buildSummarySection() {
    final isDark = _isDark;

    final List<Map<String, dynamic>> categoryBlocks = [];

    for (int i = 0; i < _categories.length; i++) {
      final cat = _categories[i];
      final catId = cat['id'] as int?;

      final List<Map<String, dynamic>> servicesForCat = [];
      for (final svc in _addedServices) {
        final svcCatId = svc['category_id'] as int?;
        if (svcCatId == catId) {
          servicesForCat.add(svc);
        }
      }

      categoryBlocks.add({
        'blockKey': i,
        'category': cat,
        'services': servicesForCat,
      });
    }

    final List<Map<String, dynamic>> orphanServices = [];
    for (final svc in _addedServices) {
      final svcCatId = svc['category_id'] as int?;
      final exists = _categories.any((c) => c['id'] == svcCatId);
      if (!exists) orphanServices.add(svc);
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
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_tree,
                      color: Colors.indigo, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (categoryBlocks.isEmpty && orphanServices.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox,
                          size: 40,
                          color:
                              isDark ? Colors.white30 : Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Nothing added yet',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color:
                              isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add categories, services and variants to see them here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ...categoryBlocks.asMap().entries.map((blockEntry) {
                final blockIndex = blockEntry.key;
                final block = blockEntry.value;
                final isLastBlock =
                    blockIndex == categoryBlocks.length - 1 &&
                        orphanServices.isEmpty;

                return _buildSummaryCategoryBlock(
                  block: block,
                  isLastBlock: isLastBlock,
                  isDark: isDark,
                );
              }),
              if (orphanServices.isNotEmpty)
                _buildSummaryOrphanBlock(
                  services: orphanServices,
                  isDark: isDark,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCategoryBlock({
    required Map<String, dynamic> block,
    required bool isLastBlock,
    required bool isDark,
  }) {
    final category = block['category'] as Map<String, dynamic>;
    final services = block['services'] as List<Map<String, dynamic>>;
    final catName = _getCategoryDisplayName(category);
    final catColor = _hexToColor(category['color'] ?? '#FF6B8B');
    final catIcon = _iconFromName(category['icon_name']);

    return Padding(
      padding: EdgeInsets.only(bottom: isLastBlock ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: catColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(catIcon, size: 16, color: catColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    catName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (services.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Row(
                children: [
                  Text(
                    '└─',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: catColor.withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No services yet',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          else
            ...services.asMap().entries.map((svcEntry) {
              final svcIndex = svcEntry.key;
              final svc = svcEntry.value;
              final isLastService = svcIndex == services.length - 1;

              return _buildSummaryServiceNode(
                service: svc,
                isLastService: isLastService,
                isDark: isDark,
                parentColor: catColor,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSummaryServiceNode({
    required Map<String, dynamic> service,
    required bool isLastService,
    required bool isDark,
    required Color parentColor,
  }) {
    final variants = service['variants'] as List;
    final svcName = service['name'] as String;
    final isFromDb = service['from_db'] == true;
    final svcIcon = _iconFromName(service['icon_name']);

    final svcConnector = isLastService ? '└─' : '├─';
    final childPrefix = isLastService ? '   ' : '│  ';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              children: [
                Text(
                  svcConnector,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: parentColor.withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(svcIcon, size: 13, color: Colors.orange),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    svcName,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isFromDb) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'SAVED',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (variants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 2),
              child: Row(
                children: [
                  Text(
                    '$childPrefix└─',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: parentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No variants — price can be set later',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          else
            ...variants.asMap().entries.map((vEntry) {
              final vIndex = vEntry.key;
              final v = vEntry.value;
              final isLastVariant = vIndex == variants.length - 1;

              return _buildSummaryVariantNode(
                v: v,
                index: vIndex,
                isLastVariant: isLastVariant,
                isDark: isDark,
                childPrefix: childPrefix,
                parentColor: parentColor,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSummaryVariantNode({
    required Map<String, dynamic> v,
    required int index,
    required bool isLastVariant,
    required bool isDark,
    required String childPrefix,
    required Color parentColor,
  }) {
    final duration = (v['duration'] as num?)?.toInt() ?? 0;
    final isFromDb = v['from_db'] == true;
    final priceNotSet = _isPriceNotSet(v);
    final priceDisplay = _formatPriceDisplay(v);

    final durationDisplay = duration == 0 ? '—' : '$duration min';
    final vConnector = isLastVariant ? '└─' : '├─';
    final circledNum = _toCircledNumber(index + 1);

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$childPrefix$vConnector',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: parentColor.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            circledNum,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.purple,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${v['gender_name']} • ${v['age_category_name']}',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          if (priceNotSet)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.price_change_outlined,
                      size: 10,
                      color: isDark ? Colors.white38 : Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(
                    priceDisplay,
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                priceDisplay,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.teal[300] : Colors.teal[700],
                ),
              ),
            ),
          const SizedBox(width: 6),
          Icon(Icons.timer_outlined,
              size: 11, color: isDark ? Colors.white38 : Colors.grey[500]),
          const SizedBox(width: 3),
          Text(
            durationDisplay,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          if (isFromDb) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryOrphanBlock({
    required List<Map<String, dynamic>> services,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.help_outline,
                      size: 16,
                      color: isDark ? Colors.white60 : Colors.grey[600]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Uncategorized',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...services.asMap().entries.map((entry) {
            final svcIndex = entry.key;
            final svc = entry.value;
            final isLastService = svcIndex == services.length - 1;

            return _buildSummaryServiceNode(
              service: svc,
              isLastService: isLastService,
              isDark: isDark,
              parentColor: Colors.grey,
            );
          }),
        ],
      ),
    );
  }

  String _toCircledNumber(int n) {
    const circled = [
      '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩',
      '⑪', '⑫', '⑬', '⑭', '⑮', '⑯', '⑰', '⑱', '⑲', '⑳',
    ];
    if (n >= 1 && n <= circled.length) return circled[n - 1];
    return '($n)';
  }

  // ============================================
  // GENDER CHIPS
  // ============================================
  Widget _buildGenderChips() {
    final isDark = _isDark;

    if (_genders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No genders available for this salon',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[200]!),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _genders.map((gender) {
          final id = gender['id'] as int;
          final isSelected = _selectedGenderId == id;
          final displayName = _getGenderDisplayName(gender);
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
                _selectedGenderId = selected ? id : null;
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
    );
  }

  // ============================================
  // AGE TYPING FORM
  // ============================================
  Widget _buildAgeTypingForm() {
    final isDark = _isDark;

    // ✅ Auto-expand if there are NO existing age categories
    //    (this is derived, not stateful — the manual toggle works too)
    final shouldAutoExpand = _ageCategories.isEmpty;
    final isAddFormExpanded = _addAgeCategoryFormExpanded || shouldAutoExpand;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Existing age categories section
          if (_ageCategories.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.check_circle,
                    size: 14, color: Colors.green[400]),
                const SizedBox(width: 6),
                Text(
                  'Existing Age Categories (${_ageCategories.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to select',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _ageCategories.map((a) {
                final isSelected = _selectedAgeCategoryId == a['id'];
                return GestureDetector(
                  onTap: () => setState(() =>
                      _selectedAgeCategoryId = isSelected ? null : a['id']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.green.withValues(alpha: 0.15)
                          : (isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Colors.green
                            : (isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!),
                      ),
                    ),
                    child: Text(
                      _getAgeCategoryDisplayName(a),
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? Colors.green
                            : (isDark ? Colors.white70 : Colors.grey[700]),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // ✅ Expandable "Add New Age Category" header with arrow
          _buildExpandableHeader(
            title: 'Add New Age Category',
            icon: Icons.add_circle_outline,
            color: Colors.green,
            isExpanded: isAddFormExpanded,
            subtitle: isAddFormExpanded
                ? 'Tap to collapse'
                : 'Tap to add a new age category',
            onTap: () {
              // ✅ Don't allow collapsing when auto-expanded (no existing
              //    categories) — user must add at least one.
              if (shouldAutoExpand) {
                _showSnackBar(
                  'Add at least one age category to continue',
                  Colors.orange,
                );
                return;
              }
              setState(() =>
                  _addAgeCategoryFormExpanded = !_addAgeCategoryFormExpanded);
            },
          ),

          // ✅ Expanded content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isAddFormExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type a name — suggestions from the master list will appear. Saves to the salon automatically.',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildAgeNameSuggestionField(),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ageMinController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              color:
                                  isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Min Age',
                            hintText: '0',
                            prefixIcon: Icon(Icons.numbers,
                                size: 18,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: AppTheme.primary, width: 2),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            errorText: _ageMinError,
                            errorMaxLines: 2,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _ageMaxController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              color:
                                  isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Max Age',
                            hintText: '100',
                            prefixIcon: Icon(Icons.numbers,
                                size: 18,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: AppTheme.primary, width: 2),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            errorText: _ageMaxError,
                            errorMaxLines: 2,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isAddingAgeCategory
                          ? null
                          : _addAgeCategoryDirect,
                      icon: _isAddingAgeCategory
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save, size: 16),
                      label: const Text('Save Age Category to Salon'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeNameSuggestionField() {
    final isDark = _isDark;

    final suggestions =
        _globalAgeCategories.map((a) => a['display_name'] as String).toList();

    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        final query = textEditingValue.text.toLowerCase();
        return suggestions.where(
          (option) => option.toLowerCase().contains(query),
        );
      },
      onSelected: (String selection) {
        final found = _globalAgeCategories.firstWhere(
          (a) => a['display_name'] == selection,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          _autoFillAgeCategory(found);
        } else {
          _ageDisplayNameController.text = selection;
        }
      },
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
        if (textController.text != _ageDisplayNameController.text) {
          textController.text = _ageDisplayNameController.text;
        }
        _ageDisplayNameController.addListener(() {
          if (textController.text != _ageDisplayNameController.text) {
            textController.text = _ageDisplayNameController.text;
          }
        });

        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: 'Age Category Name *',
            hintText: 'e.g., Adult, Child, Senior',
            prefixIcon: Icon(Icons.visibility,
                size: 18, color: isDark ? Colors.white70 : Colors.grey),
            suffixIcon: suggestions.isNotEmpty
                ? Icon(Icons.arrow_drop_down,
                    color: isDark ? Colors.white70 : Colors.grey)
                : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 2),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            errorText: _ageNameError,
            errorMaxLines: 2,
            isDense: true,
          ),
          onChanged: (value) {
            _ageDisplayNameController.text = value;
            _validateAgeFields();
          },
        );
      },
    );
  }

  Widget _buildDurationField() {
    final isDark = _isDark;
    return TextFormField(
      controller: _variantDurationController,
      keyboardType: TextInputType.number,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'e.g., 30',
        prefixIcon: Icon(Icons.timer,
            size: 18, color: isDark ? Colors.white70 : Colors.grey),
        suffixText: 'mins',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        errorText: _durationError,
        errorMaxLines: 2,
      ),
    );
  }

  Widget _buildPriceField() {
    final isDark = _isDark;
    return TextFormField(
      controller: _variantPriceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'Leave empty to set later',
        prefixIcon: CurrencyPrefix(
          symbol: _salonCurrencySymbol,
          type: CurrencyDisplayType.text,
          color: isDark ? Colors.white70 : Colors.grey,
          fontSize: 16,
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 50, minHeight: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        errorText: _priceError,
        errorMaxLines: 2,
      ),
    );
  }

  // ============================================
  // SAVE BUTTON
  // ============================================
  Widget _buildSaveButton() {
    final isDark = _isDark;
    final accentColor = AppTheme.primary;

    final bool isEnabled = _addedServices.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || !isEnabled) ? null : _saveAllServices,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled
              ? accentColor
              : (isDark ? Colors.grey[800] : Colors.grey[300]),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isEditing ? Icons.save : Icons.add,
                    size: 20,
                    color: isEnabled
                        ? Colors.white
                        : (isDark ? Colors.white60 : Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isEditing
                        ? 'Update Service'
                        : 'Save All Services',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isEnabled
                          ? Colors.white
                          : (isDark ? Colors.white60 : Colors.white70),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ============================================
  // BUILD
  // ============================================
  @override
  Widget build(BuildContext context) {
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;

    final accentColor = AppTheme.primary;
    final double padding = _isWeb ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.barberName != null
              ? '${widget.isEditing ? 'Edit' : 'Add'} Service - ${widget.barberName}'
              : widget.isEditing
                  ? 'Edit Service'
                  : 'Add New Service',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      body: _isLoadingData
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _isWeb ? 1000 : double.infinity,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.isEditing) _buildHierarchyGuideCard(),
                        if (!widget.isEditing) _buildCategoriesSection(),
                        if (!widget.isEditing) _buildServicesSection(),
                        if (!widget.isEditing) _buildVariantsSection(),
                        if (!widget.isEditing) _buildSummarySection(),
                        _buildSaveButton(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}