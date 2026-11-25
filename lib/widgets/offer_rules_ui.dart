import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

// =====================================================================
// Shared helpers + widget for offer cards (customer dashboard, salon
// profile, offers list). Put this file in lib/widgets/.
//
// Offer types (offers.offer_trigger_type):
//   appointment_time : happy hour  - dates + hours are for the APPOINTMENT
//   booking_time     : book now    - dates are for the BOOKING day
//   advance_booking  : book ahead  - booking period + appointment >= X days
// valid_from_time / valid_to_time are SALON wall-clock times.
// =====================================================================

/// Extra offers columns the cards need - add to the offers .select(...)
const String kOfferRuleColumns =
    'offer_trigger_type, valid_from_time, valid_to_time, min_advance_days, minimum_spend';

String offerTriggerOf(Map<String, dynamic> o) {
  final t = o['offer_trigger_type']?.toString();
  if (t == 'appointment_time') return 'appointment_time';
  if (t == 'advance_booking') return 'advance_booking';
  return 'booking_time';
}

/// Today's date in the SALON timezone (date only, UTC-based so that day
/// differences are never affected by device DST).
DateTime offerSalonToday(String? tzName) {
  try {
    if (tzName != null && tzName.isNotEmpty) {
      final n = tz.TZDateTime.now(tz.getLocation(tzName));
      return DateTime.utc(n.year, n.month, n.day);
    }
  } catch (_) {}
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}

DateTime? offerDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.length < 10) return null;
  final p = DateTime.tryParse(s.substring(0, 10));
  return p == null ? null : DateTime.utc(p.year, p.month, p.day);
}

/// Days until the last valid day (0 = last day, negative = expired).
int? offerDaysLeft(Map<String, dynamic> o, DateTime salonToday) {
  final to = offerDate(o['valid_to']);
  return to?.difference(salonToday).inDays;
}

class OfferClaimBlock {
  final String shortLabel; // button text
  final String message; // snackbar text
  const OfferClaimBlock(this.shortLabel, this.message);
}

/// null = the offer can be claimed now.
OfferClaimBlock? offerClaimBlock(Map<String, dynamic> o, DateTime salonToday) {
  final to = offerDate(o['valid_to']);
  final from = offerDate(o['valid_from']);
  if (to != null && to.isBefore(salonToday)) {
    return const OfferClaimBlock('Expired', 'This offer has expired');
  }
  // happy-hour offers can be claimed before their (appointment) dates start
  if (offerTriggerOf(o) != 'appointment_time' &&
      from != null &&
      from.isAfter(salonToday)) {
    final d = DateFormat('MMM d').format(from);
    return OfferClaimBlock('Starts $d', 'This offer starts on $d');
  }
  final limit = (o['usage_limit'] as num?)?.toInt();
  final used = (o['used_count'] as num?)?.toInt() ?? 0;
  if (limit != null && used >= limit) {
    return const OfferClaimBlock('Fully used', 'This offer is fully used');
  }
  return null;
}

String _range(DateTime? a, DateTime? b) {
  if (a == null || b == null) return '';
  final now = DateTime.now().year;
  final f = (a.year == now && b.year == now)
      ? DateFormat('MMM d')
      : DateFormat('MMM d, y');
  if (a == b) return f.format(a);
  return '${f.format(a)} – ${f.format(b)}';
}

int? _minutes(dynamic v) {
  if (v == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v.toString());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

String _t12(int minutes) {
  final h = minutes ~/ 60;
  final mi = (minutes % 60).toString().padLeft(2, '0');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$mi ${h >= 12 ? 'PM' : 'AM'}';
}

/// Type-specific "how does this offer work" block for an offer card.
class OfferRulesPanel extends StatelessWidget {
  final Map<String, dynamic> offer;
  final Color color;
  final String currencySymbol;

  const OfferRulesPanel({
    super.key,
    required this.offer,
    required this.color,
    this.currencySymbol = '',
  });

  @override
  Widget build(BuildContext context) {
    final type = offerTriggerOf(offer);
    final from = offerDate(offer['valid_from']);
    final to = offerDate(offer['valid_to']);
    final dates = _range(from, to);

    final String badge;
    final IconData badgeIcon;
    final rows = <MapEntry<IconData, String>>[];

    switch (type) {
      case 'appointment_time':
        badge = 'Happy Hour';
        badgeIcon = Icons.wb_twilight;
        final a = _minutes(offer['valid_from_time']);
        final b = _minutes(offer['valid_to_time']);
        if (a != null && b != null) {
          rows.add(
            MapEntry(
              Icons.schedule,
              'Appointment between ${_t12(a)} – ${_t12(b)}'
              '${a > b ? ' (overnight)' : ''}',
            ),
          );
        } else {
          rows.add(const MapEntry(Icons.schedule, 'Appointment at any time'));
        }
        if (dates.isNotEmpty) {
          rows.add(MapEntry(Icons.event, 'Appointments on $dates'));
        }
        break;
      case 'advance_booking':
        badge = 'Book Ahead';
        badgeIcon = Icons.event_available;
        final d = (offer['min_advance_days'] as num?)?.toInt() ?? 30;
        rows.add(
          MapEntry(
            Icons.update,
            'Appointment at least $d days after you book',
          ),
        );
        if (dates.isNotEmpty) {
          rows.add(MapEntry(Icons.event, 'Book during $dates'));
        }
        break;
      default:
        badge = 'Book Now';
        badgeIcon = Icons.bolt;
        if (dates.isNotEmpty) {
          rows.add(
            MapEntry(
              Icons.event,
              'Book during $dates • any appointment day & time',
            ),
          );
        }
    }

    final minSpend = (offer['minimum_spend'] as num?)?.toDouble() ?? 0;
    if (minSpend > 0) {
      rows.add(
        MapEntry(
          Icons.payments_outlined,
          'Min. spend per service $currencySymbol'
          '${minSpend.toStringAsFixed(minSpend % 1 == 0 ? 0 : 2)}',
        ),
      );
    }
    final limit = (offer['usage_limit'] as num?)?.toInt();
    final used = (offer['used_count'] as num?)?.toInt() ?? 0;
    if (limit != null && limit - used > 0) {
      rows.add(MapEntry(Icons.confirmation_number_outlined, '${limit - used} of $limit left'));
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? Colors.white70 : Colors.grey.shade800;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                badge,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          for (final r in rows) ...[
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(r.key, size: 11, color: textColor),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.value,
                    style: TextStyle(fontSize: 10.5, color: textColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}