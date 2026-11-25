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
///   id, salon_id, customer_name, services
///   (appointment_services rows: `id` or `appointment_service_id`,
///   `variant_id`), extra_charge, extra_charge_note, symbol (optional)
///
/// ✅ VARIANT RULE (same as the salon profile menu):
///   - the unit is the VARIANT, not the service
///   - a service can have many variants on one appointment
///   - the SAME variant can be on an appointment only once
///
/// ✅ OFFER RULE (same as the booking flow / DB section 63):
///   - the offers of the appointment are the ones already on its service
///     lines (appointment_services.offer_id) - they were checked and counted
///     when the customer booked, so dates / usage limit are not checked again
///   - after every add / remove the offers are re-placed on the lines:
///       * ONE offer = ONE service line (biggest discount wins)
///       * one line carries ONE offer
///       * per line: offer scope (service / variant) + minimum spend
///   - an offer that no line can carry any more is given back to the customer
///   - the preview here uses the same rule; the DB decides when saving
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

  // category -> services -> variants (same shape as the salon profile menu)
  List<Map<String, dynamic>> _tree = [];

  // දැනට appointment එකේ තියෙන services
  final List<Map<String, dynamic>> _existing = [];
  final Set<int> _removeIds = {};

  // අලුතින් add කරපු (තාම save කරලා නෑ)
  final List<Map<String, dynamic>> _added = [];

  // Offers that are already on this appointment (see OFFER RULE above)
  List<Map<String, dynamic>> _offers = [];
  final Map<int, List<Map<String, dynamic>>> _offerScope = {};

  // stored discount of every existing line (restored when nothing changed)
  final Map<int, Map<String, dynamic>> _initial = {};

  // offers that no line can carry after the current changes
  List<int> _releasedOfferIds = [];

  final TextEditingController _extraCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  String _search = '';

  String get _sym {
    final s = widget.appointment['symbol']?.toString().trim() ?? '';
    return s.isEmpty ? 'Rs.' : s;
  }

  @override
  void initState() {
    super.initState();

    final services = widget.appointment['services'] as List? ?? [];
    for (final s in services) {
      if (s == null) continue;
      final raw = Map<String, dynamic>.from(s as Map);

      if (raw['id'] == null && raw['appointment_service_id'] != null) {
        raw['id'] = raw['appointment_service_id'];
      }

      final idVal = raw['id'];
      if (idVal == null) continue;
      final id = idVal is int ? idVal : int.tryParse(idVal.toString());
      if (id == null || id < 0) continue;
      raw['id'] = id;

      final vidVal = raw['variant_id'];
      raw['variant_id'] = vidVal == null
          ? null
          : (vidVal is int ? vidVal : int.tryParse(vidVal.toString()));

      raw['duration'] = _toInt(raw['duration'], fallback: 30);
      raw['original_price'] = _toDouble(raw['original_price']);
      raw['discount_amount'] = _toDouble(raw['discount_amount']);
      raw['final_price'] = _toDouble(raw['final_price']);

      _existing.add(raw);
    }

    final extra = _toDouble(widget.appointment['extra_charge']);
    _extraCtrl.text = extra > 0 ? extra.toStringAsFixed(2) : '0';
    _noteCtrl.text = widget.appointment['extra_charge_note']?.toString() ?? '';

    _load();
  }

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
    super.dispose();
  }

  // ---------------------------------------------------------------
  // ✅ VARIANT RULE
  //   existing-kept : on the appointment and not marked for removal
  //   in-added      : ticked in this session (not saved yet)
  // ---------------------------------------------------------------
  Set<int> get _keptVariantIds => {
    for (final s in _existing)
      if (!_removeIds.contains(s['id']) && s['variant_id'] is int)
        s['variant_id'] as int,
  };

  Set<int> get _addedVariantIds => {
    for (final a in _added) a['variant_id'] as int,
  };

  bool _isOnAppointment(int variantId) => _keptVariantIds.contains(variantId);
  bool _isTicked(int variantId) => _addedVariantIds.contains(variantId);

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
      if (salonId == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Salon id missing from appointment';
          _isLoading = false;
        });
        return;
      }

      final servicesResponse = await supabase
          .from('services')
          .select('id, name, category_id')
          .eq('salon_id', salonId)
          .eq('is_active', true)
          .order('name');

      if (servicesResponse.isEmpty) {
        if (!mounted) return;
        setState(() {
          _tree = [];
          _isLoading = false;
        });
        return;
      }

      final serviceIds = servicesResponse.map((s) => s['id'] as int).toList();

      final variantsResponse = await supabase
          .from('service_variants')
          .select(
            'id, service_id, name, price, duration, salon_gender_id, salon_age_category_id, is_active',
          )
          .inFilter('service_id', serviceIds);

      final activeVariants = variantsResponse
          .where((v) => v['is_active'] == true)
          .toList();

      // categories (name, colour, order)
      final categories = await supabase
          .from('salon_categories')
          .select('id, display_name, color, display_order')
          .eq('salon_id', salonId)
          .eq('is_active', true)
          .order('display_order');

      // genders
      final genderIds = activeVariants
          .map((v) => v['salon_gender_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final Map<int, String> genderMap = {};
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

      // age categories
      final ageIds = activeVariants
          .map((v) => v['salon_age_category_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();
      final Map<int, String> ageMap = {};
      final Map<int, String> ageRangeMap = {};
      if (ageIds.isNotEmpty) {
        try {
          final rows = await supabase
              .from('salon_age_categories')
              .select('id, display_name, min_age, max_age')
              .inFilter('id', ageIds);
          for (final a in rows) {
            ageMap[a['id'] as int] = a['display_name']?.toString() ?? '';
            final mn = (a['min_age'] as num?)?.toInt();
            final mx = (a['max_age'] as num?)?.toInt();
            ageRangeMap[a['id'] as int] = (mn == null || mx == null)
                ? ''
                : (mx >= 100 ? '$mn+ yrs' : '$mn–$mx yrs');
          }
        } catch (e) {
          debugPrint('⚠️ age categories failed: $e');
        }
      }

      // variants per service
      final Map<int, List<Map<String, dynamic>>> variantsByService = {};
      for (final v in activeVariants) {
        final sid = v['service_id'] as int;
        final gId = v['salon_gender_id'] as int?;
        final aId = v['salon_age_category_id'] as int?;
        final name = v['name']?.toString().trim() ?? '';
        final gender = gId != null ? (genderMap[gId] ?? '') : '';
        final age = aId != null ? (ageMap[aId] ?? '') : '';
        variantsByService.putIfAbsent(sid, () => []).add({
          'id': v['id'] as int,
          'price': _toDouble(v['price']),
          'duration': _toInt(v['duration'], fallback: 30),
          'name': name,
          'gender': gender,
          'age': age,
          'age_range': aId != null ? (ageRangeMap[aId] ?? '') : '',
          // same text the DB stores in appointment_services.variant_label
          'label': '$name $gender $age'.trim(),
        });
      }

      // services per category
      final Map<int, List<Map<String, dynamic>>> servicesByCat = {};
      for (final s in servicesResponse) {
        final sid = s['id'] as int;
        final variants = variantsByService[sid] ?? [];
        if (variants.isEmpty) continue;
        servicesByCat.putIfAbsent(s['category_id'] as int, () => []).add({
          'id': sid,
          'name': s['name']?.toString() ?? 'Service',
          'variants': variants,
        });
      }

      final List<Map<String, dynamic>> tree = [];
      for (final c in categories) {
        final cid = c['id'] as int;
        final list = servicesByCat[cid] ?? [];
        if (list.isEmpty) continue;
        tree.add({
          'id': cid,
          'name': c['display_name']?.toString() ?? 'Category',
          'color': c['color']?.toString(),
          'services': list,
        });
      }

      // ✅ Offers that are already on this appointment's service lines
      final offerIds = <int>{};
      final initial = <int, Map<String, dynamic>>{};
      final apptId = widget.appointment['id'];

      if (apptId != null) {
        try {
          final lineRows = await supabase
              .from('appointment_services')
              .select('id, service_id, variant_id, offer_id, discount_amount, final_price')
              .eq('appointment_id', apptId);

          for (final row in lineRows) {
            final lineId = _toInt(row['id'], fallback: -1);
            final offerId = row['offer_id'] == null
                ? null
                : _toInt(row['offer_id'], fallback: -1);
            final disc = _toDouble(row['discount_amount']);

            for (final ex in _existing) {
              if (ex['id'] == lineId) {
                ex['service_id'] = row['service_id'];
                ex['offer_id'] = offerId;
                initial[lineId] = {
                  'discount_amount': disc,
                  'final_price': _toDouble(row['final_price']),
                  'offer_id': offerId,
                };
              }
            }
            if (offerId != null && offerId > 0) offerIds.add(offerId);
          }
        } catch (e) {
          debugPrint('⚠️ appointment lines failed: $e');
        }
      }

      // old bookings may still have the single offer on the appointment
      final legacy = widget.appointment['offer_id'];
      if (legacy != null) {
        final l = _toInt(legacy, fallback: -1);
        if (l > 0) offerIds.add(l);
      }

      List<Map<String, dynamic>> offers = [];
      final Map<int, List<Map<String, dynamic>>> scope = {};
      if (offerIds.isNotEmpty) {
        final rows = await supabase
            .from('offers')
            .select('id, title, discount_type, discount_value, minimum_spend')
            .inFilter('id', offerIds.toList());
        offers = rows.map<Map<String, dynamic>>(
          (r) => Map<String, dynamic>.from(r),
        ).toList();

        final scopeRows = await supabase
            .from('offer_services')
            .select('offer_id, service_id, variant_id')
            .inFilter('offer_id', offerIds.toList());
        for (final r in scopeRows) {
          scope
              .putIfAbsent(_toInt(r['offer_id']), () => [])
              .add(Map<String, dynamic>.from(r));
        }
      }

      if (!mounted) return;
      setState(() {
        _tree = tree;
        _offers = offers;
        _offerScope
          ..clear()
          ..addAll(scope);
        _initial
          ..clear()
          ..addAll(initial);
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
  // ✅ OFFER PREVIEW (same rule as DB section 63 / booking flow)
  // ---------------------------------------------------------------
  Map<String, dynamic>? _offerById(dynamic id) {
    if (id == null) return null;
    for (final o in _offers) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  String _offerLabelOf(Map<String, dynamic> o) {
    final type = o['discount_type']?.toString() ?? '';
    final value = _toDouble(o['discount_value']);
    final v = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    if (type == 'percentage') return '$v% OFF';
    if (type == 'fixed') return '$_sym $v OFF';
    return 'FREE';
  }

  /// does the offer cover this service (+ variant)? (empty scope = all)
  bool _inScope(Map<String, dynamic> o, int? serviceId, int? variantId) {
    final rows = _offerScope[_toInt(o['id'])] ?? const [];
    if (rows.isEmpty) return true;
    for (final r in rows) {
      if (r['service_id'] == serviceId &&
          (r['variant_id'] == null || r['variant_id'] == variantId)) {
        return true;
      }
    }
    return false;
  }

  double _discountOf(Map<String, dynamic> o, double price) {
    final value = _toDouble(o['discount_value']);
    switch (o['discount_type']?.toString()) {
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

  bool _lineQualifies(Map<String, dynamic> o, Map<String, dynamic> line) {
    final price = _toDouble(line['original_price']);
    if (price < _toDouble(o['minimum_spend'])) return false;
    final sid = line['service_id'] is int
        ? line['service_id'] as int
        : int.tryParse('${line['service_id']}');
    final vid = line['variant_id'] is int ? line['variant_id'] as int : null;
    return _inScope(o, sid, vid);
  }

  /// Re-place the offers on the final set of lines:
  /// ONE offer = ONE line, one line = ONE offer, biggest discount first.
  /// Call inside setState after every add / remove.
  void _recompute() {
    final changed = _removeIds.isNotEmpty || _added.isNotEmpty;

    if (!changed) {
      // nothing changed: show exactly what is stored
      for (final ex in _existing) {
        final init = _initial[ex['id']];
        if (init == null) continue;
        ex['discount_amount'] = init['discount_amount'];
        ex['final_price'] = init['final_price'];
        ex['offer_id'] = init['offer_id'];
      }
      _releasedOfferIds = [];
      return;
    }

    if (_offers.isEmpty) return;

    final lines = <Map<String, dynamic>>[..._kept, ..._added];
    for (final l in lines) {
      l['discount_amount'] = 0.0;
      l['final_price'] = _toDouble(l['original_price']);
      l['offer_id'] = null;
    }

    final done = <int>{};
    while (true) {
      Map<String, dynamic>? bestLine;
      Map<String, dynamic>? bestOffer;
      double bestDisc = 0;

      for (final o in _offers) {
        final oid = _toInt(o['id']);
        if (done.contains(oid)) continue;
        for (final l in lines) {
          if (l['offer_id'] != null) continue;
          if (!_lineQualifies(o, l)) continue;
          final d = _discountOf(o, _toDouble(l['original_price']));
          if (d > bestDisc) {
            bestDisc = d;
            bestLine = l;
            bestOffer = o;
          }
        }
      }

      if (bestLine == null || bestOffer == null) break;
      bestLine['discount_amount'] = bestDisc;
      bestLine['final_price'] = _toDouble(bestLine['original_price']) - bestDisc;
      bestLine['offer_id'] = _toInt(bestOffer['id']);
      done.add(_toInt(bestOffer['id']));
    }

    _releasedOfferIds = [
      for (final o in _offers)
        if (!done.contains(_toInt(o['id']))) _toInt(o['id']),
    ];
  }

  /// offers that could carry this service (used for the small chip in the menu)
  List<Map<String, dynamic>> _offersForService(int serviceId) => [
    for (final o in _offers)
      if (_inScope(o, serviceId, null) ||
          (_offerScope[_toInt(o['id'])] ?? const []).any(
            (r) => r['service_id'] == serviceId,
          ))
        o,
  ];

  // ---------------------------------------------------------------
  // SEARCH (service name / category name)
  // ---------------------------------------------------------------
  List<Map<String, dynamic>> get _filteredTree {
    if (_search.isEmpty) return _tree;
    final q = _search.toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final c in _tree) {
      final catMatch = c['name'].toString().toLowerCase().contains(q);
      final services = (c['services'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (s) => catMatch || s['name'].toString().toLowerCase().contains(q),
          )
          .toList();
      if (services.isNotEmpty) out.add({...c, 'services': services});
    }
    return out;
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

  int get _addedDuration => _added.fold(0, (a, i) => a + _toInt(i['duration']));

  int get _removedDuration => _existing
      .where((s) => _removeIds.contains(s['id']))
      .fold(0, (a, i) => a + _toInt(i['duration']));

  int get _durationDelta => _addedDuration - _removedDuration;

  double get _grandTotal => _servicesFinal + _extra;

  // ---------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------
  /// tick / untick a variant of the catalog
  void _toggleVariant(Map<String, dynamic> service, Map<String, dynamic> v) {
    final vid = v['id'] as int;

    // already on the appointment (and not marked for removal): locked
    if (_isOnAppointment(vid)) {
      _showSnack(
        '${service['name']} (${_variantText(v)}) is already added to this appointment',
        color: Colors.orange,
      );
      return;
    }

    if (_isTicked(vid)) {
      setState(() {
        _added.removeWhere((a) => a['variant_id'] == vid);
        _recompute();
      });
      return;
    }

    final serviceId = service['id'] as int;
    final price = _toDouble(v['price']);

    setState(() {
      _added.add({
        'variant_id': vid,
        'service_id': serviceId,
        'name': service['name'],
        'label': v['label'],
        'duration': _toInt(v['duration'], fallback: 30),
        'original_price': price,
        'discount_amount': 0.0,
        'final_price': price,
        'offer_id': null,
      });
      // the offer may move to this line if it saves more
      _recompute();
    });
  }

  String _variantText(Map<String, dynamic> v) {
    final label = v['label']?.toString() ?? '';
    return label.isEmpty ? 'Standard' : label;
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
        final released = result['offers_released'];

        String msg = '✅ Updated.';
        if (result['new_price'] != null) {
          msg += ' Total: $_sym ${newPrice.toStringAsFixed(2)}.';
        }
        if (minutesChanged != 0 && newEndTime != null) {
          final shortTime = newEndTime.length >= 5
              ? newEndTime.substring(0, 5)
              : newEndTime;
          msg += minutesChanged > 0
              ? ' Duration +$minutesChanged min (ends $shortTime).'
              : ' Duration $minutesChanged min (ends $shortTime).';
        }
        if (released is List && released.isNotEmpty) {
          msg += ' Offer returned to the customer.';
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
  Color _hexColor(String? hex) {
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      try {
        return Color(int.parse('0xFF${hex.substring(1)}'));
      } catch (_) {}
    }
    return AppTheme.primary;
  }

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
            '$_sym ${original.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              decoration: TextDecoration.lineThrough,
            ),
          ),
        Text(
          '$_sym ${finalPrice.toStringAsFixed(2)}',
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

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "🎁 Offer title (20% OFF)" under a line that carries an offer
  Widget _lineOfferTag(Map<String, dynamic> line) {
    final o = _offerById(line['offer_id']);
    if (o == null || _toDouble(line['discount_amount']) <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _infoChip(
        Icons.local_offer,
        '${o['title']} • ${_offerLabelOf(o)}',
        Colors.green.shade600,
      ),
    );
  }

  // ---------------------------------------------------------------
  // CURRENT SERVICES (already on the appointment)
  // ---------------------------------------------------------------
  Widget _existingRow(Map<String, dynamic> s) {
    final id = s['id'] as int;
    final removed = _removeIds.contains(id);
    final isStaffAdded = s['added_by'] != null;
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
                      '$duration min${isStaffAdded ? ' • added by staff' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
                if (!removed) _lineOfferTag(s),
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
                : () {
                    if (removed) {
                      // undo is not allowed while the same variant was
                      // ticked again as a replacement
                      final vid = s['variant_id'];
                      if (vid is int && _isTicked(vid)) {
                        _showSnack(
                          '${s['service_name']} is in the new services list. Untick it below first.',
                          color: Colors.orange,
                        );
                        return;
                      }
                      setState(() {
                        _removeIds.remove(id);
                        _recompute();
                      });
                    } else {
                      setState(() {
                        _removeIds.add(id);
                        _recompute();
                      });
                    }
                  },
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
                _lineOfferTag(a),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _priceText(
            _toDouble(a['original_price']),
            _toDouble(a['discount_amount']),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 20, color: Colors.red),
            onPressed: () => setState(() {
              _added.removeAt(index);
              _recompute();
            }),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // OFFER BANNER
  // ---------------------------------------------------------------
  Widget _offerBanner() {
    if (_offers.isEmpty) return const SizedBox.shrink();

    final released = [
      for (final id in _releasedOfferIds)
        if (_offerById(id) != null) _offerById(id)!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in _offers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.local_offer,
                        size: 16,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${o['title']} (${_offerLabelOf(o)})'
                          '${_toDouble(o['minimum_spend']) > 0 ? ' • min. $_sym ${_toDouble(o['minimum_spend']).toStringAsFixed(0)} per service' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Each offer applies to ONE service only (the one with the '
                'biggest discount), same as when the customer books.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),
        if (released.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${released.map((o) => o['title']).join(', ')} will not '
                    'apply to any service after this change (scope / minimum '
                    'spend). The offer will be returned to the customer.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // MENU (category -> service -> variants with checkboxes)
  // ---------------------------------------------------------------
  Widget _categoryBlock(Map<String, dynamic> cat) {
    final color = _hexColor(cat['color']?.toString());
    final services = (cat['services'] as List).cast<Map<String, dynamic>>();

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              cat['name'].toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.textColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: services.map((s) => _serviceBlock(s, color)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceBlock(Map<String, dynamic> service, Color catColor) {
    final variants = (service['variants'] as List).cast<Map<String, dynamic>>();
    final sid = service['id'] as int;
    final eligible = _offersForService(sid);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 2,
                color: catColor.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service['name'].toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textColor,
                  ),
                ),
              ),
              // the offer may apply here (final discount is shown after ticking)
              if (eligible.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🎁 ${_offerLabelOf(eligible.first)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade600,
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              children: variants
                  .map((v) => _variantRow(service, v, catColor))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _variantRow(
    Map<String, dynamic> service,
    Map<String, dynamic> v,
    Color catColor,
  ) {
    final vid = v['id'] as int;
    final onAppointment = _isOnAppointment(vid);
    final ticked = _isTicked(vid);
    final checked = onAppointment || ticked;

    final price = _toDouble(v['price']);
    final duration = _toInt(v['duration']);
    final name = v['name'].toString();
    final gender = v['gender'].toString();
    final age = v['age'].toString();
    final ageRange = v['age_range'].toString();
    final ageText = age.isEmpty
        ? ''
        : (ageRange.isEmpty ? age : '$age ($ageRange)');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Opacity(
        opacity: onAppointment ? 0.6 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _toggleVariant(service, v),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: ticked
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: ticked
                      ? AppTheme.primary.withValues(alpha: 0.5)
                      : context.dividerColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: checked,
                      // locked when the variant is already on the appointment
                      onChanged: onAppointment
                          ? null
                          : (_) => _toggleVariant(service, v),
                      activeColor: AppTheme.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (name.isNotEmpty)
                              _infoChip(
                                Icons.label_outline,
                                name,
                                Colors.teal.shade400,
                              ),
                            if (gender.isNotEmpty)
                              _infoChip(
                                Icons.person_outline,
                                gender,
                                Colors.blue.shade400,
                              ),
                            if (ageText.isNotEmpty)
                              _infoChip(
                                Icons.cake_outlined,
                                ageText,
                                Colors.purple.shade400,
                              ),
                            if (name.isEmpty &&
                                gender.isEmpty &&
                                ageText.isEmpty)
                              _infoChip(
                                Icons.check_circle_outline,
                                'Standard',
                                Colors.grey.shade600,
                              ),
                            if (onAppointment)
                              _infoChip(
                                Icons.lock_outline,
                                'Added',
                                Colors.green.shade600,
                              ),
                          ],
                        ),
                        if (duration > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: context.secondaryTextColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '$duration min',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // list price - the real discount shows after ticking
                  _priceText(price, 0),
                ],
              ),
            ),
          ),
        ),
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
    final tree = _filteredTree;

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
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _offerBanner(),

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
                            Text(
                              'Tick the options you want to add',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.secondaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(
                                () => _search = v.trim().toLowerCase(),
                              ),
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                hintText: 'Search service or category...',
                                hintStyle: TextStyle(
                                  color: context.secondaryTextColor,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: context.secondaryTextColor,
                                ),
                                suffixIcon: _search.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () => setState(() {
                                          _searchCtrl.clear();
                                          _search = '';
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
                            const SizedBox(height: 8),
                            if (tree.isEmpty)
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
                              ...tree.map(_categoryBlock),

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
                                prefixText: '$_sym ',
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
                          '$_sym ${_grandTotal.toStringAsFixed(2)}',
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
                        'Services $_sym ${_servicesFinal.toStringAsFixed(2)}'
                        '${_discountTotal > 0 ? '  •  Discount $_sym ${_discountTotal.toStringAsFixed(2)}' : ''}'
                        '${_extra > 0 ? '  •  Extra $_sym ${_extra.toStringAsFixed(2)}' : ''}'
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