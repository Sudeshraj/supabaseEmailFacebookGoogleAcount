import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/time_picker_dialog.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import '../../services/notification_service.dart';
import '../../services/currency_service.dart';
import '../../extensions/context_extensions.dart';

// ====================================================================
// CREATE / EDIT OFFER SCREEN — step-by-step wizard
//
// Selection rules:
//   • Variant ☑           → ඒ variant එකට විතරයි (variant_id = X)
//   • Service ☑ (full)    → හැම variant එකටම (variant_id = NULL)
//   • Service ▣ (partial) → සමහර variants
//
// Disabled:
//   • Services with no variants
//   • Services with no priced variants
//   • Individual variants with NULL/0 price
// ====================================================================
class CreateOfferScreen extends StatefulWidget {
  final int salonId;
  final String salonName;
  final String currencyCode;
  final Map<String, dynamic>? editingOffer;

  const CreateOfferScreen({
    super.key,
    required this.salonId,
    required this.salonName,
    required this.currencyCode,
    this.editingOffer,
  });

  @override
  State<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

/// Selection state for service + variant-level offers.
class _ServiceSelection {
  /// Services where ALL priced variants are covered (variant_id = NULL in DB)
  final Set<int> allVariantServices = {};

  /// Individual variant ids that are selected (variant_id = X)
  final Set<int> variantIds = {};

  /// serviceId -> list of ALL variant ids (including NULL-priced, used only
  /// for tri-state detection)
  final Map<int, List<int>> serviceVariantIds = {};

  /// serviceId -> list of PRICED variant ids (used for toggle)
  final Map<int, List<int>> servicePricedVariantIds = {};

  bool isServiceFullySelected(int serviceId) =>
      allVariantServices.contains(serviceId);

  bool isVariantSelected(int variantId) => variantIds.contains(variantId);

  /// Service has at least one priced variant selected but is NOT fully selected.
  bool isServicePartial(int serviceId) {
    if (allVariantServices.contains(serviceId)) return false;
    final vars = servicePricedVariantIds[serviceId] ?? const [];
    return vars.any(variantIds.contains);
  }

  void toggleServiceAll(int serviceId, List<int> pricedVariants) {
    if (allVariantServices.contains(serviceId)) {
      allVariantServices.remove(serviceId);
      for (final v in pricedVariants) {
        variantIds.remove(v);
      }
    } else {
      allVariantServices.add(serviceId);
      for (final v in pricedVariants) {
        variantIds.remove(v);
      }
    }
  }

  void toggleVariant(int serviceId, int variantId, List<int> pricedVariants) {
    if (allVariantServices.contains(serviceId)) {
      // Service was fully selected → switch to specific
      allVariantServices.remove(serviceId);
      for (final v in pricedVariants) {
        if (v != variantId) variantIds.add(v);
      }
      variantIds.remove(variantId);
    } else {
      if (variantIds.contains(variantId)) {
        variantIds.remove(variantId);
      } else {
        variantIds.add(variantId);
      }
    }
  }

  bool get isEmpty => allVariantServices.isEmpty && variantIds.isEmpty;

  void clear() {
    allVariantServices.clear();
    variantIds.clear();
  }
}

class _CreateOfferScreenState extends State<CreateOfferScreen> {
  final supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();
  final CurrencyService _currencyService = CurrencyService.instance;

  // ==================== STEP MANAGEMENT ====================
  int _currentStep = 0;
  int _furthestStep = 0;
  static const int _totalSteps = 4;

  final _detailsFormKey = GlobalKey<FormState>();
  final _limitsFormKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _discountValueController;
  late TextEditingController _pointsRequiredController;
  late TextEditingController _usageLimitController;

  // Form state
  String _discountType = 'percentage';
  DateTime _validFrom = DateTime.now();
  DateTime _validTo = DateTime.now().add(const Duration(days: 30));
  bool _sendNotification = true;

  // Time range
  bool _hasTimeRestriction = false;
  TimeOfDay? _validFromTime;
  TimeOfDay? _validToTime;

  // ✅ Selection
  final _ServiceSelection _selection = _ServiceSelection();
  List<Map<String, dynamic>> _availableServices = [];
  List<Map<String, dynamic>> _serviceMenuTree = [];
  bool _isLoadingServices = false;

  // variant metadata: variant_id -> {service_id, price}
  final Map<int, Map<String, dynamic>> _variantMeta = {};

  final List<Map<String, dynamic>> _menuIconSuggestions = [
    {'icon': Icons.content_cut, 'name': 'content_cut'},
    {'icon': Icons.face, 'name': 'face'},
    {'icon': Icons.face_retouching_natural, 'name': 'face_retouching_natural'},
    {'icon': Icons.spa, 'name': 'spa'},
    {'icon': Icons.handshake, 'name': 'handshake'},
    {'icon': Icons.build, 'name': 'build'},
    {'icon': Icons.brush, 'name': 'brush'},
    {'icon': Icons.water_drop, 'name': 'water_drop'},
    {'icon': Icons.masks, 'name': 'masks'},
    {'icon': Icons.spa_outlined, 'name': 'spa_outlined'},
  ];

  bool _isSaving = false;

  bool get _isEditing => widget.editingOffer != null;
  bool get _isDark => context.isDarkMode;
  bool get _isWeb => context.isWeb;

  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _subTextColor => _isDark ? Colors.white60 : Colors.grey[600]!;
  Color get _cardBg => _isDark ? const Color(0xFF1E1E1E) : Colors.white;
  Color get _fieldFill => _isDark ? const Color(0xFF2A2A2A) : Colors.white;
  Color get _borderColor => _isDark ? Colors.grey[700]! : Colors.grey[300]!;

  String get _salonCurrencySymbol =>
      _currencyService.getSymbol(widget.currencyCode);

  bool get _currencyUsesDecimals =>
      _currencyService.getInfo(widget.currencyCode).decimals > 0;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _discountValueController = TextEditingController();
    _pointsRequiredController = TextEditingController(text: '0');
    _usageLimitController = TextEditingController();

    if (_isEditing) {
      final offer = widget.editingOffer!;
      _titleController.text = offer['title'] ?? '';
      _descriptionController.text = offer['description'] ?? '';
      _discountValueController.text = offer['discount_value']?.toString() ?? '';
      _pointsRequiredController.text =
          offer['points_required']?.toString() ?? '0';
      _usageLimitController.text = offer['usage_limit']?.toString() ?? '';
      _discountType = offer['discount_type'] ?? 'percentage';
      _validFrom = DateTime.parse(offer['valid_from']);
      _validTo = DateTime.parse(offer['valid_to']);

      if (offer['valid_from_time'] != null && offer['valid_to_time'] != null) {
        final fromStr = offer['valid_from_time'].toString();
        final toStr = offer['valid_to_time'].toString();
        if (fromStr.isNotEmpty && toStr.isNotEmpty) {
          _hasTimeRestriction = true;
          _validFromTime = _parseTime(fromStr);
          _validToTime = _parseTime(toStr);
        }
      }
    }

    _loadServiceMenuTree();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _discountValueController.dispose();
    _pointsRequiredController.dispose();
    _usageLimitController.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _ageRangeText(int? minAge, int? maxAge) {
    if (minAge == null || maxAge == null) return '';
    if (maxAge >= 100) return '$minAge+ yrs';
    return '$minAge–$maxAge yrs';
  }

  // ============================================
  // LOAD SERVICE MENU (category → service → variants)
  // ============================================
  Future<void> _loadServiceMenuTree() async {
    setState(() => _isLoadingServices = true);

    try {
      final categoriesResponse = await supabase
          .from('salon_categories')
          .select('id, display_name, icon_name, color, display_order')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      final servicesResponse = await supabase
          .from('services')
          .select('id, name, description, icon_name, category_id, is_active')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('name');

      final flatServices = List<Map<String, dynamic>>.from(servicesResponse);
      final serviceIds = flatServices.map<int>((s) => s['id'] as int).toList();

      final variantsResponse = serviceIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await supabase
                  .from('service_variants')
                  .select(
                    'id, service_id, price, duration, salon_gender_id, salon_age_category_id, is_active',
                  )
                  .inFilter('service_id', serviceIds)
                  .eq('is_active', true),
            );

      final genderIds = variantsResponse
          .map<int?>((v) => v['salon_gender_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final ageIds = variantsResponse
          .map<int?>((v) => v['salon_age_category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      final Map<int, String> genderMap = {};
      if (genderIds.isNotEmpty) {
        try {
          final genders = await supabase
              .from('salon_genders')
              .select('id, display_name')
              .inFilter('id', genderIds);
          for (var g in genders) {
            genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('Error loading genders: $e');
        }
      }

      final Map<int, String> ageMap = {};
      final Map<int, String> ageRangeMap = {};
      if (ageIds.isNotEmpty) {
        try {
          final ages = await supabase
              .from('salon_age_categories')
              .select('id, display_name, min_age, max_age')
              .inFilter('id', ageIds);
          for (var a in ages) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
            ageRangeMap[a['id'] as int] = _ageRangeText(
              (a['min_age'] as num?)?.toInt(),
              (a['max_age'] as num?)?.toInt(),
            );
          }
        } catch (e) {
          debugPrint('Error loading age categories: $e');
        }
      }

      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      _variantMeta.clear();
      for (var v in variantsResponse) {
        final sid = v['service_id'] as int;
        final vid = v['id'] as int;
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;

        final gender = genderId != null ? (genderMap[genderId] ?? '') : '';
        final age = ageId != null ? (ageMap[ageId] ?? '') : '';
        final ageRange = ageId != null ? (ageRangeMap[ageId] ?? '') : '';

        final labelParts = <String>[];
        if (gender.isNotEmpty) labelParts.add(gender);
        if (age.isNotEmpty) {
          labelParts.add(ageRange.isEmpty ? age : '$age ($ageRange)');
        }
        final label = labelParts.isEmpty ? 'Standard' : labelParts.join(' · ');

        final price = (v['price'] as num?)?.toDouble();
        final duration = (v['duration'] as num?)?.toInt();

        variantsByService.putIfAbsent(sid, () => []).add({
          'id': vid,
          'price': price,
          'duration': duration,
          'gender': gender,
          'age': age,
          'age_range': ageRange,
          'label': label,
        });

        _variantMeta[vid] = {'service_id': sid, 'price': price ?? 0};
      }

      final Map<int, List<Map<String, dynamic>>> servicesByCategory = {};
      final List<Map<String, dynamic>> uncategorized = [];
      for (final s in flatServices) {
        final sid = s['id'] as int;
        final catId = s['category_id'] as int?;
        final entry = {
          'id': sid,
          'name': s['name'] ?? 'Service',
          'description': s['description'] ?? '',
          'icon_name': s['icon_name'],
          'variants': variantsByService[sid] ?? <Map<String, dynamic>>[],
        };
        if (catId != null) {
          servicesByCategory.putIfAbsent(catId, () => []).add(entry);
        } else {
          uncategorized.add(entry);
        }
      }

      final List<Map<String, dynamic>> tree = [];
      for (final c in categoriesResponse) {
        final cid = c['id'] as int;
        final services = servicesByCategory[cid] ?? [];
        if (services.isEmpty) continue;
        tree.add({
          'id': cid,
          'display_name': c['display_name'] ?? 'Category',
          'icon_name': c['icon_name'],
          'color': c['color'],
          'services': services,
        });
      }
      if (uncategorized.isNotEmpty) {
        tree.add({
          'id': null,
          'display_name': 'Other',
          'icon_name': null,
          'color': '#9E9E9E',
          'services': uncategorized,
        });
      }

      if (!mounted) return;
      setState(() {
        _availableServices = flatServices;
        _serviceMenuTree = tree;
        _isLoadingServices = false;
      });

      // Build variant id maps
      for (final s in flatServices) {
        final sid = s['id'] as int;
        final variants = variantsByService[sid] ?? <Map<String, dynamic>>[];
        _selection.serviceVariantIds[sid] = variants
            .map<int>((v) => v['id'] as int)
            .toList();
        _selection.servicePricedVariantIds[sid] = variants
            .where((v) {
              final p = v['price'];
              return p != null && (p as num) > 0;
            })
            .map<int>((v) => v['id'] as int)
            .toList();
      }

      // Apply editing state
      if (_isEditing) {
        _applyEditingOffer();
      }
    } catch (e) {
      debugPrint('Error loading service menu: $e');
      if (!mounted) return;
      setState(() => _isLoadingServices = false);
    }
  }

  void _applyEditingOffer() {
    final offerServices = widget.editingOffer!['offer_services'] as List? ?? [];

    if (offerServices.isEmpty) {
      // No specific services → offer applies to everything historically.
      // Since we no longer have "All Services" mode, leave selection empty.
      return;
    }

    _selection.clear();

    for (final os in offerServices) {
      final sid = os['service_id'] as int?;
      final vid = os['variant_id'] as int?;
      if (sid == null) continue;

      if (vid == null) {
        _selection.allVariantServices.add(sid);
      } else {
        _selection.variantIds.add(vid);
      }
    }
  }

  Color _hexToMenuColor(String hex) {
    if (hex.startsWith('#')) {
      try {
        return Color(int.parse('0xFF${hex.substring(1)}'));
      } catch (_) {}
    }
    return const Color(0xFFFF6B8B);
  }

  IconData _menuIconFromName(String? name) {
    final found = _menuIconSuggestions.firstWhere(
      (i) => i['name'] == name,
      orElse: () => _menuIconSuggestions.first,
    );
    return found['icon'] as IconData;
  }

  // ============================================
  // DATE/TIME PICKERS
  // ============================================
  Widget _pickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: AppTheme.primary),
      ),
      child: child!,
    );
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final validFromDay = DateTime(
      _validFrom.year,
      _validFrom.month,
      _validFrom.day,
    );
    final validToDay = DateTime(_validTo.year, _validTo.month, _validTo.day);
    final firstDate = validFromDay.isBefore(today) ? validFromDay : today;
    final farthest = today.add(const Duration(days: 365));
    final lastDate = validToDay.isAfter(farthest) ? validToDay : farthest;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: validFromDay, end: validToDay),
      helpText: 'Select Offer Validity Period',
      builder: _pickerTheme,
    );

    if (picked != null) {
      setState(() {
        _validFrom = picked.start;
        _validTo = picked.end;
      });
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  // ============================================
  // STEP VALIDATION
  // ============================================
  String? _stepError(int step) {
    switch (step) {
      case 0:
        final title = _titleController.text.trim();
        if (title.isEmpty) return 'Please enter offer title';
        if (title.length < 3) return 'Title must be at least 3 characters';
        if (_discountType != 'free_service') {
          final raw = _discountValueController.text;
          final n = double.tryParse(raw);
          if (n == null) return 'Please enter a valid discount value';
          if (n <= 0) return 'Discount must be greater than 0';
          if (_discountType == 'percentage' && n > 100) {
            return 'Percentage cannot exceed 100%';
          }
          if (_discountType == 'fixed' &&
              !_currencyUsesDecimals &&
              raw.contains('.')) {
            final decPart = raw.split('.').last;
            if (decPart.isNotEmpty && int.tryParse(decPart) != 0) {
              return '${widget.currencyCode} does not use decimals';
            }
          }
        }
        return null;
      case 1:
        if (_validTo.isBefore(_validFrom)) {
          return 'End date must be after start date';
        }
        if (_hasTimeRestriction &&
            (_validFromTime == null || _validToTime == null)) {
          return 'Please select both start and end times';
        }
        return null;
      case 2:
        if (_selection.isEmpty) {
          return 'Please select at least one service or variant';
        }
        final pts = _pointsRequiredController.text;
        if (pts.isNotEmpty) {
          final n = int.tryParse(pts);
          if (n == null || n < 0) return 'Invalid points value';
        }
        final lim = _usageLimitController.text;
        if (lim.isNotEmpty) {
          final n = int.tryParse(lim);
          if (n == null || n <= 0) return 'Usage limit must be greater than 0';
        }
        return null;
      default:
        return null;
    }
  }

  void _goNext() {
    if (_currentStep == 0) _detailsFormKey.currentState?.validate();
    if (_currentStep == 2) _limitsFormKey.currentState?.validate();

    final err = _stepError(_currentStep);
    if (err != null) {
      _showSnackBar(err, Colors.orange);
      return;
    }
    setState(() {
      _currentStep++;
      if (_currentStep > _furthestStep) _furthestStep = _currentStep;
    });
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
      if (step > _furthestStep) _furthestStep = step;
    });
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // SAVE OFFER
  // ============================================
  Future<void> _saveOffer() async {
    if (_isSaving) return;

    for (int step = 0; step <= 2; step++) {
      final err = _stepError(step);
      if (err != null) {
        _goToStep(step);
        _showSnackBar(err, Colors.orange);
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Please login');

      final offerData = {
        'salon_id': widget.salonId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'discount_type': _discountType,
        'discount_value': _discountType != 'free_service'
            ? double.parse(_discountValueController.text)
            : 0,
        'points_required': int.tryParse(_pointsRequiredController.text) ?? 0,
        'valid_from': _validFrom.toIso8601String().split('T')[0],
        'valid_to': _validTo.toIso8601String().split('T')[0],
        'valid_from_time': _hasTimeRestriction && _validFromTime != null
            ? '${_validFromTime!.hour.toString().padLeft(2, '0')}:${_validFromTime!.minute.toString().padLeft(2, '0')}:00'
            : null,
        'valid_to_time': _hasTimeRestriction && _validToTime != null
            ? '${_validToTime!.hour.toString().padLeft(2, '0')}:${_validToTime!.minute.toString().padLeft(2, '0')}:00'
            : null,
        'usage_limit': _usageLimitController.text.isNotEmpty
            ? int.parse(_usageLimitController.text)
            : null,
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      int offerId;

      if (_isEditing) {
        final offerId_ = widget.editingOffer!['id'] as int;
        await supabase.from('offers').update(offerData).eq('id', offerId_);
        offerId = offerId_;

        await supabase.from('offer_services').delete().eq('offer_id', offerId);
      } else {
        offerData['created_at'] = DateTime.now().toUtc().toIso8601String();
        offerData['used_count'] = 0;

        final inserted = await supabase
            .from('offers')
            .insert(offerData)
            .select('id')
            .single();
        offerId = inserted['id'] as int;
      }

      // ✅ Build offer_services rows (service + variant level)
      if (!_selection.isEmpty) {
        final rows = <Map<String, dynamic>>[];

        // Service-level rows (variant_id = NULL)
        for (final sid in _selection.allVariantServices) {
          rows.add({
            'offer_id': offerId,
            'service_id': sid,
            'variant_id': null,
          });
        }

        // Variant-level rows
        for (final vid in _selection.variantIds) {
          final meta = _variantMeta[vid];
          if (meta == null) continue;
          final sid = meta['service_id'] as int;
          rows.add({'offer_id': offerId, 'service_id': sid, 'variant_id': vid});
        }

        if (rows.isNotEmpty) {
          await supabase.from('offer_services').insert(rows);
        }
      }

      if (!_isEditing && _sendNotification) {
        await _sendOfferNotifications(offerData, offerId);
      }

      if (!mounted) return;

      _showSnackBar(
        _isEditing
            ? '✏️ Offer updated successfully'
            : '✨ Offer created successfully!',
        context.successColor,
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving offer: $e');
      _showSnackBar('Failed: ${e.toString()}', context.errorColor);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendOfferNotifications(
    Map<String, dynamic> offerData,
    int offerId,
  ) async {
    try {
      final followers = await supabase.rpc(
        'get_active_customer_followers',
        params: {'p_salon_id': widget.salonId},
      );

      if (followers == null || followers.isEmpty) return;

      String discountText;
      if (offerData['discount_type'] == 'percentage') {
        discountText = '${offerData['discount_value']}% OFF';
      } else if (offerData['discount_type'] == 'fixed') {
        discountText =
            '${_currencyService.format(price: offerData['discount_value'], currencyCode: widget.currencyCode)} OFF';
      } else {
        discountText = 'FREE SERVICE';
      }

      for (var follower in followers) {
        try {
          await _notificationService.sendSpecialOffer(
            customerId: follower['customer_id'] as String,
            offerTitle: offerData['title'] as String,
            offerDescription: offerData['description'] as String? ?? '',
            discountText: discountText,
            offerId: offerId,
            salonName: widget.salonName,
          );
        } catch (e) {
          debugPrint('Notification failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Error sending notifications: $e');
    }
  }

  // ============================================
  // SHARED UI HELPERS
  // ============================================
  Widget _buildStepHeader(String title, String subtitle) {
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
              color: _textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 13, color: _subTextColor)),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String message, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.15 : 0.08),
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
                color: _isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        color: _cardBg,
        margin: EdgeInsets.zero,
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
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
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
    String? helperText,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = _isDark;
    return TextFormField(
      controller: controller,
      style: TextStyle(color: _textColor),
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperStyle: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white70 : Colors.grey[500],
        ),
        hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
        prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.grey),
        errorStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderColor),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        fillColor: _fieldFill,
        filled: true,
      ),
    );
  }

  // ============================================
  // STEP INDICATOR
  // ============================================
  static const List<Map<String, dynamic>> _stepMeta = [
    {'label': 'Details', 'icon': Icons.local_offer},
    {'label': 'Validity', 'icon': Icons.event},
    {'label': 'Scope', 'icon': Icons.tune},
    {'label': 'Review', 'icon': Icons.check_circle},
  ];

  Widget _buildStepIndicatorRow() {
    final isMobile = !_isWeb;
    final circleSize = isMobile ? 34.0 : 42.0;

    return Container(
      width: double.infinity,
      color: _cardBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 12 : 16,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    width: isMobile ? 24 : 44,
                    height: 2,
                    margin: EdgeInsets.only(top: circleSize / 2 - 1),
                    color: _furthestStep > i
                        ? AppTheme.primary
                        : (_isDark ? Colors.grey[700] : Colors.grey[300]),
                  ),
              ],
            ],
          ),
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
      behavior: HitTestBehavior.opaque,
      onTap: canTap ? () => _goToStep(step) : null,
      child: SizedBox(
        width: isMobile ? 56 : 68,
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
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isMobile ? 10 : 11,
                color: isActive
                    ? AppTheme.primary
                    : (isDark ? Colors.white60 : Colors.grey[500]),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // STEP 0 — Details
  // ============================================
  Widget _buildStep0() {
    return Form(
      key: _detailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            'Offer Details',
            'Give your offer a name and choose the discount.',
          ),
          _buildCard(
            icon: Icons.local_offer,
            color: AppTheme.primary,
            title: 'Basic Information',
            children: [
              _buildTextField(
                controller: _titleController,
                label: 'Offer Title *',
                hint: 'e.g., Summer Sale',
                icon: Icons.title,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter offer title';
                  }
                  if (v.trim().length < 3) {
                    return 'Title must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _descriptionController,
                label: 'Description (Optional)',
                hint: 'Describe your offer...',
                icon: Icons.description,
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCard(
            icon: Icons.sell,
            color: Colors.green,
            title: 'Discount',
            children: [
              _buildDiscountTypeChips(),
              if (_discountType != 'free_service') ...[
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _discountValueController,
                  label: _discountType == 'percentage'
                      ? 'Discount Value (%) *'
                      : 'Discount Amount ($_salonCurrencySymbol) *',
                  hint: _discountType == 'percentage'
                      ? 'e.g., 20'
                      : 'e.g., 500',
                  icon: _discountType == 'percentage'
                      ? Icons.percent
                      : Icons.payments,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter discount value';
                    }
                    final n = double.tryParse(v);
                    if (n == null) return 'Please enter a valid number';
                    if (n <= 0) return 'Must be greater than 0';
                    if (_discountType == 'percentage' && n > 100) {
                      return 'Percentage cannot exceed 100%';
                    }
                    if (_discountType == 'fixed' &&
                        !_currencyUsesDecimals &&
                        v.contains('.')) {
                      final decPart = v.split('.').last;
                      if (decPart.isNotEmpty && int.tryParse(decPart) != 0) {
                        return '${widget.currencyCode} does not use decimals';
                      }
                    }
                    return null;
                  },
                ),
              ] else
                _buildInfoBanner(
                  'Customers will get the selected service(s) for free.',
                  Icons.card_giftcard,
                  Colors.green,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountTypeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildChoiceChip('Percentage %', 'percentage', Icons.percent),
        _buildChoiceChip(
          'Fixed $_salonCurrencySymbol',
          'fixed',
          Icons.payments,
        ),
        _buildChoiceChip('Free Service', 'free_service', Icons.card_giftcard),
      ],
    );
  }

  Widget _buildChoiceChip(String label, String value, IconData icon) {
    final isSelected = _discountType == value;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected
            ? AppTheme.primary
            : (_isDark ? Colors.white70 : Colors.black54),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppTheme.primary
              : (_isDark ? Colors.white70 : Colors.black87),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      showCheckmark: false,
      selected: isSelected,
      onSelected: (sel) {
        if (sel) setState(() => _discountType = value);
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
      backgroundColor: _cardBg,
      side: BorderSide(
        color: isSelected
            ? AppTheme.primary
            : (_isDark ? Colors.white12 : Colors.grey.shade300),
      ),
    );
  }

  // ============================================
  // STEP 1 — Validity
  // ============================================
  Widget _buildStep1() {
    final days = _validTo.difference(_validFrom).inDays + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Validity Period',
          'Choose when this offer is active.',
        ),
        _buildCard(
          icon: Icons.event,
          color: Colors.blue,
          title: 'Offer Dates',
          children: [
            _buildDateRangeField(),
            if (days > 0)
              _buildInfoBanner(
                'This offer will run for $days day${days == 1 ? '' : 's'}.',
                Icons.info_outline,
                Colors.blue,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _buildCard(
          icon: Icons.access_time,
          color: Colors.purple,
          title: 'Time of Day',
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restrict to specific hours',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Offer valid only during selected hours (e.g., happy hour)',
                        style: TextStyle(fontSize: 12, color: _subTextColor),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _hasTimeRestriction,
                  onChanged: (v) {
                    setState(() {
                      _hasTimeRestriction = v;
                      if (v) {
                        _validFromTime ??= const TimeOfDay(hour: 9, minute: 0);
                        _validToTime ??= const TimeOfDay(hour: 18, minute: 0);
                      } else {
                        _validFromTime = null;
                        _validToTime = null;
                      }
                    });
                  },
                  activeThumbColor: AppTheme.primary,
                ),
              ],
            ),
            if (_hasTimeRestriction) ...[
              const SizedBox(height: 16),
              _buildTimeRangePicker(),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDateRangeField() {
    final df = DateFormat('MMM dd, yyyy');
    return InkWell(
      onTap: _selectDateRange,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppTheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${df.format(_validFrom)}  →  ${df.format(_validTo)}',
                style: TextStyle(fontSize: 14, color: _textColor),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: _isDark ? Colors.white70 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangePicker() {
    return Row(
      children: [
        Expanded(
          child: TimePickerField(
            label: 'Start Time',
            initialTime: _validFromTime ?? const TimeOfDay(hour: 9, minute: 0),
            isRequired: true,
            onTimeSelected: (time) {
              setState(() => _validFromTime = time);
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TimePickerField(
            label: 'End Time',
            initialTime: _validToTime ?? const TimeOfDay(hour: 18, minute: 0),
            isRequired: true,
            onTimeSelected: (time) {
              setState(() => _validToTime = time);
            },
          ),
        ),
      ],
    );
  }

  // ============================================
  // STEP 2 — Scope + Limits + Notify
  // ============================================
  Widget _buildStep2() {
    return Form(
      key: _limitsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            'Scope & Limits',
            'Pick the services or variants and set optional limits.',
          ),
          _buildCard(
            icon: Icons.content_cut,
            color: Colors.indigo,
            title: 'Service Menu',
            children: [_buildServiceMenuTree()],
          ),
          const SizedBox(height: 16),
          _buildCard(
            icon: Icons.tune,
            color: Colors.orange,
            title: 'Limits',
            children: [
              _buildTextField(
                controller: _pointsRequiredController,
                label: 'Points Required',
                hint: '0 (available for all customers)',
                icon: Icons.stars,
                helperText: 'Loyalty points needed to claim',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = int.tryParse(v);
                  if (n == null) return 'Invalid number';
                  if (n < 0) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _usageLimitController,
                label: 'Usage Limit (Optional)',
                hint: 'e.g., 10 (first 10 only)',
                icon: Icons.confirmation_number,
                helperText: 'Leave empty for unlimited uses',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = int.tryParse(v);
                  if (n == null) return 'Invalid number';
                  if (n <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),
            ],
          ),
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            _buildCard(
              icon: Icons.notifications_active,
              color: Colors.blue,
              title: 'Notifications',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notify Followers',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Send a push notification to all salon followers',
                            style: TextStyle(
                              fontSize: 12,
                              color: _subTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _sendNotification,
                      onChanged: (v) => setState(() => _sendNotification = v),
                      activeThumbColor: AppTheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============================================
  // SERVICE MENU TREE (always visible, no All/Specific toggle)
  // ============================================
  Widget _buildServiceMenuTree() {
    if (_isLoadingServices) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    if (_availableServices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No services available. Add services first.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subTextColor),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectionSummary(),
          const Divider(height: 12),
          ..._serviceMenuTree.map((cat) => _buildOfferMenuCategoryBlock(cat)),
        ],
      ),
    );
  }

  Widget _buildSelectionSummary() {
    final serviceCount = _selection.allVariantServices.length;
    final variantCount = _selection.variantIds.length;
    final parts = <String>[];
    if (serviceCount > 0) parts.add('$serviceCount service(s)');
    if (variantCount > 0) parts.add('$variantCount variant(s)');

    // Check if any selectable option exists
    final hasSelectable = _serviceMenuTree.any((cat) {
      for (final s in (cat['services'] as List)) {
        final variants = s['variants'] as List;
        if (variants.any((v) {
          final p = v['price'];
          return p != null && (p as num) > 0;
        })) {
          return true;
        }
      }
      return false;
    });

    return Row(
      children: [
        Expanded(
          child: Text(
            parts.isEmpty ? 'Nothing selected' : parts.join(' · '),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: parts.isEmpty ? _subTextColor : AppTheme.primary,
            ),
          ),
        ),
        TextButton(
          onPressed: hasSelectable
              ? () {
                  setState(() {
                    if (_selection.isEmpty) {
                      // Select all services with priced variants
                      for (final cat in _serviceMenuTree) {
                        for (final s in (cat['services'] as List)) {
                          final sid = s['id'] as int;
                          final priced =
                              _selection.servicePricedVariantIds[sid] ?? [];
                          if (priced.isNotEmpty) {
                            _selection.allVariantServices.add(sid);
                          }
                        }
                      }
                      _selection.variantIds.clear();
                    } else {
                      _selection.clear();
                    }
                  });
                }
              : null,
          child: Text(_selection.isEmpty ? 'Select All' : 'Clear All'),
        ),
      ],
    );
  }

  Widget _buildOfferMenuCategoryBlock(Map<String, dynamic> cat) {
    final color = _hexToMenuColor(cat['color']?.toString() ?? '#FF6B8B');
    final icon = _menuIconFromName(cat['icon_name'] as String?);
    final services = cat['services'] as List;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cat['display_name']?.toString() ?? 'Category',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...services.map(
            (s) => _buildOfferServiceBlock(s as Map<String, dynamic>, color),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferServiceBlock(Map<String, dynamic> service, Color catColor) {
    final sid = service['id'] as int;
    final variants = service['variants'] as List;

    final pricedVariantIds =
        _selection.servicePricedVariantIds[sid] ?? const <int>[];

    final hasVariants = variants.isNotEmpty;
    final hasPricedVariants = pricedVariantIds.isNotEmpty;

    final isFull = _selection.isServiceFullySelected(sid);
    final isPartial = _selection.isServicePartial(sid);

    // ✅ Service is selectable only if it has at least one priced variant
    final canSelectService = hasVariants && hasPricedVariants;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service row
          InkWell(
            onTap: canSelectService
                ? () {
                    setState(() {
                      _selection.toggleServiceAll(sid, pricedVariantIds);
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      tristate: true,
                      value: isFull ? true : (isPartial ? null : false),
                      onChanged: canSelectService
                          ? (_) {
                              setState(() {
                                _selection.toggleServiceAll(
                                  sid,
                                  pricedVariantIds,
                                );
                              });
                            }
                          : null,
                      activeColor: AppTheme.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      service['name']?.toString() ?? 'Service',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: canSelectService ? _textColor : _subTextColor,
                      ),
                    ),
                  ),
                  // ✅ Status badge
                  if (!hasVariants)
                    _buildStatusBadge(
                      'No variants',
                      Colors.orange,
                      Icons.warning_amber,
                    )
                  else if (!hasPricedVariants)
                    _buildStatusBadge(
                      'No price set',
                      Colors.orange,
                      Icons.warning_amber,
                    )
                  else
                    _buildStatusBadge(
                      '${pricedVariantIds.length} priced',
                      Colors.green,
                      Icons.check_circle_outline,
                    ),
                ],
              ),
            ),
          ),
          // Variants
          if (hasVariants)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: variants.asMap().entries.map((e) {
                  final isLast = e.key == variants.length - 1;
                  return _buildOfferVariantRow(
                    service,
                    e.value as Map<String, dynamic>,
                    catColor,
                    isLast,
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferVariantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> variant,
    Color catColor,
    bool isLast,
  ) {
    final sid = service['id'] as int;
    final vid = variant['id'] as int;
    final price = variant['price'] as double?;
    final duration = variant['duration'] as int?;
    final label = variant['label']?.toString() ?? 'Standard';
    final connector = isLast ? '└─' : '├─';

    // ✅ Variant is selectable only if it has a valid price
    final hasPrice = price != null && price > 0;

    final serviceFull = _selection.isServiceFullySelected(sid);
    final variantChecked = serviceFull || _selection.isVariantSelected(vid);

    final pricedVariantIds =
        _selection.servicePricedVariantIds[sid] ?? const <int>[];

    return InkWell(
      onTap: hasPrice
          ? () {
              setState(() {
                _selection.toggleVariant(sid, vid, pricedVariantIds);
              });
            }
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            Text(
              connector,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: catColor.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: variantChecked,
                onChanged: hasPrice
                    ? (_) {
                        setState(() {
                          _selection.toggleVariant(sid, vid, pricedVariantIds);
                        });
                      }
                    : null,
                activeColor: AppTheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: hasPrice ? _textColor : _subTextColor,
                ),
              ),
            ),
            if (duration != null && duration > 0) ...[
              Icon(Icons.timer_outlined, size: 11, color: _subTextColor),
              const SizedBox(width: 2),
              Text(
                '${duration}m',
                style: TextStyle(fontSize: 11, color: _subTextColor),
              ),
              const SizedBox(width: 8),
            ],
            // ✅ Price or "No price" badge
            if (!hasPrice)
              _buildStatusBadge('No price', Colors.orange, Icons.warning_amber)
            else
              Text(
                'Rs. ${price.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // STEP 3 — Review
  // ============================================
  String get _discountSummary {
    if (_discountType == 'free_service') return 'Free Service';
    final v = double.tryParse(_discountValueController.text);
    if (v == null) return 'Not set';
    if (_discountType == 'percentage') {
      return '${_discountValueController.text}% OFF';
    }
    return '${_currencyService.format(price: v, currencyCode: widget.currencyCode)} OFF';
  }

  String get _servicesSummary {
    final serviceCount = _selection.allVariantServices.length;
    final variantCount = _selection.variantIds.length;

    if (serviceCount == 0 && variantCount == 0) {
      return 'No selection';
    }

    final List<String> labels = [];

    for (final cat in _serviceMenuTree) {
      for (final s in (cat['services'] as List)) {
        final sid = s['id'] as int;
        if (_selection.allVariantServices.contains(sid)) {
          labels.add('${s['name']} (all variants)');
        } else {
          for (final v in (s['variants'] as List)) {
            final vid = v['id'] as int;
            if (_selection.variantIds.contains(vid)) {
              final vLabel = v['label']?.toString() ?? 'Variant';
              labels.add('${s['name']} · $vLabel');
            }
          }
        }
      }
    }

    if (labels.isEmpty) {
      return '$serviceCount service(s) · $variantCount variant(s)';
    }

    if (labels.length <= 3) {
      return labels.join(', ');
    }
    return '${labels.take(3).join(', ')} +${labels.length - 3} more';
  }

  Widget _buildReviewTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDark ? Colors.grey[700]! : Colors.grey[200]!,
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
                  style: TextStyle(fontSize: 12, color: _subTextColor),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
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
    final df = DateFormat('MMM dd, yyyy');
    final timeText =
        _hasTimeRestriction && _validFromTime != null && _validToTime != null
        ? '\n${_formatTime(_validFromTime!)} - ${_formatTime(_validToTime!)} daily'
        : '';

    final points = int.tryParse(_pointsRequiredController.text) ?? 0;
    final limit = _usageLimitController.text.isEmpty
        ? 'Unlimited uses'
        : '${_usageLimitController.text} uses';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          _isEditing ? 'Review & Update' : 'Review & Create',
          'Check everything below, then tap "${_isEditing ? 'Update Offer' : 'Create Offer'}" to finish.',
        ),
        _buildReviewTile(
          icon: Icons.local_offer,
          title: 'Offer Title',
          value: _titleController.text.trim().isEmpty
              ? 'Not set'
              : _titleController.text.trim(),
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.sell,
          title: 'Discount',
          value: _discountSummary,
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.event,
          title: 'Validity',
          value: '${df.format(_validFrom)} → ${df.format(_validTo)}$timeText',
          onEdit: () => _goToStep(1),
        ),
        _buildReviewTile(
          icon: Icons.content_cut,
          title: 'Service / Variant Scope',
          value: _servicesSummary,
          onEdit: () => _goToStep(2),
        ),
        _buildReviewTile(
          icon: Icons.tune,
          title: 'Points Required · Usage Limit',
          value: '$points pts · $limit',
          onEdit: () => _goToStep(2),
        ),
        if (!_isEditing)
          _buildReviewTile(
            icon: Icons.notifications_active,
            title: 'Notify Followers',
            value: _sendNotification ? 'Yes' : 'No',
            onEdit: () => _goToStep(2),
          ),
        _buildInfoBanner(
          _isEditing
              ? 'Tapping "Update Offer" will save your changes.'
              : 'Tapping "Create Offer" will publish this offer with the details above.',
          Icons.info_outline,
          AppTheme.primary,
        ),
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
        return _buildStep2();
      case 3:
        return _buildReviewStep();
      default:
        return const SizedBox();
    }
  }

  // ============================================
  // STEP ACTIONS
  // ============================================
  Widget _buildStepActions() {
    final isDark = _isDark;
    final isLastStep = _currentStep == _totalSteps - 1;
    final busy = _isSaving;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.arrow_back, size: 18),
                        SizedBox(width: 6),
                        Text('Back'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: _currentStep > 0 ? 2 : 1,
              child: ElevatedButton(
                onPressed: busy ? null : (isLastStep ? _saveOffer : _goNext),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Saving...',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLastStep
                                  ? (_isEditing
                                        ? 'Update Offer'
                                        : 'Create Offer')
                                  : 'Continue',
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
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Offer' : 'Create New Offer',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWeb ? 1000 : double.infinity,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStepIndicatorRow(),
                    Padding(
                      padding: EdgeInsets.all(isWeb ? 32 : 16),
                      child: _buildStepContent(),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWeb ? 32 : 16,
                        0,
                        isWeb ? 32 : 16,
                        isWeb ? 32 : 16,
                      ),
                      child: _buildStepActions(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
