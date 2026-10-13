import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/create_offer_screen.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';
import '../../services/currency_service.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class OwnerOffersScreen extends StatefulWidget {
  final String? salonId;

  const OwnerOffersScreen({super.key, this.salonId});

  @override
  State<OwnerOffersScreen> createState() => _OwnerOffersScreenState();
}

class _OwnerOffersScreenState extends State<OwnerOffersScreen>
    with SingleTickerProviderStateMixin {
  // ✅ Default salon timezone (DB default — NOT user timezone!)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';

  final supabase = Supabase.instance.client;
  final CurrencyService _currencyService = CurrencyService.instance;

  // ✅ Currency — DB → timezone-derived → LKR fallback
  String _salonCurrencyCode = '';

  // ✅ Salon timezone
  String _salonTimezone = '';

  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _filteredOffers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int? _currentSalonId;
  String? _currentSalonName;

  // Scroll
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingButton = true;

  // Timezone
  String userTimezone = '';
  bool _isTimezoneLoaded = false;

  late bool _isDark;
  late bool _isWeb;

  // Tab controller
  late TabController _tabController;

  // Counts
  int _totalCount = 0;
  int _activeCount = 0;
  int _expiredCount = 0;
  int _inactiveCount = 0;

  bool _isProcessing = false;

  // ✅ Effective currency getter
  String get _effectiveCurrencyCode {
    if (_salonCurrencyCode.isNotEmpty) {
      return _salonCurrencyCode;
    }
    if (_salonTimezone.isNotEmpty) {
      return TimezoneService.getCurrencyForTimezone(_salonTimezone);
    }
    return 'LKR';
  }

  // ✅ Currency symbol
  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(_effectiveCurrencyCode);

  // ✅ Salon "today" — fallback to salon default (NOT device)
  DateTime get _salonToday {
    final tz = _salonTimezone.isNotEmpty
        ? _salonTimezone
        : _kDefaultSalonTimezone;
    try {
      final now = TimezoneService.getNowInTimezone(tz);
      return DateTime(now.year, now.month, now.day);
    } catch (e) {
      debugPrint('❌ Error getting salon today: $e');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initializeTimezone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = context.isDarkMode;
    _isWeb = context.isWeb;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 100 ? s.substring(0, 100) : s;
  }

  String _formatPrice(dynamic amount) {
    if (amount == null) return '$_salonCurrencySymbol 0';
    return _currencyService.format(
      price: amount,
      currencyCode: _effectiveCurrencyCode,
    );
  }

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    userTimezone = prefs.getString(TimezoneService.kUserTimezone) ??
        TimezoneService.getCurrentTimezone();

    if (userTimezone.isEmpty) {
      userTimezone = _kDefaultSalonTimezone;
    }

    if (!mounted) return;

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadSalonAndOffers();
  }

  // ============================================
  // ✅ DATE HELPERS (DATE columns — no timezone)
  // ============================================

  /// ✅ Offers use DATE columns — no timezone conversion
  DateTime _parseDateOnly(String dateStr) {
    try {
      final parsed = DateTime.parse(dateStr);
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (e) {
      debugPrint('❌ Error parsing date: $e');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
  }

  String _formatLocalDate(String dateStr) {
    try {
      final date = _parseDateOnly(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  // ✅ Active: is_active=true, valid_from <= today, valid_to > today
  bool _isOfferActive(Map<String, dynamic> offer) {
    try {
      final nowLocal = _salonToday;
      final validToLocal = _parseDateOnly(offer['valid_to'] as String);
      final validFromLocal = _parseDateOnly(offer['valid_from'] as String);
      return offer['is_active'] == true &&
          validToLocal.isAfter(nowLocal) &&
          !validFromLocal.isAfter(nowLocal);
    } catch (e) {
      return false;
    }
  }

  // ✅ Expired: is_active=true, valid_to < today
  bool _isOfferExpired(Map<String, dynamic> offer) {
    try {
      if (offer['is_active'] != true) return false;
      final nowLocal = _salonToday;
      final validToLocal = _parseDateOnly(offer['valid_to'] as String);
      return validToLocal.isBefore(nowLocal);
    } catch (e) {
      return false;
    }
  }

  // ✅ FIX: Inactive includes is_active=false OR future-valid (not yet started)
  bool _isOfferInactive(Map<String, dynamic> offer) {
    if (offer['is_active'] != true) return true;

    // Also inactive if future-valid (not yet started)
    try {
      final nowLocal = _salonToday;
      final validFromLocal = _parseDateOnly(offer['valid_from'] as String);
      if (validFromLocal.isAfter(nowLocal)) return true;
    } catch (e) {
      // ignore
    }

    return false;
  }

  int _getDaysLeft(Map<String, dynamic> offer) {
    try {
      final nowLocal = _salonToday;
      final validToLocal = _parseDateOnly(offer['valid_to'] as String);
      return validToLocal.difference(nowLocal).inDays;
    } catch (e) {
      return 0;
    }
  }

  void _onScroll() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.pixels > 200 && _showFloatingButton) {
      setState(() => _showFloatingButton = false);
    } else if (_scrollController.position.pixels <= 200 &&
        !_showFloatingButton) {
      setState(() => _showFloatingButton = true);
    }
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() => _applyStatusFilter());
    }
  }

  void _applyStatusFilter() {
    switch (_tabController.index) {
      case 0: // Active
        _filteredOffers = _offers.where((o) => _isOfferActive(o)).toList();
        break;
      case 1: // Expired
        _filteredOffers = _offers.where((o) => _isOfferExpired(o)).toList();
        break;
      case 2: // Inactive
        _filteredOffers = _offers.where((o) => _isOfferInactive(o)).toList();
        break;
      case 3: // All
      default:
        _filteredOffers = List.from(_offers);
        break;
    }
  }

  // ✅ Helper: parse salon result → set fields
  void _setSalonFromResult(Map<String, dynamic> salon) {
    _currentSalonId = salon['id'] as int;
    _currentSalonName = salon['name'] as String?;

    final currencyCode = salon['currency_code'] as String?;
    if (currencyCode != null && currencyCode.isNotEmpty) {
      _salonCurrencyCode = currencyCode;
    }

    final timezone = salon['timezone'] as String?;
    if (timezone != null && timezone.isNotEmpty) {
      _salonTimezone = timezone;
    }
  }

  Future<void> _loadSalonAndOffers() async {
    if (!mounted) return;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }

      // ✅ STEP 1: Check owner role
      final ownerCheck = await supabase
          .from('user_roles')
          .select('status, roles!inner(name)')
          .eq('user_id', user.id)
          .eq('roles.name', 'owner')
          .maybeSingle();

      if (ownerCheck == null || ownerCheck['status'] != 'active') {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Your account is not active as an owner.';
          _isLoading = false;
        });
        return;
      }

      // ✅ STEP 2: Check profile (blocked/inactive)
      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMessage =
                'Your account has been blocked. Please contact support.';
            _isLoading = false;
          });
          return;
        }
        if (profileCheck['is_active'] == false) {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMessage =
                'Your profile is inactive. Please contact support.';
            _isLoading = false;
          });
          return;
        }
      }

      // ✅ STEP 3: Load salon (specific ID or first owned)
      if (widget.salonId != null && widget.salonId!.isNotEmpty) {
        final salonIdInt = int.tryParse(widget.salonId!);
        if (salonIdInt != null) {
          final salonResult = await supabase
              .from('salons')
              .select('id, name, currency_code, timezone')
              .eq('id', salonIdInt)
              .eq('owner_id', user.id)
              .maybeSingle();

          if (salonResult != null) {
            if (!mounted) return;
            setState(() {
              _setSalonFromResult(salonResult);
            });
            await _loadOffers();
            return;
          }
        }
      }

      // ✅ Fallback — first active salon
      final salonResult = await supabase
          .from('salons')
          .select('id, name, currency_code, timezone')
          .eq('owner_id', user.id)
          .eq('is_active', true)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      if (salonResult == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = "You don't own any salon.";
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _setSalonFromResult(salonResult);
      });

      await _loadOffers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load salon data.';
        _isLoading = false;
      });
    }
  }

  // ============================================
  // ✅ LOAD OFFERS (variant-aware + grouped)
  // ============================================
  Future<void> _loadOffers() async {
    final salonId = _currentSalonId;
    if (salonId == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final result = await supabase
          .from('offers')
          .select('''
            id,
            title,
            description,
            discount_type,
            discount_value,
            points_required,
            valid_from,
            valid_to,
            valid_from_time,
            valid_to_time,
            image_url,
            is_active,
            usage_limit,
            used_count,
            applicable_for,
            created_at,
            updated_at,
            offer_services (
              service_id,
              variant_id,
              services:service_id (id, name),
              service_variants:variant_id (id, salon_gender_id, salon_age_category_id)
            )
          ''')
          .eq('salon_id', salonId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      // ✅ Load gender/age lookups
      final genderIds = <int>{};
      final ageIds = <int>{};
      for (final o in result) {
        final svcList = o['offer_services'] as List? ?? [];
        for (final os in svcList) {
          final variant = os['service_variants'];
          if (variant != null) {
            final gid = variant['salon_gender_id'] as int?;
            final aid = variant['salon_age_category_id'] as int?;
            if (gid != null) genderIds.add(gid);
            if (aid != null) ageIds.add(aid);
          }
        }
      }

      final Map<int, String> genderMap = {};
      if (genderIds.isNotEmpty) {
        try {
          final genders = await supabase
              .from('salon_genders')
              .select('id, display_name')
              .inFilter('id', genderIds.toList());
          for (var g in genders) {
            genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('Gender lookup failed: $e');
        }
      }

      final Map<int, String> ageMap = {};
      if (ageIds.isNotEmpty) {
        try {
          final ages = await supabase
              .from('salon_age_categories')
              .select('id, display_name')
              .inFilter('id', ageIds.toList());
          for (var a in ages) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('Age lookup failed: $e');
        }
      }

      // ✅ FIX: Group scope by service (avoid duplicate service names)
      final offers = List<Map<String, dynamic>>.from(result).map((o) {
        final offer = Map<String, dynamic>.from(o);
        final svcList = (offer['offer_services'] as List? ?? []);

        // Group variants by service name
        final Map<String, List<String>> groupedByService = {};
        final Set<String> wholeServices = {};

        for (final os in svcList) {
          final service = os['services'];
          final variant = os['service_variants'];
          final serviceName = service?['name']?.toString() ?? 'Service';

          if (variant == null) {
            // Whole service (any variant)
            wholeServices.add(serviceName);
          } else {
            final gid = variant['salon_gender_id'] as int?;
            final aid = variant['salon_age_category_id'] as int?;
            final gender = gid != null ? (genderMap[gid] ?? '') : '';
            final age = aid != null ? (ageMap[aid] ?? '') : '';
            final labelParts = <String>[];
            if (gender.isNotEmpty) labelParts.add(gender);
            if (age.isNotEmpty) labelParts.add(age);
            final vLabel = labelParts.isEmpty ? 'Standard' : labelParts.join(' ');
            groupedByService.putIfAbsent(serviceName, () => []).add(vLabel);
          }
        }

        // Build summary parts
        final summaryParts = <String>[];

        // Whole services first
        for (final svcName in wholeServices) {
          summaryParts.add(svcName);
        }

        // Then services with variants
        groupedByService.forEach((svcName, variants) {
          if (wholeServices.contains(svcName)) return; // already added
          if (variants.length == 1) {
            summaryParts.add('$svcName · ${variants.first}');
          } else {
            summaryParts.add('$svcName (${variants.length} variants)');
          }
        });

        offer['scope_summary'] = summaryParts.isEmpty
            ? 'All Services'
            : summaryParts.join(', ');
        return offer;
      }).toList();

      // ✅ Consistent counts (future-valid → inactive)
      int total = offers.length;
      int active = 0;
      int expired = 0;
      int inactive = 0;

      for (var offer in offers) {
        if (_isOfferInactive(offer)) {
          inactive++;
        } else if (_isOfferExpired(offer)) {
          expired++;
        } else if (_isOfferActive(offer)) {
          active++;
        } else {
          // Edge case safety — count as inactive
          inactive++;
        }
      }

      if (!mounted) return;
      setState(() {
        _offers = offers;
        _totalCount = total;
        _activeCount = active;
        _expiredCount = expired;
        _inactiveCount = inactive;
        _applyStatusFilter();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading offers: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load offers.';
        _isLoading = false;
      });
    }
  }

  // ✅ Pass salonTimezone to CreateOfferScreen
  Future<void> _openCreateOffer() async {
    if (_currentSalonId == null || !mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateOfferScreen(
          salonId: _currentSalonId!,
          salonName: _currentSalonName ?? 'Salon',
          currencyCode: _effectiveCurrencyCode,
          salonTimezone: _salonTimezone,
        ),
      ),
    );

    if (result == true && mounted) {
      await _loadOffers();
    }
  }

  Future<void> _openEditOffer(Map<String, dynamic> offer) async {
    if (_currentSalonId == null || !mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateOfferScreen(
          salonId: _currentSalonId!,
          salonName: _currentSalonName ?? 'Salon',
          currencyCode: _effectiveCurrencyCode,
          salonTimezone: _salonTimezone,
          editingOffer: offer,
        ),
      ),
    );

    if (result == true && mounted) {
      await _loadOffers();
    }
  }

  Future<void> _toggleOfferStatus(int offerId, bool isActive) async {
    if (_isProcessing || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      await supabase
          .from('offers')
          .update({
            'is_active': !isActive,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', offerId);

      await _loadOffers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !isActive ? '✅ Offer activated' : '⏸️ Offer deactivated',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: !isActive ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ${_shortError(e)}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteOffer(int offerId) async {
    if (!mounted) return;
    final isDark = _isDark;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Offer',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this offer?\n\nThis action cannot be undone.',
          style: TextStyle(
            height: 1.4,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
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

    if (confirm != true || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      await supabase.from('offers').delete().eq('id', offerId);
      await _loadOffers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🗑️ Offer deleted',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ${_shortError(e)}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _getDiscountText(Map<String, dynamic> offer) {
    switch (offer['discount_type']) {
      case 'percentage':
        return '${offer['discount_value']}% OFF';
      case 'fixed':
        return '${_formatPrice(offer['discount_value'])} OFF';
      default:
        return 'FREE SERVICE';
    }
  }

  Color _getStatusColor(Map<String, dynamic> offer) {
    if (offer['is_active'] != true) return Colors.grey;
    if (_isOfferExpired(offer)) return Colors.red;
    if (_isOfferInactive(offer)) return Colors.grey;
    return Colors.green;
  }

  String _getStatusText(Map<String, dynamic> offer) {
    if (offer['is_active'] != true) return 'Inactive';
    if (_isOfferExpired(offer)) return 'Expired';
    if (_isOfferInactive(offer)) {
      // Future-valid
      final daysUntilStart = _daysUntilStart(offer);
      return daysUntilStart > 0 ? 'Starts in $daysUntilStart d' : 'Inactive';
    }
    final daysLeft = _getDaysLeft(offer);
    return daysLeft == 0 ? 'Ends today' : '$daysLeft days left';
  }

  int _daysUntilStart(Map<String, dynamic> offer) {
    try {
      final nowLocal = _salonToday;
      final validFromLocal = _parseDateOnly(offer['valid_from'] as String);
      return validFromLocal.difference(nowLocal).inDays;
    } catch (e) {
      return 0;
    }
  }

  // ✅ Use pre-built scope_summary
  String _getServiceScopeSummary(Map<String, dynamic> offer) {
    final summary = offer['scope_summary']?.toString();
    if (summary != null && summary.isNotEmpty) {
      return '✂️ $summary';
    }

    final offerServices = offer['offer_services'] as List? ?? [];
    if (offerServices.isEmpty) return '🌐 All Services';

    if (offerServices.length == 1) {
      final row = offerServices.first as Map;
      final svc = row['services'] as Map?;
      final variant = row['service_variants'] as Map?;

      if (variant == null) {
        return '✂️ ${svc?['name'] ?? 'Service'}';
      }

      return '✂️ ${svc?['name'] ?? 'Service'} · Variant';
    }

    return '✂️ ${offerServices.length} Services';
  }

  // ============================================
  // BUILD
  // ============================================
  @override
  Widget build(BuildContext context) {
    _isDark = context.isDarkMode;
    _isWeb = context.isWeb;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage Offers',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (_currentSalonName != null)
              Text(
                _currentSalonName!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: _isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: !_isTimezoneLoaded
            ? _buildInitialLoading()
            : _isLoading && _offers.isEmpty
                ? _buildLoadingState()
                : _hasError && _offers.isEmpty
                    ? _buildErrorState()
                    : _isWeb
                        ? _buildWebLayout()
                        : _buildMobileLayout(),
      ),
      floatingActionButton:
          _showFloatingButton && !_isLoading && !_hasError && _offers.isNotEmpty
              ? FloatingActionButton(
                  onPressed: _openCreateOffer,
                  backgroundColor: AppTheme.primary,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
    );
  }

  Widget _buildInitialLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 16),
          Text(
            'Loading offers...',
            style: TextStyle(
              color: _isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: _isDark ? Colors.white70 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(
                color: _isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadSalonAndOffers,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildStatCards(),
        Container(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: _buildTabBar(),
        ),
        Expanded(child: _buildOfferList()),
      ],
    );
  }

  Widget _buildWebLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: RefreshIndicator(
          onRefresh: _loadOffers,
          color: AppTheme.primary,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildStatCards(isWeb: true),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildTabBar(),
                      ),
                    ]),
                  ),
                ),
                if (_filteredOffers.isEmpty)
                  SliverToBoxAdapter(
                    child: _buildEmptyState(scrollable: false),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 420,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 340,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _buildOfferCard(_filteredOffers[index], false),
                        childCount: _filteredOffers.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCards({bool isWeb = false}) {
    final padding = isWeb
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(16, 12, 16, 12);

    return Container(
      padding: padding,
      color: isWeb
          ? Colors.transparent
          : (_isDark ? const Color(0xFF1E1E1E) : Colors.grey[50]),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Active',
              _activeCount,
              Icons.check_circle_outline,
              Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Expired',
              _expiredCount,
              Icons.timer_off_outlined,
              Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Inactive',
              _inactiveCount,
              Icons.pause_circle_outline,
              Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Total',
              _totalCount,
              Icons.local_offer_outlined,
              AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: _isDark ? Colors.white60 : Colors.grey[600],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      labelColor: AppTheme.primary,
      unselectedLabelColor: _isDark ? Colors.white60 : Colors.grey[600],
      indicatorColor: AppTheme.primary,
      indicatorWeight: 3,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.normal,
      ),
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 16),
              const SizedBox(width: 6),
              Text('Active ($_activeCount)'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_off_outlined, size: 16),
              const SizedBox(width: 6),
              Text('Expired ($_expiredCount)'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pause_circle_outline, size: 16),
              const SizedBox(width: 6),
              Text('Inactive ($_inactiveCount)'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.list_alt, size: 16),
              const SizedBox(width: 6),
              Text('All ($_totalCount)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfferList() {
    if (_filteredOffers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadOffers,
        color: AppTheme.primary,
        child: _buildEmptyState(scrollable: true),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOffers,
      color: AppTheme.primary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _filteredOffers.length,
        itemBuilder: (context, index) {
          return _buildOfferCard(_filteredOffers[index], true);
        },
      ),
    );
  }

  Widget _buildEmptyState({bool scrollable = true}) {
    String message;
    IconData icon;

    switch (_tabController.index) {
      case 0:
        message = 'No active offers';
        icon = Icons.check_circle_outline;
        break;
      case 1:
        message = 'No expired offers';
        icon = Icons.timer_off_outlined;
        break;
      case 2:
        message = 'No inactive offers';
        icon = Icons.pause_circle_outline;
        break;
      default:
        message = 'No offers yet';
        icon = Icons.local_offer_outlined;
    }

    final content = Container(
      constraints: BoxConstraints(
        minHeight: (MediaQuery.of(context).size.height - 400).clamp(
          0.0,
          double.infinity,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: _isDark ? Colors.white30 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: _isDark ? Colors.white60 : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Create Offer" to create your first offer',
            style: TextStyle(
              fontSize: 13,
              color: _isDark ? Colors.white70 : Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openCreateOffer,
            icon: const Icon(Icons.add),
            label: const Text('Create Offer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (!scrollable) return content;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: content,
    );
  }

  // =====================================================
  // OFFER CARD
  // =====================================================
  Widget _buildOfferCard(Map<String, dynamic> offer, bool isSmallScreen) {
    final isDark = _isDark;
    final statusColor = _getStatusColor(offer);
    final statusText = _getStatusText(offer);
    final discountText = _getDiscountText(offer);
    final validFrom = _formatLocalDate(offer['valid_from'] as String);
    final validTo = _formatLocalDate(offer['valid_to'] as String);
    final usageLimit = offer['usage_limit'];
    final usedCount = offer['used_count'] ?? 0;
    final serviceScope = _getServiceScopeSummary(offer);
    final pointsRequired = (offer['points_required'] ?? 0) as int;
    final isActive = offer['is_active'] == true;
    final isExpired = _isOfferExpired(offer);
    final isInactive = _isOfferInactive(offer);
    final daysLeft = _getDaysLeft(offer);

    BorderSide borderSide;
    if (isInactive) {
      borderSide = BorderSide(
        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        width: 1,
      );
    } else if (isExpired) {
      borderSide = BorderSide(color: Colors.red.shade300, width: 1.5);
    } else {
      borderSide = BorderSide(color: Colors.green.shade400, width: 1.5);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: borderSide,
      ),
      child: InkWell(
        onTap: () => _openEditOffer(offer),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ROW 1: Status + Discount + Days left
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      discountText,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const Spacer(),

                  if (!isInactive && !isExpired && daysLeft >= 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: daysLeft <= 3
                            ? Colors.orange.withValues(alpha: 0.12)
                            : Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            daysLeft <= 3
                                ? Icons.warning_amber
                                : Icons.schedule,
                            size: 10,
                            color: daysLeft <= 3
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            daysLeft == 0 ? 'Ends today' : '$daysLeft d',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: daysLeft <= 3
                                  ? Colors.orange.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // ROW 2: Title + Description
              Text(
                offer['title'] ?? 'Offer',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (offer['description'] != null &&
                  offer['description'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  offer['description'],
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // ROW 3: Scope + Points
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        serviceScope,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.indigo.shade200
                              : Colors.indigo.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  if (pointsRequired > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            '$pointsRequired pts',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // ROW 4: Validity + Usage
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: isDark ? Colors.white60 : Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isSmallScreen ? validTo : '$validFrom - $validTo',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  if (usageLimit != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 10,
                            color: isDark
                                ? Colors.purple.shade200
                                : Colors.purple.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$usedCount / $usageLimit',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.purple.shade200
                                  : Colors.purple.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // ACTION BUTTONS
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _toggleOfferStatus(
                                offer['id'],
                                offer['is_active'] == true,
                              ),
                      icon: Icon(
                        isActive ? Icons.pause : Icons.play_arrow,
                        size: 16,
                      ),
                      label: Text(
                        isActive ? 'DEACTIVATE' : 'ACTIVATE',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isActive ? Colors.orange : Colors.green,
                        side: BorderSide(
                          color: isActive ? Colors.orange : Colors.green,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _openEditOffer(offer),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text(
                        'EDIT',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _deleteOffer(offer['id']),
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text(
                        'DELETE',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}