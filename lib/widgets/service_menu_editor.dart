import 'package:flutter/material.dart';
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

      setState(() {
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
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
                'id, service_id, price, duration, salon_gender_id, salon_age_category_id')
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

      setState(() {
        _categories
          ..clear()
          ..addAll(loadedCategories);
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        _showSnackBar(_friendlyError(e), Colors.red);
      }
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
  // FRIENDLY ERRORS + DUPLICATE CHECKS
  // ============================================
  String _friendlyError(Object e) {
    if (e is PostgrestException) {
      switch (e.code) {
        case '23505':
          return 'Two items are exactly the same (for example a service with the same gender, age category and duration). Please remove or change the duplicate.';
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
    int? ignoreIndex,
  }) {
    for (int i = 0; i < variants.length; i++) {
      if (i == ignoreIndex) continue;
      final v = variants[i];
      if (v['gender_id'] == gender &&
          v['age_category_id'] == age &&
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
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(
                            color:
                                isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          labelText: 'Category Name *',
                          hintText: 'e.g., Hair, Nails, Spa',
                          prefixIcon: Icon(Icons.category,
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
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
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    Navigator.pop(dialogContext, {
                      'display_name': name,
                      'description': descController.text.trim(),
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
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(
                            color:
                                isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          labelText: 'Service Name *',
                          hintText: 'e.g., Hair Cut, Facial',
                          prefixIcon: Icon(Icons.build,
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
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
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    Navigator.pop(dialogContext, {
                      'name': name,
                      'description': descController.text.trim(),
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

    setState(() {
      final services = _categories[categoryIndex]['services'] as List;
      if (editServiceIndex != null) {
        services[editServiceIndex] = {
          ...services[editServiceIndex],
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
          ? (existing['price'] as double).toString()
          : '',
    );
    final durationController = TextEditingController(
      text: existing != null && (existing['duration'] as int) > 0
          ? (existing['duration'] as int).toString()
          : '',
    );

    // Temporary new age category fields
    final newAgeNameController = TextEditingController();
    final newAgeMinController = TextEditingController(text: '0');
    final newAgeMaxController = TextEditingController(text: '100');
    bool showNewAgeForm = false;
    String? variantError;

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
                      // Gender
                      Text(
                        'Gender',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
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
                      const SizedBox(height: 16),

                      // Age Category
                      Row(
                        children: [
                          Text(
                            'Age Category',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white70 : Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setDialogState(() {
                              showNewAgeForm = !showNewAgeForm;
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
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                            ),
                          ),
                        ],
                      ),
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
                      if (showNewAgeForm) ...[
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
                              TextFormField(
                                controller: newAgeNameController,
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87),
                                decoration: InputDecoration(
                                  labelText: 'Age Name *',
                                  hintText: 'e.g., Adult',
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
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: newAgeMinController,
                                      keyboardType:
                                          TextInputType.number,
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87),
                                      decoration: InputDecoration(
                                        labelText: 'Min',
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
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87),
                                      decoration: InputDecoration(
                                        labelText: 'Max',
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
                                    final name = newAgeNameController.text
                                        .trim();
                                    final min = int.tryParse(
                                        newAgeMinController.text.trim());
                                    final max = int.tryParse(
                                        newAgeMaxController.text.trim());
                                    if (name.isEmpty ||
                                        min == null ||
                                        max == null ||
                                        min > max) {
                                      return;
                                    }

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
                                        showNewAgeForm = false;
                                      });
                                    } catch (e) {
                                      debugPrint('Error adding age: $e');
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
                      const SizedBox(height: 16),

                      // Price & Duration
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87),
                              decoration: InputDecoration(
                                labelText: 'Price (optional)',
                                hintText: '0',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
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
                                    const BoxConstraints(
                                        minWidth: 50, minHeight: 20),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
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
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: durationController,
                              onChanged: (_) {
                                if (variantError != null) {
                                  setDialogState(() => variantError = null);
                                }
                              },
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87),
                              decoration: InputDecoration(
                                labelText: 'Duration (mins)',
                                hintText: '30',
                                prefixIcon: Icon(Icons.timer,
                                    size: 18,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
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
                          ),
                        ],
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
                    if (selectedGenderId == null &&
                        selectedAgeId == null &&
                        priceController.text.trim().isEmpty &&
                        durationController.text.trim().isEmpty) {
                      return;
                    }

                    final priceText = priceController.text.trim();
                    final durationText = durationController.text.trim();
                    final priceSet = priceText.isNotEmpty;
                    final price =
                        priceSet ? double.tryParse(priceText) ?? 0.0 : 0.0;
                    final duration = durationText.isNotEmpty
                        ? int.tryParse(durationText) ?? 0
                        : 0;

                    // Block duplicates right here, before they reach the list
                    if (_isDuplicateVariant(
                      service['variants'] as List,
                      gender: selectedGenderId,
                      age: selectedAgeId,
                      duration: duration,
                      ignoreIndex: editVariantIndex,
                    )) {
                      setDialogState(() {
                        variantError =
                            'This service already has a variant with the same gender, age category and duration. Change one of them, or edit the existing variant instead.';
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

    setState(() {
      final variants = (service['variants'] as List);
      if (editVariantIndex != null) {
        variants[editVariantIndex] = {
          ...variants[editVariantIndex],
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
                '"${svc['name']}" (${cat['display_name']}) has two variants with the same gender, age category and duration. Please remove or change one of them.',
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
      for (int ci = 0; ci < _categories.length; ci++) {
        final cat = _categories[ci];
        final catData = <String, dynamic>{
          'display_name': cat['display_name'],
          'description': (cat['description'] as String).isEmpty
              ? null
              : cat['description'],
          'icon_name': cat['icon_name'],
          'color': cat['color'],
          'display_order': ci,
          'is_active': true,
        };

        int catId;
        if (cat['id'] is int) {
          catId = cat['id'] as int;
          await supabase
              .from('salon_categories')
              .update(catData)
              .eq('id', catId);
        } else {
          final inserted = await supabase
              .from('salon_categories')
              .insert({...catData, 'salon_id': widget.salonId})
              .select('id')
              .single();
          catId = inserted['id'] as int;
        }

        for (final svc in (cat['services'] as List)) {
          final svcData = <String, dynamic>{
            'name': svc['name'],
            'description': (svc['description'] as String).isEmpty
                ? null
                : svc['description'],
            'category_id': catId,
            'icon_name': svc['icon_name'],
            'is_active': true,
          };

          int svcId;
          if (svc['id'] is int) {
            svcId = svc['id'] as int;
            await supabase
                .from('services')
                .update({
                  ...svcData,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', svcId);
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

            final variantData = <String, dynamic>{
              'salon_gender_id': resolvedGenderId,
              'salon_age_category_id': v['age_category_id'],
              'price': v['price_set'] == true ? v['price'] : null,
              'duration': ((v['duration'] as num?)?.toInt() ?? 0) == 0
                  ? null
                  : v['duration'],
              'is_active': true,
            };

            if (v['variant_id'] is int) {
              await supabase
                  .from('service_variants')
                  .update(variantData)
                  .eq('id', v['variant_id'] as int);
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
      _showSnackBar(
        'Saved: ${_categories.length} categor${_categories.length == 1 ? 'y' : 'ies'}, '
        '$totalServices service${totalServices == 1 ? '' : 's'}, '
        '$totalVariants variant${totalVariants == 1 ? '' : 's'}',
        Colors.green,
      );
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
                child: Icon(Icons.account_tree_outlined, size: 18, color: accent),
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
                    if (ok) {
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
                    if (ok) {
                      setState(() {
                        (_categories[catIndex]['services'] as List)
                            .removeAt(si);
                      });
                    }
                  },
                ));

                for (int vi = 0; vi < variants.length; vi++) {
                  final v = variants[vi];
                  final duration = (v['duration'] as num?)?.toInt() ?? 0;
                  widgets.add(_buildTreeLine(
                    isDark: isDark,
                    prefix: '│  │  ├─ ${_toCircledNumber(vi + 1)}',
                    icon: Icons.tune,
                    iconColor: Colors.purple,
                    label:
                        '${v['gender_name']} • ${v['age_category_name']} • ${duration == 0 ? '—' : '$duration min'}',
                    trailingText: _formatPriceDisplay(v),
                    trailingMuted: v['price_set'] != true,
                    onEdit: () => _openVariantDialog(
                      categoryIndex: catIndex,
                      serviceIndex: si,
                      editVariantIndex: vi,
                    ),
                    onDelete: () async {
                      final ok = await _confirmDelete(
                        title: 'Delete Variant?',
                        message:
                            'Remove this variant (${v['gender_name']} • ${v['age_category_name']})?',
                      );
                      if (ok) {
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
    String? trailingText,
    bool trailingMuted = false,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
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
          if (icon != null) ...[
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: trailingMuted
                    ? (isDark ? Colors.white38 : Colors.grey[500])
                    : Colors.teal,
              ),
            ),
            const SizedBox(width: 6),
          ],
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