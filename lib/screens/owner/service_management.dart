// servite list <--menue eka
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/owner/add_services.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/services/currency_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceManagementScreen extends StatefulWidget {
  final int salonId;
  final String salonName;

  const ServiceManagementScreen({
    super.key,
    required this.salonId,
    required this.salonName,
  });

  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  // Search and filter
  String _searchQuery = '';
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];

  // Gender and age categories for variant form
  List<Map<String, dynamic>> _genders = [];
  List<Map<String, dynamic>> _ageCategories = [];
  // Suggestions for the age-name field (global list, optional)
  List<Map<String, dynamic>> _globalAgeCategories = [];
  List<String> get _globalAgeNames => _globalAgeCategories
      .map((a) => (a['display_name'] ?? '').toString())
      .where((n) => n.isNotEmpty)
      .toList();

  // Currency Service (singleton)
  final CurrencyService _currencyService = CurrencyService.instance;

  // Empty initial - DB එකෙන් load වෙනකම් effective getter use කරනවා
  String _salonCurrencyCode = '';

  // Effective currency code getter - DB load fail නම් fallback
  String get _effectiveCurrencyCode {
    if (_salonCurrencyCode.isNotEmpty) return _salonCurrencyCode;
    return 'LKR'; // Last resort only
  }

  // Currency getters
  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_effectiveCurrencyCode);

  String get _salonPriceHint =>
      _currencyService.getHint(_effectiveCurrencyCode);

  bool get _currencyUsesDecimals =>
      _currencyService.getInfo(_effectiveCurrencyCode).decimals > 0;

  // For expansion state - track expanded services
  final Set<int> _expandedServices = {};

  // Alternating card colors
  final List<Color> _cardColors = [
    const Color(0xFFE3F2FD),
    const Color(0xFFFCE4EC),
    const Color(0xFFE8F5E9),
    const Color(0xFFFFF3E0),
    const Color(0xFFF3E5F5),
    const Color(0xFFE0F7FA),
    const Color(0xFFFFEBEE),
    const Color(0xFFE8EAF6),
  ];

  final ScrollController _scrollController = ScrollController();

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================
  // ✅ SAFE PARSERS (num / String / null – web & mobile දෙකටම)
  // ============================================

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? fallback;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? fallback;
  }

  // ============================================
  // ✅ TEXT LIMITS + SANITISING (same limits are enforced again in the DB)
  // ============================================
  static const int _maxServiceName = 60;
  static const int _maxVariantName = 50;
  static const int _maxAgeName = 30;
  static const int _maxDescription = 200;

  // Invisible / control characters: C0 controls, DEL, zero-width chars,
  // bidi overrides (used to spoof text) and the BOM.
  static final RegExp _badCharsSingleLine = RegExp(
      r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');
  // Same, but a description may keep line breaks (\n = \u000A).
  static final RegExp _badCharsMultiLine = RegExp(
      r'[\u0000-\u0009\u000B-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

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

  /// Price input: digits (+ one decimal point when the currency uses decimals).
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

  // ============================================
  // ✅ VARIANT DISPLAY HELPERS (nothing is shown for values that are not set)
  // ============================================

  /// 45 → "45 min", 60 → "1 hr", 90 → "1 hr 30 min", 120 → "2 hrs".
  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    final hText = h == 1 ? '1 hr' : '$h hrs';
    return m == 0 ? hText : '$hText $m min';
  }

  /// "Adult (18-60 yrs)" – the age name with its range when both are set.
  String _ageDisplayName(Map<String, dynamic> ageCat) {
    String name = (ageCat['display_name'] ?? 'Unknown').toString();
    if (ageCat['min_age'] != null && ageCat['max_age'] != null) {
      name = '$name (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
    }
    return name;
  }

  /// "500" instead of "500.0" when a stored price is put back in a text field.
  String _plainPrice(double p) =>
      p == p.truncateToDouble() ? p.toInt().toString() : p.toString();

  /// Gender / age / duration parts that are actually set.
  List<String> _variantDetailParts(Map<String, dynamic> v) {
    final parts = <String>[];
    final gender = (v['gender_name'] ?? '').toString().trim();
    final age = (v['age_name'] ?? '').toString().trim();
    final duration = _toInt(v['duration']);
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

  /// Price text, or null when no price has been set (so nothing is shown).
  String? _variantPriceText(Map<String, dynamic> v) {
    if (v['price_set'] != true) return null;
    final price = _toDouble(v['price']);
    if (price == 0) return 'Free';
    return _formatPrice(price);
  }

  /// Second line of a variant row (long names wrap, so the details and the
  /// price always sit on their own line and stay visible on small screens).
  String _variantSecondLine(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    final parts = <String>[
      if (vName.isNotEmpty) ..._variantDetailParts(v),
      if (_variantPriceText(v) != null) _variantPriceText(v)!,
    ];
    return parts.join(' • ');
  }

  /// Readable summary used in confirmation messages.
  String _variantLabel(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    final parts = <String>[
      if (vName.isNotEmpty) vName,
      ..._variantDetailParts(v),
    ];
    return parts.isEmpty ? 'Standard' : parts.join(' • ');
  }

  /// The title + second line used in every variant row (web and mobile).
  Widget _buildVariantTexts(
    Map<String, dynamic> variant,
    bool isDark, {
    double titleSize = 13,
    double subSize = 12,
  }) {
    final second = _variantSecondLine(variant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _variantTitle(variant),
          softWrap: true,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: titleSize,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        if (second.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            second,
            softWrap: true,
            style: TextStyle(
              fontSize: subSize,
              color: isDark ? Colors.white60 : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  // ============================================
  // ✅ FRIENDLY ERRORS (raw database errors are never shown to the user)
  // ============================================
  String _friendlyError(
    Object e, {
    String? duplicateMessage,
    String? linkedMessage,
  }) {
    if (e is PostgrestException) {
      switch (e.code) {
        case '23505':
          return duplicateMessage ??
              'This item already exists. Please change it and try again.';
        case '23503':
          return linkedMessage ??
              "This item is linked to other records (like bookings), so it can't be changed right now.";
        case '23514':
        case '22001':
        case '22003':
          return 'Some values are not allowed. Please check the text length and the numbers, then try again.';
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

  static const String _variantDuplicateMessage =
      'This service already has a variant with the same name, gender, age category and duration. Change one of them, or edit the existing variant instead.';

  bool _isDuplicateVariant(
    List variants, {
    required int? gender,
    required int? age,
    required int duration,
    String name = '',
    dynamic ignoreId,
  }) {
    final n = name.trim().toLowerCase();
    for (final v in variants) {
      if (ignoreId != null && v['id'] == ignoreId) continue;
      if (v['gender_id'] == gender &&
          v['age_category_id'] == age &&
          (v['name'] ?? '').toString().trim().toLowerCase() == n &&
          _toInt(v['duration']) == duration) {
        return true;
      }
    }
    return false;
  }

  // ============================================
  // ✅ SUGGESTION TEXT FIELD
  // Shows suggestions while typing. Typing never changes other fields.
  // ============================================
  Widget _suggestField({
    Key? fieldKey,
    required TextEditingController controller,
    required List<String> suggestions,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    String? errorText,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onPicked,
    int maxLength = 60,
  }) {
    return Autocomplete<String>(
      key: fieldKey,
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (TextEditingValue v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return suggestions.where((o) {
          final l = o.toLowerCase();
          return l.contains(q);
        });
      },
      onSelected: (String s) {
        controller.text = s;
        onChanged?.call(s);
        onPicked?.call(s);
      },
      fieldViewBuilder: (context, tc, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: tc,
          focusNode: focusNode,
          inputFormatters: _textFormatters(maxLength),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          onChanged: (v) {
            controller.text = v;
            onChanged?.call(v);
          },
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterText: '',
            errorText: errorText,
            errorMaxLines: 2,
            prefixIcon: Icon(
              icon,
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
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // ✅ CURRENCY HELPERS
  // ============================================

  String _formatPrice(dynamic price) {
    return _currencyService.format(
      price: price,
      currencyCode: _effectiveCurrencyCode,
    );
  }

  /// Price is optional (empty = not set). When typed it must be a valid,
  /// non-negative number; 0 is allowed and shows as "Free".
  String? _validatePriceForCurrency(String priceText) {
    if (priceText.isEmpty) return null;

    final price = double.tryParse(priceText);
    if (price == null) return 'Enter a valid price';
    if (price < 0) return 'Price cannot be negative';

    if (!_currencyUsesDecimals && priceText.contains('.')) {
      final decimalPart = priceText.split('.').last;
      if (decimalPart.isNotEmpty && int.tryParse(decimalPart) != 0) {
        return '$_effectiveCurrencyCode does not use decimals';
      }
    }

    return null;
  }

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
          setState(() {
            _salonCurrencyCode = currency;
          });
          debugPrint('✅ Salon currency loaded: $_salonCurrencyCode');
        }
      }
    } catch (e) {
      debugPrint('Error loading salon currency: $e');
    }
  }

  // ============================================
  // ✅ ACCESS: owner, or employee with 'manage_services'
  // ============================================
  Future<bool> _canManageServices(String userId) async {
    final salon = await supabase
        .from('salons')
        .select('owner_id')
        .eq('id', widget.salonId)
        .maybeSingle();

    if (salon != null && salon['owner_id'] == userId) {
      final r = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', userId)
          .eq('role_id', 3)
          .maybeSingle();
      return r != null && r['status'] == 'active';
    }

    // employee: permission is decided by the server (role + owner's plan)
    try {
      final res = await supabase.rpc('get_my_staff_access');
      for (final s in (res as List)) {
        if ((s['salon_id'] as num).toInt() == widget.salonId &&
            (s['permissions'] as List).contains('manage_services')) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error checking staff access: $e');
    }
    return false;
  }

  // ============================================
  // DATA LOADING
  // ============================================

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          _showSnackBar('Please login to manage services', Colors.orange);
          setState(() => _isLoading = false);
        }
        return;
      }

      // ✅ STEP 1: Check if profile is active and not blocked
      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          if (mounted) {
            _showSnackBar(
              'Your account has been blocked. Please contact support.',
              Colors.red,
            );
            setState(() => _isLoading = false);
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          if (mounted) {
            _showSnackBar(
              'Your profile is inactive. Please contact support.',
              Colors.red,
            );
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      // ✅ STEP 2: salon OWNER (active owner role) or an employee with the
      //            'manage_services' permission (admin, Silver+ plan)
      final allowed = await _canManageServices(user.id);
      if (!allowed) {
        if (mounted) {
          _showSnackBar(
            'You do not have permission to manage services in this salon.',
            Colors.red,
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // ✅ STEP 3: Load salon currency
      await _loadSalonCurrency();

      // Load categories
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Load genders for variant form
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Load age categories for variant form
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Global age-name suggestions (optional – ignored if the table is missing)
      List<Map<String, dynamic>> globalAgeCategories = [];
      try {
        final g = await supabase
            .from('age_categories')
            .select('display_name, min_age, max_age')
            .eq('is_active', true);
        globalAgeCategories = List<Map<String, dynamic>>.from(g);
      } catch (e) {
        debugPrint('Could not load global age categories: $e');
      }

      if (!mounted) return;

      setState(() {
        _globalAgeCategories = globalAgeCategories;
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _genders = List<Map<String, dynamic>>.from(gendersResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
      });

      await _loadServices();
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        _showSnackBar(_friendlyError(e), Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServices() async {
    if (!mounted) return;

    try {
      final servicesResponse = await supabase
          .from('services')
          .select('''
            id,
            name,
            description,
            icon_name,
            category_id,
            is_active,
            created_at,
            updated_at
          ''')
          .eq('salon_id', widget.salonId)
          .order('name');

      final services = List<Map<String, dynamic>>.from(servicesResponse);

      if (services.isEmpty) {
        if (!mounted) return;
        setState(() {
          _services = [];
          _expandedServices.clear();
        });
        return;
      }

      final serviceIds = services.map<int>((s) => s['id'] as int).toList();

      final variantsResponse = await supabase
          .from('service_variants')
          .select('''
            id,
            service_id,
            name,
            price,
            duration,
            is_active,
            salon_gender_id,
            salon_age_category_id
          ''')
          .inFilter('service_id', serviceIds)
          .eq('is_active', true);

      final allVariants = List<Map<String, dynamic>>.from(variantsResponse);

      final genderIdToName = <int, String>{};
      for (var g in _genders) {
        genderIdToName[g['id'] as int] = g['display_name'] as String;
      }

      final ageIdToInfo = <int, Map<String, dynamic>>{};
      for (var a in _ageCategories) {
        ageIdToInfo[a['id'] as int] = a;
      }

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var v in allVariants) {
        final sid = v['service_id'] as int;
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        // Only real values are kept; nothing is shown for "not set".
        final genderName =
            genderId != null ? (genderIdToName[genderId] ?? '') : '';
        var ageName = '';
        if (ageId != null && ageIdToInfo.containsKey(ageId)) {
          ageName = _ageDisplayName(ageIdToInfo[ageId]!);
        }

        // price can be NULL (= not set yet); 0 means "Free"
        final rawPrice = v['price'];
        final priceNum = rawPrice == null ? null : _toDouble(rawPrice);

        variantsByService.putIfAbsent(sid, () => []).add({
          'id': v['id'],
          'name': (v['name'] ?? '').toString().trim(),
          'gender_name': genderName,
          'age_name': ageName,
          // ✅ always store as proper numbers (web may return String)
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': _toInt(v['duration']),
          'is_active': v['is_active'],
          'gender_id': genderId,
          'age_category_id': ageId,
        });
      }

      for (var service in services) {
        final sid = service['id'] as int;
        final serviceVariants = variantsByService[sid] ?? [];

        service['variants'] = serviceVariants;
        service['variant_count'] = serviceVariants.length;
        service['has_variants'] = serviceVariants.isNotEmpty;

        final category = _categories.firstWhere(
          (c) => c['id'] == service['category_id'],
          orElse: () => {'display_name': 'Uncategorized'},
        );
        service['category_name'] = category['display_name'];
      }

      if (!mounted) return;
      setState(() {
        _services = services;

        _expandedServices.clear();
        for (var service in services) {
          if (service['has_variants'] == true) {
            _expandedServices.add(service['id'] as int);
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading services: $e');
      rethrow;
    }
  }

  void _toggleExpand(int serviceId) {
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
      }
    });
  }

  // ============================================
  // ✅ ADD / EDIT VARIANT DIALOG (one dialog, numbered sections)
  //   1 Gender (optional)   2 Age category (optional)   3 Price (optional)
  //   4 Duration (required, hours + minutes → stored as total minutes)
  //   5 Variant name (optional; required when no gender and no age is set)
  // ============================================
  Future<void> _showAddVariantDialog(Map<String, dynamic> service) =>
      _showVariantDialog(service);

  Future<void> _showEditVariantDialog(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) => _showVariantDialog(service, variant: variant);

  Future<void> _showVariantDialog(
    Map<String, dynamic> service, {
    Map<String, dynamic>? variant,
  }) async {
    final bool isEdit = variant != null;

    int? selectedGenderId = variant?['gender_id'] as int?;
    int? selectedAgeId = variant?['age_category_id'] as int?;

    final priceController = TextEditingController(
      text: isEdit && variant['price_set'] == true
          ? _plainPrice(_toDouble(variant['price']))
          : '',
    );

    // Duration is typed as hours + minutes and stored as total minutes.
    final existingTotal = isEdit ? _toInt(variant['duration']) : 0;
    final hoursController = TextEditingController(
      text: existingTotal >= 60 ? (existingTotal ~/ 60).toString() : '',
    );
    final minutesController = TextEditingController(
      text: existingTotal > 0 && existingTotal % 60 > 0
          ? (existingTotal % 60).toString()
          : '',
    );
    final nameController = TextEditingController(
      text: (variant?['name'] ?? '').toString(),
    );

    // Temporary new age category fields
    final newAgeNameController = TextEditingController();
    final newAgeMinController = TextEditingController(text: '0');
    final newAgeMaxController = TextEditingController(text: '100');
    bool showNewAgeForm = false;
    bool isSavingAge = false;
    int ageFormResetCounter = 0; // rebuilds the suggestion field after clear

    String? nameError;
    String? variantError;
    String? durationError;
    String? priceError;
    String? ageNameError;
    String? ageMinError;
    String? ageMaxError;
    bool isSaving = false;

    // Optional sections stay hidden until opened with the arrow. Edit mode
    // opens a section automatically when the variant already has a value.
    bool genderOpen = selectedGenderId != null;
    bool ageOpen = selectedAgeId != null;
    bool priceOpen = isEdit && variant['price_set'] == true;

    final isDark = context.isDarkMode;

    // ── Duration helpers (hours + minutes → total minutes) ──
    String? validateDuration(String hText, String mText) {
      final h = hText.trim(), m = mText.trim();
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
    int? parseDuration(String hText, String mText) {
      if (validateDuration(hText, mText) != null) return null;
      final h = hText.trim().isEmpty ? 0 : int.parse(hText.trim());
      final m = mText.trim().isEmpty ? 0 : int.parse(mText.trim());
      return h * 60 + m;
    }

    InputDecoration fieldDecoration({
      String? hint,
      String? suffix,
      Widget? prefix,
      String? errorText,
      bool redBorder = false,
    }) {
      return InputDecoration(
        hintText: hint,
        suffixText: suffix,
        counterText: '',
        errorText: errorText,
        errorMaxLines: 2,
        prefixIcon: prefix,
        prefixIconConstraints: prefix is Padding
            ? const BoxConstraints(minWidth: 50, minHeight: 20)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: redBorder
                ? Colors.red
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      );
    }

    Widget durationInput({
      required TextEditingController controller,
      required String hint,
      required String suffix,
      required void Function(VoidCallback) setDialogState,
      IconData? icon,
    }) {
      return TextFormField(
        controller: controller,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        keyboardType: TextInputType.number,
        onChanged: (_) {
          setDialogState(() {
            variantError = null;
            // Show a message while typing, but stay quiet while both empty
            durationError =
                hoursController.text.trim().isEmpty &&
                    minutesController.text.trim().isEmpty
                ? null
                : validateDuration(hoursController.text, minutesController.text);
          });
        },
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: fieldDecoration(
          hint: hint,
          suffix: suffix,
          redBorder: durationError != null,
          prefix: icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.grey,
                )
              : null,
        ),
      );
    }

    // Numbered section header. [open] == null → not collapsible (always shown).
    Widget sectionHeader({
      required int number,
      required String title,
      required String summary,
      required Color color,
      bool? open,
      VoidCallback? onTap,
      bool isRequired = false,
      Widget? trailing,
    }) {
      final content = Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (isRequired)
                      Text(
                        ' *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[300],
                        ),
                      ),
                  ],
                ),
                if (summary.isNotEmpty)
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (open != null)
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 22,
                color: isDark ? Colors.white70 : Colors.grey[600],
              ),
            ),
        ],
      );

      if (open == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        );
      }
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: content,
        ),
      );
    }

    Widget sectionDivider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(
        height: 1,
        color: isDark ? Colors.grey[800] : Colors.grey[200],
      ),
    );

    // Validates the "new age category" mini form. Shows errors under the
    // fields and returns true only when everything is valid.
    bool validateAge(void Function(VoidCallback) set) {
      final name = _cleanText(newAgeNameController.text, _maxAgeName);
      final min = int.tryParse(newAgeMinController.text.trim());
      final max = int.tryParse(newAgeMaxController.text.trim());

      String? nameErr;
      String? minErr;
      String? maxErr;

      if (name.isEmpty) {
        nameErr = 'Name is required';
      } else if (_ageCategories.any(
        (a) =>
            a['display_name'].toString().toLowerCase() == name.toLowerCase(),
      )) {
        nameErr = 'This age category already exists';
      }

      if (min == null) {
        minErr = 'Numbers only';
      } else if (min < 0 || min > 150) {
        minErr = 'Age must be 0-150';
      }

      if (max == null) {
        maxErr = 'Numbers only';
      } else if (max < 0 || max > 150) {
        maxErr = 'Age must be 0-150';
      } else if (min != null && max < min) {
        maxErr = 'Max must be >= min';
      }

      set(() {
        ageNameError = nameErr;
        ageMinError = minErr;
        ageMaxError = maxErr;
      });

      return nameErr == null && minErr == null && maxErr == null;
    }

    Widget ageNumberField(
      TextEditingController c,
      String label,
      String? err,
      void Function(VoidCallback) set,
      VoidCallback clearErr,
    ) {
      return TextFormField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 3,
        onChanged: (_) => set(clearErr),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          errorText: err,
          errorMaxLines: 2,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        ),
      );
    }

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final noGenderNoAge =
                selectedGenderId == null && selectedAgeId == null;

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.all(20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getIconForName(service['icon_name']),
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Edit Variant' : 'Add New Variant',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'For "${service['name']}"',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Gender (optional, hidden until expanded)
                    sectionHeader(
                      number: 1,
                      title: 'Gender',
                      color: Colors.blue,
                      open: genderOpen,
                      summary: selectedGenderId != null
                          ? (_genders
                                    .firstWhere(
                                      (g) => g['id'] == selectedGenderId,
                                      orElse: () => {'display_name': 'Selected'},
                                    )['display_name']
                                    ?.toString() ??
                                'Selected')
                          : 'Optional — tap the arrow to choose',
                      onTap: () =>
                          setDialogState(() => genderOpen = !genderOpen),
                    ),
                    if (genderOpen) ...[
                      const SizedBox(height: 6),
                      if (_genders.isEmpty)
                        Text(
                          'No genders available for this salon.',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.white38 : Colors.grey[500],
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _genders.map((g) {
                          final id = g['id'] as int;
                          final isSelected = selectedGenderId == id;
                          return FilterChip(
                            label: Text(
                              g['display_name'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.blue
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.grey[700]),
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (v) => setDialogState(() {
                              selectedGenderId = v ? id : null;
                              variantError = null;
                              nameError = null;
                            }),
                            backgroundColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey[100],
                            selectedColor: Colors.blue.withValues(alpha: 0.2),
                            checkmarkColor: Colors.blue,
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.blue
                                    : (isDark
                                          ? Colors.grey[700]!
                                          : Colors.grey[300]!),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    sectionDivider(),

                    // 2. Age Category (optional, hidden until expanded)
                    sectionHeader(
                      number: 2,
                      title: 'Age Category',
                      color: Colors.green,
                      open: ageOpen,
                      summary: selectedAgeId != null
                          ? _ageDisplayName(
                              _ageCategories.firstWhere(
                                (a) => a['id'] == selectedAgeId,
                                orElse: () => {'display_name': 'Selected'},
                              ),
                            )
                          : 'Optional — tap the arrow to choose',
                      onTap: () => setDialogState(() => ageOpen = !ageOpen),
                      trailing: (ageOpen && _ageCategories.isNotEmpty)
                          ? TextButton.icon(
                              onPressed: () => setDialogState(() {
                                showNewAgeForm = !showNewAgeForm;
                                ageNameError = null;
                                ageMinError = null;
                                ageMaxError = null;
                              }),
                              icon: Icon(
                                showNewAgeForm
                                    ? Icons.close
                                    : Icons.add_circle_outline,
                                size: 14,
                                color: Colors.green,
                              ),
                              label: Text(
                                showNewAgeForm ? 'Cancel' : 'Add New',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                minimumSize: Size.zero,
                              ),
                            )
                          : null,
                    ),
                    if (ageOpen) ...[
                      if (_ageCategories.isEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'No age categories yet — add one below.',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.white38 : Colors.grey[500],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      if (_ageCategories.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _ageCategories.map((a) {
                            final id = a['id'] as int;
                            final isSelected = selectedAgeId == id;
                            return FilterChip(
                              label: Text(
                                _ageDisplayName(a),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.green
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.grey[700]),
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (v) => setDialogState(() {
                                selectedAgeId = v ? id : null;
                                variantError = null;
                                nameError = null;
                              }),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[100],
                              selectedColor: Colors.green.withValues(
                                alpha: 0.2,
                              ),
                              checkmarkColor: Colors.green,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: isSelected
                                      ? Colors.green
                                      : (isDark
                                            ? Colors.grey[700]!
                                            : Colors.grey[300]!),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (showNewAgeForm || _ageCategories.isEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.green.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              _suggestField(
                                fieldKey: ValueKey(
                                  'age_name_$ageFormResetCounter',
                                ),
                                controller: newAgeNameController,
                                suggestions: _globalAgeNames,
                                label: 'Age Name *',
                                maxLength: _maxAgeName,
                                hint: 'e.g., Adult',
                                icon: Icons.visibility,
                                isDark: isDark,
                                errorText: ageNameError,
                                onChanged: (_) =>
                                    setDialogState(() => ageNameError = null),
                                // Picking a suggestion fills min and max age
                                onPicked: (picked) {
                                  final key = picked.trim().toLowerCase();
                                  for (final a in _globalAgeCategories) {
                                    if ((a['display_name'] ?? '')
                                            .toString()
                                            .trim()
                                            .toLowerCase() ==
                                        key) {
                                      setDialogState(() {
                                        newAgeMinController.text =
                                            (a['min_age'] ?? 0).toString();
                                        newAgeMaxController.text =
                                            (a['max_age'] ?? 100).toString();
                                        ageNameError = null;
                                        ageMinError = null;
                                        ageMaxError = null;
                                      });
                                      break;
                                    }
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ageNumberField(
                                      newAgeMinController,
                                      'Min',
                                      ageMinError,
                                      setDialogState,
                                      () => ageMinError = null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ageNumberField(
                                      newAgeMaxController,
                                      'Max',
                                      ageMaxError,
                                      setDialogState,
                                      () => ageMaxError = null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: isSavingAge
                                      ? null
                                      : () async {
                                          if (!validateAge(setDialogState)) {
                                            return;
                                          }
                                          final name = _cleanText(
                                            newAgeNameController.text,
                                            _maxAgeName,
                                          );
                                          final min = int.parse(
                                            newAgeMinController.text.trim(),
                                          );
                                          final max = int.parse(
                                            newAgeMaxController.text.trim(),
                                          );

                                          setDialogState(
                                            () => isSavingAge = true,
                                          );
                                          try {
                                            final inserted = await supabase
                                                .from('salon_age_categories')
                                                .insert({
                                                  'salon_id': widget.salonId,
                                                  'display_name': name,
                                                  'min_age': min,
                                                  'max_age': max,
                                                  'display_order':
                                                      _ageCategories.length,
                                                  'is_active': true,
                                                })
                                                .select()
                                                .single();

                                            if (!mounted) return;
                                            if (!dialogContext.mounted) return;

                                            setState(() {
                                              _ageCategories.add(
                                                Map<String, dynamic>.from(
                                                  inserted,
                                                ),
                                              );
                                            });
                                            setDialogState(() {
                                              selectedAgeId =
                                                  inserted['id'] as int;
                                              newAgeNameController.clear();
                                              newAgeMinController.text = '0';
                                              newAgeMaxController.text = '100';
                                              ageFormResetCounter++;
                                              ageNameError = null;
                                              ageMinError = null;
                                              ageMaxError = null;
                                              showNewAgeForm = false;
                                              isSavingAge = false;
                                              nameError = null;
                                            });
                                          } catch (e) {
                                            debugPrint('Error adding age: $e');
                                            if (dialogContext.mounted) {
                                              setDialogState(() {
                                                isSavingAge = false;
                                                ageNameError = _friendlyError(
                                                  e,
                                                  duplicateMessage:
                                                      'This age category already exists',
                                                );
                                              });
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.save, size: 14),
                                  label: const Text(
                                    'Save Age Category',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
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
                      ],
                    ],
                    sectionDivider(),

                    // 3. Price (optional, hidden until expanded)
                    sectionHeader(
                      number: 3,
                      title: 'Price',
                      color: Colors.teal,
                      open: priceOpen,
                      summary: priceController.text.trim().isNotEmpty
                          ? '$_salonCurrencySymbol ${priceController.text.trim()}'
                          : 'Optional — tap the arrow to set',
                      onTap: () =>
                          setDialogState(() => priceOpen = !priceOpen),
                    ),
                    if (priceOpen) ...[
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: priceController,
                        inputFormatters: _priceFormatters,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (v) {
                          setDialogState(() {
                            variantError = null;
                            priceError = _validatePriceForCurrency(v.trim());
                          });
                        },
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: fieldDecoration(
                          hint: _salonPriceHint,
                          errorText: priceError,
                          prefix: Padding(
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Leave empty to set the price later. 0 shows as "Free".',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                    ],
                    sectionDivider(),

                    // 4. Duration (always shown, required)
                    sectionHeader(
                      number: 4,
                      title: 'Duration',
                      color: Colors.orange,
                      isRequired: true,
                      summary: 'Required — hours and minutes',
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: durationInput(
                            controller: hoursController,
                            hint: '0',
                            suffix: 'hrs',
                            icon: Icons.timer,
                            setDialogState: setDialogState,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: durationInput(
                            controller: minutesController,
                            hint: '30',
                            suffix: 'mins',
                            setDialogState: setDialogState,
                          ),
                        ),
                      ],
                    ),
                    if (durationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          durationError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      )
                    else if (parseDuration(
                          hoursController.text,
                          minutesController.text,
                        ) !=
                        null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          'Total: ${_formatDuration(parseDuration(hoursController.text, minutesController.text)!)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                        ),
                      ),
                    sectionDivider(),

                    // 5. Variant name (optional; required when only the
                    // duration is set — no gender and no age)
                    sectionHeader(
                      number: 5,
                      title: 'Variant name',
                      color: Colors.indigo,
                      isRequired: noGenderNoAge,
                      summary: noGenderNoAge
                          ? 'Required — no gender or age is set'
                          : 'Optional — e.g., Short hair, Long hair',
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: nameController,
                      maxLength: _maxVariantName,
                      inputFormatters: _textFormatters(_maxVariantName),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setDialogState(() {
                        variantError = null;
                        nameError = null;
                      }),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: fieldDecoration(
                        hint: 'e.g., Short hair',
                        errorText: nameError,
                        prefix: Icon(
                          Icons.label_outline,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ),

                    if (variantError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                variantError!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final priceText = priceController.text.trim();

                          // Price is optional, but when typed it must be valid.
                          final priceErr = _validatePriceForCurrency(priceText);
                          if (priceErr != null) {
                            setDialogState(() {
                              priceOpen = true;
                              priceError = priceErr;
                            });
                            return;
                          }

                          // Duration is the only required number.
                          final durErr = validateDuration(
                            hoursController.text,
                            minutesController.text,
                          );
                          if (durErr != null) {
                            setDialogState(() => durationError = durErr);
                            return;
                          }
                          // Stored as total minutes (all calculations use minutes)
                          final duration = parseDuration(
                            hoursController.text,
                            minutesController.text,
                          )!;

                          // Name is optional, but mandatory when only the
                          // duration is set (no gender and no age).
                          final variantName = _cleanText(
                            nameController.text,
                            _maxVariantName,
                          );
                          if (variantName.isEmpty &&
                              selectedGenderId == null &&
                              selectedAgeId == null) {
                            setDialogState(() {
                              nameError =
                                  'Name is required when only duration is set (no gender or age)';
                            });
                            return;
                          }

                          final priceSet = priceText.isNotEmpty;
                          final price = priceSet
                              ? double.tryParse(priceText)
                              : null;

                          // Block duplicates before they reach the database.
                          if (_isDuplicateVariant(
                            service['variants'] as List,
                            gender: selectedGenderId,
                            age: selectedAgeId,
                            duration: duration,
                            name: variantName,
                            ignoreId: variant?['id'],
                          )) {
                            setDialogState(
                              () => variantError = _variantDuplicateMessage,
                            );
                            return;
                          }

                          if (!mounted) return;
                          setDialogState(() {
                            isSaving = true;
                            variantError = null;
                          });
                          setState(() => _isProcessing = true);

                          try {
                            final payload = <String, dynamic>{
                              'salon_gender_id': selectedGenderId,
                              'salon_age_category_id': selectedAgeId,
                              'name': variantName.isEmpty ? null : variantName,
                              'price': price,
                              'duration': duration,
                            };

                            if (isEdit) {
                              await supabase
                                  .from('service_variants')
                                  .update({
                                    ...payload,
                                    'updated_at': DateTime.now()
                                        .toIso8601String(),
                                  })
                                  .eq('id', variant['id']);
                            } else {
                              await supabase.from('service_variants').insert({
                                ...payload,
                                'service_id': service['id'],
                                'is_active': true,
                              });
                            }

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            await _loadServices();

                            if (mounted) {
                              _showSnackBar(
                                isEdit
                                    ? 'Variant updated successfully!'
                                    : 'Variant added successfully!',
                                Colors.green,
                              );
                            }
                          } catch (e) {
                            debugPrint('Error saving variant: $e');
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                                variantError = _friendlyError(
                                  e,
                                  duplicateMessage: _variantDuplicateMessage,
                                );
                              });
                            }
                          } finally {
                            if (mounted) setState(() => _isProcessing = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isEdit ? 'Save Changes' : 'Add Variant',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      // ✅ Dispose controllers after dialog closes
      priceController.dispose();
      hoursController.dispose();
      minutesController.dispose();
      nameController.dispose();
      newAgeNameController.dispose();
      newAgeMinController.dispose();
      newAgeMaxController.dispose();
    }
  }

  // ============================================
  // ✅ DELETE VARIANT
  // ============================================
  Future<void> _deleteVariant(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
  ) async {
    if (!mounted) return;

    final isDark = context.isDarkMode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: null,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Delete Variant',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "Are you sure you want to delete this variant?",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Service: ${service['name']}',
                      softWrap: true,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _variantLabel(variant),
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                    if (_variantPriceText(variant) != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _variantPriceText(variant)!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone!',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.red[300] : Colors.red,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style:
                  TextStyle(color: isDark ? Colors.white60 : Colors.black87),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);

      try {
        await supabase
            .from('service_variants')
            .delete()
            .eq('id', variant['id']);

        await _loadServices();

        if (mounted) {
          _showSnackBar('Variant deleted successfully', Colors.green);
        }
      } catch (e) {
        debugPrint('Error deleting variant: $e');
        if (mounted) {
          _showSnackBar(
            _friendlyError(
              e,
              linkedMessage:
                  "This variant is already used by bookings or barbers, so it can't be deleted right now.",
            ),
            Colors.red,
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  // ============================================
  // ✅ EDIT SERVICE (with proper controller dispose)
  // ============================================
  Future<void> _editService(Map<String, dynamic> service) async {
    final nameController = TextEditingController(text: service['name']);
    final descriptionController = TextEditingController(
      text: service['description'] ?? '',
    );
    // The dropdown only accepts a value that is in its list.
    int? selectedCategoryId = _categories.any(
      (c) => c['id'] == service['category_id'],
    )
        ? service['category_id'] as int?
        : null;
    String? nameError;
    String? categoryError;
    String? saveError;
    bool isSaving = false;

    final isDark = context.isDarkMode;

    InputDecoration decoration(String label, {String? errorText}) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Colors.white60 : Colors.grey[600],
        ),
        counterText: '',
        errorText: errorText,
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      );
    }

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: null,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getIconForName(service['icon_name']),
                            color: AppTheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Edit Service',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: nameController,
                      maxLength: _maxServiceName,
                      inputFormatters: _textFormatters(_maxServiceName),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setDialogState(() {
                        nameError = null;
                        saveError = null;
                      }),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: decoration(
                        'Service Name *',
                        errorText: nameError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: descriptionController,
                      maxLines: 3,
                      maxLength: _maxDescription,
                      inputFormatters: _textFormatters(
                        _maxDescription,
                        multiLine: true,
                      ),
                      onChanged: (_) => setDialogState(() => saveError = null),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: decoration('Description'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: selectedCategoryId,
                      isExpanded: true,
                      decoration: decoration(
                        'Category *',
                        errorText: categoryError,
                      ),
                      dropdownColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.white,
                      items: _categories.map((category) {
                        return DropdownMenuItem<int>(
                          value: category['id'] as int,
                          child: Text(
                            category['display_name'],
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedCategoryId = value;
                          categoryError = null;
                          saveError = null;
                        });
                      },
                    ),
                    if (saveError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                saveError!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black87,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final cleanName = _cleanText(
                            nameController.text,
                            _maxServiceName,
                          );
                          final cleanDescription = _cleanText(
                            descriptionController.text,
                            _maxDescription,
                            multiLine: true,
                          );

                          String? nErr;
                          String? cErr;
                          if (cleanName.isEmpty) {
                            nErr = 'Service name is required';
                          } else if (selectedCategoryId != null &&
                              _services.any(
                                (s) =>
                                    s['id'] != service['id'] &&
                                    s['category_id'] == selectedCategoryId &&
                                    (s['name'] ?? '')
                                            .toString()
                                            .trim()
                                            .toLowerCase() ==
                                        cleanName.toLowerCase(),
                              )) {
                            nErr =
                                'A service with this name already exists in this category';
                          }
                          if (selectedCategoryId == null) {
                            cErr = 'Please select a category';
                          }
                          if (nErr != null || cErr != null) {
                            setDialogState(() {
                              nameError = nErr;
                              categoryError = cErr;
                            });
                            return;
                          }

                          if (!mounted) return;
                          setDialogState(() {
                            isSaving = true;
                            saveError = null;
                          });
                          setState(() => _isProcessing = true);

                          try {
                            await supabase
                                .from('services')
                                .update({
                                  'name': cleanName,
                                  'description': cleanDescription.isEmpty
                                      ? null
                                      : cleanDescription,
                                  'category_id': selectedCategoryId,
                                  'updated_at': DateTime.now()
                                      .toIso8601String(),
                                })
                                .eq('id', service['id']);

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            await _loadServices();

                            if (mounted) {
                              _showSnackBar(
                                'Service updated successfully!',
                                Colors.green,
                              );
                            }
                          } catch (e) {
                            debugPrint('Error updating service: $e');
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                                saveError = _friendlyError(
                                  e,
                                  duplicateMessage:
                                      'A service with this name already exists in this category.',
                                );
                              });
                            }
                          } finally {
                            if (mounted) setState(() => _isProcessing = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      // ✅ Dispose controllers after dialog closes
      nameController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _deleteService(Map<String, dynamic> service) async {
    if (!mounted) return;

    final isDark = context.isDarkMode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: null,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Delete Service',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "Are you sure you want to delete '${service['name']}'?",
                softWrap: true,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ This will also delete:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• ${service['variant_count']} variant${service['variant_count'] != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    Text(
                      '• All barber assignments',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This action cannot be undone!',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.red[300] : Colors.red,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style:
                  TextStyle(color: isDark ? Colors.white60 : Colors.black87),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);

      try {
        await supabase.from('services').delete().eq('id', service['id']);

        await _loadServices();

        if (mounted) {
          _showSnackBar('Service deleted successfully', Colors.green);
        }
      } catch (e) {
        debugPrint('Error deleting service: $e');
        if (mounted) {
          _showSnackBar(
            _friendlyError(
              e,
              linkedMessage:
                  "This service is already used by bookings, so it can't be deleted right now.",
            ),
            Colors.red,
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((service) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          service['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (service['description']?.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ??
              false);

      final matchesCategory =
          _selectedCategoryId == null ||
          service['category_id'] == _selectedCategoryId;

      return matchesSearch && matchesCategory;
    }).toList();
  }

  // ============================================
  // ADD SERVICE CARDS
  // ============================================

  Widget _buildAddServiceCard() {
    final isDark = context.isDarkMode;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: InkWell(
        onTap: _isProcessing
            ? null
            : () async {
                if (!mounted) return;
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddServiceScreen(salonId: widget.salonId),
                  ),
                );
                if (result == true && mounted) {
                  await _loadServices();
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFFFF6B8B).withValues(alpha: 0.6),
                      const Color(0xFFFF6B8B).withValues(alpha: 0.3),
                    ]
                  : [const Color(0xFFF8AEBE), const Color(0xFFF5A4D3)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                'Add New Service',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Create a new service\nfor your salon',
                style: TextStyle(fontSize: 11, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddServiceCardMobile() {
    final isDark = context.isDarkMode;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: InkWell(
        onTap: _isProcessing
            ? null
            : () async {
                if (!mounted) return;
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddServiceScreen(salonId: widget.salonId),
                  ),
                );
                if (result == true && mounted) {
                  await _loadServices();
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFFFF6B8B).withValues(alpha: 0.6),
                      const Color(0xFFFF6B8B).withValues(alpha: 0.3),
                    ]
                  : [const Color(0xFFF8AEBE), const Color(0xFFF5A4D3)],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add New Service',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // SERVICE CARD (WEB)
  // ============================================

  Widget _buildServiceCardWeb(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isExpanded = _expandedServices.contains(service['id']);
    final accentColor = AppTheme.primary;
    final cardColor = _cardColors[index % _cardColors.length];
    final isDark = context.isDarkMode;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? const Color(0xFF2A2A2A) : cardColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.white.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          isDark ? const Color(0xFF3A3A3A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getIconForName(service['icon_name']),
                      color: accentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isDark ? Colors.white : Colors.grey[800],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service['category_name'],
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _editService(service),
                        tooltip: 'Edit Service',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _deleteService(service),
                        tooltip: 'Delete Service',
                      ),
                      if (hasVariants)
                        IconButton(
                          icon: AnimatedRotation(
                            duration: const Duration(milliseconds: 300),
                            turns: isExpanded ? 0.5 : 0.0,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: isDark ? Colors.white60 : Colors.grey,
                            ),
                          ),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () => _toggleExpand(service['id']),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            if (service['description'] != null &&
                service['description'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service['description'],
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Variants',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _showAddVariantDialog(service),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Variant'),
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (hasVariants && isExpanded) ...[
                      ...variants.map((variant) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[200]!,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color:
                                      Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_offer,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildVariantTexts(variant, isDark),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: Colors.blue,
                                    ),
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _showEditVariantDialog(
                                            service,
                                            variant,
                                          ),
                                    tooltip: 'Edit Variant',
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    onPressed: _isProcessing
                                        ? null
                                        : () =>
                                            _deleteVariant(service, variant),
                                    tooltip: 'Delete Variant',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else if (!hasVariants) ...[
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 48,
                              color:
                                  isDark ? Colors.white30 : Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No variants added yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Click "Add Variant" to add price and duration options',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // SERVICE CARD (MOBILE)
  // ============================================

  Widget _buildServiceCardMobile(Map<String, dynamic> service, int index) {
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isExpanded = _expandedServices.contains(service['id']);
    final accentColor = AppTheme.primary;
    final cardColor = _cardColors[index % _cardColors.length];
    final isDark = context.isDarkMode;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      elevation: 2,
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? const Color(0xFF2A2A2A) : cardColor,
        ),
        child: Column(
          children: [
            InkWell(
              onTap: hasVariants ? () => _toggleExpand(service['id']) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF3A3A3A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForName(service['icon_name']),
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color:
                                  isDark ? Colors.white : Colors.grey[800],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  service['category_name'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasVariants) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${variants.length} variants',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _editService(service),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: _isProcessing
                              ? null
                              : () => _deleteService(service),
                        ),
                        if (hasVariants)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                              color: isDark ? Colors.white60 : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (service['description'] != null &&
                service['description'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  service['description'],
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ),

            if (hasVariants && isExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    Divider(
                      color: isDark ? Colors.grey[700] : Colors.grey[200],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Variants',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _showAddVariantDialog(service),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Variant'),
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...variants.map((variant) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.local_offer,
                                color: Colors.orange,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildVariantTexts(
                                variant,
                                isDark,
                                subSize: 11,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () => _showEditVariantDialog(
                                          service,
                                          variant,
                                        ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : () =>
                                          _deleteVariant(service, variant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // WEB VIEW
  // ============================================

  Widget _buildWebViewSliver() {
    final filteredServices = _filteredServices;
    final isDark = context.isDarkMode;

    if (filteredServices.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(isDark),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == filteredServices.length) {
              return _buildAddServiceCard();
            }
            final service = filteredServices[index];
            return _buildServiceCardWeb(service, index);
          },
          childCount: filteredServices.length + 1,
        ),
      ),
    );
  }

  // ============================================
  // MOBILE VIEW
  // ============================================

  Widget _buildMobileViewSliver() {
    final filteredServices = _filteredServices;
    final isDark = context.isDarkMode;

    if (filteredServices.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(isDark),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == filteredServices.length) {
              return _buildAddServiceCardMobile();
            }
            final service = filteredServices[index];
            return _buildServiceCardMobile(service, index);
          },
          childCount: filteredServices.length + 1,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox,
              size: 64,
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No services added yet',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : () async {
                      if (!mounted) return;
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddServiceScreen(salonId: widget.salonId),
                        ),
                      );
                      if (result == true && mounted) {
                        await _loadServices();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add Your First Service'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForName(String? iconName) {
    switch (iconName) {
      case 'content_cut':
        return Icons.content_cut;
      case 'face':
        return Icons.face;
      case 'face_retouching_natural':
        return Icons.face_retouching_natural;
      case 'spa':
        return Icons.spa;
      case 'handshake':
        return Icons.handshake;
      case 'build':
        return Icons.build;
      case 'brush':
        return Icons.brush;
      case 'cut':
        return Icons.cut;
      case 'water_drop':
        return Icons.water_drop;
      case 'masks':
        return Icons.masks;
      case 'spa_outlined':
        return Icons.spa_outlined;
      default:
        return Icons.build;
    }
  }

  // ============================================
  // MAIN BUILD METHOD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Services - ${widget.salonName}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _isProcessing
                ? null
                : () async {
                    if (!mounted) return;
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            AddServiceScreen(salonId: widget.salonId),
                      ),
                    );
                    if (result == true && mounted) {
                      await _loadServices();
                    }
                  },
            tooltip: 'Add New Service',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child:
                    CircularProgressIndicator(color: AppTheme.primary),
              )
            : isWeb
                ? _buildWebLayout()
                : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildSearchAndFilter()),
              _buildWebViewSliver(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildSearchAndFilter()),
        _buildMobileViewSliver(),
      ],
    );
  }

  Widget _buildSearchAndFilter() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Column(
        children: [
          TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style:
                TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Search services...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 2),
              ),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF2A2A2A) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 45,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: Text(
                    'All',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: _selectedCategoryId == null,
                  onSelected: (_) =>
                      setState(() => _selectedCategoryId = null),
                  selectedColor:
                      AppTheme.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppTheme.primary,
                  backgroundColor: isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.grey[100],
                ),
                const SizedBox(width: 8),
                ..._categories.map((category) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        category['display_name'],
                        style: TextStyle(
                          color:
                              isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: _selectedCategoryId == category['id'],
                      onSelected: (_) => setState(() {
                        _selectedCategoryId = category['id'] as int;
                      }),
                      selectedColor:
                          AppTheme.primary.withValues(alpha: 0.2),
                      checkmarkColor: AppTheme.primary,
                      backgroundColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.grey[100],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}