import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  // Duration is typed as hours + minutes and stored as total minutes.
  final TextEditingController _variantHoursController = TextEditingController();
  final TextEditingController _variantMinutesController =
      TextEditingController();
  final TextEditingController _variantNameController = TextEditingController();
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

  // ==================== HARDCODED GENDER LIST ====================
  static const List<Map<String, dynamic>> _hardcodedGenders = [
    {'id': 1, 'display_name': 'Male'},
    {'id': 2, 'display_name': 'Female'},
    {'id': 3, 'display_name': 'Unisex'},
  ];

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
  List<Map<String, dynamic>> _globalCategories = [];

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
  String? _variantNameError;
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
  bool _genderExpanded = false;
  bool _ageExpanded = false;
  bool _priceExpanded = false;
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

  // ============================================
  // ✅ CURRENCY GETTERS
  // ============================================
  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_salonCurrencyCode);

  bool get _currencyUsesDecimals =>
      _currencyService.getInfo(_salonCurrencyCode).decimals > 0;

  String get _salonPriceHint => _currencyService.getHint(_salonCurrencyCode);

  String get _examplePrice {
    if (_currencyUsesDecimals) {
      return '$_salonCurrencySymbol${15.00}';
    }
    return '$_salonCurrencySymbol${1500}';
  }

  String get _examplePriceFemale {
    if (_currencyUsesDecimals) {
      return '$_salonCurrencySymbol${18.00}';
    }
    return '$_salonCurrencySymbol${1800}';
  }

  String get _examplePriceChild {
    if (_currencyUsesDecimals) {
      return '$_salonCurrencySymbol${4.00}';
    }
    return '$_salonCurrencySymbol${400}';
  }

  // ============================================
  // TEXT LIMITS + SANITISING (the same limits are enforced again in the DB)
  // ============================================
  static const int _maxCategoryName = 40;
  static const int _maxServiceName = 60;
  static const int _maxVariantName = 50;
  static const int _maxAgeName = 30;
  static const int _maxDescription = 200;

  // Invisible / control characters: C0 controls, DEL, zero-width chars,
  // bidi overrides (used to spoof text) and the BOM.
  static final RegExp _badCharsSingleLine = RegExp(
    r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );
  // Same, but a description may keep line breaks (\n = \u000A).
  static final RegExp _badCharsMultiLine = RegExp(
    r'[\u0000-\u0009\u000B-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  /// Blocks bad characters and over-long text while typing / pasting.
  List<TextInputFormatter> _textFormatters(int max, {bool multiLine = false}) {
    return [
      FilteringTextInputFormatter.deny(
        multiLine ? _badCharsMultiLine : _badCharsSingleLine,
      ),
      LengthLimitingTextInputFormatter(max),
    ];
  }

  /// Final clean-up before a value is stored: removes bad characters,
  /// collapses repeated spaces, trims and cuts to [max].
  String _cleanText(String input, int max, {bool multiLine = false}) {
    var t = input.replaceAll(
      multiLine ? _badCharsMultiLine : _badCharsSingleLine,
      '',
    );
    if (multiLine) {
      t = t
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
          .join('\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
    } else {
      t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return t.length > max ? t.substring(0, max).trim() : t;
  }

  bool _isKnownIcon(String? name) =>
      name != null && _iconSuggestions.any((i) => i['name'] == name);

  bool _isHexColor(String? hex) =>
      hex != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex);

  /// Max 8 whole digits (DB column is DECIMAL(10,2)) so a huge number can
  /// never overflow the column.
  List<TextInputFormatter> get _priceFormatters => _currencyUsesDecimals
      ? [
          FilteringTextInputFormatter.allow(RegExp(r'^\d{0,8}(\.\d{0,2})?')),
          LengthLimitingTextInputFormatter(11),
        ]
      : [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(8),
        ];

  /// Maps a technical error to a short message the user can act on.
  /// (Raw database errors are never shown on screen.)
  String _friendlyError(Object e) {
    if (e is PostgrestException) {
      switch (e.code) {
        case '23505':
          return 'This already exists (same name, or the same name + gender + age + duration). Please change it.';
        case '23514':
        case '22001':
          return 'Some text is too long or has characters that are not allowed.';
        case '22003':
          return 'A number is too large.';
        case '23503':
          return "This is linked to other records (like bookings), so it can't be changed right now.";
        case '42501':
          return "You don't have permission to make this change.";
      }
    }
    final text = e.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('timeout')) {
      return "Couldn't reach the server. Please check your internet connection and try again.";
    }
    return 'Something went wrong. Please try again.';
  }

  // ============================================
  // DURATION (hours + minutes → total minutes)
  // ============================================
  /// Error text for the current hours/minutes input, or null when valid.
  String? _durationValidationMessage() {
    final h = _variantHoursController.text.trim();
    final m = _variantMinutesController.text.trim();
    if (h.isEmpty && m.isEmpty) return 'Duration is required';
    final hours = h.isEmpty ? 0 : int.tryParse(h);
    final mins = m.isEmpty ? 0 : int.tryParse(m);
    if (hours == null || mins == null) return 'Enter numbers only';
    if (hours > 23) return 'Hours must be between 0 and 23';
    if (mins > 59) return 'Minutes must be between 0 and 59';
    if (hours * 60 + mins <= 0) return 'Duration must be greater than 0';
    return null;
  }

  /// Total minutes, or null while the input is empty / invalid.
  int? get _parsedDuration {
    if (_durationValidationMessage() != null) return null;
    final h = _variantHoursController.text.trim();
    final m = _variantMinutesController.text.trim();
    return (h.isEmpty ? 0 : int.parse(h)) * 60 + (m.isEmpty ? 0 : int.parse(m));
  }

  /// 45 → "45 min", 60 → "1 hr", 90 → "1 hr 30 min", 120 → "2 hrs".
  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    final hText = h == 1 ? '1 hr' : '$h hrs';
    return m == 0 ? hText : '$hText $m min';
  }

  // ============================================
  // VARIANT LABEL HELPERS (only values that are set are shown)
  // ============================================
  /// Gender / age / duration parts that are actually set (no "Any").
  List<String> _variantDetailParts(Map<String, dynamic> v) {
    final parts = <String>[];
    final gender = (v['gender_name'] ?? '').toString();
    final age = (v['age_category_name'] ?? '').toString();
    final duration = (v['duration'] as num?)?.toInt() ?? 0;
    if (gender.isNotEmpty && gender != 'Any') parts.add(gender);
    if (age.isNotEmpty && age != 'Any') parts.add(age);
    if (duration > 0) parts.add(_formatDuration(duration));
    return parts;
  }

  /// Main line of a variant row: its name, or (no name) the set details.
  String _variantTitle(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    if (vName.isNotEmpty) return vName;
    final parts = _variantDetailParts(v);
    return parts.isEmpty ? 'Standard' : parts.join(' • ');
  }

  /// Second line of a variant row. When a name is the title, the details
  /// move down here; otherwise they are already in the title.
  List<String> _variantSubtitleParts(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    return vName.isNotEmpty ? _variantDetailParts(v) : <String>[];
  }

  /// Second line widget: details • price (price in teal). Wraps on phones.
  Widget _variantSecondLine(
    Map<String, dynamic> v, {
    double fontSize = 11,
  }) {
    final isDark = _isDark;
    final details = _variantSubtitleParts(v);
    final hasPrice = v['price_set'] == true;
    if (details.isEmpty && !hasPrice) return const SizedBox.shrink();
    final detailColor = isDark ? Colors.white60 : Colors.grey[600];
    return Text.rich(
      TextSpan(
        children: [
          if (details.isNotEmpty)
            TextSpan(
              text: details.join(' • '),
              style: TextStyle(fontSize: fontSize, color: detailColor),
            ),
          if (details.isNotEmpty && hasPrice)
            TextSpan(
              text: ' • ',
              style: TextStyle(fontSize: fontSize, color: detailColor),
            ),
          if (hasPrice)
            TextSpan(
              text: _formatPriceDisplay(v),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.teal[300] : Colors.teal[700],
              ),
            ),
        ],
      ),
    );
  }

  /// "Beard Trim • Male • Adult (18-60 yrs) • 30 min" for messages.
  String _variantLabel(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    final parts = <String>[
      if (vName.isNotEmpty) vName,
      ..._variantDetailParts(v),
    ];
    return parts.isEmpty ? 'Standard' : parts.join(' • ');
  }

  /// Variant form is ready to submit: a service is picked and the duration
  /// is valid. (The "name needed" rule is explained on the name field.)
  bool get _canSubmitVariant =>
      _variantTargetServiceIndex != null && _parsedDuration != null;

  /// Name is optional — but required when only the duration is set
  /// (no gender and no age).
  bool get _variantNameRequired =>
      _selectedGenderId == null && _selectedAgeCategoryId == null;

  /// Clears every variant input. Call inside setState.
  void _resetVariantForm() {
    _editingVariantIndex = -1;
    _selectedGenderId = null;
    _selectedAgeCategoryId = null;
    _variantPriceController.clear();
    _variantHoursController.clear();
    _variantMinutesController.clear();
    _variantNameController.clear();
    _priceError = null;
    _durationError = null;
    _variantNameError = null;
    _genderExpanded = false;
    _ageExpanded = false;
    _priceExpanded = false;
  }

  @override
  void initState() {
    super.initState();
    _ageMinController.text = '0';
    _ageMaxController.text = '100';
    _genders = List<Map<String, dynamic>>.from(_hardcodedGenders);
    _loadData();
    _loadSalonCurrency();
    _selectedIcon = _iconSuggestions.first['name'];
    _selectedCategoryColor = _categoryColorOptions.first['hex'];

    _variantPriceController.addListener(_onVariantFieldChanged);
    _variantHoursController.addListener(_onVariantFieldChanged);
    _variantMinutesController.addListener(_onVariantFieldChanged);
    _variantNameController.addListener(_onVariantNameChanged);
    _serviceNameController.addListener(_validateServiceName);
    _newCategoryNameController.addListener(_validateCategoryName);
    _ageDisplayNameController.addListener(_validateAgeFields);
    _ageMinController.addListener(_validateAgeFields);
    _ageMaxController.addListener(_validateAgeFields);
  }

  void _onVariantFieldChanged() {
    if (!mounted) return;
    _validatePrice();
    _validateDuration();
  }

  void _onVariantNameChanged() {
    if (!mounted) return;
    // Clear the "name required" message as soon as the user types.
    if (_variantNameError != null) setState(() => _variantNameError = null);
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
    _variantHoursController.dispose();
    _variantMinutesController.dispose();
    _variantNameController.dispose();
    _newCategoryNameController.dispose();
    _newCategoryDescriptionController.dispose();
    _ageDisplayNameController.dispose();
    _ageMinController.dispose();
    _ageMaxController.dispose();
    super.dispose();
  }

  // ============================================
  // ✅ CURRENCY LOADING
  // ============================================
  Future<void> _loadSalonCurrency() async {
    try {
      final response = await supabase
          .from('salons')
          .select('currency_code')
          .eq('id', widget.salonId)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        final currency = response['currency_code'] as String?;
        if (currency != null && currency.isNotEmpty) {
          setState(() => _salonCurrencyCode = currency);
        }
      }

      debugPrint('✅ Salon currency loaded: $_salonCurrencyCode');
    } catch (e) {
      debugPrint('Error loading salon currency: $e');
    }
  }

  // ============================================
  // VALIDATION
  // ============================================
  void _validateServiceName() {
    final String name = _cleanText(
      _serviceNameController.text,
      _maxServiceName,
    );
    if (name.isEmpty) {
      if (mounted) setState(() => _serviceNameError = null);
      return;
    }
    if (widget.isEditing && widget.serviceId != null) {
      if (mounted) setState(() => _serviceNameError = null);
      return;
    }
    final bool exists = _addedServices.asMap().entries.any(
      (e) =>
          e.value['name'].toString().toLowerCase() == name.toLowerCase() &&
          e.key != _editingServiceIndex,
    );
    if (mounted) {
      setState(() {
        _serviceNameError = exists
            ? 'A service with this name already exists'
            : null;
      });
    }
  }

  void _validateCategoryName() {
    final String name = _cleanText(
      _newCategoryNameController.text,
      _maxCategoryName,
    );
    if (name.isEmpty) {
      if (mounted) setState(() => _categoryNameError = null);
      return;
    }
    final bool exists = _categories.any(
      (c) =>
          c['display_name'].toString().toLowerCase() == name.toLowerCase() &&
          c['id'] != _editingCategoryId,
    );
    if (mounted) {
      setState(() {
        _categoryNameError = exists
            ? 'A category with this name already exists'
            : null;
      });
    }
  }

  void _validateAgeFields() {
    if (!mounted) return;
    setState(() {
      final name = _cleanText(_ageDisplayNameController.text, _maxAgeName);
      if (name.isEmpty) {
        _ageNameError = null;
      } else {
        final exists = _ageCategories.any(
          (a) =>
              a['display_name'].toString().toLowerCase() == name.toLowerCase(),
        );
        _ageNameError = exists ? 'This age category already exists' : null;
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
      if (mounted) setState(() => _priceError = null);
      return;
    }

    final double? price = double.tryParse(priceText);
    if (price == null) {
      if (mounted) setState(() => _priceError = 'Please enter a valid number');
      return;
    }
    if (price < 0) {
      if (mounted) setState(() => _priceError = 'Price cannot be negative');
      return;
    }
    if (price > 99999999.99) {
      if (mounted) setState(() => _priceError = 'Price is too large');
      return;
    }

    if (!_currencyUsesDecimals && priceText.contains('.')) {
      final decimalPart = priceText.split('.').last;
      if (decimalPart.isNotEmpty && int.tryParse(decimalPart) != 0) {
        if (mounted) {
          setState(() {
            _priceError = '$_salonCurrencyCode does not use decimals';
          });
        }
        return;
      }
    }

    if (mounted) setState(() => _priceError = null);
  }

  /// Live validation of hours + minutes. Stays quiet while both are empty
  /// (the "required" message appears when the user tries to add).
  void _validateDuration() {
    if (!mounted) return;
    final bool bothEmpty =
        _variantHoursController.text.trim().isEmpty &&
        _variantMinutesController.text.trim().isEmpty;
    setState(() {
      _durationError = bothEmpty ? null : _durationValidationMessage();
    });
  }

  // ============================================
  // DATA LOADING
  // ============================================
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoadingData = true);

    try {
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select(
            'id, display_name, description, icon_name, color, display_order, is_active',
          )
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

      List<dynamic> globalCategoriesResponse = [];
      try {
        globalCategoriesResponse = await supabase
            .from('categories')
            .select(
              'id, display_name, description, icon_name, color, display_order',
            )
            .eq('is_active', true)
            .order('display_order');
      } catch (e) {
        debugPrint('Could not load global categories: $e');
      }

      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
        _globalAgeCategories = List<Map<String, dynamic>>.from(
          globalAgeResponse,
        );
        _globalCategories = List<Map<String, dynamic>>.from(
          globalCategoriesResponse,
        );
        _genders = List<Map<String, dynamic>>.from(_hardcodedGenders);

        if (_categories.isNotEmpty && _selectedCategoryId == null) {
          _selectedCategoryId = _categories.first['id'] as int;
        }

        _addAgeCategoryFormExpanded = _ageCategories.isEmpty;
      });

      await _loadExistingServicesFromDb();

      if (widget.isEditing && widget.serviceId != null) {
        await _loadServiceForEdit();
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        _showSnackBar(_friendlyError(e), Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  int? _genderIdFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    final match = _hardcodedGenders.firstWhere(
      (g) => (g['display_name'] as String).toLowerCase() == name.toLowerCase(),
      orElse: () => {},
    );
    return match.isNotEmpty ? match['id'] as int? : null;
  }

  String _genderNameFromId(int? id) {
    if (id == null) return 'Any';
    final match = _hardcodedGenders.firstWhere(
      (g) => g['id'] == id,
      orElse: () => {'display_name': 'Any'},
    );
    return match['display_name'] as String? ?? 'Any';
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

      final serviceIds = uniqueServices
          .map<int>((s) => s['id'] as int)
          .toList();

      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, service_id, name, price, duration, salon_gender_id, salon_age_category_id',
          )
          .inFilter('service_id', serviceIds)
          .eq('is_active', true);

      final salonGenderIdToName = <int, String>{};
      try {
        final salonGenderRows = await supabase
            .from('salon_genders')
            .select('id, display_name')
            .eq('salon_id', widget.salonId);
        for (var g in salonGenderRows) {
          salonGenderIdToName[g['id'] as int] = (g['display_name'] ?? 'Any')
              .toString();
        }
      } catch (e) {
        debugPrint('Could not load salon genders map: $e');
      }

      final ageIdToName = <int, String>{};
      for (var a in _ageCategories) {
        ageIdToName[a['id'] as int] = _getAgeCategoryDisplayName(a);
      }

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var v in variantsResponse) {
        final sid = v['service_id'] as int;
        final rawGenderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final storedGenderName = rawGenderId != null
            ? (salonGenderIdToName[rawGenderId] ?? 'Any')
            : 'Any';
        final genderId = _genderIdFromName(storedGenderName);

        final genderName = _genderNameFromId(genderId);
        final ageName = ageId != null ? (ageIdToName[ageId] ?? 'Any') : 'Any';

        final priceNum = (v['price'] as num?)?.toDouble();

        variantsByService.putIfAbsent(sid, () => []).add({
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_category_name': ageName,
          'name': (v['name'] ?? '').toString().trim(),
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'variant_id': v['id'],
          'from_db': true,
          'stored_gender_id': rawGenderId,
        });
      }

      if (!mounted) return;
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
          .select(
            'id, name, price, duration, salon_gender_id, salon_age_category_id',
          )
          .eq('service_id', widget.serviceId!)
          .eq('is_active', true);

      final salonGenderIdToName = <int, String>{};
      try {
        final salonGenderRows = await supabase
            .from('salon_genders')
            .select('id, display_name')
            .eq('salon_id', widget.salonId);
        for (var g in salonGenderRows) {
          salonGenderIdToName[g['id'] as int] = (g['display_name'] ?? 'Any')
              .toString();
        }
      } catch (e) {
        debugPrint('Could not load salon genders map: $e');
      }

      final variants = <Map<String, dynamic>>[];
      for (var v in variantsResponse) {
        final rawGenderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final storedGenderName = rawGenderId != null
            ? (salonGenderIdToName[rawGenderId] ?? 'Any')
            : 'Any';
        final genderId = _genderIdFromName(storedGenderName);

        final ageCat = ageId != null
            ? _ageCategories.firstWhere(
                (a) => a['id'] == ageId,
                orElse: () => {
                  'display_name': 'Any',
                  'min_age': 0,
                  'max_age': 0,
                },
              )
            : {'display_name': 'Any', 'min_age': 0, 'max_age': 0};

        final priceNum = (v['price'] as num?)?.toDouble();

        variants.add({
          'gender_id': genderId,
          'gender_name': _genderNameFromId(genderId),
          'age_category_id': ageId,
          'age_category_name': _getAgeCategoryDisplayName(ageCat),
          'name': (v['name'] ?? '').toString().trim(),
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'variant_id': v['id'],
          'from_db': true,
          'stored_gender_id': rawGenderId,
        });
      }

      if (!mounted) return;
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
    if (serviceIndex >= _addedServices.length) return;

    final service = _addedServices[serviceIndex];
    final serviceId = service['id'];
    if (serviceId == null) return;

    if (mounted) setState(() => _isLoadingVariants = true);
    try {
      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, name, price, duration, salon_gender_id, salon_age_category_id',
          )
          .eq('service_id', serviceId)
          .eq('is_active', true);

      final salonGenderIdToName = <int, String>{};
      try {
        final salonGenderRows = await supabase
            .from('salon_genders')
            .select('id, display_name')
            .eq('salon_id', widget.salonId);
        for (var g in salonGenderRows) {
          salonGenderIdToName[g['id'] as int] = (g['display_name'] ?? 'Any')
              .toString();
        }
      } catch (e) {
        debugPrint('Could not load salon genders map: $e');
      }

      final ageIdToName = <int, String>{};
      for (var a in _ageCategories) {
        ageIdToName[a['id'] as int] = _getAgeCategoryDisplayName(a);
      }

      final loaded = <Map<String, dynamic>>[];
      for (var v in variantsResponse) {
        final rawGenderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final storedGenderName = rawGenderId != null
            ? (salonGenderIdToName[rawGenderId] ?? 'Any')
            : 'Any';
        final genderId = _genderIdFromName(storedGenderName);

        final ageName = ageId != null ? (ageIdToName[ageId] ?? 'Any') : 'Any';

        final priceNum = (v['price'] as num?)?.toDouble();

        loaded.add({
          'gender_id': genderId,
          'gender_name': _genderNameFromId(genderId),
          'age_category_id': ageId,
          'age_category_name': ageName,
          'name': (v['name'] ?? '').toString().trim(),
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'variant_id': v['id'],
          'from_db': true,
          'stored_gender_id': rawGenderId,
        });
      }

      if (!mounted) return;
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

  /// ✅ FIX: Use index loop instead of `variants.indexOf(v)`
  bool _isVariantDuplicate(int serviceIndex) {
    if (serviceIndex >= _addedServices.length) return false;

    final service = _addedServices[serviceIndex];
    final variants = service['variants'] as List;

    final newGenderId = _selectedGenderId;
    final newAgeId = _selectedAgeCategoryId;
    final newDuration = _parsedDuration ?? 0;
    final newName = _cleanText(
      _variantNameController.text,
      _maxVariantName,
    ).toLowerCase();

    for (int i = 0; i < variants.length; i++) {
      // Skip the variant being edited
      if (_editingVariantIndex >= 0 && i == _editingVariantIndex) continue;

      final v = variants[i];
      final sameGender = (v['gender_id'] as int?) == newGenderId;
      final sameAge = (v['age_category_id'] as int?) == newAgeId;
      final sameDuration =
          ((v['duration'] as num?)?.toInt() ?? 0) == newDuration;
      final sameName =
          (v['name'] ?? '').toString().trim().toLowerCase() == newName;

      if (sameGender && sameAge && sameDuration && sameName) return true;
    }
    return false;
  }

  /// Only called for variants whose price is set (unset prices are hidden).
  String _formatPriceDisplay(Map<String, dynamic> v) {
    final price = (v['price'] as num?)?.toDouble() ?? 0.0;
    if (price == 0) {
      return 'Free';
    }
    return _currencyService.format(
      price: price,
      currencyCode: _salonCurrencyCode,
    );
  }

  // ============================================
  // CATEGORY MANAGEMENT
  // ============================================
  Future<void> _addOrUpdateCategory() async {
    _validateCategoryName();
    final displayName = _cleanText(
      _newCategoryNameController.text,
      _maxCategoryName,
    );
    if (displayName.isEmpty) {
      _showSnackBar('Category name is required', Colors.orange);
      return;
    }
    if (_categoryNameError != null) {
      _showSnackBar(_categoryNameError!, Colors.orange);
      return;
    }
    final categoryDescription = _cleanText(
      _newCategoryDescriptionController.text,
      _maxDescription,
      multiLine: true,
    );

    if (mounted) setState(() => _isLoading = true);
    try {
      final data = {
        'salon_id': widget.salonId,
        'display_name': displayName,
        'description': categoryDescription.isEmpty ? null : categoryDescription,
        'icon_name': _isKnownIcon(_selectedIcon)
            ? _selectedIcon
            : _iconSuggestions.first['name'],
        'color': _isHexColor(_selectedCategoryColor)
            ? _selectedCategoryColor
            : _categoryColorOptions.first['hex'],
        'is_active': true,
      };

      if (_editingCategoryId != null) {
        await supabase
            .from('salon_categories')
            .update(data)
            .eq('id', _editingCategoryId!);

        if (!mounted) return;
        setState(() {
          final idx = _categories.indexWhere(
            (c) => c['id'] == _editingCategoryId,
          );
          if (idx >= 0) {
            _categories[idx] = {..._categories[idx], ...data};
          }
          _editingCategoryId = null;
          _newCategoryNameController.clear();
          _newCategoryDescriptionController.clear();
          _selectedIcon = _iconSuggestions.first['name'];
          _selectedCategoryColor = _categoryColorOptions.first['hex'];
          _categoryNameError = null;
        });
      } else {
        data['display_order'] = _categories.length;

        final inserted = await supabase
            .from('salon_categories')
            .insert(data)
            .select()
            .single();

        if (!mounted) return;
        setState(() {
          _categories.add(Map<String, dynamic>.from(inserted));
          _selectedCategoryId = inserted['id'] as int;
          _newCategoryNameController.clear();
          _newCategoryDescriptionController.clear();
          _selectedIcon = _iconSuggestions.first['name'];
          _selectedCategoryColor = _categoryColorOptions.first['hex'];
          _categoryNameError = null;
        });
      }
    } catch (e) {
      debugPrint('Error saving category: $e');
      if (mounted) _showSnackBar(_friendlyError(e), Colors.red);
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
    if (index >= _categories.length) return;

    final cat = _categories[index];
    final catId = cat['id'] as int?;
    final catName = cat['display_name'] ?? '';

    final confirmed = await _showConfirmDialog(
      title: 'Delete Category?',
      message:
          'This will permanently remove "$catName" and all services under it (with their variants) from the salon.',
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      if (catId != null) {
        await supabase.from('salon_categories').delete().eq('id', catId);

        if (!mounted) return;
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
      }
    } catch (e) {
      debugPrint('Error deleting category: $e');
      if (mounted) _showSnackBar(_friendlyError(e), Colors.red);
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
    });
    _validateAgeFields();
  }

  Future<void> _addAgeCategoryDirect() async {
    _validateAgeFields();

    final displayName = _cleanText(_ageDisplayNameController.text, _maxAgeName);
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

    if (mounted) setState(() => _isAddingAgeCategory = true);

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

      if (!mounted) return;
      setState(() {
        _ageCategories.add(Map<String, dynamic>.from(inserted));
        _selectedAgeCategoryId = inserted['id'] as int;

        _ageDisplayNameController.clear();
        _ageMinController.text = '0';
        _ageMaxController.text = '100';
        _ageNameError = null;
        _ageMinError = null;
        _ageMaxError = null;
        _addAgeCategoryFormExpanded = false;
      });
    } catch (e) {
      debugPrint('Error adding age category: $e');
      if (mounted) _showSnackBar(_friendlyError(e), Colors.red);
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
    final name = _cleanText(_serviceNameController.text, _maxServiceName);
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
      'description': _cleanText(
        _serviceDescriptionController.text,
        _maxDescription,
        multiLine: true,
      ),
      'icon_name': _isKnownIcon(_selectedIcon)
          ? _selectedIcon
          : _iconSuggestions.first['name'],
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
  }

  void _editAddedService(int index) {
    if (index >= _addedServices.length) return;

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
    if (index >= _addedServices.length) return;

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
    int serviceId,
    int localIndex,
    String serviceName,
  ) async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete Service?',
      message:
          'This will permanently remove "$serviceName" and all its variants from the salon.',
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('services').delete().eq('id', serviceId);

      if (!mounted) return;
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
      debugPrint('Error removing service: $e');
      if (mounted) _showSnackBar(_friendlyError(e), Colors.red);
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

    _validatePrice();

    // Duration is the only always-required field of a variant.
    final durationMessage = _durationValidationMessage();
    if (durationMessage != null) {
      setState(() => _durationError = durationMessage);
      _showSnackBar(durationMessage, Colors.orange);
      return;
    }

    if (_priceError != null) {
      _showSnackBar('Please fix the errors before adding', Colors.orange);
      return;
    }

    // Name is optional, but mandatory when only the duration is set
    // (no gender and no age).
    final variantName = _cleanText(_variantNameController.text, _maxVariantName);
    if (variantName.isEmpty && _variantNameRequired) {
      const message =
          'Name is required when only duration is set (no gender or age)';
      setState(() {
        _variantNameError = message;
      });
      _showSnackBar(message, Colors.orange);
      return;
    }

    final priceText = _variantPriceController.text.trim();
    final bool priceSet = priceText.isNotEmpty;
    final double price;
    if (!priceSet) {
      price = 0;
    } else {
      final parsed = double.tryParse(priceText);
      if (parsed == null || parsed < 0 || parsed > 99999999.99) {
        _showSnackBar('Please enter a valid price', Colors.orange);
        return;
      }
      price = parsed;
    }

    // Stored as total minutes (all calculations use minutes)
    final int duration = _parsedDuration!;

    if (_isVariantDuplicate(_variantTargetServiceIndex!)) {
      _showSnackBar(
        'This name + gender + age + duration combination is already added',
        Colors.orange,
      );
      return;
    }

    final genderName = _genderNameFromId(_selectedGenderId);
    final ageName = _selectedAgeCategoryId != null
        ? _getAgeCategoryDisplayName(
            _ageCategories.firstWhere(
              (a) => a['id'] == _selectedAgeCategoryId,
              orElse: () => {'display_name': 'Any', 'min_age': 0, 'max_age': 0},
            ),
          )
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
          'name': variantName,
          'price': price,
          'price_set': priceSet,
          'duration': duration,
          'edited': true,
        };
      } else {
        (service['variants'] as List).add({
          'gender_id': _selectedGenderId,
          'gender_name': genderName,
          'age_category_id': _selectedAgeCategoryId,
          'age_category_name': ageName,
          'name': variantName,
          'price': price,
          'price_set': priceSet,
          'duration': duration,
        });
      }

      _resetVariantForm();
    });
  }

  void _editVariant(int serviceIndex, int variantIndex) {
    if (serviceIndex >= _addedServices.length) return;

    final service = _addedServices[serviceIndex];
    final variants = service['variants'] as List;
    if (variantIndex >= variants.length) return;

    final v = variants[variantIndex];

    setState(() {
      _variantTargetServiceIndex = serviceIndex;
      _editingVariantIndex = variantIndex;

      _selectedGenderId = v['gender_id'] as int?;
      _selectedAgeCategoryId = v['age_category_id'] as int?;

      final price = (v['price'] as num).toDouble();
      final priceSet = v['price_set'] == true;
      // A price of 0 ("Free") was typed on purpose, so keep it as "0"
      _variantPriceController.text = !priceSet
          ? ''
          : (price == 0
                ? '0'
                : (_currencyUsesDecimals
                      ? price.toString()
                      : price.toInt().toString()));

      // Split the stored total minutes back into hours + minutes
      final duration = (v['duration'] as num?)?.toInt() ?? 0;
      _variantHoursController.text = duration >= 60
          ? (duration ~/ 60).toString()
          : '';
      _variantMinutesController.text = duration > 0 && duration % 60 > 0
          ? (duration % 60).toString()
          : '';
      _variantNameController.text = (v['name'] ?? '').toString();
      _durationError = null;
      _variantNameError = null;

      // Open the optional sections that already have a value
      _genderExpanded = _selectedGenderId != null;
      _ageExpanded = _selectedAgeCategoryId != null;
      _priceExpanded = priceSet;
    });
  }

  void _cancelEditVariant() {
    setState(_resetVariantForm);
  }

  void _removeVariant(int serviceIndex, int variantIndex) {
    if (serviceIndex >= _addedServices.length) return;

    final service = _addedServices[serviceIndex];
    final variants = service['variants'] as List;
    if (variantIndex >= variants.length) return;

    final variant = variants[variantIndex];

    if (variant['from_db'] == true && variant['variant_id'] != null) {
      _confirmRemoveDbVariant(
        serviceIndex,
        variantIndex,
        variant['variant_id'] as int,
      );
    } else {
      setState(() {
        variants.removeAt(variantIndex);
      });
    }
  }

  Future<void> _confirmRemoveDbVariant(
    int serviceIndex,
    int variantIndex,
    int variantId,
  ) async {
    String variantText = 'this variant';
    if (serviceIndex < _addedServices.length) {
      final list = _addedServices[serviceIndex]['variants'] as List;
      if (variantIndex < list.length) {
        variantText =
            '"${_variantLabel(Map<String, dynamic>.from(list[variantIndex]))}"';
      }
    }
    final confirmed = await _showConfirmDialog(
      title: 'Delete Variant?',
      message: 'This will permanently remove $variantText from the salon.',
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      try {
        await supabase.from('service_variants').delete().eq('id', variantId);

        if (!mounted) return;
        setState(() {
          if (serviceIndex < _addedServices.length) {
            final service = _addedServices[serviceIndex];
            final variants = service['variants'] as List;
            if (variantIndex < variants.length) {
              variants.removeAt(variantIndex);
            }
          }
        });
        _showSnackBar('Variant removed', Colors.orange);
      } catch (e) {
        debugPrint('Error removing variant: $e');
        if (mounted) _showSnackBar(_friendlyError(e), Colors.red);
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: _isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
  Future<void> _saveAllServices() async {
    if (_addedServices.isEmpty) {
      _showSnackBar('Please add at least one service', Colors.orange);
      return;
    }

    final totalVariantsPreview = _addedServices.fold<int>(
      0,
      (sum, s) => sum + (s['variants'] as List).length,
    );

    final confirmed = await _showSaveConfirmDialog(
      title: widget.isEditing ? 'Update Service?' : 'Save Services?',
      message: widget.isEditing
          ? 'This will save your changes to "${_addedServices.isNotEmpty ? _addedServices.first['name'] : ''}" to the database.'
          : 'This will save ${_addedServices.length} service${_addedServices.length == 1 ? '' : 's'} '
                'and $totalVariantsPreview variant${totalVariantsPreview == 1 ? '' : 's'} to the database.',
    );

    if (confirmed != true) return;

    await _performSaveAllServices();
  }

  Future<bool?> _showSaveConfirmDialog({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: _isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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

  /// ✅ FIX: Removed unused `toInsertKeys` variable
  Future<Map<String, int>> _ensureSalonGenders() async {
    final Map<String, int> byNameLower = {};

    final existing = await supabase
        .from('salon_genders')
        .select('id, display_name')
        .eq('salon_id', widget.salonId);

    for (var g in existing) {
      final name = (g['display_name'] ?? '').toString();
      byNameLower[name.trim().toLowerCase()] = g['id'] as int;
    }

    int nextOrder = existing.length;
    final List<Map<String, dynamic>> toInsert = [];

    for (final hg in _hardcodedGenders) {
      final name = (hg['display_name'] as String).trim();
      final key = name.toLowerCase();
      if (byNameLower.containsKey(key)) continue;

      toInsert.add({
        'salon_id': widget.salonId,
        'display_name': name,
        'display_order': nextOrder++,
        'is_active': true,
      });
    }

    if (toInsert.isNotEmpty) {
      try {
        final inserted = await supabase
            .from('salon_genders')
            .insert(toInsert)
            .select('id, display_name');

        for (var row in inserted) {
          final name = (row['display_name'] ?? '').toString();
          byNameLower[name.trim().toLowerCase()] = row['id'] as int;
        }
      } catch (e) {
        debugPrint('Could not bulk insert salon genders: $e');
      }
    }

    return byNameLower;
  }

  Future<void> _performSaveAllServices() async {
    if (mounted) setState(() => _isLoading = true);

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
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      final Map<String, int> genderIdByNameLower = await _ensureSalonGenders();

      final existingServicesResponse = await supabase
          .from('services')
          .select('id, name')
          .eq('salon_id', widget.salonId);

      final Map<String, int> existingServiceIdByName = {};
      for (var s in existingServicesResponse) {
        existingServiceIdByName[(s['name'] as String).trim().toLowerCase()] =
            s['id'] as int;
      }

      final Set<int> usedServiceIds = {};

      for (final service in _addedServices) {
        final fromDb = service['from_db'] == true;
        final localId = service['id'] as int?;
        final svcName = _cleanText(
          (service['name'] ?? '').toString(),
          _maxServiceName,
        );
        final svcDescription = _cleanText(
          (service['description'] ?? '').toString(),
          _maxDescription,
          multiLine: true,
        );
        final svcIcon = _isKnownIcon(service['icon_name']?.toString())
            ? service['icon_name']
            : _iconSuggestions.first['name'];
        final svcNameLower = svcName.toLowerCase();

        int serviceId;

        if (fromDb && localId != null) {
          serviceId = localId;
          usedServiceIds.add(serviceId);

          await supabase
              .from('services')
              .update({
                'name': svcName,
                'description': svcDescription.isEmpty ? null : svcDescription,
                'category_id': service['category_id'],
                'icon_name': svcIcon,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', serviceId);

          await supabase
              .from('service_variants')
              .delete()
              .eq('service_id', serviceId);
        } else if (widget.isEditing &&
            widget.serviceId != null &&
            localId == widget.serviceId) {
          serviceId = widget.serviceId!;
          usedServiceIds.add(serviceId);

          await supabase
              .from('services')
              .update({
                'name': svcName,
                'description': svcDescription.isEmpty ? null : svcDescription,
                'category_id': service['category_id'],
                'icon_name': svcIcon,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', serviceId);
        } else {
          final existingId = existingServiceIdByName[svcNameLower];

          if (existingId != null && !usedServiceIds.contains(existingId)) {
            serviceId = existingId;
            usedServiceIds.add(serviceId);

            await supabase
                .from('services')
                .update({
                  'name': svcName,
                  'description': svcDescription.isEmpty ? null : svcDescription,
                  'category_id': service['category_id'],
                  'icon_name': svcIcon,
                  'is_active': true,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', serviceId);

            await supabase
                .from('service_variants')
                .delete()
                .eq('service_id', serviceId);
          } else {
            final serviceData = {
              'salon_id': widget.salonId,
              'name': svcName,
              'description': svcDescription.isEmpty ? null : svcDescription,
              'category_id': service['category_id'],
              'icon_name': svcIcon,
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

        // Bulk insert variants
        final variants = service['variants'] as List;
        if (variants.isNotEmpty) {
          final List<Map<String, dynamic>> variantDataList = [];
          for (final v in variants) {
            final genderName = (v['gender_name'] as String? ?? 'Any').trim();
            final genderKey = genderName.toLowerCase();
            final resolvedGenderId = genderName == 'Any'
                ? null
                : genderIdByNameLower[genderKey];

            final variantNameClean = _cleanText(
              (v['name'] ?? '').toString(),
              _maxVariantName,
            );
            variantDataList.add({
              'service_id': serviceId,
              'salon_gender_id': resolvedGenderId,
              'salon_age_category_id': v['age_category_id'],
              'name': variantNameClean.isEmpty ? null : variantNameClean,
              'price': v['price_set'] == true ? v['price'] : null,
              'duration': ((v['duration'] as num?)?.toInt() ?? 0) == 0
                  ? null
                  : v['duration'],
              'is_active': true,
            });
          }

          final insertedVariants = await supabase
              .from('service_variants')
              .insert(variantDataList)
              .select('id');

          if (widget.salonBarberId != null) {
            final List<Map<String, dynamic>> barberServiceData = [];
            for (
              int i = 0;
              i < insertedVariants.length && i < variants.length;
              i++
            ) {
              barberServiceData.add({
                'salon_barber_id': widget.salonBarberId!,
                'service_id': serviceId,
                'variant_id': insertedVariants[i]['id'],
                'custom_price': variants[i]['price'],
              });
            }
            if (barberServiceData.isNotEmpty) {
              await supabase.from('barber_services').insert(barberServiceData);
            }
          }
        } else if (widget.salonBarberId != null) {
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

      setState(() {
        _isLoading = false;
        _addedServices.clear();
        _dbServiceIds.clear();
        _variantTargetServiceIndex = null;
        _editingServiceIndex = -1;
        _resetVariantForm();
        _serviceNameController.clear();
        _serviceDescriptionController.clear();
      });

      await _loadData();

      if (!mounted) return;
      _showSnackBar(
        'Saved successfully. You can continue adding more services.',
        Colors.green,
      );
    } catch (e) {
      if (mounted) {
        final errorText = e.toString();
        if (errorText.contains('duplicate key value violates unique') &&
            errorText.contains('service_variants')) {
          _showSnackBar(
            'Two variants are exactly the same (name, gender, age and duration). Please change or remove one.',
            Colors.orange,
          );
        } else if (errorText.contains(
          'duplicate key value violates unique constraint',
        )) {
          _showSnackBar(
            'A service with this name already exists. Please use a different name.',
            Colors.orange,
          );
        } else {
          debugPrint('Error saving services: $e');
          _showSnackBar(_friendlyError(e), Colors.red);
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
              child: Icon(icon, color: color, size: isMainHeader ? 22 : 18),
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
  // HIERARCHY GUIDE
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
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.25)),
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
                  child: Icon(
                    Icons.account_tree,
                    color: AppTheme.primary,
                    size: 20,
                  ),
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
              'have many variants (by name, gender, age, price and duration).',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      levelLabel('Category', Colors.orange),
                      arrow(Colors.orange),
                      const Icon(Icons.folder, size: 15, color: Colors.orange),
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
                      const Icon(
                        Icons.content_cut,
                        size: 13,
                        color: Colors.blue,
                      ),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      levelLabel('Variant', Colors.purple),
                      arrow(Colors.purple),
                      Text(
                        '│  ├─ ①',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Male • Adult   $_examplePrice • 30 min',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
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
                            color: isDark ? Colors.white38 : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Female • Child  $_examplePriceFemale • 45 min',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
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
                      const Icon(
                        Icons.water_drop,
                        size: 13,
                        color: Colors.blue,
                      ),
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
                            color: isDark ? Colors.white38 : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Short hair   Free • 15 min',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                            color: isDark ? Colors.white38 : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Male • Child  $_examplePriceChild • 10 min',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.grey[700],
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
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
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
  // CATEGORY NAME — Autocomplete
  // ✅ FIX: Removed addListener inside fieldViewBuilder (memory leak)
  // ============================================
  Widget _buildCategoryNameSuggestionField() {
    final isDark = _isDark;

    final suggestionSet = <String>{};
    for (final c in _globalCategories) {
      final name = c['display_name']?.toString();
      if (name != null && name.isNotEmpty) suggestionSet.add(name);
    }
    for (final c in _categories) {
      final name = c['display_name']?.toString();
      if (name != null && name.isNotEmpty) suggestionSet.add(name);
    }
    final suggestions = suggestionSet.toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Autocomplete<String>(
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
          final found = _globalCategories.firstWhere(
            (c) => c['display_name'] == selection,
            orElse: () => {},
          );
          if (found.isNotEmpty) {
            _autoFillCategory(found);
          } else {
            _newCategoryNameController.text = selection;
            _validateCategoryName();
          }
        },
        fieldViewBuilder:
            (context, textController, focusNode, onFieldSubmitted) {
              // ✅ Sync one-time (no listener accumulation)
              if (textController.text != _newCategoryNameController.text) {
                textController.text = _newCategoryNameController.text;
              }

              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                inputFormatters: _textFormatters(_maxCategoryName),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  counterText: '',
                  labelText: 'Category Name *',
                  hintText: 'e.g., Hair, Nails, Spa',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  prefixIcon: Icon(
                    Icons.category,
                    size: 18,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  suffixIcon: suggestions.isNotEmpty
                      ? Icon(
                          Icons.arrow_drop_down,
                          color: isDark ? Colors.white70 : Colors.grey,
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppTheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  errorText: _categoryNameError,
                  errorMaxLines: 2,
                ),
                onChanged: (value) {
                  _newCategoryNameController.text = value;
                  _validateCategoryName();
                },
              );
            },
      ),
    );
  }

  // ============================================
  // SERVICE NAME — Autocomplete (suggestions from the salon's own services)
  // Picking one fills the description + icon. Typing never changes other fields.
  // ============================================
  Widget _buildServiceNameSuggestionField() {
    final isDark = _isDark;

    final suggestions = <String>{
      for (final s in _addedServices)
        if ((s['name'] ?? '').toString().isNotEmpty) s['name'].toString(),
    }.toList();

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
        final found = _addedServices.firstWhere(
          (s) => (s['name'] ?? '').toString() == selection,
          orElse: () => {},
        );
        setState(() {
          _serviceNameController.text = selection;
          // Only picking a suggestion fills the other fields
          if (found.isNotEmpty) {
            _serviceDescriptionController.text = (found['description'] ?? '')
                .toString();
            final icon = found['icon_name']?.toString();
            if (_isKnownIcon(icon)) _selectedIcon = icon;
          }
        });
        _validateServiceName();
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        // Sync one-time (no listener accumulation)
        if (textController.text != _serviceNameController.text) {
          textController.text = _serviceNameController.text;
        }

        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          inputFormatters: _textFormatters(_maxServiceName),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'e.g., Hair Cut, Facial',
            counterText: '',
            prefixIcon: Icon(
              Icons.build,
              size: 18,
              color: isDark ? Colors.white70 : Colors.grey,
            ),
            suffixIcon: suggestions.isNotEmpty
                ? Icon(
                    Icons.arrow_drop_down,
                    color: isDark ? Colors.white70 : Colors.grey,
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            errorText: _serviceNameError,
            errorMaxLines: 2,
          ),
          // Typing only updates the name (never other fields)
          onChanged: (value) => _serviceNameController.text = value,
        );
      },
    );
  }

  void _autoFillCategory(Map<String, dynamic> selected) {
    setState(() {
      _newCategoryNameController.text =
          selected['display_name']?.toString() ?? '';
      _newCategoryDescriptionController.text =
          selected['description']?.toString() ?? '';

      // Only accept an icon / colour the app actually knows
      final iconName = selected['icon_name']?.toString();
      if (_isKnownIcon(iconName)) {
        _selectedIcon = iconName;
      }

      final colorHex = selected['color']?.toString();
      if (_isHexColor(colorHex)) {
        _selectedCategoryColor = colorHex!;
      }

      _validateCategoryName();
    });
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
                    style: TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCategoryNameSuggestionField(),
          TextFormField(
            controller: _newCategoryDescriptionController,
            maxLines: 2,
            maxLength: _maxDescription,
            inputFormatters: _textFormatters(_maxDescription, multiLine: true),
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g., Hair cutting and styling',
              prefixIcon: Icon(
                Icons.description,
                size: 18,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
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
              icon: Icon(isEditingCat ? Icons.save : Icons.add, size: 18),
              label: Text(isEditingCat ? 'Update Category' : 'Add Category'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isEditingCat ? Colors.orange : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
                    Icon(
                      Icons.inbox,
                      size: 36,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No categories yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey[500],
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
                      horizontal: 4,
                      vertical: 0,
                    ),
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: _hexToColor(
                        cat['color'] ?? '#FF6B8B',
                      ).withValues(alpha: 0.15),
                      child: Icon(
                        _iconFromName(cat['icon_name']),
                        size: 14,
                        color: _hexToColor(cat['color'] ?? '#FF6B8B'),
                      ),
                    ),
                    title: Text(
                      _getCategoryDisplayName(cat),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected || isBeingEdited
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isBeingEdited
                            ? Colors.orange
                            : (isSelected
                                  ? AppTheme.primary
                                  : (isDark ? Colors.white : Colors.black87)),
                      ),
                    ),
                    subtitle: (cat['description'] ?? '').toString().isNotEmpty
                        ? Text(
                            cat['description'],
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () => setState(() => _selectedCategoryId = catId),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.blue,
                          ),
                          onPressed: () => _editCategory(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Edit',
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: isDark ? Colors.red[300] : Colors.red,
                          ),
                          onPressed: () => _deleteCategory(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete',
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            color: AppTheme.primary,
                            size: 18,
                          ),
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
                  child: const Icon(
                    Icons.category,
                    color: Colors.orange,
                    size: 20,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_categories.length} items',
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
                        : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
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
                  setState(() => _selectedCategoryColor = opt['hex'] as String),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: opt['color'] as Color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: (opt['color'] as Color).withValues(
                              alpha: 0.5,
                            ),
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
      try {
        return Color(int.parse('0xFF${hex.substring(1)}'));
      } catch (_) {
        return AppTheme.primary;
      }
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
              const Icon(
                Icons.add_circle_outline,
                size: 18,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                _editingServiceIndex >= 0 ? 'Edit Service' : 'Add New Service',
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
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add at least one category above first',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.grey[700],
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
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.category,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: _categories.map((cat) {
                return DropdownMenuItem<int>(
                  value: cat['id'] as int,
                  child: Text(
                    _getCategoryDisplayName(cat),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedCategoryId = v),
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
            _buildServiceNameSuggestionField(),
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
              maxLength: _maxDescription,
              inputFormatters: _textFormatters(
                _maxDescription,
                multiLine: true,
              ),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Describe this service...',
                prefixIcon: Icon(
                  Icons.description,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a category to continue',
                      style: TextStyle(
                        fontSize: 11,
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
                    Icon(
                      Icons.inbox,
                      size: 36,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No services yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey[500],
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
                      horizontal: 4,
                      vertical: 0,
                    ),
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
                            color: isSelected ? Colors.purple : Colors.orange,
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
                                  color: Colors.white,
                                  width: 1.5,
                                ),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
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
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.blue,
                          ),
                          onPressed: () => _editAddedService(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Edit',
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: isDark ? Colors.red[300] : Colors.red,
                          ),
                          onPressed: () => _removeAddedService(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete',
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.purple,
                            size: 18,
                          ),
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
                  child: const Icon(
                    Icons.build,
                    color: Colors.orange,
                    size: 20,
                  ),
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
              Icon(
                Icons.info_outline,
                color: isDark ? Colors.white60 : Colors.grey,
                size: 32,
              ),
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

    final selectedService =
        _variantTargetServiceIndex != null &&
            _variantTargetServiceIndex! < _addedServices.length
        ? _addedServices[_variantTargetServiceIndex!]
        : null;
    final variants = selectedService != null
        ? (selectedService['variants'] as List)
        : <dynamic>[];

    final isEditingVariant = _editingVariantIndex >= 0;
    // Add Variant is enabled once the duration is valid; the name rule
    // ("required when no gender and no age") is explained on the name field.
    final canAddVariant = _canSubmitVariant;

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
                    style: TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isEditingVariant
                ? 'Update the fields below'
                : 'Duration is required. Gender, age, price and name are optional '
                      '(name is required when no gender and no age).',
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
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Choose a service...',
              prefixIcon: Icon(
                Icons.build,
                size: 18,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                  '${svc['name']} • $vCount variant${vCount == 1 ? '' : 's'}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              );
            }).toList(),
            onChanged: (v) async {
              setState(() {
                _variantTargetServiceIndex = v;
                _resetVariantForm();
              });

              if (v != null && v < _addedServices.length) {
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
              title: '1. Gender',
              icon: Icons.wc,
              color: Colors.blue,
              isExpanded: _genderExpanded,
              subtitle: _selectedGenderId != null
                  ? _genderNameFromId(_selectedGenderId)
                  : 'Tap to select gender (optional)',
              onTap: () => setState(() => _genderExpanded = !_genderExpanded),
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
              title: '2. Age Category',
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
              onTap: () => setState(() => _ageExpanded = !_ageExpanded),
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
              title: '3. Price',
              icon: Icons.attach_money,
              color: Colors.teal,
              isExpanded: _priceExpanded,
              subtitle: _variantPriceController.text.isNotEmpty
                  ? '$_salonCurrencySymbol${_variantPriceController.text}'
                  : 'Tap to enter price (optional — add later)',
              onTap: () => setState(() => _priceExpanded = !_priceExpanded),
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
            const SizedBox(height: 8),

            // 4. Duration — always shown, required (hours + minutes)
            _buildStaticSectionHeader(
              title: '4. Duration',
              icon: Icons.timer,
              color: Colors.orange,
              isRequired: true,
              subtitle: _parsedDuration != null
                  ? _formatDuration(_parsedDuration!)
                  : 'Required — hours and minutes',
            ),
            const SizedBox(height: 8),
            _buildDurationField(),
            const SizedBox(height: 8),

            // 5. Variant name — optional, required when no gender and no age
            _buildStaticSectionHeader(
              title: '5. Variant Name',
              icon: Icons.label_outline,
              color: Colors.indigo,
              isRequired: _variantNameRequired,
              subtitle: _variantNameRequired
                  ? 'Required — no gender or age is set'
                  : 'Optional — e.g., Short hair, Long hair',
            ),
            const SizedBox(height: 8),
            _buildVariantNameField(),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canAddVariant ? _saveVariant : null,
                icon: Icon(isEditingVariant ? Icons.save : Icons.add, size: 18),
                label: Text(
                  isEditingVariant ? 'Update Variant' : 'Add Variant',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEditingVariant
                      ? Colors.orange
                      : (canAddVariant
                            ? Colors.purple
                            : (isDark ? Colors.grey[800] : Colors.grey[300])),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (!canAddVariant && !isEditingVariant) ...[
              const SizedBox(height: 6),
              Text(
                'Enter the duration to enable',
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
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a service to add variants',
                      style: TextStyle(
                        fontSize: 11,
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
                    Icon(
                      Icons.tune,
                      size: 36,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a service to view its variants',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey[500],
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
                    Icon(
                      Icons.inbox,
                      size: 36,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No variants added yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey[500],
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
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Name (or the set details) wraps to 2 lines; details +
                  // price always sit on their own line below, so nothing is
                  // pushed off a narrow phone screen. Unset values are hidden.
                  title: Text(
                    _variantTitle(v),
                    maxLines: 2,
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
                  subtitle:
                      (_variantSubtitleParts(v).isNotEmpty ||
                          v['price_set'] == true)
                      ? _variantSecondLine(v)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.blue,
                        ),
                        onPressed: () =>
                            _editVariant(_variantTargetServiceIndex!, index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit',
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: isDark ? Colors.red[300] : Colors.red,
                        ),
                        onPressed: () =>
                            _removeVariant(_variantTargetServiceIndex!, index),
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
            // Always open — no collapse arrow
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tune,
                    color: Colors.purple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Variants (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Add price and duration options for a service',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: variantForm()),
                  const SizedBox(width: 12),
                  Expanded(child: variantsList()),
                ],
              )
            else
              Column(
                children: [
                  variantForm(),
                  const SizedBox(height: 12),
                  variantsList(),
                ],
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
                  child: const Icon(
                    Icons.account_tree,
                    color: Colors.indigo,
                    size: 20,
                  ),
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
                      Icon(
                        Icons.inbox,
                        size: 40,
                        color: isDark ? Colors.white30 : Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Nothing added yet',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add categories, services and variants to see them here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey[500],
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                    maxLines: 2,
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
                      horizontal: 5,
                      vertical: 1,
                    ),
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
    final isFromDb = v['from_db'] == true;
    final vConnector = isLastVariant ? '└─' : '├─';
    final circledNum = _toCircledNumber(index + 1);

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          // Name (or set details) on the first line (wraps to 2 lines);
          // details + price on the line below. Unset values are hidden.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _variantTitle(v),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                _variantSecondLine(v, fontSize: 10.5),
              ],
            ),
          ),
          if (isFromDb) ...[
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
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
                  child: Icon(
                    Icons.help_outline,
                    size: 16,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
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
      '①',
      '②',
      '③',
      '④',
      '⑤',
      '⑥',
      '⑦',
      '⑧',
      '⑨',
      '⑩',
      '⑪',
      '⑫',
      '⑬',
      '⑭',
      '⑮',
      '⑯',
      '⑰',
      '⑱',
      '⑲',
      '⑳',
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
                'No genders available',
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
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select one gender',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
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
        ],
      ),
    );
  }

  // ============================================
  // AGE TYPING FORM
  // ✅ FIX: Removed addListener inside fieldViewBuilder (memory leak)
  // ============================================
  Widget _buildAgeTypingForm() {
    final isDark = _isDark;

    // The "new age category" form is hidden when categories already exist
    // (tap "Add New"); it opens by itself when there are none.
    final showNewForm = _addAgeCategoryFormExpanded || _ageCategories.isEmpty;

    InputDecoration ageNumberDecoration(String label, String? error) {
      return InputDecoration(
        labelText: label,
        counterText: '',
        errorText: error,
        errorMaxLines: 2,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _ageCategories.isEmpty
                    ? 'No age categories yet — add one below.'
                    : 'Tap to select',
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: _ageCategories.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
              ),
            ),
            if (_ageCategories.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() {
                  _addAgeCategoryFormExpanded = !_addAgeCategoryFormExpanded;
                  _ageNameError = null;
                  _ageMinError = null;
                  _ageMaxError = null;
                }),
                icon: Icon(
                  _addAgeCategoryFormExpanded
                      ? Icons.close
                      : Icons.add_circle_outline,
                  size: 14,
                  color: Colors.green,
                ),
                label: Text(
                  _addAgeCategoryFormExpanded ? 'Cancel' : 'Add New',
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        if (_ageCategories.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ageCategories.map((a) {
              final id = a['id'] as int;
              final isSelected = _selectedAgeCategoryId == id;
              return FilterChip(
                label: Text(
                  _getAgeCategoryDisplayName(a),
                  style: TextStyle(
                    color: isSelected
                        ? Colors.green
                        : (isDark ? Colors.white70 : Colors.grey[700]),
                  ),
                ),
                selected: isSelected,
                onSelected: (v) =>
                    setState(() => _selectedAgeCategoryId = v ? id : null),
                backgroundColor: isDark
                    ? const Color(0xFF2A2A2A)
                    : Colors.grey[100],
                selectedColor: Colors.green.withValues(alpha: 0.2),
                checkmarkColor: Colors.green,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: isSelected
                        ? Colors.green
                        : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        if (showNewForm) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2A2A2A)
                  : Colors.green.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                _buildAgeNameSuggestionField(),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ageMinController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: ageNumberDecoration('Min', _ageMinError),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _ageMaxController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: ageNumberDecoration('Max', _ageMaxError),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAddingAgeCategory
                        ? null
                        : _addAgeCategoryDirect,
                    icon: _isAddingAgeCategory
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 14),
                    label: const Text(
                      'Save Age Category',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// ✅ FIX: Removed addListener inside fieldViewBuilder (memory leak)
  Widget _buildAgeNameSuggestionField() {
    final isDark = _isDark;

    final suggestions = _globalAgeCategories
        .map((a) => a['display_name'] as String)
        .toList();

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
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        // ✅ Sync one-time (no listener accumulation)
        if (textController.text != _ageDisplayNameController.text) {
          textController.text = _ageDisplayNameController.text;
        }

        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          inputFormatters: _textFormatters(_maxAgeName),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            counterText: '',
            labelText: 'Age Category Name *',
            hintText: 'e.g., Adult, Child, Senior',
            prefixIcon: Icon(
              Icons.visibility,
              size: 18,
              color: isDark ? Colors.white70 : Colors.grey,
            ),
            suffixIcon: suggestions.isNotEmpty
                ? Icon(
                    Icons.arrow_drop_down,
                    color: isDark ? Colors.white70 : Colors.grey,
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
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

  /// Header for a section that is always visible (no arrow): number, title,
  /// optional red * and a one-line hint.
  Widget _buildStaticSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
    required String subtitle,
    bool isRequired = false,
  }) {
    final isDark = _isDark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (isRequired)
                      Text(
                        ' *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[300],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _variantInputDecoration({
    String? hint,
    String? suffix,
    Widget? prefixIcon,
    String? errorText,
  }) {
    final isDark = _isDark;
    return InputDecoration(
      hintText: hint,
      suffixText: suffix,
      prefixIcon: prefixIcon,
      counterText: '',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: errorText != null
              ? Colors.red
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  /// Duration: two number inputs (hours + minutes). Saved as total minutes.
  Widget _buildDurationField() {
    final isDark = _isDark;
    final total = _parsedDuration;

    Widget input(TextEditingController c, String hint, String suffix) {
      return TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: _variantInputDecoration(
          hint: hint,
          suffix: suffix,
          errorText: _durationError,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: input(_variantHoursController, '0', 'hrs')),
            const SizedBox(width: 10),
            Expanded(child: input(_variantMinutesController, '30', 'mins')),
          ],
        ),
        if (_durationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _durationError!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          )
        else if (total != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Total: ${_formatDuration(total)}',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }

  /// Optional variant name (required when no gender and no age).
  Widget _buildVariantNameField() {
    final isDark = _isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _variantNameController,
          maxLength: _maxVariantName,
          inputFormatters: _textFormatters(_maxVariantName),
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration:
              _variantInputDecoration(
                hint: 'e.g., Short hair',
                errorText: _variantNameError,
                prefixIcon: Icon(
                  Icons.label_outline,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
              ).copyWith(
                errorText: _variantNameError,
                errorMaxLines: 2,
              ),
        ),
      ],
    );
  }

  Widget _buildPriceField() {
    final isDark = _isDark;
    return TextFormField(
      controller: _variantPriceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: _priceFormatters,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: _salonPriceHint,
        prefixIcon: CurrencyPrefix(
          symbol: _salonCurrencySymbol,
          type: CurrencyDisplayType.text,
          color: isDark ? Colors.white70 : Colors.grey,
          fontSize: 16,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 50,
          minHeight: 20,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
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
                  color: Colors.white,
                  strokeWidth: 2,
                ),
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
                    widget.isEditing ? 'Update Service' : 'Save All Services',
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