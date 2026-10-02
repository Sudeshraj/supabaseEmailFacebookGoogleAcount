import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

/// Barber ට / Owner ට appointment එකකට services add/remove කරන්නයි extra
/// charge දාන්නයි bottom sheet එක. Save කළාම
/// `barber_update_appointment_services` RPC එක call වෙනවා.
///
/// appointment map එකේ තියෙන්න ඕන keys:
///   id, salon_id, offer_id, customer_name, services
///   (appointment_services rows — supports both `id` and
///   `appointment_service_id` keys), extra_charge, extra_charge_note
///
/// Save සාර්ථක නම් `true` return කරනවා (screen එක refresh කරන්න).
class EditAppointmentServicesSheet extends StatefulWidget {
  final Map<String, dynamic> appointment;

  const EditAppointmentServicesSheet({super.key, required this.appointment});

  @override
  State<EditAppointmentServicesSheet> createState() =>
      _EditAppointmentServicesSheetState();
}

class _EditAppointmentServicesSheetState
    extends State<EditAppointmentServicesSheet> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  // Salon services catalog (service -> variants), flat-queried (see _load())
  List<Map<String, dynamic>> _catalog = [];

  // දැනට appointment එකේ තියෙන services
  final List<Map<String, dynamic>> _existing = [];
  final Set<int> _removeIds = {};

  // අලුතින් add කරපු (තාම save කරලා නෑ)
  final List<Map<String, dynamic>> _added = [];

  // Appointment එකේ offer එක (active නම්)
  Map<String, dynamic>? _offer;
  Set<int> _offerServiceIds = {};

  final TextEditingController _extraCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  int? _expandedServiceId;
  String _search = '';
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();

    // ✅ FIX: services rows may use either `id` (barber screen) or
    // `appointment_service_id` (owner screen) as the primary key. Normalize
    // everything to `id` so downstream code has a single source of truth.
    final services = widget.appointment['services'] as List? ?? [];
    for (final s in services) {
      if (s == null) continue;
      final raw = Map<String, dynamic>.from(s as Map);

      // Normalize id
      if (raw['id'] == null && raw['appointment_service_id'] != null) {
        raw['id'] = raw['appointment_service_id'];
      }

      // Skip rows without a valid id (shouldn't happen with schema, but
      // defensive against partial data / RLS-filtered joins).
      final idVal = raw['id'];
      if (idVal == null) continue;
      final id = idVal is int ? idVal : int.tryParse(idVal.toString());
      if (id == null || id < 0) continue;
      raw['id'] = id;

      // Normalize numeric fields safely
      raw['duration'] = _toInt(raw['duration'], fallback: 30);
      raw['original_price'] = _toDouble(raw['original_price']);
      raw['discount_amount'] = _toDouble(raw['discount_amount']);
      raw['final_price'] = _toDouble(raw['final_price']);

      _existing.add(raw);
    }

    final extra = _toDouble(widget.appointment['extra_charge']);
    _extraCtrl.text = extra > 0 ? extra.toStringAsFixed(2) : '0';
    _noteCtrl.text = widget.appointment['extra_charge_note']?.toString() ?? '';

    _searchFocus.addListener(() {
      setState(
        () => _showSuggestions = _searchFocus.hasFocus && _search.isNotEmpty,
      );
    });

    _load();
  }

  // ✅ Safe numeric helpers
  int _toInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  double _toDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    _noteCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------------
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final salonId = widget.appointment['salon_id'];
      debugPrint('🔍 [EDIT SHEET] Loading catalog for salon_id: $salonId');

      if (salonId == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Salon id missing from appointment';
          _isLoading = false;
        });
        return;
      }

      // STEP 1: services
      final servicesResponse = await supabase
          .from('services')
          .select('id, name, category_id')
          .eq('salon_id', salonId)
          .eq('is_active', true);

      if (servicesResponse.isEmpty) {
        if (!mounted) return;
        setState(() {
          _catalog = [];
          _isLoading = false;
        });
        return;
      }

      final serviceIds = servicesResponse.map((s) => s['id'] as int).toList();

      // STEP 2: variants
      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, service_id, price, duration, salon_gender_id, salon_age_category_id, is_active',
          )
          .inFilter('service_id', serviceIds);

      final activeVariants = variantsResponse
          .where((v) => v['is_active'] == true)
          .toList();

      // STEP 3: categories
      final categoryIds = servicesResponse
          .map((s) => s['category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      Map<int, String> categoryMap = {};
      if (categoryIds.isNotEmpty) {
        try {
          final rows = await supabase
              .from('salon_categories')
              .select('id, display_name')
              .inFilter('id', categoryIds);
          for (final c in rows) {
            categoryMap[c['id'] as int] =
                c['display_name']?.toString() ?? 'Other';
          }
        } catch (e) {
          debugPrint('⚠️ categories failed: $e');
        }
      }

      // STEP 4: genders
      final genderIds = activeVariants
          .map((v) => v['salon_gender_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      Map<int, String> genderMap = {};
      if (genderIds.isNotEmpty) {
        try {
          final rows = await supabase
              .from('salon_genders')
              .select('id, display_name')
              .inFilter('id', genderIds);
          for (final g in rows) {
            genderMap[g['id'] as int] = g['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('⚠️ genders failed: $e');
        }
      }

      // STEP 5: age categories
      final ageIds = activeVariants
          .map((v) => v['salon_age_category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      Map<int, String> ageMap = {};
      if (ageIds.isNotEmpty) {
        try {
          final rows = await supabase
              .from('salon_age_categories')
              .select('id, display_name')
              .inFilter('id', ageIds);
          for (final a in rows) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
          }
        } catch (e) {
          debugPrint('⚠️ age categories failed: $e');
        }
      }

      // STEP 6: group
      final Map<int, Map<String, dynamic>> grouped = {};
      for (final s in servicesResponse) {
        final id = s['id'] as int;
        final catId = s['category_id'] as int?;
        grouped[id] = {
          'id': id,
          'name': s['name']?.toString() ?? 'Service',
          'category': catId != null ? (categoryMap[catId] ?? '') : '',
          'variants': <Map<String, dynamic>>[],
        };
      }
      for (final v in activeVariants) {
        final sid = v['service_id'] as int;
        final genderId = v['salon_gender_id'] as int?;
        final ageId = v['salon_age_category_id'] as int?;
        final gender = genderId != null ? (genderMap[genderId] ?? '') : '';
        final age = ageId != null ? (ageMap[ageId] ?? '') : '';
        (grouped[sid]?['variants'] as List?)?.add({
          'id': v['id'] as int,
          'price': _toDouble(v['price']),
          'duration': _toInt(v['duration'], fallback: 30),
          'label': '$gender $age'.trim(),
        });
      }

      final catalog = grouped.values.toList();
      debugPrint('✅ [EDIT SHEET] Grouped into ${catalog.length} service(s)');

      // Offer
      Map<String, dynamic>? offer;
      Set<int> offerServiceIds = {};
      final offerId = widget.appointment['offer_id'];
      if (offerId != null) {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final o = await supabase
            .from('offers')
            .select('id, title, discount_type, discount_value')
            .eq('id', offerId)
            .eq('is_active', true)
            .lte('valid_from', today)
            .gte('valid_to', today)
            .maybeSingle();

        if (o != null) {
          offer = o;
          final rows = await supabase
              .from('offer_services')
              .select('service_id')
              .eq('offer_id', offerId);
          offerServiceIds = rows
              .map<int>((r) => r['service_id'] as int)
              .toSet();
        }
      }

      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _offer = offer;
        _offerServiceIds = offerServiceIds;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('❌ [EDIT SHEET] Error loading catalog: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load services: $e';
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------
  // DISCOUNT preview
  // ---------------------------------------------------------------
  bool _offerApplies(int serviceId) {
    if (_offer == null) return false;
    return _offerServiceIds.isEmpty || _offerServiceIds.contains(serviceId);
  }

  double _discountFor(int serviceId, double price) {
    if (!_offerApplies(serviceId)) return 0;
    final type = _offer!['discount_type']?.toString() ?? '';
    final value = _toDouble(_offer!['discount_value']);

    switch (type) {
      case 'percentage':
        return (price * value / 100 * 100).round() / 100;
      case 'fixed':
        return value > price ? price : value;
      case 'free_service':
        return price;
      default:
        return 0;
    }
  }

  String _offerLabel() {
    if (_offer == null) return '';
    final type = _offer!['discount_type']?.toString() ?? '';
    final value = _toDouble(_offer!['discount_value']);
    final v = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    if (type == 'percentage') return '$v% OFF';
    if (type == 'fixed') return 'Rs. $v OFF';
    return 'FREE';
  }

  // ---------------------------------------------------------------
  // SEARCH + SUGGESTIONS
  // ---------------------------------------------------------------
  List<Map<String, dynamic>> get _filteredCatalog {
    if (_search.isEmpty) return _catalog;
    final q = _search.toLowerCase();
    return _catalog.where((s) {
      return s['name'].toString().toLowerCase().contains(q) ||
          s['category'].toString().toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _suggestions {
    if (_search.isEmpty) return [];
    final q = _search.toLowerCase();
    final matches = _catalog
        .where((s) => s['name'].toString().toLowerCase().contains(q))
        .toList();
    matches.sort((a, b) {
      final an = a['name'].toString().toLowerCase();
      final bn = b['name'].toString().toLowerCase();
      final aStarts = an.startsWith(q) ? 0 : 1;
      final bStarts = bn.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts - bStarts;
      return an.compareTo(bn);
    });
    return matches.take(6).toList();
  }

  void _pickSuggestion(Map<String, dynamic> service) {
    final variants = (service['variants'] as List).cast<Map<String, dynamic>>();
    setState(() {
      _searchCtrl.text = service['name'].toString();
      _search = service['name'].toString().toLowerCase();
      _showSuggestions = false;
      _expandedServiceId = service['id'] as int;
    });
    _searchFocus.unfocus();

    if (variants.length == 1) {
      _addVariant(service, variants.first);
    }
  }

  // ---------------------------------------------------------------
  // TOTALS
  // ---------------------------------------------------------------
  double _sum(Iterable<Map<String, dynamic>> items, String key) =>
      items.fold(0.0, (a, i) => a + _toDouble(i[key]));

  List<Map<String, dynamic>> get _kept =>
      _existing.where((s) => !_removeIds.contains(s['id'])).toList();

  double get _extra => double.tryParse(_extraCtrl.text.trim()) ?? 0;

  double get _servicesFinal =>
      _sum(_kept, 'final_price') + _sum(_added, 'final_price');

  double get _discountTotal =>
      _sum(_kept, 'discount_amount') + _sum(_added, 'discount_amount');

  int get _addedDuration =>
      _added.fold(0, (a, i) => a + _toInt(i['duration']));

  int get _removedDuration => _existing
      .where((s) => _removeIds.contains(s['id']))
      .fold(0, (a, i) => a + _toInt(i['duration']));

  int get _durationDelta => _addedDuration - _removedDuration;

  double get _grandTotal => _servicesFinal + _extra;

  // ---------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------
  void _addVariant(Map<String, dynamic> service, Map<String, dynamic> variant) {
    final price = _toDouble(variant['price']);
    final discount = _discountFor(service['id'] as int, price);

    final alreadyAdded = _added.any((a) => a['variant_id'] == variant['id']);
    if (alreadyAdded) {
      _showSnack(
        '${service['name']} is already in the list',
        color: Colors.orange,
      );
      return;
    }

    setState(() {
      _added.add({
        'variant_id': variant['id'],
        'service_id': service['id'],
        'name': service['name'],
        'label': variant['label'],
        'duration': _toInt(variant['duration'], fallback: 30),
        'original_price': price,
        'discount_amount': discount,
        'final_price': price - discount,
      });
    });
    _showSnack('${service['name']} added', color: Colors.green.shade600);
  }

  void _showSnack(String msg, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final text = _extraCtrl.text.trim();
    final extra = double.tryParse(text.isEmpty ? '0' : text);

    if (extra == null || extra < 0) {
      _showSnack('Please enter a valid extra amount');
      return;
    }
    if (_kept.isEmpty && _added.isEmpty) {
      _showSnack('At least one service is required');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final result = await supabase.rpc(
        'barber_update_appointment_services',
        params: {
          'p_appointment_id': widget.appointment['id'],
          'p_add_variant_ids': _added.map((a) => a['variant_id']).toList(),
          'p_remove_ids': _removeIds.toList(),
          'p_extra_charge': extra,
          'p_extra_note': _noteCtrl.text.trim(),
        },
      );

      if (result['success'] == true) {
        if (!mounted) return;
        final newPrice = _toDouble(result['new_price']);
        final newEndTime = result['new_end_time']?.toString();
        final minutesChanged = _toInt(result['minutes_changed']);

        String msg = '✅ Updated.';
        if (result['new_price'] != null) {
          msg += ' Total: Rs. ${newPrice.toStringAsFixed(2)}.';
        }
        if (minutesChanged != 0 && newEndTime != null) {
          final shortTime = newEndTime.length >= 5
              ? newEndTime.substring(0, 5)
              : newEndTime;
          msg += minutesChanged > 0
              ? ' Duration +$minutesChanged min (ends $shortTime).'
              : ' Duration $minutesChanged min (ends $shortTime).';
        }
        _showSnack(msg, color: Colors.green.shade600);
        Navigator.pop(context, true);
      } else {
        throw Exception(result['message'] ?? 'Update failed');
      }
    } catch (e) {
      if (mounted) {
        _showSnack(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------
  // UI HELPERS
  // ---------------------------------------------------------------
  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: context.textColor,
        ),
      ),
    );
  }

  Widget _itemBox({required Widget child, bool highlight = false}) {
    final isDark = context.isDarkMode;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? AppTheme.primary
              : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
        ),
      ),
      child: child,
    );
  }

  Widget _priceText(double original, double discount, {bool struck = false}) {
    final finalPrice = original - discount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (discount > 0)
          Text(
            'Rs. ${original.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              decoration: TextDecoration.lineThrough,
            ),
          ),
        Text(
          'Rs. ${finalPrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: discount > 0 ? Colors.green.shade600 : AppTheme.primary,
            decoration: struck ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }

  Widget _existingRow(Map<String, dynamic> s) {
    // ✅ Safe id extraction — never throws
    final rawId = s['id'] ?? s['appointment_service_id'];
    if (rawId == null) return const SizedBox.shrink();
    final id = rawId is int ? rawId : int.tryParse(rawId.toString());
    if (id == null || id < 0) return const SizedBox.shrink();

    final removed = _removeIds.contains(id);
    final isBarberAdded = s['added_by'] != null;
    final original = _toDouble(s['original_price']);
    final discount = _toDouble(s['discount_amount']);
    final duration = _toInt(s['duration'], fallback: 30);
    final variantLabel = s['variant_label']?.toString() ?? '';

    final wouldBeLastRemoval = !removed && _kept.length <= 1 && _added.isEmpty;

    return _itemBox(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s['service_name']?.toString() ?? 'Service',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.textColor,
                    decoration: removed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  children: [
                    if (variantLabel.isNotEmpty)
                      Text(
                        variantLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primary,
                        ),
                      ),
                    Text(
                      '$duration min${isBarberAdded ? ' • added by staff' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _priceText(original, discount, struck: removed),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              removed ? Icons.undo : Icons.delete_outline,
              size: 20,
              color: removed
                  ? AppTheme.primary
                  : (wouldBeLastRemoval ? Colors.grey : Colors.red),
            ),
            onPressed: wouldBeLastRemoval
                ? () => _showSnack(
                    'At least one service is required - add a replacement first',
                    color: Colors.orange,
                  )
                : () => setState(() {
                    if (removed) {
                      _removeIds.remove(id);
                    } else {
                      _removeIds.add(id);
                    }
                  }),
          ),
        ],
      ),
    );
  }

  Widget _addedRow(int index) {
    final a = _added[index];
    final label = a['label']?.toString() ?? '';

    return _itemBox(
      highlight: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a['name'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  children: [
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primary,
                        ),
                      ),
                    Text(
                      '${a['duration']} min • new',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _priceText(_toDouble(a['original_price']), _toDouble(a['discount_amount'])),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 20, color: Colors.red),
            onPressed: () => setState(() => _added.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _serviceTile(Map<String, dynamic> service) {
    final isDark = context.isDarkMode;
    final id = service['id'] as int;
    final expanded = _expandedServiceId == id;
    final variants = (service['variants'] as List).cast<Map<String, dynamic>>();
    final hasOffer = _offerApplies(id);
    final singleVariant = variants.length == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: variants.isEmpty
                ? null
                : () => setState(
                    () => _expandedServiceId = expanded ? null : id,
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'].toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.textColor,
                          ),
                        ),
                        if ((service['category'] as String).isNotEmpty)
                          Text(
                            service['category'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.secondaryTextColor,
                            ),
                          ),
                        if (variants.isEmpty)
                          Text(
                            'No active variants',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasOffer)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _offerLabel(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ),
                  if (singleVariant)
                    SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () => _addVariant(service, variants.first),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                  else if (variants.isNotEmpty)
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: context.secondaryTextColor,
                    ),
                ],
              ),
            ),
          ),
          if (expanded && !singleVariant)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: variants.map((v) => _variantRow(service, v)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _variantRow(Map<String, dynamic> service, Map<String, dynamic> v) {
    final price = _toDouble(v['price']);
    final discount = _discountFor(service['id'] as int, price);
    final label = v['label'].toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.isEmpty ? 'Standard' : label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.textColor,
                  ),
                ),
                Text(
                  '${v['duration']} min',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          _priceText(price, discount),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: () => _addVariant(service, v),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsOverlay() {
    final isDark = context.isDarkMode;
    final suggestions = _suggestions;
    if (!_showSuggestions || suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: isDark ? Colors.grey[800] : Colors.grey[100],
        ),
        itemBuilder: (context, index) {
          final s = suggestions[index];
          final variants = (s['variants'] as List).cast<Map<String, dynamic>>();
          return ListTile(
            dense: true,
            leading: Icon(
              Icons.content_cut,
              size: 18,
              color: AppTheme.primary,
            ),
            title: Text(
              s['name'].toString(),
              style: TextStyle(fontSize: 13, color: context.textColor),
            ),
            subtitle: Text(
              variants.length == 1
                  ? 'Tap to add directly'
                  : '${variants.length} variants',
              style: TextStyle(
                fontSize: 11,
                color: context.secondaryTextColor,
              ),
            ),
            onTap: () => _pickSuggestion(s),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final filtered = _filteredCatalog;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Services & Extra Charge',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textColor,
                          ),
                        ),
                        Text(
                          widget.appointment['customer_name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: context.textColor),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: context.textColor),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        _searchFocus.unfocus();
                        setState(() => _showSuggestions = false);
                      },
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_offer != null)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.local_offer,
                                      size: 18,
                                      color: Colors.green.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Offer: ${_offer!['title']} (${_offerLabel()}) - eligible services only',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            _sectionTitle('Current services'),
                            if (_existing.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Text(
                                  'No services on this appointment yet',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.secondaryTextColor,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            else
                              ..._existing.map(_existingRow),

                            if (_added.isNotEmpty) ...[
                              _sectionTitle('New services'),
                              ...List.generate(_added.length, _addedRow),
                            ],

                            _sectionTitle('Add service'),
                            TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              onChanged: (v) => setState(() {
                                _search = v.trim().toLowerCase();
                                _showSuggestions = _search.isNotEmpty;
                              }),
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                hintText: 'Type a service name...',
                                hintStyle: TextStyle(
                                  color: context.secondaryTextColor,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: context.secondaryTextColor,
                                ),
                                suffixIcon: _search.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          size: 18,
                                        ),
                                        onPressed: () => setState(() {
                                          _searchCtrl.clear();
                                          _search = '';
                                          _showSuggestions = false;
                                        }),
                                      )
                                    : null,
                                isDense: true,
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.grey[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            _suggestionsOverlay(),
                            const SizedBox(height: 8),
                            if (filtered.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'No services found',
                                  style: TextStyle(
                                    color: context.secondaryTextColor,
                                  ),
                                ),
                              )
                            else
                              ...filtered.map(_serviceTile),

                            _sectionTitle('Extra charge (optional)'),
                            TextField(
                              controller: _extraCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d{0,8}(\.\d{0,2})?'),
                                ),
                              ],
                              onTap: () {
                                if (_extraCtrl.text == '0') _extraCtrl.clear();
                              },
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                prefixText: 'Rs. ',
                                hintText: '0',
                                helperText:
                                    'Added on top of the services total (default 0)',
                                isDense: true,
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.grey[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _noteCtrl,
                              maxLength: 120,
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                hintText: 'Note for extra charge (optional)',
                                isDense: true,
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.grey[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Sticky bottom
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: bg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.textColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Rs. ${_grandTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Services Rs. ${_servicesFinal.toStringAsFixed(2)}'
                        '${_discountTotal > 0 ? '  •  Discount Rs. ${_discountTotal.toStringAsFixed(2)}' : ''}'
                        '${_extra > 0 ? '  •  Extra Rs. ${_extra.toStringAsFixed(2)}' : ''}'
                        '${_durationDelta != 0 ? '  •  ${_durationDelta > 0 ? '+' : ''}$_durationDelta min' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.secondaryTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_isSaving || _isLoading) ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
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
    );
  }
}