import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';
import '../../services/currency_service.dart';

// ============================================================
// ✅ Custom exceptions for cleaner error handling 
// ============================================================
class BarberRoleNotFoundException implements Exception {
  final String message;
  BarberRoleNotFoundException(this.message);
  @override
  String toString() => message;
}

class BarberInactiveException implements Exception {
  final String message;
  BarberInactiveException(this.message);
  @override
  String toString() => message;
}

class BarberBlockedException implements Exception {
  final String message;
  BarberBlockedException(this.message);
  @override
  String toString() => message;
}

class BarberNotInSalonException implements Exception {
  final String message;
  BarberNotInSalonException(this.message);
  @override
  String toString() => message;
}

class InvalidSalonIdException implements Exception {
  final String message;
  InvalidSalonIdException(this.message);
  @override
  String toString() => message;
}

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

  // ==================== ✅ ROLE (owner only) ====================
  // What is stored now ...
  bool _canSetRole = false; // true only for the salon OWNER
  String _currentRole = 'barber'; // barber | cashier | admin
  bool _currentTakes = true; // false = desk-only (no appointments)
  // ... and what the check boxes show now (can be edited)
  bool _isBarber = true;
  bool _isCashier = false;
  bool _isAdmin = false;

  /// Was Cashier ticked by the user BEFORE Admin was ticked? (Admin ticks
  /// Cashier automatically; un-ticking Admin restores the user's choice.)
  bool _cashierBeforeAdmin = false;

  /// This person already has services in this salon (kept in the database
  /// even while desk-only). Going desk-only -> barber again then needs no
  /// new services.
  bool _hasKeptServices = false;

  // ==================== ✅ CURRENCY STATE ====================
  String _salonCurrencyCode = 'LKR';

  // For search/filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  // For expansion state (all services with variants start expanded)
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
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ FIX: Only called here, not in build
    _checkScreenSize();
  }

  // ✅ Check screen size for responsive layout
  // ✅ FIX: Uses `addPostFrameCallback` to avoid setState during build
  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;
    final width = size.width;

    if (_isTablet != isTablet || _isWeb != isWeb || _screenWidth != width) {
      // ✅ Safe setState via post-frame callback
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isTablet = isTablet;
            _isWeb = isWeb;
            _screenWidth = width;
          });
        }
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
    if (mounted) setState(() => _isLoading = true);

    try {
      // ✅ Use tryParse instead of parse
      final salonIdInt = int.tryParse(widget.salonId);
      if (salonIdInt == null) {
        throw InvalidSalonIdException(
          'Invalid salon ID: ${widget.salonId}',
        );
      }

      // ==================== STEP 0: Load salon currency ====================
      try {
        final salonCurrencyResponse = await supabase
            .from('salons')
            .select('currency_code')
            .eq('id', salonIdInt)
            .maybeSingle();

        if (mounted && salonCurrencyResponse != null) {
          setState(() {
            _salonCurrencyCode =
                salonCurrencyResponse['currency_code'] as String? ?? 'LKR';
          });
        }
        debugPrint('✅ Salon currency loaded: $_salonCurrencyCode');
      } catch (e) {
        debugPrint('⚠️ Could not load salon currency, using LKR: $e');
      }

      // ==================== STEP 1: Check barber role ====================
      final barberRoleCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', widget.barberId)
          .eq('role_id', 2)
          .maybeSingle();

      if (barberRoleCheck == null) {
        throw BarberRoleNotFoundException(
          'Barber role not found. Please assign barber role first.',
        );
      }

      if (barberRoleCheck['status'] != 'active') {
        throw BarberInactiveException(
          'Barber account is ${barberRoleCheck['status']}. Please reactivate the barber first.',
        );
      }

      // ==================== STEP 2: Check profile status ====================
      final barberProfileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', widget.barberId)
          .maybeSingle();

      if (barberProfileCheck != null) {
        if (barberProfileCheck['is_blocked'] == true) {
          throw BarberBlockedException(
            'Barber account is blocked. Please contact support.',
          );
        }
        if (barberProfileCheck['is_active'] == false) {
          throw BarberInactiveException(
            'Barber profile is inactive. Please reactivate the barber first.',
          );
        }
      }

      // ==================== STEP 3: Get salon_barber_id ====================
      final salonBarberResponse = await supabase
          .from('salon_barbers')
          .select('id, takes_appointments, staff_role')
          .eq('barber_id', widget.barberId)
          .eq('salon_id', salonIdInt)
          .eq('status', 'active')
          .maybeSingle();

      if (salonBarberResponse == null) {
        throw BarberNotInSalonException('Barber not found in this salon');
      }

      _salonBarberId =
          widget.salonBarberId ?? (salonBarberResponse['id'] as int);

      // ✅ Current role + is the logged-in user the salon OWNER?
      //    (only the owner may change roles; an admin employee may not)
      _currentTakes = salonBarberResponse['takes_appointments'] != false;
      _currentRole = (salonBarberResponse['staff_role'] ?? 'barber').toString();
      _isBarber = _currentTakes;
      _isAdmin = _currentRole == 'admin';
      _isCashier = _currentRole == 'cashier' || _isAdmin;

      final ownerRow = await supabase
          .from('salons')
          .select('owner_id')
          .eq('id', salonIdInt)
          .maybeSingle();
      _canSetRole =
          ownerRow != null &&
          ownerRow['owner_id'] == supabase.auth.currentUser?.id;

      // ==================== STEP 4: Load genders ====================
      final gendersResponse = await supabase
          .from('salon_genders')
          .select('id, display_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true);

      _genderMap = {};
      for (var g in gendersResponse) {
        _genderMap[g['id']] = g['display_name'];
      }

      // ==================== STEP 5: Load age categories ====================
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

      // ==================== STEP 6: Load categories ====================
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

      // ==================== STEP 7: Get already assigned services ====================
      final existingServices = await supabase
          .from('barber_services')
          .select('service_id, variant_id')
          .eq('salon_barber_id', _salonBarberId!);

      _hasKeptServices = existingServices.isNotEmpty;

      final Set<String> assignedServiceKeys = {};
      for (var item in existingServices) {
        if (item['variant_id'] == null) {
          assignedServiceKeys.add('service_${item['service_id']}');
        } else {
          assignedServiceKeys.add('variant_${item['variant_id']}');
        }
      }

      // ==================== STEP 8: Load services ====================
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, category_id, icon_name')
          .eq('salon_id', salonIdInt)
          .eq('is_active', true)
          .order('name');

      // ✅ Extract service IDs for filtering variants
      final List<int> serviceIds = servicesResponse
          .map<int>((s) => s['id'] as int)
          .toList();

      // ==================== STEP 9: Load variants for those services only ====================
      final List<dynamic> variantsResponse = serviceIds.isEmpty
          ? <dynamic>[]
          : await supabase
              .from('service_variants')
              .select(
                'id, service_id, price, duration, salon_gender_id, salon_age_category_id',
              )
              .inFilter('service_id', serviceIds)
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
        final ageData = _ageCategoryMap[ageId] ??
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

      // ==================== STEP 10: Build services list ====================
      final List<Map<String, dynamic>> processedServices = [];
      for (var service in servicesResponse) {
        final serviceId = service['id'] as int;
        final variants = variantsByService[serviceId] ?? [];
        final categoryId = service['category_id'];
        final category = _categoryMap[categoryId] ??
            {
              'display_name': 'Other',
              'icon_name': 'build',
              'color': '#FF6B8B',
            };
        final categoryName = category['display_name'];

        variants.sort((a, b) {
          if (a['gender_name'] != b['gender_name']) {
            return a['gender_name'].compareTo(b['gender_name']);
          }
          return a['age_name'].compareTo(b['age_name']);
        });

        final isFullServiceAssigned =
            assignedServiceKeys.contains('service_$serviceId');
        final allVariantsAssigned = variants.isNotEmpty &&
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
                  .map((v) => (v['price'] as num?)?.toDouble() ?? 0.0)
                  .reduce((a, b) => a < b ? a : b)
              : 0.0,
          'maxPrice': variants.isNotEmpty
              ? variants
                  .map((v) => (v['price'] as num?)?.toDouble() ?? 0.0)
                  .reduce((a, b) => a > b ? a : b)
              : 0.0,
        });
      }

      if (!mounted) return;
      setState(() {
        _services = processedServices;

        // ✅ UI: all services that have variants start expanded
        _expandedServices.clear();
        for (var s in processedServices) {
          if (s['hasVariants'] == true) {
            _expandedServices.add(s['id_str'] as String);
          }
        }
      });
    } on BarberInactiveException catch (e) {
      debugPrint('❌ Barber inactive: ${e.message}');
      if (mounted) {
        _showSnackBar(e.message, context.errorColor);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } on BarberBlockedException catch (e) {
      debugPrint('❌ Barber blocked: ${e.message}');
      if (mounted) {
        _showSnackBar(e.message, context.errorColor);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } on BarberRoleNotFoundException catch (e) {
      debugPrint('❌ Role not found: ${e.message}');
      if (mounted) {
        _showSnackBar(e.message, context.errorColor);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } on BarberNotInSalonException catch (e) {
      debugPrint('❌ Not in salon: ${e.message}');
      if (mounted) {
        _showSnackBar(e.message, context.errorColor);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } on InvalidSalonIdException catch (e) {
      debugPrint('❌ Invalid salon: ${e.message}');
      if (mounted) {
        _showSnackBar(e.message, context.errorColor);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading services: $e');
      if (mounted) {
        _showSnackBar('Error: ${e.toString()}', context.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ✅ ROLE HELPERS
  // ============================================================

  /// admin > cashier > barber
  String get _staffRoleNow =>
      _isAdmin ? 'admin' : (_isCashier ? 'cashier' : 'barber');

  bool get _roleChanged =>
      _canSetRole &&
      (_staffRoleNow != _currentRole || _isBarber != _currentTakes);

  /// Services list is only shown for people who take appointments.
  bool get _showServices => _canSetRole ? _isBarber : _currentTakes;

  bool get _hasChanges => _roleChanged || _getSelectedCount() > 0;

  String get _roleSummary {
    final extra = _isAdmin ? 'Admin' : (_isCashier ? 'Cashier' : '');
    if (_isBarber && extra.isEmpty) return 'Barber only';
    if (_isBarber) return 'Barber + $extra';
    return '$extra (desk only)';
  }

  void _toggleRole(String role, bool value) {
    // Rule: at least one role always stays ticked. Nothing else changes
    // behind the user's back, except "Admin includes Cashier".
    String? blocked;
    setState(() {
      switch (role) {
        case 'barber':
          if (!value && !_isCashier && !_isAdmin) {
            blocked = 'At least one role must stay selected';
            break;
          }
          _isBarber = value;
          break;
        case 'cashier':
          if (_isAdmin) break; // locked: included in Admin
          if (!value && !_isBarber) {
            blocked = 'At least one role must stay selected';
            break;
          }
          _isCashier = value;
          break;
        case 'admin':
          if (value) {
            _cashierBeforeAdmin = _isCashier;
            _isAdmin = true;
            _isCashier = true; // admin includes cashier
          } else {
            _isAdmin = false;
            // back to the user's earlier choice; a desk-only person keeps
            // Cashier so that a role is always selected
            _isCashier = _cashierBeforeAdmin || !_isBarber;
          }
          break;
      }
    });
    if (blocked != null) _showSnackBar(blocked!, context.warningColor);
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

  /// ✅ Toggle full service selection.
  /// An empty set means "full service" (all variants selected).
  void _toggleFullService(String serviceId) {
    setState(() {
      if (_selectedVariants.containsKey(serviceId)) {
        // Already selected → deselect
        _selectedVariants.remove(serviceId);
      } else {
        // ✅ Empty set = "full service"
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

  // ============================================================
  // ✅ SAVE SERVICES — Single batch insert
  // ============================================================
  Future<int> _countUpcomingAppointments() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await supabase
          .from('appointments')
          .select('id')
          .eq('salon_id', int.parse(widget.salonId))
          .eq('barber_id', widget.barberId)
          .gte('appointment_date', today)
          .inFilter('status', ['pending', 'confirmed', 'in_progress']);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<bool?> _confirmDeskOnly(int upcoming) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        backgroundColor: dialogContext.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Stop taking new bookings?',
          style: TextStyle(
            color: dialogContext.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This person has $upcoming upcoming appointment(s).\n\n'
          '• Customers will no longer see them in the barber list (no new bookings)\n'
          '• The existing $upcoming appointment(s) stay with them and must be finished, moved or cancelled as usual',
          style: TextStyle(color: dialogContext.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveServices() async {
    if (_salonBarberId == null) {
      _showSnackBar('Barber not found in this salon', context.errorColor);
      return;
    }

    final hasServices = _selectedVariants.isNotEmpty;
    final roleChanged = _roleChanged;

    if (!roleChanged && !hasServices) {
      _showSnackBar(
        'Please select at least one service',
        context.warningColor,
      );
      return;
    }

    // desk-only -> barber needs services (and a schedule, made by the server)
    final becomesBarber = _canSetRole && _isBarber && !_currentTakes;
    if (becomesBarber && !hasServices && !_hasKeptServices) {
      _showSnackBar(
        'Select at least one service to make this person a barber',
        context.warningColor,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // ✅ Service rows: [{service_id, variant_id}]
      //    (empty variant set = "full service")
      final List<Map<String, dynamic>> serviceRows = [];
      for (var entry in _selectedVariants.entries) {
        final serviceId = int.tryParse(entry.key);
        if (serviceId == null) continue;

        if (entry.value.isEmpty) {
          serviceRows.add({'service_id': serviceId, 'variant_id': null});
        } else {
          for (int variantId in entry.value) {
            serviceRows.add({'service_id': serviceId, 'variant_id': variantId});
          }
        }
      }

      // ---- 1. desk-only -> barber: ONE atomic call (services + schedule + role)
      if (becomesBarber) {
        final result = await supabase.rpc(
          'add_barber_to_salon',
          params: {
            'p_salon_id': int.parse(widget.salonId),
            'p_barber_id': widget.barberId,
            'p_services': serviceRows,
            'p_meta': {
              'barber_name': widget.barberName,
              'source': 'add_services_screen',
            },
            'p_takes_appointments': true,
            'p_staff_role': _staffRoleNow,
          },
        );
        final res = Map<String, dynamic>.from(result as Map);
        if (!mounted) return;
        if (res['success'] != true) {
          _showSnackBar(
            res['message']?.toString() ?? 'Failed to save',
            context.errorColor,
          );
          return;
        }
        _showSnackBar(
          serviceRows.isEmpty
              ? 'Saved: $_roleSummary (previous services kept)'
              : 'Saved: $_roleSummary, ${serviceRows.length} service(s) added',
          context.successColor,
        );
        Navigator.pop(context, true);
        return;
      }

      // ---- 2. role / desk-only change (owner only)
      if (roleChanged) {
        // barber -> desk-only with upcoming appointments: warn, don't block
        if (_currentTakes && !_isBarber) {
          final upcoming = await _countUpcomingAppointments();
          if (upcoming > 0) {
            if (!mounted) return;
            final ok = await _confirmDeskOnly(upcoming);
            if (ok != true) return;
          }
        }
        final roleRes = await supabase.rpc(
          'set_staff_role',
          params: {
            'p_salon_id': int.parse(widget.salonId),
            'p_barber_id': widget.barberId,
            'p_staff_role': _staffRoleNow,
            'p_takes_appointments': _isBarber,
          },
        );
        final rr = Map<String, dynamic>.from(roleRes as Map);
        if (!mounted) return;
        if (rr['success'] != true) {
          _showSnackBar(
            rr['message']?.toString() ?? 'Could not change the role',
            context.errorColor,
          );
          return;
        }
        _currentRole = _staffRoleNow;
        _currentTakes = _isBarber;
      }

      // ---- 3. services (only for people who take appointments)
      int added = 0;
      if (_showServices && serviceRows.isNotEmpty) {
        final rowsToInsert = serviceRows
            .map((r) => {...r, 'salon_barber_id': _salonBarberId!})
            .toList();

        // ✅ Single batch insert
        await supabase.from('barber_services').insert(rowsToInsert);
        added = rowsToInsert.length;
      }

      if (!mounted) return;

      _showSnackBar(
        [
          if (roleChanged) 'Role: $_roleSummary',
          if (added > 0) 'Successfully added $added service(s)',
        ].join(' • '),
        context.successColor,
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('❌ Error saving: $e');
      if (!mounted) return;

      // ✅ Handle duplicate key violation gracefully
      if (e.toString().contains('duplicate key') ||
          e.toString().contains('unique constraint')) {
        _showSnackBar(
          'Some services are already assigned to this barber.',
          context.warningColor,
        );
      } else {
        _showSnackBar('Error saving: $e', context.errorColor);
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
      // ✅ Added missing icons
      case 'water_drop':
        return Icons.water_drop;
      case 'masks':
        return Icons.masks;
      case 'spa_outlined':
        return Icons.spa_outlined;
      case 'palette':
        return Icons.palette;
      case 'shower':
        return Icons.shower;
      case 'cleaning_services':
        return Icons.cleaning_services;
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          if (selectedCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.white,
                  ),
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
          if (_hasChanges)
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
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  // ✅ Role card, search bar and cards share ONE container,
                  //    so cards start exactly where the search bar starts
                  //    (same as ServiceManagement)
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    children: [
                      if (_canSetRole) _buildRoleCard(padding),
                      if (_showServices) ...[
                        _buildSearchAndFilterBar(padding),
                        Expanded(
                          child: _filteredServices.isEmpty
                              ? _buildEmptyState()
                              : _buildServicesList(padding, selectedCount),
                        ),
                      ] else
                        Expanded(child: _buildDeskOnlyInfo(padding)),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: _hasChanges && !_isWeb
          ? FloatingActionButton(
              onPressed: _isSaving ? null : _saveServices,
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              tooltip: selectedCount > 0 ? 'Save ($selectedCount)' : 'Save role',
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Badge(
                      isLabelVisible: selectedCount > 0,
                      label: Text('$selectedCount'),
                      backgroundColor: Colors.white,
                      textColor: primaryColor,
                      offset: const Offset(10, -10),
                      child: const Icon(Icons.save),
                    ),
            )
          : null,
    );
  }

  // ============================================================
  // ✅ ROLE CARD (owner only) — expanded by default
  //    Web: 3 tiles in a row | Mobile: tiles stacked
  // ============================================================
  Widget _buildRoleCard(double padding) {
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;

    Widget roleBox({
      required String role,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      bool enabled = true,
    }) {
      return Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => _toggleRole(role, !value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: value
                  ? primaryColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value ? primaryColor : borderColor,
                width: value ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  onChanged:
                      enabled ? (v) => _toggleRole(role, v ?? false) : null,
                  activeColor: primaryColor,
                  visualDensity: VisualDensity.compact,
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: primaryColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final barberBox = roleBox(
      role: 'barber',
      icon: Icons.content_cut,
      title: 'Barber',
      subtitle: 'Takes customer appointments (services required)',
      value: _isBarber,
    );
    final cashierBox = roleBox(
      role: 'cashier',
      icon: Icons.point_of_sale,
      title: 'Cashier',
      subtitle: _isAdmin
          ? 'Included in Admin'
          : 'Front desk: all appointments, payments, Book / VIP',
      value: _isCashier,
      enabled: !_isAdmin,
    );
    final adminBox = roleBox(
      role: 'admin',
      icon: Icons.admin_panel_settings_outlined,
      title: 'Admin',
      subtitle: 'Cashier + services, barbers, offers, revenue, reports',
      value: _isAdmin,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _roleChanged ? primaryColor : borderColor,
            width: _roleChanged ? 2 : 1,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true, // ✅ default expanded
            leading: Icon(Icons.badge_outlined, color: primaryColor),
            title: Text(
              'Role in this salon',
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
            ),
            subtitle: Text(
              _roleChanged ? '$_roleSummary (not saved yet)' : _roleSummary,
              style: TextStyle(
                fontSize: 12,
                color: _roleChanged ? primaryColor : secondaryTextColor,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (_isWeb)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: barberBox),
                    const SizedBox(width: 12),
                    Expanded(child: cashierBox),
                    const SizedBox(width: 12),
                    Expanded(child: adminBox),
                  ],
                )
              else
                Column(
                  children: [
                    barberBox,
                    const SizedBox(height: 8),
                    cashierBox,
                    const SizedBox(height: 8),
                    adminBox,
                  ],
                ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: secondaryTextColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Cashier / Admin access works while your salon is on Silver or higher. Press Save to apply.',
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ DESK-ONLY INFO (shown instead of the services list)
  // ============================================================
  Widget _buildDeskOnlyInfo(double padding) {
    final secondaryTextColor = context.secondaryTextColor;
    final textColor = context.textColor;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(padding + 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.point_of_sale,
              size: _isWeb ? 72 : 56,
              color: secondaryTextColor.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Desk only - no services needed',
              style: TextStyle(
                fontSize: _isWeb ? 20 : 17,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _canSetRole
                  ? 'This person does not take appointments, so there is nothing to assign here. Tick "Barber" above to make this person a barber too.'
                  : 'This person does not take appointments, so services can not be assigned.',
              style: TextStyle(
                fontSize: _isWeb ? 15 : 13,
                color: secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
                  onSelected: (_) =>
                      setState(() => _selectedCategory = 'all'),
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
    final primaryColor = context.primaryColor;

    final hasFilters =
        _searchQuery.isNotEmpty || _selectedCategory != 'all';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters ? Icons.search_off : Icons.inbox_outlined,
              size: _isWeb ? 80 : 64,
              color: secondaryTextColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters ? 'No services found' : 'No services available',
              style: TextStyle(
                fontSize: _isWeb ? 20 : 18,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Try adjusting your search or filters'
                  : 'Add services to this salon first',
              style: TextStyle(
                fontSize: _isWeb ? 16 : 14,
                color: secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _selectedCategory = 'all');
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear Filters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ SERVICES LIST — responsive
  //    Web: 2-3 column grid (Wrap) | Mobile: single column list
  // ============================================================
  Widget _buildServicesList(double padding, int selectedCount) {
    final filtered = _filteredServices;

    if (_isWeb) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectedCount > 0) ...[
              _buildSelectionBar(selectedCount),
              const SizedBox(height: 16),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                const double spacing = 16;
                // Same idea as ServiceManagement's maxCrossAxisExtent: 400
                int cols = (constraints.maxWidth / 400).ceil();
                if (cols < 1) cols = 1;

                // ✅ Fixed column grid: every row has `cols` slots, cards fill
                //    slots from the LEFT; empty slots stay blank on the right.
                //    (1 filtered service = 1st slot, never centered)
                final List<Widget> rows = [];
                for (int i = 0; i < filtered.length; i += cols) {
                  final List<Widget> rowChildren = [];
                  for (int j = 0; j < cols; j++) {
                    if (j > 0) rowChildren.add(const SizedBox(width: spacing));
                    final int idx = i + j;
                    rowChildren.add(
                      Expanded(
                        child: idx < filtered.length
                            ? _buildServiceCard(filtered[idx], idx)
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  rows.add(
                    Padding(
                      padding: const EdgeInsets.only(bottom: spacing),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: rowChildren,
                      ),
                    ),
                  );
                }

                return SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rows,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    // Mobile / tablet-portrait
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        padding,
        0,
        padding,
        _hasChanges ? 96 : padding, // space for the FAB
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildServiceCard(filtered[index], index),
        );
      },
    );
  }

  // ✅ Selected summary + Save button (web only; mobile uses the FAB)
  Widget _buildSelectionBar(int selectedCount) {
    final primaryColor = context.primaryColor;
    final cardColor = context.cardColor;

    return Card(
      margin: EdgeInsets.zero,
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
              onPressed: _isSaving ? null : _saveServices,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ SERVICE CARD (same card for web + mobile)
  //    Header: icon, name, category chip, variants count, price range
  //    Body  : variants (expanded by default)
  // ============================================================
  Widget _buildServiceCard(Map<String, dynamic> service, int index) {
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;
    final successColor = context.successColor;
    final isDark = context.isDarkMode;

    final serviceId = service['id_str'] as String;
    final variants = service['variants'] as List;
    final hasVariants = variants.isNotEmpty;
    final isFullServiceAssigned = service['isFullServiceAssigned'] == true;
    final allVariantsAssigned = service['allVariantsAssigned'] == true;
    final isFullServiceSelected = _isFullServiceSelected(serviceId);
    final selectedVariantCount = _selectedVariants[serviceId]?.length ?? 0;
    final isExpanded = _expandedServices.contains(serviceId);
    final categoryColor = _getCategoryColor(context, service['category_name']);
    final cardBgColor = _getCardColor(context, index);
    final description = (service['description'] ?? '').toString();

    final isCompletelyAssigned =
        !hasVariants ? isFullServiceAssigned : allVariantsAssigned;
    final isSelected = isFullServiceSelected || selectedVariantCount > 0;

    return Opacity(
      opacity: isCompletelyAssigned ? 0.7 : 1.0,
      child: Card(
        margin: EdgeInsets.zero,
        color: cardColor,
        elevation: isSelected ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? primaryColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cardBgColor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ==================== HEADER ====================
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: hasVariants
                    ? () => _toggleExpand(serviceId)
                    : (isCompletelyAssigned
                        ? null
                        : () => _toggleFullService(serviceId)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDark
                              ? cardColor
                              : Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            _getIconForName(service['icon_name']),
                            color: primaryColor,
                            size: 20,
                          ),
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
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 15,
                                color: isCompletelyAssigned
                                    ? secondaryTextColor
                                    : textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        categoryColor.withValues(alpha: 0.15),
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
                                if (hasVariants)
                                  Text(
                                    '${variants.length} variants',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                if (hasVariants && !isCompletelyAssigned)
                                  Text(
                                    _formatPriceRange(
                                      service['minPrice'],
                                      service['maxPrice'],
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: secondaryTextColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
                          size: 22,
                          color: selectedVariantCount > 0
                              ? primaryColor
                              : secondaryTextColor,
                        ),
                    ],
                  ),
                ),
              ),

              // ==================== BODY ====================
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    if (isCompletelyAssigned)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Container(
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
                      ),

                    if (!hasVariants && !isCompletelyAssigned)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Text(
                          'Full Service',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),

                    // ✅ Variants (shown when expanded)
                    if (hasVariants && isExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          children: variants.map<Widget>((variant) {
                            return _buildVariantRow(
                              serviceId: serviceId,
                              variant: variant as Map<String, dynamic>,
                              isCompletelyAssigned: isCompletelyAssigned,
                            );
                          }).toList(),
                        ),
                      ),

                    if (selectedVariantCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Text(
                          '$selectedVariantCount variant${selectedVariantCount > 1 ? 's' : ''} selected',
                          style: TextStyle(
                            fontSize: 11,
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ One variant row (checkbox + gender/age + price/duration + badge)
  Widget _buildVariantRow({
    required String serviceId,
    required Map<String, dynamic> variant,
    required bool isCompletelyAssigned,
  }) {
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final cardColor = context.cardColor;
    final borderColor = context.dividerColor;
    final successColor = context.successColor;
    final isDark = context.isDarkMode;

    final variantId = variant['id'] as int;
    final isAssigned = variant['isAssigned'] == true;
    final isVarSelected = _isVariantSelected(serviceId, variantId);
    final disabled = isAssigned || isCompletelyAssigned;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isVarSelected
            ? primaryColor.withValues(alpha: 0.08)
            : (isDark
                ? cardColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isVarSelected ? primaryColor : borderColor,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : () => _toggleVariant(serviceId, variantId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: isVarSelected,
                onChanged:
                    disabled ? null : (_) => _toggleVariant(serviceId, variantId),
                activeColor: primaryColor,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant['display_text'],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isVarSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isVarSelected ? primaryColor : textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatPrice(variant['price'])} • ${variant['duration']} min',
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAssigned)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: successColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Assigned',
                    style: TextStyle(fontSize: 9, color: successColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}