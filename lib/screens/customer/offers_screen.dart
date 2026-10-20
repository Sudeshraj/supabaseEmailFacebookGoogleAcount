import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../extensions/context_extensions.dart';
import '../../services/currency_service.dart';
import '../../services/currency_settings_service.dart'; // ✅ NEW
import '../../services/timezone_service.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final supabase = Supabase.instance.client;
  final CurrencyService _currencyService = CurrencyService.instance;
  final CurrencySettingsService _currencySettings =
      CurrencySettingsService.instance; // ✅ NEW

  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // ✅ Default salon timezone + currency
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';
  static const String _kDefaultCurrency = 'LKR'; // ✅ NEW

  // ✅ NEW: User currency + per-salon exchange rates cache
  String _userCurrencyCode = _kDefaultCurrency;
  // Key: salonId, Value: exchange rate (salon → user)
  final Map<int, double?> _salonExchangeRates = {};

  // Filter and sort state
  String _selectedFilter = 'all';
  String _selectedSort = 'newest';

  // Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  // Track claiming state per offer
  final Set<int> _claimingOfferIds = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================
  // ✅ HELPER: Get salon timezone
  // ============================================
  String _getSalonTimezone(Map<String, dynamic>? salon) {
    final tz = salon?['timezone'] as String?;
    if (tz != null && tz.isNotEmpty) return tz;
    return _kDefaultSalonTimezone;
  }

  // ============================================
  // ✅ HELPER: Get salon currency code
  // ============================================
  String _getSalonCurrencyCode(Map<String, dynamic>? salon) {
    final code = salon?['currency_code'] as String?;
    if (code != null && code.isNotEmpty) return code;
    return _kDefaultCurrency;
  }

  // ============================================
  // ✅ HELPER: Currency symbol from salon code
  // ============================================
  String _getSalonCurrencySymbol(Map<String, dynamic>? salon) {
    final code = _getSalonCurrencyCode(salon);
    return _currencyService.getSymbol(code);
  }


  // ✅ NEW: Format user approx amount
  String _formatUserPrice(dynamic amount) {
    return _currencyService.format(
      price: amount,
      currencyCode: _userCurrencyCode,
    );
  }

  // ✅ NEW: Get cached exchange rate for salon
  double? _getExchangeRateForSalon(Map<String, dynamic>? salon) {
    final salonId = salon?['id'] as int?;
    if (salonId == null) return null;
    return _salonExchangeRates[salonId];
  }

  // ✅ NEW: Check if approx display needed
  bool _shouldShowApprox(Map<String, dynamic>? salon) {
    final rate = _getExchangeRateForSalon(salon);
    final salonCurrency = _getSalonCurrencyCode(salon);
    return rate != null &&
        rate > 0 &&
        _userCurrencyCode != salonCurrency;
  }

  // ============================================
  // INITIALIZATION
  // ============================================

  Future<void> _initialize() async {
    await TimezoneService.initialize();

    // ✅ NEW: Load user's preferred currency
    try {
      _userCurrencyCode = await _currencySettings.getUserCurrency();
      debugPrint('✅ User currency loaded: $_userCurrencyCode');
    } catch (e) {
      debugPrint('⚠️ Failed to load user currency: $e');
      _userCurrencyCode = _kDefaultCurrency;
    }

    await _loadOffers();
  }

  // ============================================
  // ✅ NEW: Load exchange rate for a specific salon
  // ============================================
  Future<double?> _loadExchangeRateForSalon(int salonId, String salonCurrency) async {
    // Same currency → rate = 1.0
    if (salonCurrency == _userCurrencyCode) {
      _salonExchangeRates[salonId] = 1.0;
      return 1.0;
    }

    // Check cache
    if (_salonExchangeRates.containsKey(salonId)) {
      return _salonExchangeRates[salonId];
    }

    try {
      final rate = await _currencySettings.getExchangeRate(
        fromCurrency: salonCurrency,
        toCurrency: _userCurrencyCode,
      );
      _salonExchangeRates[salonId] = rate;
      debugPrint(
        '✅ Exchange rate for salon $salonId: 1 $salonCurrency = '
        '${rate?.toStringAsFixed(6) ?? "?"} $_userCurrencyCode',
      );
      return rate;
    } catch (e) {
      debugPrint('⚠️ Failed to load rate for salon $salonId: $e');
      _salonExchangeRates[salonId] = null;
      return null;
    }
  }

  // ============================================
  // ✅ ROLE CHECK (role name based)
  // ============================================

  Future<bool> _checkCustomerActive() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final result = await supabase
          .from('user_roles')
          .select('status, roles!inner(name)')
          .eq('user_id', user.id)
          .eq('roles.name', 'customer')
          .maybeSingle();

      return result != null && result['status'] == 'active';
    } catch (e) {
      debugPrint('Role check error: $e');
      return false;
    }
  }

  Future<String?> _checkProfileStatus() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'Please login to continue';

    try {
      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck == null) return null;

      if (profileCheck['is_blocked'] == true) {
        return 'Your account has been blocked. Please contact support.';
      }
      if (profileCheck['is_active'] == false) {
        return 'Your profile is inactive. Please contact support.';
      }
      return null;
    } catch (e) {
      debugPrint('Profile check error: $e');
      return null;
    }
  }

  // ============================================
  // ✅ LOAD OFFERS (with currency + timezone)
  // ============================================

  Future<void> _loadOffers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // ✅ Refresh user currency (in case changed from settings)
      try {
        _userCurrencyCode = await _currencySettings.getUserCurrency();
      } catch (e) {
        debugPrint('⚠️ Failed to refresh user currency: $e');
      }

      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to view offers';
          _isLoading = false;
        });
        return;
      }

      // ✅ Role check by name
      final isCustomer = await _checkCustomerActive();
      if (!mounted) return;

      if (!isCustomer) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Your account is not active. Please contact support.';
          _isLoading = false;
        });
        return;
      }

      // ✅ Profile status check
      final profileError = await _checkProfileStatus();
      if (!mounted) return;

      if (profileError != null) {
        setState(() {
          _hasError = true;
          _errorMessage = profileError;
          _isLoading = false;
        });
        return;
      }

      final followedSalonsResult = await supabase
          .from('salon_followers')
          .select('salon_id')
          .eq('customer_id', user.id);

      if (!mounted) return;

      if (followedSalonsResult.isEmpty) {
        setState(() {
          _offers = [];
          _isLoading = false;
        });
        return;
      }

      final List<int> followedSalonIds = [];
      for (var item in followedSalonsResult) {
        followedSalonIds.add(item['salon_id'] as int);
      }

      final todayUtc = DateTime.now().toUtc().toIso8601String().split('T')[0];

      // ✅ Load offers + offer_services + salon currency/timezone
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
            image_url,
            is_active,
            usage_limit,
            used_count,
            salon_id,
            salons:salon_id (
              id,
              name,
              logo_url,
              address,
              phone,
              currency_code,
              currency_symbol,
              timezone
            ),
            offer_services (
              service_id,
              variant_id,
              services:service_id (id, name),
              service_variants:variant_id (id, salon_gender_id, salon_age_category_id)
            )
          ''')
          .inFilter('salon_id', followedSalonIds)
          .eq('is_active', true)
          .lte('valid_from', todayUtc)
          .gte('valid_to', todayUtc)
          .order('created_at', ascending: false);

      if (!mounted) return;

      if (result.isEmpty) {
        setState(() {
          _offers = [];
          _isLoading = false;
        });
        return;
      }

      // ✅ NEW: Load exchange rates for all unique salons
      final uniqueSalons = <int, String>{};
      for (final o in result) {
        final salon = o['salons'] as Map<String, dynamic>?;
        final salonId = salon?['id'] as int?;
        final salonCurrency = _getSalonCurrencyCode(salon);
        if (salonId != null) {
          uniqueSalons[salonId] = salonCurrency;
        }
      }

      // Load rates in parallel
      await Future.wait(
        uniqueSalons.entries.map((e) => _loadExchangeRateForSalon(e.key, e.value)),
      );

      if (!mounted) return;

      // ✅ Load customer claims
      final offerIds = result.map<int>((o) => o['id'] as int).toList();
      Map<int, String> claimStatus = {};

      try {
        final claims = await supabase
            .from('customer_offers')
            .select('offer_id, status')
            .eq('customer_id', user.id)
            .inFilter('offer_id', offerIds);

        if (!mounted) return;

        for (var claim in claims) {
          claimStatus[claim['offer_id'] as int] = claim['status'] as String;
        }
      } catch (e) {
        debugPrint('Error loading claims: $e');
      }

      // ✅ Load gender/age lookups for variant labels
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
        final genders = await supabase
            .from('salon_genders')
            .select('id, display_name')
            .inFilter('id', genderIds.toList());
        if (!mounted) return;
        for (var g in genders) {
          genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
        }
      }

      final Map<int, String> ageMap = {};
      if (ageIds.isNotEmpty) {
        final ages = await supabase
            .from('salon_age_categories')
            .select('id, display_name')
            .inFilter('id', ageIds.toList());
        if (!mounted) return;
        for (var a in ages) {
          ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
        }
      }

      // ✅ Build variant/scope summary + merge claim status + precompute dates
      final enriched = result.map<Map<String, dynamic>>((o) {
        final offer = Map<String, dynamic>.from(o);
        final svcList = (offer['offer_services'] as List? ?? []);
        final scopeParts = <String>[];

        for (final os in svcList) {
          final service = os['services'];
          final variant = os['service_variants'];
          final serviceName = service?['name']?.toString() ?? 'Service';

          if (variant == null) {
            scopeParts.add(serviceName);
          } else {
            final gid = variant['salon_gender_id'] as int?;
            final aid = variant['salon_age_category_id'] as int?;
            final gender = gid != null ? (genderMap[gid] ?? '') : '';
            final age = aid != null ? (ageMap[aid] ?? '') : '';
            final labelParts = <String>[];
            if (gender.isNotEmpty) labelParts.add(gender);
            if (age.isNotEmpty) labelParts.add(age);
            final vLabel =
                labelParts.isEmpty ? 'Standard' : labelParts.join(' ');
            scopeParts.add('$serviceName · $vLabel');
          }
        }

        final salon = offer['salons'] as Map<String, dynamic>?;
        final salonTz = _getSalonTimezone(salon);
        final salonId = salon?['id'] as int?;

        offer['scope_summary'] =
            scopeParts.isEmpty ? 'All services' : scopeParts.join(', ');
        offer['claim_status'] = claimStatus[offer['id'] as int];
        offer['_salon_timezone'] = salonTz;

        // ✅ NEW: Attach cached exchange rate
        if (salonId != null) {
          offer['_exchange_rate'] = _salonExchangeRates[salonId];
        }

        // ✅ Precompute days_left using SALON timezone
        offer['_days_left'] = _getDaysLeft(
          offer['valid_to'] as String,
          salonTimezone: salonTz,
        );
        // ✅ Precompute is_active using SALON timezone
        offer['_is_active'] = _isOfferActiveWithTimezone(
          offer,
          salonTimezone: salonTz,
        );

        return offer;
      }).toList();

      if (!mounted) return;
      setState(() {
        _offers = enriched;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading offers: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load offers. Please try again.';
        _isLoading = false;
      });
    }
  }

  // ============================================
  // ✅ DATE HELPERS (SALON TIMEZONE)
  // ============================================

  int _getDaysLeft(String validTo, {String? salonTimezone}) {
    try {
      final tz = salonTimezone ?? _kDefaultSalonTimezone;

      // ✅ Get "now" in SALON timezone
      DateTime salonNow;
      try {
        salonNow = TimezoneService.getNowInTimezone(tz);
      } catch (e) {
        salonNow = DateTime.now();
      }

      final todaySalonMidnight = DateTime(
        salonNow.year,
        salonNow.month,
        salonNow.day,
      );

      final validToDate = DateTime.parse(validTo);
      final validToMidnight = DateTime(
        validToDate.year,
        validToDate.month,
        validToDate.day,
      );

      return validToMidnight.difference(todaySalonMidnight).inDays;
    } catch (e) {
      debugPrint('Error calculating days left: $e');
      return -1;
    }
  }

  bool _isOfferActiveWithTimezone(
    Map<String, dynamic> offer, {
    String? salonTimezone,
  }) {
    try {
      final tz = salonTimezone ??
          (offer['_salon_timezone'] as String?) ??
          _kDefaultSalonTimezone;

      final validFromUtc = DateTime.parse(offer['valid_from'] as String);
      final validToUtc = DateTime.parse(offer['valid_to'] as String);

      // ✅ Get "now" in SALON timezone
      DateTime salonNow;
      try {
        salonNow = TimezoneService.getNowInTimezone(tz);
      } catch (e) {
        salonNow = DateTime.now();
      }

      final todaySalonMidnight = DateTime(
        salonNow.year,
        salonNow.month,
        salonNow.day,
      );

      final fromSalonMidnight = DateTime(
        validFromUtc.year,
        validFromUtc.month,
        validFromUtc.day,
      );
      final toSalonMidnight = DateTime(
        validToUtc.year,
        validToUtc.month,
        validToUtc.day,
      );

      return !fromSalonMidnight.isAfter(todaySalonMidnight) &&
          toSalonMidnight.isAfter(todaySalonMidnight);
    } catch (e) {
      debugPrint('Error checking offer active: $e');
      return false;
    }
  }

  // ============================================
  // ✅ FILTERED AND SORTED OFFERS
  // ============================================

  List<Map<String, dynamic>> get _filteredAndSortedOffers {
    List<Map<String, dynamic>> filtered = List.from(_offers);

    switch (_selectedFilter) {
      case 'active':
        filtered = filtered
            .where((offer) => offer['_is_active'] == true)
            .toList();
        break;
      case 'expiring':
        filtered = filtered.where((offer) {
          final daysLeft = offer['_days_left'] as int? ?? -1;
          return daysLeft <= 7 && daysLeft >= 0;
        }).toList();
        break;
      case 'points':
        filtered = filtered.where((offer) {
          return (offer['points_required'] ?? 0) > 0;
        }).toList();
        break;
      default:
        break;
    }

    switch (_selectedSort) {
      case 'newest':
        filtered.sort((a, b) {
          final aDate = DateTime.parse(a['valid_from']);
          final bDate = DateTime.parse(b['valid_from']);
          return bDate.compareTo(aDate);
        });
        break;
      case 'discount':
        filtered.sort((a, b) {
          final aValue = (a['discount_value'] ?? 0).toDouble();
          final bValue = (b['discount_value'] ?? 0).toDouble();
          return bValue.compareTo(aValue);
        });
        break;
      case 'points':
        filtered.sort((a, b) {
          final aPoints = a['points_required'] ?? 0;
          final bPoints = b['points_required'] ?? 0;
          return aPoints.compareTo(bPoints);
        });
        break;
      default:
        break;
    }

    return filtered;
  }

  // ============================================
  // ✅ HELPER METHODS (with salon currency)
  // ============================================

  String _getDiscountText(Map<String, dynamic> offer) {
    if (offer['discount_type'] == 'percentage') {
      return '${offer['discount_value']}% OFF';
    } else if (offer['discount_type'] == 'fixed') {
      // ✅ Use salon currency symbol
      final salon = offer['salons'] as Map<String, dynamic>?;
      final symbol = _getSalonCurrencySymbol(salon);
      final value = (offer['discount_value'] as num?)?.toDouble() ?? 0;
      return '$symbol ${value.toStringAsFixed(2)} OFF';
    } else {
      return 'FREE SERVICE';
    }
  }

  // ✅ NEW: Approx user currency for fixed discount
  String? _getDiscountUserApprox(Map<String, dynamic> offer) {
    if (offer['discount_type'] != 'fixed') return null;

    final salon = offer['salons'] as Map<String, dynamic>?;
    if (!_shouldShowApprox(salon)) return null;

    final rate = _getExchangeRateForSalon(salon);
    if (rate == null || rate <= 0) return null;

    final value = (offer['discount_value'] as num?)?.toDouble() ?? 0;
    final userAmount = value * rate;
    return _formatUserPrice(userAmount);
  }

  String _getDiscountIcon(String? discountType) {
    switch (discountType) {
      case 'percentage':
        return '💰';
      case 'fixed':
        return '💵';
      case 'free_service':
        return '🎁';
      default:
        return '🏷️';
    }
  }

  Color _getDiscountColor(String? discountType) {
    switch (discountType) {
      case 'percentage':
        return AppTheme.primary;
      case 'fixed':
        return Colors.green.shade600;
      case 'free_service':
        return Colors.purple.shade600;
      default:
        return Colors.orange.shade600;
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================
  // ✅ APPLY OFFER (with salon-specific points)
  // ============================================

  Future<void> _applyOffer(Map<String, dynamic> offer) async {
    final offerId = offer['id'] as int;

    if (_claimingOfferIds.contains(offerId)) return;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          _showSnackBar('Please login to apply offers', Colors.orange);
          context.push('/login');
        }
        return;
      }

      // Already claimed check
      if (offer['claim_status'] == 'active') {
        if (mounted) {
          _showSnackBar(
            'You have already claimed this offer',
            Colors.orange,
          );
        }
        return;
      }
      if (offer['claim_status'] == 'used') {
        if (mounted) {
          _showSnackBar('You have already used this offer', Colors.red);
        }
        return;
      }

      // Role check by name
      final isCustomer = await _checkCustomerActive();
      if (!mounted) return;

      if (!isCustomer) {
        _showSnackBar(
          'Your account is not active. Please contact support.',
          Colors.red,
        );
        return;
      }

      // Profile status check
      final profileError = await _checkProfileStatus();
      if (!mounted) return;

      if (profileError != null) {
        _showSnackBar(profileError, Colors.red);
        return;
      }

      // ✅ Use precomputed active status
      if (offer['_is_active'] != true) {
        if (mounted) _showSnackBar('This offer has expired', Colors.red);
        return;
      }

      // ✅ Salon-specific points check
      final pointsRequired =
          (offer['points_required'] as num?)?.toInt() ?? 0;
      final offerSalonId = offer['salon_id'] as int?;

      if (pointsRequired > 0 && offerSalonId != null) {
        try {
          final loyaltyResult = await supabase.rpc(
            'get_customer_loyalty_for_salon',
            params: {
              'p_customer_id': user.id,
              'p_salon_id': offerSalonId,
            },
          );

          if (!mounted) return;

          final userPoints = (loyaltyResult is Map)
              ? (loyaltyResult['current_points'] as num?)?.toInt() ?? 0
              : 0;

          if (userPoints < pointsRequired) {
            if (mounted) {
              _showSnackBar(
                'You need $pointsRequired points at this salon to apply',
                Colors.orange,
              );
            }
            return;
          }
        } catch (e) {
          debugPrint('⚠️ Error checking salon loyalty: $e');
          // Fall through — server will validate anyway
        }
      }

      // Usage limit check
      final usageLimit = offer['usage_limit'];
      final usedCount = offer['used_count'] ?? 0;
      if (usageLimit != null && usedCount >= usageLimit) {
        if (mounted) {
          _showSnackBar(
            'This offer has reached its usage limit',
            Colors.red,
          );
        }
        return;
      }

      if (!mounted) return;

      // ✅ UPDATED: Confirm dialog with user approx
      final salon = offer['salons'] as Map<String, dynamic>?;
      final userApprox = _getDiscountUserApprox(offer);

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          backgroundColor: context.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Text(
                _getDiscountIcon(offer['discount_type']),
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  offer['title'] as String? ?? 'Offer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer['description'] as String? ?? '',
                  style: TextStyle(color: context.secondaryTextColor),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getDiscountColor(offer['discount_type'])
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _getDiscountText(offer),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _getDiscountColor(offer['discount_type']),
                        ),
                      ),
                      // ✅ NEW: user approx in dialog
                      if (userApprox != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '≈ $userApprox in your currency',
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: context.secondaryTextColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if ((offer['scope_summary'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Scope: ${offer['scope_summary']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (pointsRequired > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Requires $pointsRequired points at this salon',
                          style: const TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
                // ✅ NEW: Payment note
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: context.secondaryTextColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Payment charged in ${_getSalonCurrencyCode(salon)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: context.secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
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
                style: TextStyle(color: context.secondaryTextColor),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply Offer'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (confirmed != true) return;

      setState(() => _claimingOfferIds.add(offerId));

      // ✅ Atomic RPC (salon-specific)
      final response = await supabase.rpc(
        'claim_offer',
        params: {'p_offer_id': offerId},
      );

      if (!mounted) return;
      setState(() => _claimingOfferIds.remove(offerId));

      final result =
          response is Map ? response : <String, dynamic>{};
      final success = result['success'] == true;

      if (!success) {
        final msg =
            (result['message'] ?? 'Failed to claim offer').toString();
        _showSnackBar(msg, Colors.red);
        if (mounted) await _loadOffers();
        return;
      }

      _showSnackBar(
        '✅ "${offer['title']}" applied successfully!',
        Colors.green,
      );

      // Refresh in background
      if (mounted) _loadOffers();

      // Navigate to booking flow with offer
      if (mounted) {
        context.push(
          '/customer/booking-flow',
          extra: {'offer': offer},
        );
      }
    } catch (e) {
      debugPrint('Error applying offer: $e');
      if (mounted) {
        setState(() => _claimingOfferIds.remove(offerId));
        _showSnackBar(
          'Error applying offer. Please try again.',
          Colors.red,
        );
      }
    }
  }

  // ============================================
  // NAVIGATION METHODS
  // ============================================

  void _navigateToSalonProfile(Map<String, dynamic>? salonData) {
    if (salonData == null || salonData.isEmpty) return;
    final salon = <String, dynamic>{
      'id': salonData['id'],
      'name': salonData['name'],
      'logo_url': salonData['logo_url'],
      'address': salonData['address'],
      'phone': salonData['phone'],
    };
    context.push('/customer/salon-profile', extra: salon);
  }

  // ============================================
  // ✅ OFFER CARD
  // ============================================

  Widget _buildOfferCard(
    Map<String, dynamic> offer, {
    required bool isMobile,
  }) {
    final isDark = context.isDarkMode;
    final salonData = offer['salons'] as Map<String, dynamic>?;
    final salonName = salonData?['name']?.toString() ?? 'Salon';
    final salonLogo = salonData?['logo_url']?.toString();
    final salonAddress = salonData?['address']?.toString();

    final offerId = offer['id'] as int;
    final isClaiming = _claimingOfferIds.contains(offerId);
    final claimStatus = offer['claim_status'] as String?;
    final isClaimed = claimStatus == 'active';
    final isUsed = claimStatus == 'used';

    // ✅ Use precomputed values
    final daysLeft = offer['_days_left'] as int? ?? -1;
    final isActive = offer['_is_active'] as bool? ?? false;

    final discountColor = _getDiscountColor(offer['discount_type']);
    final discountIcon = _getDiscountIcon(offer['discount_type']);
    final discountText = _getDiscountText(offer);
    final discountUserApprox = _getDiscountUserApprox(offer); // ✅ NEW
    final scopeSummary = offer['scope_summary']?.toString() ?? '';

    String statusText = '';
    Color? statusColor = Colors.green;

    if (daysLeft < 0) {
      statusText = 'Expired';
      statusColor = isDark ? Colors.red[300] : Colors.red;
    } else if (daysLeft == 0) {
      statusText = 'Last day';
      statusColor = isDark ? Colors.orange[300] : Colors.orange;
    } else if (daysLeft <= 3) {
      statusText = '$daysLeft days left';
      statusColor = isDark ? Colors.orange[300] : Colors.orange;
    } else if (daysLeft <= 7) {
      statusText = '$daysLeft days left';
      statusColor = isDark ? Colors.blue[300] : Colors.blue;
    } else {
      statusText = '$daysLeft days left';
      statusColor = isDark ? Colors.green[300] : Colors.green;
    }

    // Button label / state
    final String buttonLabel;
    final bool buttonEnabled;
    if (isClaiming) {
      buttonLabel = 'Claiming...';
      buttonEnabled = false;
    } else if (isUsed) {
      buttonLabel = 'Used';
      buttonEnabled = false;
    } else if (isClaimed) {
      buttonLabel = 'Claimed';
      buttonEnabled = false;
    } else if (!isActive) {
      buttonLabel = 'Expired';
      buttonEnabled = false;
    } else {
      buttonLabel = 'Apply Offer';
      buttonEnabled = true;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? discountColor.withValues(alpha: 0.15)
                  : discountColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _navigateToSalonProfile(salonData),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: isDark
                        ? discountColor.withValues(alpha: 0.2)
                        : discountColor.withValues(alpha: 0.1),
                    backgroundImage: salonLogo != null
                        ? NetworkImage(salonLogo)
                        : null,
                    child: salonLogo == null
                        ? Text(
                            salonName.isNotEmpty
                                ? salonName[0].toUpperCase()
                                : 'S',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.white : discountColor,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _navigateToSalonProfile(salonData),
                        child: Text(
                          salonName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                isDark ? Colors.white : Colors.grey[800],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (salonAddress != null)
                        Text(
                          salonAddress,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isUsed || isClaimed)
                  Container(
                    constraints: const BoxConstraints(minWidth: 70),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (isUsed ? Colors.grey : Colors.green)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUsed ? Icons.check_circle : Icons.bookmark,
                          size: 12,
                          color: isUsed ? Colors.grey : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isUsed ? 'Used' : 'Claimed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isUsed ? Colors.grey : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(minWidth: 70),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor?.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
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

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ UPDATED: Discount chip with user approx
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        discountColor,
                        discountColor.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        discountIcon,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            discountText,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          // ✅ NEW: approx in chip
                          if (discountUserApprox != null)
                            Text(
                              '≈ $discountUserApprox',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  offer['title'] as String? ?? 'Offer',
                  style: TextStyle(
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  offer['description'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                if (scopeSummary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: discountColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.content_cut,
                          size: 12,
                          color: discountColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            scopeSummary,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: discountColor,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                if ((offer['points_required'] ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.amber[800]!.withValues(alpha: 0.2)
                          : Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${offer['points_required']} points required',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.amber[300]
                                : Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: buttonEnabled
                            ? () => _applyOffer(offer)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: discountColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[300],
                          disabledForegroundColor: isDark
                              ? Colors.white38
                              : Colors.grey[600],
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isClaiming
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                buttonLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () =>
                          _navigateToSalonProfile(salonData),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.white60
                            : Colors.grey[600],
                        side: BorderSide(
                          color: isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'View Salon',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white60
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // WEB LAYOUT
  // ============================================

  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;
    final filteredOffers = _filteredAndSortedOffers;

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.grey[50],
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildFilterSortBar(),
              const SizedBox(height: 16),
              Expanded(
                child: filteredOffers.isEmpty
                    ? _buildEmptyFilterWidget()
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 400,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: filteredOffers.length,
                        itemBuilder: (context, index) => _buildOfferCard(
                          filteredOffers[index],
                          isMobile: false,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // MOBILE LAYOUT
  // ============================================

  Widget _buildMobileLayout() {
    final filteredOffers = _filteredAndSortedOffers;

    return Column(
      children: [
        _buildFilterSortBar(),
        const SizedBox(height: 16),
        Expanded(
          child: filteredOffers.isEmpty
              ? _buildEmptyFilterWidget()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredOffers.length,
                  itemBuilder: (context, index) => _buildOfferCard(
                    filteredOffers[index],
                    isMobile: true,
                  ),
                ),
        ),
      ],
    );
  }

  // ============================================
  // FILTER AND SORT BAR
  // ============================================

  Widget _buildFilterSortBar() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFilter,
                  icon: Icon(
                    Icons.filter_list,
                    size: 18,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  isExpanded: true,
                  dropdownColor:
                      isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('All Offers'),
                    ),
                    DropdownMenuItem(
                      value: 'active',
                      child: Text('Active'),
                    ),
                    DropdownMenuItem(
                      value: 'expiring',
                      child: Text('Expiring Soon'),
                    ),
                    DropdownMenuItem(
                      value: 'points',
                      child: Text('Points Required'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedFilter = value);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSort,
                  icon: Icon(
                    Icons.sort,
                    size: 18,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  isExpanded: true,
                  dropdownColor:
                      isDark ? const Color(0xFF2A2A2A) : Colors.white,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Newest First'),
                    ),
                    DropdownMenuItem(
                      value: 'discount',
                      child: Text('Best Discount'),
                    ),
                    DropdownMenuItem(
                      value: 'points',
                      child: Text('Lowest Points'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedSort = value);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_filteredAndSortedOffers.length}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.primary,
            ),
          ),
          Text(
            ' offers',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // EMPTY FILTER WIDGET
  // ============================================

  Widget _buildEmptyFilterWidget() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off,
            size: 48,
            color: isDark ? Colors.white30 : Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'No offers match your filter',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedFilter = 'all';
                _selectedSort = 'newest';
              });
            },
            child: Text(
              'Clear Filters',
              style: TextStyle(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // MAIN BUILD METHOD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWeb = screenWidth > 800;
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Special Offers',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOffers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading offers...',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              )
            : _hasError
                ? _buildErrorWidget()
                : _offers.isEmpty
                    ? _buildEmptyOffersWidget()
                    : isWeb
                        ? _buildWebLayout()
                        : _buildMobileLayout(),
      ),
    );
  }

  // ============================================
  // ERROR WIDGET
  // ============================================

  Widget _buildErrorWidget() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: isDark ? Colors.white70 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadOffers,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // EMPTY OFFERS WIDGET
  // ============================================

  Widget _buildEmptyOffersWidget() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_offer_outlined,
              size: 64,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Offers Available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow salons to see their special offers here',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Browse Salons'),
          ),
        ],
      ),
    );
  }
}