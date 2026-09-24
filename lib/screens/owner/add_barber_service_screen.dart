// meka use karanne baber list screen eken edit service gihin service baberta add karaddi
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';
import '../../services/currency_service.dart';

class AddBarberServiceScreen extends StatefulWidget {
  final String salonId;
  final String barberId;
  final int? salonBarberId;
  final String? barberName;

  const AddBarberServiceScreen({
    super.key,
    required this.salonId,
    required this.barberId,
    this.salonBarberId,
    this.barberName,
  });

  @override
  State<AddBarberServiceScreen> createState() => _AddBarberServiceScreenState();
}

class _AddBarberServiceScreenState extends State<AddBarberServiceScreen> {
  final supabase = Supabase.instance.client;

  // ==================== ✅ CURRENCY SERVICE ====================
  final CurrencyService _currencyService = CurrencyService.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _services = [];
  final Map<String, Set<int>> _selectedVariants = {};
  int? _salonBarberId;

  // ==================== ✅ CURRENCY STATE ====================
  String _salonCurrencyCode = 'LKR';

  // For search/filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  // For expansion state
  final Set<String> _expandedServices = {};

  // Maps for lookups
  Map<int, String> _genderMap = {};
  Map<int, Map<String, dynamic>> _ageCategoryMap = {};
  Map<int, Map<String, dynamic>> _categoryMap = {};

  // ✅ Android 16: Responsive screen variables
  bool _isWeb = false;
  bool _isTablet = false;
  double _screenWidth = 0;

  // ==================== ✅ CURRENCY HELPERS ====================
  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_salonCurrencyCode);

  String _formatPrice(dynamic price) {
    if (price == null) return '$_salonCurrencySymbol 0';
    return _currencyService.format(
      price: price,
      currencyCode: _salonCurrencyCode,
    );
  }

  String _formatPriceRange(dynamic minPrice, dynamic maxPrice) {
    if (minPrice == null || maxPrice == null) {
      return '${_salonCurrencySymbol}0';
    }
    if (minPrice == maxPrice) {
      return _formatPrice(minPrice);
    }
    return '${_formatPrice(minPrice)} - ${_formatPrice(maxPrice)}';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  // ✅ Android 16: Check screen size for responsive layout
  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;
    final width = size.width;

    if (_isTablet != isTablet || _isWeb != isWeb || _screenWidth != width) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
        _screenWidth = width;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final salonIdInt = int.parse(widget.salonId);

      // ==================== ✅ STEP 0: Load salon currency ====================
      try {
        final salonCurrencyResponse = await supabase
            .from('salons')
            .select('currency_code')
            .eq('id', salonIdInt)
            .single();

        if (mounted) {
          setState(() {
            _salonCurrencyCode =
                salonCurrencyResponse['currency_code'] as String? ?? 'LKR';
          });
        }
        debugPrint('✅ Salon currency loaded: $_salonCurrencyCode');
      } catch (e) {
        debugPrint('⚠️ Could not load salon currency, using LKR: $e');
      }

      // ✅ STEP 1: Check if barber has active role in user_roles
      final barberRoleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', widget.barberId)
          .eq('role_id', 2)
          .maybeSingle();

      if (barberRoleCheck == null) {
        throw Exception(
          'Barber role not found. Please assign barber role first.',
        );
      }

      if (barberRoleCheck['status'] != 'active') {
        throw Exception(
          'Barber account is ${barberRoleCheck['status']}. Please reactivate the barber first.',
        );
      }

      // ✅ STEP 2: Check if barber profile is active and not blocked
      final barberProfileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', widget.barberId)
          .maybeSingle();

      if (barberProfileCheck != null) {
        if (barberProfileCheck['is_blocked'] == true) {
          throw Exception('Barber account is blocked. Please contact support.');
        }
        if (barberProfileCheck['is_active'] == false) {
          throw Exception(
            'Barber profile is inactive. Please reactivate the barber first.',
          );
        }
      }

      // Step 3: Get salon_barber_id if not provided
      if (widget.salonBarberId == null) {
        final salonBarberResponse = await supabase
            .from('salon_barbers')
            .select('id')
            .eq('barber_id', widget.barberId)
            .eq('salon_id', salonIdInt)
            .eq('status', 'active')
            .maybeSingle();

        if (salonBarberResponse != null) {
          _salonBarberId = salonBarberResponse['id'] as int;
        } else {
          throw Exception('Barber not found in this salon');
        }
      } else {
        _salonBarberId = widget.salonBarberId;
      }

      // Step 4: Load genders
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _genderMap = {};
      for (var g in gendersResponse) {
        _genderMap[g['id']] = g['display_name'];
      }

      // Step 5: Load age categories
      final ageCategoriesResponse = await supabase
          .from('salon_age_categories')
          .select('id, display_name, min_age, max_age')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _ageCategoryMap = {};
      for (var a in ageCategoriesResponse) {
        _ageCategoryMap[a['id']] = {
          'display_name': a['display_name'],
          'min_age': a['min_age'],
          'max_age': a['max_age'],
        };
      }

      // Step 6: Load categories
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _categoryMap = {};
      for (var c in categoriesResponse) {
        _categoryMap[c['id']] = {
          'display_name': c['display_name'],
          'icon_name': c['icon_name'] ?? 'build',
          'color': c['color'] ?? '#FF6B8B',
        };
      }

      // Step 7: Get already assigned services
      final existingServices = await supabase
          .from('barber_services')
          .select('service_id, variant_id')
          .eq('salon_barber_id', _salonBarberId!);

      final Set<String> assignedServiceKeys = {};
      for (var item in existingServices) {
        if (item['variant_id'] == null) {
          assignedServiceKeys.add('service_${item['service_id']}');
        } else {
          assignedServiceKeys.add('variant_${item['variant_id']}');
        }
      }

      // Step 8: Load services
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, category_id, icon_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('name');

      // Step 9: Load variants
      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, service_id, price, duration, salon_gender_id, salon_age_category_id',
          )
          .eq('is_active', true);

      // Group variants by service
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (var variant in variantsResponse) {
        final serviceId = variant['service_id'] as int;
        if (!variantsByService.containsKey(serviceId)) {
          variantsByService[serviceId] = [];
        }

        final genderId = variant['salon_gender_id'];
        final genderName = _genderMap[genderId] ?? 'Unknown';

        final ageId = variant['salon_age_category_id'];
        final ageData =
            _ageCategoryMap[ageId] ??
            {'display_name': 'Unknown', 'min_age': 0, 'max_age': 0};
        final ageName =
            '${ageData['display_name']} (${ageData['min_age']}-${ageData['max_age']} yrs)';

        final variantId = variant['id'] as int;

        variantsByService[serviceId]!.add({
          'id': variantId,
          'price': variant['price'],
          'duration': variant['duration'],
          'gender_id': genderId,
          'gender_name': genderName,
          'age_category_id': ageId,
          'age_name': ageName,
          'display_text': '$genderName • $ageName',
          'isAssigned': assignedServiceKeys.contains('variant_$variantId'),
        });
      }

      // Step 10: Build services list
      final List<Map<String, dynamic>> processedServices = [];
      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final variants = variantsByService[serviceId] ?? [];
        final categoryId = service['category_id'];
        final category =
            _categoryMap[categoryId] ??
            {'display_name': 'Other', 'icon_name': 'build', 'color': '#FF6B8B'};
        final categoryName = category['display_name'];

        variants.sort((a, b) {
          if (a['gender_name'] != b['gender_name']) {
            return a['gender_name'].compareTo(b['gender_name']);
          }
          return a['age_name'].compareTo(b['age_name']);
        });

        final isFullServiceAssigned = assignedServiceKeys.contains(
          'service_$serviceId',
        );
        final allVariantsAssigned =
            variants.isNotEmpty &&
            variants.every((v) => v['isAssigned'] == true);

        processedServices.add({
          'id': serviceId,
          'id_str': serviceId.toString(),
          'name': service['name'] ?? 'Unknown',
          'category_id': categoryId,
          'category_name': categoryName,
          'category_icon': category['icon_name'],
          'category_color': category['color'],
          'description': service['description'] ?? '',
          'icon_name': service['icon_name'] ?? category['icon_name'],
          'variants': variants,
          'hasVariants': variants.isNotEmpty,
          'variantCount': variants.length,
          'isFullServiceAssigned': isFullServiceAssigned,
          'allVariantsAssigned': allVariantsAssigned,
          'minPrice': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a < b ? a : b)
              : 0,
          'maxPrice': variants.isNotEmpty
              ? variants
                    .map((v) => v['price'] as double)
                    .reduce((a, b) => a > b ? a : b)
              : 0,
        });
      }

      setState(() {
        _services = processedServices;
      });
    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      if (mounted) {
        _showSnackBar('Error: ${e.toString()}', context.errorColor);
        if (e.toString().contains('inactive') ||
            e.toString().contains('blocked')) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleVariant(String serviceId, int variantId) {
    setState(() {
      if (!_selectedVariants.containsKey(serviceId)) {
        _selectedVariants[serviceId] = {};
      }

      if (_selectedVariants[serviceId]!.contains(variantId)) {
        _selectedVariants[serviceId]!.remove(variantId);
        if (_selectedVariants[serviceId]!.isEmpty) {
          _selectedVariants.remove(serviceId);
        }
      } else {
        _selectedVariants[serviceId]!.add(variantId);
      }
    });
  }

  void _toggleFullService(String serviceId) {
    setState(() {
      if (_selectedVariants.containsKey(serviceId)) {
        _selectedVariants.remove(serviceId);
      } else {
        _selectedVariants[serviceId] = {};
      }
    });
  }

  void _toggleExpand(String serviceId) {
    setState(() {
      if (_expandedServices.contains(serviceId)) {
        _expandedServices.remove(serviceId);
      } else {
        _expandedServices.add(serviceId);
      }
    });
  }

  bool _isVariantSelected(String serviceId, int variantId) {
    return _selectedVariants[serviceId]?.contains(variantId) ?? false;
  }

  bool _isFullServiceSelected(String serviceId) {
    return _selectedVariants.containsKey(serviceId) &&
        _selectedVariants[serviceId]!.isEmpty;
  }

  int _getSelectedCount() {
    int count = 0;
    _selectedVariants.forEach((serviceId, variants) {
      if (variants.isEmpty) {
        count += 1;
      } else {
        count += variants.length;
      }
    });
    return count;
  }

  Future<void> _saveServices() async {
    if (_selectedVariants.isEmpty) {
      _showSnackBar('Please select at least one service', context.warningColor);
      return;
    }

    if (_salonBarberId == null) {
      _showSnackBar('Barber not found in this salon', context.errorColor);
      return;
    }

    setState(() => _isSaving = true);

    try {
      int addedCount = 0;

      for (var entry in _selectedVariants.entries) {
        final serviceId = int.parse(entry.key);
        final variantIds = entry.value;

        if (variantIds.isEmpty) {
          await supabase.from('barber_services').insert({
            'salon_barber_id': _salonBarberId!,
            'service_id': serviceId,
            'variant_id': null,
          });
          addedCount++;
        } else {
          for (int variantId in variantIds) {
            await supabase.from('barber_services').insert({
              'salon_barber_id': _salonBarberId!,
              'service_id': serviceId,
              'variant_id': variantId,
            });
            addedCount++;
          }
        }
      }

      if (mounted) {
        _showSnackBar(
          'Successfully added $addedCount service(s)',
          context.successColor,
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Error saving services: $e');
      if (mounted) {
        _showSnackBar('Error saving services: $e', context.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<String> get _categories {
    final categories = _services
        .map((s) => s['category_name'] as String)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((service) {
      if (_selectedCategory != 'all' &&
          service['category_name'] != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final name = (service['name'] as String).toLowerCase();
        if (!name.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Color _getCategoryColor(BuildContext context, String categoryName) {
    final isDark = context.isDarkMode;
    switch (categoryName.toLowerCase()) {
      case 'hair':
        return isDark ? const Color(0xFF60A5FA) : const Color(0xFF3B82F6);
      case 'skin':
        return AppTheme.primary;
      case 'grooming':
        return isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
      case 'wellness':
        return AppTheme.success;
      case 'nails':
        return isDark ? const Color(0xFFC084FC) : const Color(0xFFA855F7);
      default:
        return AppTheme.primary;
    }
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
      default:
        return Icons.category;
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

  // ✅ Alternating card color - uses context colors
  Color _getCardColor(BuildContext context, int index) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;

    if (isDark) {
      final opacity = 0.05 + (index % 8) * 0.01;
      return context.cardColor.withValues(alpha: opacity);
    } else {
      final opacity = 0.03 + (index % 8) * 0.008;
      return primaryColor.withValues(alpha: opacity);
    }
  }

  // ============================================================
  // ✅ BUILD METHOD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    _checkScreenSize();

    final primaryColor = context.primaryColor;
    final backgroundColor = context.backgroundColor;

    final int selectedCount = _getSelectedCount();
    final double padding = _isWeb ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Services',
              style: TextStyle(
                fontSize: _isWeb ? 20 : 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.barberName != null)
              Text(
                'for ${widget.barberName}',
                style: TextStyle(
                  fontSize: _isWeb ? 14 : 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          // ✅ Currency badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _salonCurrencySymbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _salonCurrencyCode,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (selectedCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '$selectedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          if (selectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.save, color: Colors.white),
                      onPressed: _saveServices,
                      tooltip: 'Save Services',
                    ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : Column(
                children: [
                  _buildSearchAndFilterBar(padding),
                  Expanded(
                    child: _filteredServices.isEmpty
                        ? _buildEmptyState()
                        : _isWeb
                            ? _buildWebView(padding, selectedCount)
                            : _buildMobileView(padding, selectedCount),
                  ),
                ],
              ),
      ),
      floatingActionButton: selectedCount > 0 && !_isWeb
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveServices,
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save ($selectedCount)'),
            )
          : null,
    );
  }

  // ============================================================
  // ✅ SEARCH AND FILTER BAR
  // ============================================================
  Widget _buildSearchAndFilterBar(double padding) {
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final primaryColor = context.primaryColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;

    return Container(
      padding: EdgeInsets.all(padding),
      color: context.backgroundColor,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: 'Search services...',
              hintStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.search, color: secondaryTextColor),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: secondaryTextColor),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryColor, width: 2),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: _isWeb ? 16 : 12,
              ),
              filled: true,
              fillColor: cardColor,
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
                      fontSize: _isWeb ? 14 : 12,
                      color: _selectedCategory == 'all'
                          ? primaryColor
                          : secondaryTextColor,
                    ),
                  ),
                  selected: _selectedCategory == 'all',
                  onSelected: (_) => setState(() => _selectedCategory = 'all'),
                  selectedColor: primaryColor.withValues(alpha: 0.2),
                  checkmarkColor: primaryColor,
                  backgroundColor: cardColor,
                  side: BorderSide(color: borderColor),
                ),
                const SizedBox(width: 8),
                ..._categories.map((category) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        category[0].toUpperCase() + category.substring(1),
                        style: TextStyle(
                          fontSize: _isWeb ? 14 : 12,
                          color: _selectedCategory == category
                              ? primaryColor
                              : secondaryTextColor,
                        ),
                      ),
                      selected: _selectedCategory == category,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = category),
                      selectedColor: primaryColor.withValues(alpha: 0.2),
                      checkmarkColor: primaryColor,
                      backgroundColor: cardColor,
                      side: BorderSide(color: borderColor),
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

  // ============================================================
  // ✅ EMPTY STATE
  // ============================================================
  Widget _buildEmptyState() {
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: _isWeb ? 80 : 64,
            color: secondaryTextColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No services found',
            style: TextStyle(
              fontSize: _isWeb ? 20 : 18,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedCategory != 'all'
                ? 'Try adjusting your search or filters'
                : 'No services available',
            style: TextStyle(
              fontSize: _isWeb ? 16 : 14,
              color: secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ WEB VIEW
  // ============================================================
  Widget _buildWebView(double padding, int selectedCount) {
    final primaryColor = context.primaryColor;
    final cardColor = context.cardColor;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedCount > 0) ...[
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: primaryColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: primaryColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$selectedCount service${selectedCount > 1 ? 's' : ''} selected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: context.textColor,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _saveServices,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.9,
                ),
                itemCount: _filteredServices.length,
                itemBuilder: (context, index) {
                  final service = _filteredServices[index];
                  return _buildServiceCardWeb(service, index);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ WEB SERVICE CARD
  // ============================================================
  Widget _buildServiceCardWeb(Map<String, dynamic> service, int index) {
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;
    final successColor = context.successColor;
    final isDark = context.isDarkMode;

    final serviceId = service['id_str'];
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
    final allVariantsAssigned = service['allVariantsAssigned'] == true;
    final isFullServiceSelected = _isFullServiceSelected(serviceId);
    final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
    final categoryColor = _getCategoryColor(context, service['category_name']);
    final cardBgColor = _getCardColor(context, index);

    final isCompletelyAssigned = !hasVariants
        ? isFullServiceAssigned
        : allVariantsAssigned;

    final isSelected = isFullServiceSelected || selectedVariantCount > 0;

    return Opacity(
      opacity: isCompletelyAssigned ? 0.7 : 1.0,
      child: Card(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? primaryColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        elevation: isSelected ? 4 : 2,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cardBgColor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.4),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark ? cardColor : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Icon(
                          _getIconForName(service['icon_name']),
                          color: primaryColor,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: categoryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  service['category_name'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: categoryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (hasVariants) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${variants.length} variants',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!hasVariants)
                      Checkbox(
                        value: _selectedVariants.containsKey(serviceId),
                        onChanged: isCompletelyAssigned
                            ? null
                            : (_) => _toggleFullService(serviceId),
                        activeColor: primaryColor,
                      ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasVariants && !isCompletelyAssigned) ...[
                        Text(
                          _formatPriceRange(
                            service['minPrice'],
                            service['maxPrice'],
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      if (isCompletelyAssigned)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: successColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: successColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Already assigned',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: successColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (!hasVariants && !isCompletelyAssigned) ...[
                        const Spacer(),
                        Center(
                          child: Text(
                            'Full Service',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ],

                      if (hasVariants) ...[
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: variants.length,
                            itemBuilder: (context, vIndex) {
                              final variant = variants[vIndex];
                              final variantId = variant['id'] as int;
                              final isAssigned = variant['isAssigned'] == true;
                              final isVarSelected = _isVariantSelected(
                                serviceId,
                                variantId,
                              );

                              return GestureDetector(
                                onTap: isAssigned || isCompletelyAssigned
                                    ? null
                                    : () =>
                                          _toggleVariant(serviceId, variantId),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isVarSelected
                                        ? primaryColor.withValues(alpha: 0.1)
                                        : (isDark
                                              ? cardColor.withValues(alpha: 0.5)
                                              : Colors.white.withValues(
                                                  alpha: 0.6,
                                                )),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isVarSelected
                                          ? primaryColor
                                          : borderColor,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isVarSelected
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        size: 14,
                                        color: isVarSelected
                                            ? primaryColor
                                            : secondaryTextColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              variant['display_text'],
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isVarSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: isVarSelected
                                                    ? primaryColor
                                                    : textColor,
                                              ),
                                            ),
                                            Text(
                                              '${_formatPrice(variant['price'])} • ${variant['duration']} min',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isAssigned)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: successColor.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Assigned',
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: successColor,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                      if (selectedVariantCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '$selectedVariantCount variant${selectedVariantCount > 1 ? 's' : ''} selected',
                            style: TextStyle(
                              fontSize: 10,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
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
    );
  }

  // ============================================================
  // ✅ MOBILE VIEW
  // ============================================================
  Widget _buildMobileView(double padding, int selectedCount) {
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;
    final successColor = context.successColor;
    final isDark = context.isDarkMode;

    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _filteredServices.length,
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        final serviceId = service['id_str'];
        final variants = service['variants'] as List;
        final hasVariants = variants.isNotEmpty;
        final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
        final allVariantsAssigned = service['allVariantsAssigned'] == true;
        final isFullServiceSelected = _isFullServiceSelected(serviceId);
        final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
        final isExpanded = _expandedServices.contains(serviceId);
        final categoryColor = _getCategoryColor(
          context,
          service['category_name'],
        );
        final cardBgColor = _getCardColor(context, index);

        final isCompletelyAssigned = !hasVariants
            ? isFullServiceAssigned
            : allVariantsAssigned;

        final isSelected = isFullServiceSelected || selectedVariantCount > 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? primaryColor : borderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cardBgColor,
            ),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  InkWell(
                    onTap: hasVariants ? () => _toggleExpand(serviceId) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? cardColor
                                  : Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Icon(
                                _getIconForName(service['icon_name']),
                                color: primaryColor,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service['name'],
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    fontSize: 14,
                                    color: isCompletelyAssigned
                                        ? secondaryTextColor
                                        : textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: categoryColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        service['category_name'],
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: categoryColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (hasVariants) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '${variants.length} variants',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!hasVariants)
                            Checkbox(
                              value: _selectedVariants.containsKey(serviceId),
                              onChanged: isCompletelyAssigned
                                  ? null
                                  : (_) => _toggleFullService(serviceId),
                              activeColor: primaryColor,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (hasVariants)
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                              color: selectedVariantCount > 0
                                  ? primaryColor
                                  : secondaryTextColor,
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (isExpanded && hasVariants)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        children: variants.map((variant) {
                          final variantId = variant['id'] as int;
                          final isAssigned = variant['isAssigned'] == true;
                          final isVarSelected = _isVariantSelected(
                            serviceId,
                            variantId,
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isVarSelected
                                  ? primaryColor.withValues(alpha: 0.08)
                                  : (isDark
                                        ? cardColor.withValues(alpha: 0.5)
                                        : Colors.white.withValues(alpha: 0.6)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isVarSelected
                                    ? primaryColor
                                    : borderColor,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 0,
                              ),
                              leading: Checkbox(
                                value: isVarSelected,
                                onChanged: isAssigned || isCompletelyAssigned
                                    ? null
                                    : (_) =>
                                          _toggleVariant(serviceId, variantId),
                                activeColor: primaryColor,
                                visualDensity: VisualDensity.compact,
                              ),
                              title: Text(
                                variant['display_text'],
                                style: TextStyle(
                                  fontWeight: isVarSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 12,
                                  color: textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_formatPrice(variant['price'])} • ${variant['duration']} min',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: secondaryTextColor,
                                ),
                              ),
                              trailing: isAssigned
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: successColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Assigned',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: successColor,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}