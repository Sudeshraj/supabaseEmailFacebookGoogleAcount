import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/services/currency_service.dart';

/// The service menu editor (categories → services → variants) as a reusable
/// widget. Use it inside any screen: the dashboard, or the standalone
/// AddServiceScreen wrapper.
class ServiceMenuEditor extends StatefulWidget {
  final int salonId;

  /// Show the tree's own title row. Turn off when the parent already has a
  /// heading (e.g. the dashboard's "Service Menu" section).
  final bool showHeader;

  /// Called after services were saved successfully.
  final VoidCallback? onSaved;

  /// Colour used for the tree card border/tint and the save button.
  final Color accentColor;

  const ServiceMenuEditor({
    super.key,
    required this.salonId,
    this.showHeader = true,
    this.onSaved,
    this.accentColor = AppTheme.primary,
  });

  @override
  State<ServiceMenuEditor> createState() => _ServiceMenuEditorState();
}

class _ServiceMenuEditorState extends State<ServiceMenuEditor> {
  // ==================== SERVICES ====================
  final CurrencyService _currencyService = CurrencyService.instance;

  // ==================== HARDCODED GENDER LIST ====================
  static const List<Map<String, dynamic>> _hardcodedGenders = [
    {'id': 1, 'display_name': 'Male'},
    {'id': 2, 'display_name': 'Female'},
    {'id': 3, 'display_name': 'Unisex'},
  ];

  // ==================== DATA ====================
  List<Map<String, dynamic>> _genders = [];
  List<Map<String, dynamic>> _ageCategories = [];

  // Suggestion sources. Category rows keep description/icon/color so picking
  // a suggestion can auto-fill them.
  List<Map<String, dynamic>> _globalCategories = [];
  List<String> _globalAgeNames = [];

  // Local tree: each category has services, each service has variants
  final List<Map<String, dynamic>> _categories = [];

  // ==================== LOADING ====================
  bool _isLoadingData = true;
  bool _isLoading = false;

  // ==================== CURRENCY ====================
  String _salonCurrencyCode = 'LKR';

  // ==================== THEME ====================
  bool _isDark = false;

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
      'icon': Icons.water_drop,
      'name': 'water_drop',
      'label': 'Wash',
      'color': 0xFF00BCD4,
    },
    {
      'icon': Icons.masks,
      'name': 'masks',
      'label': 'Masks',
      'color': 0xFF607D8B,
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

  // ==================== SUGGESTION GETTERS ====================
  List<String> get _categorySuggestions => {
        ..._globalCategories.map((c) => (c['display_name'] ?? '').toString()),
        ..._categories.map((c) => (c['display_name'] ?? '').toString()),
      }.where((n) => n.isNotEmpty).toList();

  List<String> get _serviceSuggestions => {
        for (final c in _categories)
          for (final s in (c['services'] as List)) (s['name'] ?? '').toString(),
      }.where((n) => n.isNotEmpty).toList();

  /// Description / icon / colour stored for a suggested category name.
  /// Global master list first, then the salon's own categories.
  Map<String, dynamic>? _categoryDefaults(String name) {
    final key = name.trim().toLowerCase();
    for (final c in [..._globalCategories, ..._categories]) {
      if ((c['display_name'] ?? '').toString().trim().toLowerCase() == key) {
        return c;
      }
    }
    return null;
  }

  /// Description / icon stored for a suggested service name (salon services).
  Map<String, dynamic>? _serviceDefaults(String name) {
    final key = name.trim().toLowerCase();
    for (final c in _categories) {
      for (final s in (c['services'] as List)) {
        if ((s['name'] ?? '').toString().trim().toLowerCase() == key) {
          return s as Map<String, dynamic>;
        }
      }
    }
    return null;
  }

  bool _isKnownIcon(String? name) =>
      name != null && _iconSuggestions.any((i) => i['name'] == name);

  bool _isHexColor(String? hex) =>
      hex != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex);

  @override
  void initState() {
    super.initState();
    _genders = List<Map<String, dynamic>>.from(_hardcodedGenders);
    _loadData();
    _loadSalonCurrency();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = context.isDarkMode;
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
  // DATA LOADING
  // ============================================
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return; // ✅ guard
    if (!silent) setState(() => _isLoadingData = true);

    try {
      // Load existing salon categories + services + variants
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select(
              'id, display_name, description, icon_name, color, display_order')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age, display_order')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Global suggestion lists (optional — ignore if the tables are missing)
      List<Map<String, dynamic>> globalCategories = [];
      try {
        final g = await supabase
            .from('categories')
            .select('display_name, description, icon_name, color')
            .eq('is_active', true);
        globalCategories = List<Map<String, dynamic>>.from(g);
      } catch (e) {
        debugPrint('Could not load global categories: $e');
      }

      List<String> globalAgeNames = [];
      try {
        final g = await supabase
            .from('age_categories')
            .select('display_name')
            .eq('is_active', true);
        globalAgeNames =
            g.map<String>((e) => e['display_name'].toString()).toList();
      } catch (e) {
        debugPrint('Could not load global age categories: $e');
      }

      if (!mounted) return; // ✅ guard
      setState(() {
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
        _globalCategories = globalCategories;
        _globalAgeNames = globalAgeNames;
      });

      // Load services for this salon
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('name');

      // Load variants for these services
      List<dynamic> variantsResponse = [];
      if (servicesResponse.isNotEmpty) {
        final serviceIds =
            servicesResponse.map<int>((s) => s['id'] as int).toList();
        variantsResponse = await supabase
            .from('service_variants')
            .select(
                'id, service_id, name, price, duration, salon_gender_id, salon_age_category_id')
            .inFilter('service_id', serviceIds)
            .eq('is_active', true);
      }

      // Build maps for gender/age lookup
      final salonGenderIdToName = <int, String>{};
      try {
        final salonGenderRows = await supabase
            .from('salon_genders')
            .select('id, display_name')
            .eq('salon_id', widget.salonId);
        for (var g in salonGenderRows) {
          salonGenderIdToName[g['id'] as int] =
              (g['display_name'] ?? 'Any').toString();
        }
      } catch (e) {
        debugPrint('Could not load salon genders: $e');
      }

      if (!mounted) return; // ✅ guard

      final ageIdToName = <int, String>{};
      for (var a in _ageCategories) {
        ageIdToName[a['id'] as int] = _getAgeCategoryDisplayName(a);
      }

      // Group variants by service
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var v in variantsResponse) {
        final sid = v['service_id'] as int;
        final rawGenderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final storedGenderName = rawGenderId != null
            ? (salonGenderIdToName[rawGenderId] ?? 'Any')
            : 'Any';
        final genderId = _genderIdFromName(storedGenderName);
        final ageName =
            ageId != null ? (ageIdToName[ageId] ?? 'Any') : 'Any';

        final priceNum = (v['price'] as num?)?.toDouble();

        variantsByService.putIfAbsent(sid, () => []).add({
          'gender_id': genderId,
          'gender_name': _genderNameFromId(genderId),
          'age_category_id': ageId,
          'age_category_name': ageName,
          'price': priceNum ?? 0.0,
          'price_set': priceNum != null,
          'duration': (v['duration'] as num?)?.toInt() ?? 0,
          'name': (v['name'] ?? '').toString().trim(),
          'variant_id': v['id'],
          'from_db': true,
        });
      }

      // Group services by category_id
      final Map<int, List<Map<String, dynamic>>> servicesByCategory = {};
      for (var s in servicesResponse) {
        final catId = s['category_id'] as int?;
        if (catId == null) continue;
        servicesByCategory.putIfAbsent(catId, () => []).add({
          'id': s['id'],
          'name': s['name'] ?? '',
          'description': s['description'] ?? '',
          'icon_name': s['icon_name'] ?? 'content_cut',
          'variants': variantsByService[s['id'] as int] ?? [],
          'from_db': true,
        });
      }

      // Build categories tree
      final List<Map<String, dynamic>> loadedCategories = [];
      for (var c in categoriesResponse) {
        final catId = c['id'] as int;
        loadedCategories.add({
          'id': catId,
          'display_name': c['display_name'] ?? '',
          'description': c['description'] ?? '',
          'icon_name': c['icon_name'] ?? 'content_cut',
          'color': c['color'] ?? '#FF6B8B',
          'services': servicesByCategory[catId] ?? [],
          'from_db': true,
        });
      }

      if (!mounted) return;
      setState(() {
        _categories
          ..clear()
          ..addAll(loadedCategories);
        _isLoadingData = false;
      });
    } catch (e) {
      if (!mounted) return; // ✅ guard
      setState(() => _isLoadingData = false);
      _showSnackBar(_friendlyError(e), Colors.red);
    }
  }

  // ============================================
  // HELPERS
  // ============================================
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

  String _getAgeCategoryDisplayName(Map<String, dynamic> ageCat) {
    String name = ageCat['display_name'] ?? 'Unknown';
    if (ageCat['min_age'] != null && ageCat['max_age'] != null) {
      name = '$name (${ageCat['min_age']}-${ageCat['max_age']} yrs)';
    }
    return name;
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
  // TEXT LIMITS + SANITISING (same limits are enforced again in the DB)
  // ============================================
  static const int _maxCategoryName = 40;
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
  List<TextInputFormatter> _textFormatters(int max,
      {bool multiLine = false}) {
    return [
      FilteringTextInputFormatter.deny(
          multiLine ? _badCharsMultiLine : _badCharsSingleLine),
      LengthLimitingTextInputFormatter(max),
    ];
  }

  /// Final clean-up before a value is stored: removes bad characters,
  /// collapses repeated spaces, trims and cuts to [max].
  String _cleanText(String input, int max, {bool multiLine = false}) {
    var t = input.replaceAll(
        multiLine ? _badCharsMultiLine : _badCharsSingleLine, '');
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

  /// 45 → "45 min", 60 → "1 hr", 90 → "1 hr 30 min", 120 → "2 hrs".
  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    final hText = h == 1 ? '1 hr' : '$h hrs';
    return m == 0 ? hText : '$hText $m min';
  }

  /// Main line of a variant row: its name, or (no name) the set details.
  String _variantTitle(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    if (vName.isNotEmpty) return vName;
    final parts = _variantDetailParts(v);
    return parts.isEmpty ? 'Standard' : parts.join(' • ');
  }

  /// Second line of a variant row. Only when a name is shown as the title,
  /// the details move down here; otherwise they are already in the title.
  List<String> _variantSubtitleParts(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    return vName.isNotEmpty ? _variantDetailParts(v) : <String>[];
  }

  /// Readable variant summary that skips anything that isn't set:
  /// "Beard Trim • Male • Adult (18-60 yrs) • 30 min". No "Any" or dashes.
  String _variantLabel(Map<String, dynamic> v) {
    final vName = (v['name'] ?? '').toString().trim();
    final parts = <String>[
      if (vName.isNotEmpty) vName,
      ..._variantDetailParts(v),
    ];
    return parts.isEmpty ? 'Standard' : parts.join(' • ');
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

  // ============================================
  // SUGGESTION TEXT FIELD
  // Shows suggestions while typing. Typing never changes other fields; only
  // when a suggestion is actually picked, [onPicked] runs (the dialogs use it
  // to auto-fill description / icon / colour).
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
          return l.contains(q) && l != q;
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
            prefixIcon: Icon(icon,
                size: 18, color: isDark ? Colors.white70 : Colors.grey),
            suffixIcon: suggestions.isNotEmpty
                ? Icon(Icons.arrow_drop_down,
                    color: isDark ? Colors.white70 : Colors.grey)
                : null,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        );
      },
    );
  }

  // ============================================
  // FRIENDLY ERRORS + DUPLICATE CHECKS
  // ============================================
  String _friendlyError(Object e) {
    if (e is PostgrestException) {
      switch (e.code) {
        case '23505':
          return 'Two items are exactly the same (for example a service with the same name, gender, age category and duration). Please remove or change the duplicate.';
        case '23503':
          return "Some of these services are already linked to other records (like bookings), so they can't be replaced right now.";
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

  bool _isDuplicateVariant(
    List variants, {
    required int? gender,
    required int? age,
    required int duration,
    String name = '',
    int? ignoreIndex,
  }) {
    final n = name.trim().toLowerCase();
    for (int i = 0; i < variants.length; i++) {
      if (i == ignoreIndex) continue;
      final v = variants[i];
      if (v['gender_id'] == gender &&
          v['age_category_id'] == age &&
          (v['name'] ?? '').toString().trim().toLowerCase() == n &&
          ((v['duration'] as num?)?.toInt() ?? 0) == duration) {
        return true;
      }
    }
    return false;
  }

  bool _hasDuplicateVariants(List variants) {
    for (int i = 0; i < variants.length; i++) {
      final v = variants[i];
      if (_isDuplicateVariant(
        variants,
        gender: v['gender_id'] as int?,
        age: v['age_category_id'] as int?,
        duration: (v['duration'] as num?)?.toInt() ?? 0,
        name: (v['name'] ?? '').toString(),
        ignoreIndex: i,
      )) {
        return true;
      }
    }
    return false;
  }

  // ============================================
  // DIALOGS: CATEGORY
  // ============================================
  Future<void> _openCategoryDialog({int? editIndex}) async {
    final existing = editIndex != null ? _categories[editIndex] : null;

    final nameController = TextEditingController(
      text: existing?['display_name'] ?? '',
    );
    final descController = TextEditingController(
      text: existing?['description'] ?? '',
    );
    String selectedIcon =
        (existing?['icon_name'] as String?) ?? _iconSuggestions.first['name'];
    String selectedColorHex =
        (existing?['color'] as String?) ?? _categoryColorOptions.first['hex'];

    final isDark = _isDark;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.all(20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.category,
                        color: Colors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    editIndex != null ? 'Edit Category' : 'Add New Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _suggestField(
                        controller: nameController,
                        suggestions: _categorySuggestions,
                        label: 'Category Name *',
                        maxLength: _maxCategoryName,
                        hint: 'e.g., Hair, Nails, Spa',
                        icon: Icons.category,
                        isDark: isDark,
                        // Picking a suggestion fills description, icon, colour
                        onPicked: (picked) {
                          final d = _categoryDefaults(picked);
                          if (d == null) return;
                          setDialogState(() {
                            descController.text =
                                (d['description'] ?? '').toString();
                            final icon = d['icon_name']?.toString();
                            if (_isKnownIcon(icon)) selectedIcon = icon!;
                            final color = d['color']?.toString();
                            if (_isHexColor(color)) selectedColorHex = color!;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
                        maxLength: _maxDescription,
                        inputFormatters:
                            _textFormatters(_maxDescription, multiLine: true),
                        style: TextStyle(
                            color:
                                isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          hintText: 'e.g., Hair cutting and styling',
                          prefixIcon: Icon(Icons.description,
                              size: 18,
                              color:
                                  isDark ? Colors.white70 : Colors.grey),
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
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                            final isSelected =
                                selectedIcon == item['name'];
                            final color = Color(item['color']);
                            return GestureDetector(
                              onTap: () => setDialogState(() {
                                selectedIcon = item['name'] as String;
                              }),
                              child: Container(
                                width: 52,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withValues(alpha: 0.15)
                                      : (isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? color
                                        : (isDark
                                            ? Colors.grey[700]!
                                            : Colors.grey[300]!),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      item['icon'],
                                      size: 20,
                                      color: isSelected
                                          ? color
                                          : (isDark
                                              ? Colors.white60
                                              : Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['label'],
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: isSelected
                                            ? color
                                            : (isDark
                                                ? Colors.white60
                                                : Colors.grey[600]),
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
                      const SizedBox(height: 16),
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
                          final isSelected =
                              selectedColorHex == opt['hex'];
                          return GestureDetector(
                            onTap: () => setDialogState(() {
                              selectedColorHex = opt['hex'];
                            }),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: opt['color'],
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.white, width: 2)
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
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 14)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name =
                        _cleanText(nameController.text, _maxCategoryName);
                    if (name.isEmpty) return;

                    Navigator.pop(dialogContext, {
                      'display_name': name,
                      'description': _cleanText(
                          descController.text, _maxDescription,
                          multiLine: true),
                      'icon_name': selectedIcon,
                      'color': selectedColorHex,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(editIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    if (!mounted) return; // ✅ guard (widget may be disposed while dialog open)

    setState(() {
      if (editIndex != null) {
        _categories[editIndex] = {
          ..._categories[editIndex],
          ...result,
        };
      } else {
        _categories.add({
          'id': null,
          ...result,
          'services': <Map<String, dynamic>>[],
          'from_db': false,
        });
      }
    });

    _showSnackBar(
      editIndex != null ? 'Category updated' : 'Category added',
      AppTheme.primary,
    );
  }

  // ============================================
  // DIALOGS: SERVICE
  // ============================================
  Future<void> _openServiceDialog({
    required int categoryIndex,
    int? editServiceIndex,
  }) async {
    final category = _categories[categoryIndex];
    final existing = editServiceIndex != null
        ? (category['services'] as List)[editServiceIndex]
        : null;

    final nameController = TextEditingController(
      text: existing?['name'] ?? '',
    );
    final descController = TextEditingController(
      text: existing?['description'] ?? '',
    );
    String selectedIcon =
        (existing?['icon_name'] as String?) ?? _iconSuggestions.first['name'];

    final isDark = _isDark;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.all(20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.build,
                        color: Colors.blue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editServiceIndex != null
                              ? 'Edit Service'
                              : 'Add New Service',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'Under "${category['display_name']}"',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _suggestField(
                        controller: nameController,
                        suggestions: _serviceSuggestions,
                        label: 'Service Name *',
                        maxLength: _maxServiceName,
                        hint: 'e.g., Hair Cut, Facial',
                        icon: Icons.build,
                        isDark: isDark,
                        // Picking a suggestion fills description and icon
                        onPicked: (picked) {
                          final d = _serviceDefaults(picked);
                          if (d == null) return;
                          setDialogState(() {
                            descController.text =
                                (d['description'] ?? '').toString();
                            final icon = d['icon_name']?.toString();
                            if (_isKnownIcon(icon)) selectedIcon = icon!;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
                        maxLength: _maxDescription,
                        inputFormatters:
                            _textFormatters(_maxDescription, multiLine: true),
                        style: TextStyle(
                            color:
                                isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          hintText: 'Describe this service...',
                          prefixIcon: Icon(Icons.description,
                              size: 18,
                              color:
                                  isDark ? Colors.white70 : Colors.grey),
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
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                            final isSelected =
                                selectedIcon == item['name'];
                            final color = Color(item['color']);
                            return GestureDetector(
                              onTap: () => setDialogState(() {
                                selectedIcon = item['name'] as String;
                              }),
                              child: Container(
                                width: 52,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withValues(alpha: 0.15)
                                      : (isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? color
                                        : (isDark
                                            ? Colors.grey[700]!
                                            : Colors.grey[300]!),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      item['icon'],
                                      size: 20,
                                      color: isSelected
                                          ? color
                                          : (isDark
                                              ? Colors.white60
                                              : Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['label'],
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: isSelected
                                            ? color
                                            : (isDark
                                                ? Colors.white60
                                                : Colors.grey[600]),
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
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name =
                        _cleanText(nameController.text, _maxServiceName);
                    if (name.isEmpty) return;

                    Navigator.pop(dialogContext, {
                      'name': name,
                      'description': _cleanText(
                          descController.text, _maxDescription,
                          multiLine: true),
                      'icon_name': selectedIcon,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(editServiceIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    if (!mounted) return; // ✅ guard

    setState(() {
      final services = _categories[categoryIndex]['services'] as List;
      if (editServiceIndex != null) {
        services[editServiceIndex] = <String, dynamic>{
          ...services[editServiceIndex] as Map<String, dynamic>,
          ...result,
        };
      } else {
        services.add({
          'id': null,
          ...result,
          'variants': <Map<String, dynamic>>[],
          'from_db': false,
        });
      }
    });

    _showSnackBar(
      editServiceIndex != null ? 'Service updated' : 'Service added',
      AppTheme.primary,
    );
  }

  // ============================================
  // DIALOGS: VARIANT
  // ============================================
  Future<void> _openVariantDialog({
    required int categoryIndex,
    required int serviceIndex,
    int? editVariantIndex,
  }) async {
    final category = _categories[categoryIndex];
    final service = (category['services'] as List)[serviceIndex];
    final existing = editVariantIndex != null
        ? (service['variants'] as List)[editVariantIndex]
        : null;

    int? selectedGenderId = existing?['gender_id'] as int?;
    int? selectedAgeId = existing?['age_category_id'] as int?;
    final priceController = TextEditingController(
      text: existing != null && existing['price_set'] == true
          ? (_currencyUsesDecimals
              ? (existing['price'] as double).toString()
              : (existing['price'] as double).toInt().toString())
          : '',
    );
    // Duration is typed as hours + minutes and stored as total minutes.
    final existingTotal = existing != null
        ? ((existing['duration'] as num?)?.toInt() ?? 0)
        : 0;
    final hoursController = TextEditingController(
      text: existingTotal >= 60 ? (existingTotal ~/ 60).toString() : '',
    );
    final minutesController = TextEditingController(
      text: existingTotal > 0 && existingTotal % 60 > 0
          ? (existingTotal % 60).toString()
          : '',
    );

    // Temporary new age category fields
    final newAgeNameController = TextEditingController();
    final newAgeMinController = TextEditingController(text: '0');
    final newAgeMaxController = TextEditingController(text: '100');
    bool showNewAgeForm = false;
    int ageFormResetCounter = 0; // rebuilds the suggestion field after clear
    final nameController =
        TextEditingController(text: (existing?['name'] ?? '').toString());
    String? nameError;
    String? variantError;
    String? durationError;
    String? priceError;
    String? ageNameError;
    String? ageMinError;
    String? ageMaxError;

    // Optional sections stay hidden until opened with the arrow. Edit mode
    // opens a section automatically when the variant already has a value.
    bool genderOpen = existing?['gender_id'] != null;
    bool ageOpen = existing?['age_category_id'] != null;
    bool priceOpen = existing != null && existing['price_set'] == true;

    final isDark = _isDark;

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
                    : validateDuration(
                        hoursController.text, minutesController.text);
          });
        },
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: hint,
          suffixText: suffix,
          prefixIcon: icon != null
              ? Icon(icon,
                  size: 18, color: isDark ? Colors.white70 : Colors.grey)
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: durationError != null
                    ? Colors.red
                    : (isDark ? Colors.grey[700]! : Colors.grey[300]!)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      } else if (_ageCategories.any((a) =>
          a['display_name'].toString().toLowerCase() == name.toLowerCase())) {
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

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.all(20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune,
                        color: Colors.purple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          editVariantIndex != null
                              ? 'Edit Variant'
                              : 'Add New Variant',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'For "${service['name']}"',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
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
                            ? _genderNameFromId(selectedGenderId)
                            : 'Optional — tap the arrow to choose',
                        onTap: () =>
                            setDialogState(() => genderOpen = !genderOpen),
                      ),
                      if (genderOpen) ...[
                      const SizedBox(height: 6),
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
                            }),
                            backgroundColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey[100],
                            selectedColor:
                                Colors.blue.withValues(alpha: 0.2),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                          height: 1,
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                        ),
                      ),

                      // 2. Age Category (optional, hidden until expanded)
                      sectionHeader(
                        number: 2,
                        title: 'Age Category',
                        color: Colors.green,
                        open: ageOpen,
                        summary: selectedAgeId != null
                            ? _getAgeCategoryDisplayName(
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
                                      fontSize: 11, color: Colors.green),
                                ),
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
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
                                _getAgeCategoryDisplayName(a),
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
                              }),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[100],
                              selectedColor:
                                  Colors.green.withValues(alpha: 0.2),
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
                                color:
                                    Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              _suggestField(
                                fieldKey: ValueKey(
                                    'age_name_$ageFormResetCounter'),
                                controller: newAgeNameController,
                                suggestions: _globalAgeNames,
                                label: 'Age Name *',
                                maxLength: _maxAgeName,
                                hint: 'e.g., Adult',
                                icon: Icons.visibility,
                                isDark: isDark,
                                errorText: ageNameError,
                                onChanged: (_) => setDialogState(
                                    () => ageNameError = null),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: newAgeMinController,
                                      keyboardType:
                                          TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter
                                            .digitsOnly,
                                      ],
                                      maxLength: 3,
                                      onChanged: (_) => setDialogState(
                                          () => ageMinError = null),
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87),
                                      decoration: InputDecoration(
                                        labelText: 'Min',
                                        counterText: '',
                                        errorText: ageMinError,
                                        errorMaxLines: 2,
                                        isDense: true,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF1E1E1E)
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: newAgeMaxController,
                                      keyboardType:
                                          TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter
                                            .digitsOnly,
                                      ],
                                      maxLength: 3,
                                      onChanged: (_) => setDialogState(
                                          () => ageMaxError = null),
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87),
                                      decoration: InputDecoration(
                                        labelText: 'Max',
                                        counterText: '',
                                        errorText: ageMaxError,
                                        errorMaxLines: 2,
                                        isDense: true,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF1E1E1E)
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (!validateAge(setDialogState)) {
                                      return;
                                    }

                                    final name = _cleanText(
                                        newAgeNameController.text,
                                        _maxAgeName);
                                    final min = int.parse(
                                        newAgeMinController.text.trim());
                                    final max = int.parse(
                                        newAgeMaxController.text.trim());

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

                                      // ✅ guard: the editor or the dialog
                                      // may be gone by the time the insert
                                      // returns.
                                      if (!mounted) return;
                                      if (!dialogContext.mounted) return;

                                      setState(() {
                                        _ageCategories.add(
                                            Map<String, dynamic>.from(
                                                inserted));
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
                                      });
                                    } catch (e) {
                                      debugPrint('Error adding age: $e');
                                      if (mounted) {
                                        _showSnackBar(
                                            _friendlyError(e), Colors.red);
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.save, size: 14),
                                  label: const Text('Save Age Category',
                                      style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                          height: 1,
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                        ),
                      ),

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
                        onChanged: (v) {
                          final t = v.trim();
                          final p = double.tryParse(t);
                          setDialogState(() {
                            variantError = null;
                            if (t.isEmpty) {
                              priceError = null;
                            } else if (p == null) {
                              priceError = 'Enter a valid price';
                            } else if (p < 0) {
                              priceError = 'Price cannot be negative';
                            } else {
                              priceError = null;
                            }
                          });
                        },
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Leave empty to set later',
                          errorText: priceError,
                          errorMaxLines: 2,
                          prefixIcon: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Center(
                              widthFactor: 1.0,
                              child: Text(
                                _salonCurrencySymbol,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey),
                              ),
                            ),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 50, minHeight: 20),
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
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                          height: 1,
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                        ),
                      ),
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
                                fontSize: 12, color: Colors.red),
                          ),
                        )
                      else if (parseDuration(hoursController.text,
                              minutesController.text) !=
                          null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            'Total: ${_formatDuration(parseDuration(hoursController.text, minutesController.text)!)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                          height: 1,
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                        ),
                      ),

                      // 5. Variant name (optional; required when only the
                      // duration is set — no gender and no age)
                      sectionHeader(
                        number: 5,
                        title: 'Variant name',
                        color: Colors.indigo,
                        isRequired:
                            selectedGenderId == null && selectedAgeId == null,
                        summary: (selectedGenderId == null &&
                                selectedAgeId == null)
                            ? 'Required — no gender or age is set'
                            : 'Optional — e.g., Short hair, Long hair',
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        maxLength: _maxVariantName,
                        inputFormatters: _textFormatters(_maxVariantName),
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) {
                          setDialogState(() {
                            variantError = null;
                            nameError = null;
                          });
                        },
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'e.g., Short hair',
                          counterText: '',
                          errorText: nameError,
                          errorMaxLines: 2,
                          prefixIcon: Icon(Icons.label_outline,
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
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
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
                                color: Colors.red.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  variantError!,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final priceText = priceController.text.trim();

                    // Price is optional, but when typed it must be a valid
                    // non-negative number.
                    if (priceText.isNotEmpty) {
                      final p = double.tryParse(priceText);
                      if (p == null || p < 0) {
                        setDialogState(() {
                          priceError = 'Enter a valid price';
                        });
                        return;
                      }
                    }

                    // Duration is the only required field for a variant.
                    final durErr = validateDuration(
                        hoursController.text, minutesController.text);
                    if (durErr != null) {
                      setDialogState(() => durationError = durErr);
                      return;
                    }
                    // Stored as total minutes (all calculations use minutes)
                    final duration = parseDuration(
                        hoursController.text, minutesController.text)!;

                    // Name is optional, but mandatory when only the duration
                    // is set (no gender and no age).
                    final variantName =
                        _cleanText(nameController.text, _maxVariantName);
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
                    final price =
                        priceSet ? double.tryParse(priceText) ?? 0.0 : 0.0;

                    // Block duplicates right here, before they reach the list
                    if (_isDuplicateVariant(
                      service['variants'] as List,
                      gender: selectedGenderId,
                      age: selectedAgeId,
                      duration: duration,
                      name: variantName,
                      ignoreIndex: editVariantIndex,
                    )) {
                      setDialogState(() {
                        variantError =
                            'This service already has a variant with the same name, gender, age category and duration. Change one of them, or edit the existing variant instead.';
                      });
                      return;
                    }

                    final ageName = selectedAgeId != null
                        ? _getAgeCategoryDisplayName(_ageCategories
                            .firstWhere((a) => a['id'] == selectedAgeId))
                        : 'Any';

                    Navigator.pop(dialogContext, {
                      'gender_id': selectedGenderId,
                      'gender_name':
                          _genderNameFromId(selectedGenderId),
                      'age_category_id': selectedAgeId,
                      'age_category_name': ageName,
                      'price': price,
                      'price_set': priceSet,
                      'duration': duration,
                      'name': variantName,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child:
                      Text(editVariantIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    if (!mounted) return; // ✅ guard

    setState(() {
      final variants = (service['variants'] as List);
      if (editVariantIndex != null) {
        variants[editVariantIndex] = <String, dynamic>{
          ...variants[editVariantIndex] as Map<String, dynamic>,
          ...result,
        };
      } else {
        variants.add({
          'variant_id': null,
          ...result,
          'from_db': false,
        });
      }
    });

    _showSnackBar(
      editVariantIndex != null ? 'Variant updated' : 'Variant added',
      AppTheme.primary,
    );
  }

  // ============================================
  // DELETE CONFIRM
  // ============================================
  Future<bool> _confirmDelete({
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    Color confirmColor = Colors.red,
  }) async {
    final isDark = _isDark;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ============================================
  // SAVE ALL TO DB
  // ============================================
  Future<void> _saveAllServices() async {
    if (_categories.isEmpty) {
      _showSnackBar('Please add at least one category', Colors.orange);
      return;
    }

    final totalServices = _categories.fold<int>(
        0, (sum, c) => sum + (c['services'] as List).length);
    final totalVariants = _categories.fold<int>(
        0,
        (sum, c) =>
            sum +
            (c['services'] as List).fold<int>(
                0, (s, svc) => s + (svc['variants'] as List).length));

    if (totalServices == 0) {
      _showSnackBar('Please add at least one service', Colors.orange);
      return;
    }

    // Check for duplicates first, before touching the database
    for (final cat in _categories) {
      for (final svc in (cat['services'] as List)) {
        if (_hasDuplicateVariants(svc['variants'] as List)) {
          await showCustomAlert(
            context: context,
            title: 'Duplicate variants',
            message:
                '"${svc['name']}" (${cat['display_name']}) has two variants with the same name, gender, age category and duration. Please remove or change one of them.',
            isError: true,
          );
          return;
        }
      }
    }

    final seenNames = <String>{};
    for (final cat in _categories) {
      for (final svc in (cat['services'] as List)) {
        final key = (svc['name'] as String).trim().toLowerCase();
        if (!seenNames.add(key)) {
          await showCustomAlert(
            context: context,
            title: 'Duplicate service name',
            message:
                '"${svc['name']}" is used more than once. Each service name must be unique in the salon.',
            isError: true,
          );
          return;
        }
      }
    }

    final confirmed = await _confirmDelete(
      title: 'Save Services?',
      message:
          'This will save ${_categories.length} categor${_categories.length == 1 ? 'y' : 'ies'}, '
          '$totalServices service${totalServices == 1 ? '' : 's'}, '
          'and $totalVariants variant${totalVariants == 1 ? '' : 's'} to the database.',
      confirmLabel: 'OK',
      confirmColor: AppTheme.primary,
    );

    if (!confirmed) return;
    if (!mounted) return; // ✅ guard

    setState(() => _isLoading = true);

    try {
      // Ensure hardcoded genders exist in salon_genders
      final Map<String, int> genderIdByName = {};
      final existingGenders = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', widget.salonId);
      for (var g in existingGenders) {
        genderIdByName[(g['display_name'] as String).toLowerCase()] =
            g['id'] as int;
      }

      int nextOrder = existingGenders.length;
      for (final hg in _hardcodedGenders) {
        final name = hg['display_name'] as String;
        if (genderIdByName.containsKey(name.toLowerCase())) continue;
        try {
          final inserted = await supabase
              .from('salon_genders')
              .insert({
                'salon_id': widget.salonId,
                'display_name': name,
                'display_order': nextOrder++,
                'is_active': true,
              })
              .select('id')
              .single();
          genderIdByName[name.toLowerCase()] = inserted['id'] as int;
        } catch (e) {
          debugPrint('Could not insert gender "$name": $e');
        }
      }

      // ── Non-destructive sync ─────────────────────────────────────────
      // Rows that already exist are UPDATED in place, new rows are inserted,
      // and only what the user removed on this screen is deleted. Row IDs stay
      // the same, so barber assignments and bookings are not broken.
      final userId = supabase.auth.currentUser?.id;

      final localCatIds = <int>{};
      final localServiceIds = <int>{};
      final localVariantIds = <int>{};
      for (final cat in _categories) {
        if (cat['id'] is int) localCatIds.add(cat['id'] as int);
        for (final svc in (cat['services'] as List)) {
          if (svc['id'] is int) localServiceIds.add(svc['id'] as int);
          for (final v in (svc['variants'] as List)) {
            if (v['variant_id'] is int) {
              localVariantIds.add(v['variant_id'] as int);
            }
          }
        }
      }

      final dbCats = await supabase
          .from('salon_categories')
          .select('id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true);
      final dbServices = await supabase
          .from('services')
          .select('id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true);
      final dbServiceIds =
          dbServices.map<int>((s) => s['id'] as int).toList();
      final List<dynamic> dbVariants = dbServiceIds.isEmpty
          ? <dynamic>[]
          : await supabase
              .from('service_variants')
              .select('id')
              .inFilter('service_id', dbServiceIds)
              .eq('is_active', true);

      final removedCatIds = dbCats
          .map<int>((c) => c['id'] as int)
          .where((id) => !localCatIds.contains(id))
          .toList();
      final removedServiceIds =
          dbServiceIds.where((id) => !localServiceIds.contains(id)).toList();
      final removedVariantIds = dbVariants
          .map<int>((v) => v['id'] as int)
          .where((id) => !localVariantIds.contains(id))
          .toList();

      // 1) Delete only what the user removed (before inserting, so a variant
      //    that was removed and re-added never hits the unique constraint).
      if (removedVariantIds.isNotEmpty) {
        await supabase
            .from('service_variants')
            .delete()
            .inFilter('id', removedVariantIds);
      }
      if (removedServiceIds.isNotEmpty) {
        await supabase
            .from('service_variants')
            .delete()
            .inFilter('service_id', removedServiceIds);
        try {
          await supabase
              .from('barber_services')
              .delete()
              .inFilter('service_id', removedServiceIds);
        } catch (_) {}
        await supabase
            .from('services')
            .delete()
            .inFilter('id', removedServiceIds);
      }
      if (removedCatIds.isNotEmpty) {
        await supabase
            .from('salon_categories')
            .delete()
            .inFilter('id', removedCatIds);
      }

      // 2) Update existing rows, insert new ones.
      final failedUpdates = <String>[];
      for (int ci = 0; ci < _categories.length; ci++) {
        final cat = _categories[ci];
        // Defence in depth: clean every text again right before it is sent.
        final catDesc = _cleanText(
            (cat['description'] ?? '').toString(), _maxDescription,
            multiLine: true);
        final catData = <String, dynamic>{
          'display_name': _cleanText(
              (cat['display_name'] ?? '').toString(), _maxCategoryName),
          'description': catDesc.isEmpty ? null : catDesc,
          'icon_name': _isKnownIcon(cat['icon_name']?.toString())
              ? cat['icon_name']
              : 'content_cut',
          'color': _isHexColor(cat['color']?.toString())
              ? cat['color']
              : '#FF6B8B',
          'display_order': ci,
          'is_active': true,
        };

        int catId;
        if (cat['id'] is int) {
          catId = cat['id'] as int;
          final updated = await supabase
              .from('salon_categories')
              .update(catData)
              .eq('id', catId)
              .select('id');
          if (updated.isEmpty) {
            failedUpdates.add('category "${cat['display_name']}"');
          }
        } else {
          final inserted = await supabase
              .from('salon_categories')
              .insert({...catData, 'salon_id': widget.salonId})
              .select('id')
              .single();
          catId = inserted['id'] as int;
        }

        for (final svc in (cat['services'] as List)) {
          final svcDesc = _cleanText(
              (svc['description'] ?? '').toString(), _maxDescription,
              multiLine: true);
          final svcData = <String, dynamic>{
            'name':
                _cleanText((svc['name'] ?? '').toString(), _maxServiceName),
            'description': svcDesc.isEmpty ? null : svcDesc,
            'category_id': catId,
            'icon_name': _isKnownIcon(svc['icon_name']?.toString())
                ? svc['icon_name']
                : 'content_cut',
            'is_active': true,
          };

          int svcId;
          if (svc['id'] is int) {
            svcId = svc['id'] as int;
            final updated = await supabase
                .from('services')
                .update({
                  ...svcData,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', svcId)
                .select('id');
            if (updated.isEmpty) {
              failedUpdates.add('service "${svc['name']}"');
            }
          } else {
            final inserted = await supabase
                .from('services')
                .insert({
                  ...svcData,
                  'salon_id': widget.salonId,
                  'created_by': userId,
                })
                .select('id')
                .single();
            svcId = inserted['id'] as int;
          }

          for (final v in (svc['variants'] as List)) {
            final genderName = (v['gender_name'] as String? ?? 'Any').trim();
            final resolvedGenderId = genderName == 'Any'
                ? null
                : genderIdByName[genderName.toLowerCase()];

            final cleanVariantName =
                _cleanText((v['name'] ?? '').toString(), _maxVariantName);
            final variantData = <String, dynamic>{
              'salon_gender_id': resolvedGenderId,
              'salon_age_category_id': v['age_category_id'],
              'name': cleanVariantName.isEmpty ? null : cleanVariantName,
              'price': v['price_set'] == true ? v['price'] : null,
              'duration': ((v['duration'] as num?)?.toInt() ?? 0) == 0
                  ? null
                  : v['duration'],
              'is_active': true,
            };

            if (v['variant_id'] is int) {
              final updated = await supabase
                  .from('service_variants')
                  .update(variantData)
                  .eq('id', v['variant_id'] as int)
                  .select('id');
              if (updated.isEmpty) {
                failedUpdates.add(
                    'a variant of "${svc['name']}" (${_variantLabel(v)})');
              }
            } else {
              await supabase
                  .from('service_variants')
                  .insert({...variantData, 'service_id': svcId});
            }
          }
        }
      }

      // Refresh from the database in the background — no full-page spinner
      await _loadData(silent: true);

      if (!mounted) return;

      if (failedUpdates.isNotEmpty) {
        // The list you see now reflects the server's actual data — the
        // edits above never reached it, so nothing was lost, but nothing
        // was saved either.
        await showCustomAlert(
          context: context,
          title: "Some changes weren't saved",
          message:
              "New items saved fine, but ${failedUpdates.length} existing "
              "item${failedUpdates.length == 1 ? '' : 's'} could not be "
              'updated — most likely your account lacks UPDATE permission '
              '(a Supabase Row Level Security policy) on this table. '
              'Ask whoever manages the database to allow UPDATE for your '
              'role, then try again.\n\nAffected: ${failedUpdates.join(', ')}',
          isError: true,
        );
      } else {
        _showSnackBar(
          'Saved: ${_categories.length} categor${_categories.length == 1 ? 'y' : 'ies'}, '
          '$totalServices service${totalServices == 1 ? '' : 's'}, '
          '$totalVariants variant${totalVariants == 1 ? '' : 's'}',
          Colors.green,
        );
      }
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('Error saving: $e');
      if (!mounted) return;
      await showCustomAlert(
        context: context,
        title: "Couldn't save",
        message:
            '${_friendlyError(e)}\n\nYour changes are still on this screen. Fix the issue and press Save again.',
        isError: true,
      );
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // TREE VIEW
  // ============================================
  Widget _buildTreeCard() {
    final isDark = _isDark;
    final accent = widget.accentColor;
    final base = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
                accent.withValues(alpha: isDark ? 0.08 : 0.05), base),
            Color.alphaBlend(
                accent.withValues(alpha: isDark ? 0.16 : 0.11), base),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.account_tree_outlined,
                      size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your Services',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (_categories.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_categories.length} CATEGOR${_categories.length == 1 ? 'Y' : 'IES'}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Categories contain services. Services contain variants.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_categories.isEmpty) ...[
            // Nothing yet — clickable skeleton of the same tree shape.
            _buildAddLine(
              isDark: isDark,
              prefix: '└─',
              label: 'New Category',
              color: Colors.orange,
              onTap: () => _openCategoryDialog(),
            ),
            _buildAddLine(
              isDark: isDark,
              prefix: '   └─',
              label: 'New Service',
              color: Colors.blue,
              muted: true,
              onTap: () =>
                  _showSnackBar('Add a category first', Colors.orange),
            ),
            _buildAddLine(
              isDark: isDark,
              prefix: '      └─',
              label: 'New Variant',
              color: Colors.purple,
              muted: true,
              onTap: () => _showSnackBar(
                  'Add a category and service first', Colors.orange),
            ),
          ] else ...[
            // Every list ends with its own "+ New ..." line (└─), so real
            // items are always ├─ and the add button is always the last item.
            ..._categories.asMap().entries.expand((catEntry) {
              final catIndex = catEntry.key;
              final cat = catEntry.value;
              final catColor = _hexToColor(cat['color'] ?? '#FF6B8B');
              final catIcon = _iconFromName(cat['icon_name']);
              final services = cat['services'] as List;

              final widgets = <Widget>[
                _buildTreeLine(
                  isDark: isDark,
                  prefix: '├─ 📁',
                  icon: catIcon,
                  iconColor: catColor,
                  label: cat['display_name'] as String,
                  onEdit: () => _openCategoryDialog(editIndex: catIndex),
                  onDelete: () async {
                    final ok = await _confirmDelete(
                      title: 'Delete Category?',
                      message:
                          'Remove "${cat['display_name']}" and all its services?',
                    );
                    if (ok && mounted) {
                      // ✅ guard
                      setState(() => _categories.removeAt(catIndex));
                    }
                  },
                ),
              ];

              for (int si = 0; si < services.length; si++) {
                final svc = services[si];
                final svcIcon = _iconFromName(svc['icon_name']);
                final variants = svc['variants'] as List;

                widgets.add(_buildTreeLine(
                  isDark: isDark,
                  prefix: '│  ├─',
                  icon: svcIcon,
                  iconColor: Colors.orange,
                  label: svc['name'] as String,
                  onEdit: () => _openServiceDialog(
                    categoryIndex: catIndex,
                    editServiceIndex: si,
                  ),
                  onDelete: () async {
                    final ok = await _confirmDelete(
                      title: 'Delete Service?',
                      message: 'Remove "${svc['name']}" and its variants?',
                    );
                    if (ok && mounted) {
                      // ✅ guard
                      setState(() {
                        (_categories[catIndex]['services'] as List)
                            .removeAt(si);
                      });
                    }
                  },
                ));

                for (int vi = 0; vi < variants.length; vi++) {
                  final v = variants[vi];
                  widgets.add(_buildTreeLine(
                    isDark: isDark,
                    prefix: '│  │  ├─ ${_toCircledNumber(vi + 1)}',
                    icon: Icons.tune,
                    iconColor: Colors.purple,
                    // Only values that are set are shown. Long names wrap;
                    // details + price go on the line below.
                    label: _variantTitle(v),
                    details: _variantSubtitleParts(v),
                    trailingText:
                        v['price_set'] == true ? _formatPriceDisplay(v) : null,
                    onEdit: () => _openVariantDialog(
                      categoryIndex: catIndex,
                      serviceIndex: si,
                      editVariantIndex: vi,
                    ),
                    onDelete: () async {
                      final ok = await _confirmDelete(
                        title: 'Delete Variant?',
                        message:
                            'Remove this variant (${_variantLabel(v)})?',
                      );
                      if (ok && mounted) {
                        // ✅ guard
                        setState(() {
                          ((_categories[catIndex]['services']
                                      as List)[si]['variants']
                                  as List)
                              .removeAt(vi);
                        });
                      }
                    },
                  ));
                }

                // Last item of the variant list
                widgets.add(_buildAddLine(
                  isDark: isDark,
                  prefix: '│  │  └─',
                  label: 'New Variant',
                  color: Colors.purple,
                  onTap: () => _openVariantDialog(
                    categoryIndex: catIndex,
                    serviceIndex: si,
                  ),
                ));
              }

              // Last item of the service list
              widgets.add(_buildAddLine(
                isDark: isDark,
                prefix: '│  └─',
                label: 'New Service',
                color: Colors.blue,
                onTap: () => _openServiceDialog(categoryIndex: catIndex),
              ));

              return widgets;
            }),

            // Last item of the category list
            _buildAddLine(
              isDark: isDark,
              prefix: '└─',
              label: 'New Category',
              color: Colors.orange,
              onTap: () => _openCategoryDialog(),
            ),
          ],
        ],
      ),
    );
  }

  // A "+ New ..." button rendered as the final item of a tree list.
  Widget _buildAddLine({
    required bool isDark,
    required String prefix,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    final c = muted ? color.withValues(alpha: 0.55) : color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            prefix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white38 : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 12, color: c),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: c,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A single tree row: monospace connector prefix, small icon, label,
  // optional trailing price badge, optional edit/delete.
  Widget _buildTreeLine({
    required bool isDark,
    required String prefix,
    IconData? icon,
    Color? iconColor,
    required String label,
    List<String> details = const [],
    String? trailingText,
    bool trailingMuted = false,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final detailColor = isDark ? Colors.white54 : Colors.grey[600];
    final hasSecondLine = details.isNotEmpty || trailingText != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prefix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white38 : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 6),
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 13, color: iconColor),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name: wraps to 2 lines, then "…"
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white70 : Colors.grey[800],
                  ),
                ),
                // Details + price always get their own line, so they can
                // never be pushed off a narrow phone screen.
                if (hasSecondLine)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (details.isNotEmpty)
                            TextSpan(
                              text: details.join(' • '),
                              style: TextStyle(
                                  fontSize: 10.5, color: detailColor),
                            ),
                          if (details.isNotEmpty && trailingText != null)
                            TextSpan(
                              text: ' • ',
                              style: TextStyle(
                                  fontSize: 10.5, color: detailColor),
                            ),
                          if (trailingText != null)
                            TextSpan(
                              text: trailingText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: trailingMuted
                                    ? (isDark
                                        ? Colors.white38
                                        : Colors.grey[500])
                                    : Colors.teal,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (onEdit != null)
            _iconAction(
              icon: Icons.edit_outlined,
              color: Colors.blue,
              tooltip: 'Edit',
              size: 14,
              onTap: onEdit,
            ),
          if (onDelete != null)
            _iconAction(
              icon: Icons.delete_outline,
              color: Colors.red,
              tooltip: 'Delete',
              size: 14,
              onTap: onDelete,
            ),
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

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    double size = 16,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size, color: color),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      splashRadius: 15,
    );
  }

  // ============================================
  // SAVE BUTTON
  // ============================================
  Widget _buildSaveButton() {
    final isDark = _isDark;
    final hasData = _categories.isNotEmpty;

    return Center(
      child: SizedBox(
        height: 42,
        child: ElevatedButton(
          onPressed: (_isLoading || !hasData) ? null : _saveAllServices,
          style: ElevatedButton.styleFrom(
            backgroundColor: hasData
                ? widget.accentColor
                : (isDark ? Colors.grey[800] : Colors.grey[300]),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 26),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(21)),
            elevation: 1,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save,
                        size: 18,
                        color: hasData
                            ? Colors.white
                            : (isDark ? Colors.white60 : Colors.white70)),
                    const SizedBox(width: 8),
                    Text(
                      'Save All Services',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hasData
                            ? Colors.white
                            : (isDark ? Colors.white60 : Colors.white70),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ============================================
  // BUILD
  // ============================================
  @override
  Widget build(BuildContext context) {
    _isDark = context.isDarkMode;

    if (_isLoadingData) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTreeCard(),
        _buildSaveButton(),
      ],
    );
  }
}