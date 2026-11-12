// Shared appointment UI for the OWNER and BARBER appointment screens.
// One card, one button bar, one details sheet, one set of dialogs/actions,
// so both screens look and behave exactly the same (mobile + web).
//
// Required pubspec: cached_network_image, supabase_flutter, pdf, printing
// (bill_service.dart is the same file from the previous step)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/bill_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/edit_appointment_services_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef Appt = Map<String, dynamic>;

// =====================================================================
// RULES: which buttons an appointment gets
// =====================================================================
class ApptFlags {
  final String status;
  final String payment;

  ApptFlags(Appt a)
      : status = (a['status'] as String?) ?? 'pending',
        payment = (a['payment_status'] as String?) ?? 'unpaid';

  bool get isPaid => payment == 'paid';
  bool get isPartial => payment == 'partial';
  bool get isRefunded => payment == 'refunded';
  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress';
  bool get isCancelled => status == 'cancelled';
  bool get isNoShow => status == 'no_show';
  bool get isWaiting => status == 'pending' || status == 'confirmed';
  bool get isLive => isWaiting || isInProgress || isCompleted;
  bool get isPendingPayment => isCompleted && !isPaid;

  bool get canStart => isWaiting;
  bool get canEnd => isInProgress;
  bool get canPay => isLive && !isPaid; // unpaid + partial
  bool get canBill => isLive && isPaid; // paid -> BILL replaces PAY
  bool get canEdit => isWaiting || isInProgress || (isCompleted && !isPaid);
  bool get canCancel => isWaiting;
}

class ApptCounts {
  int total = 0, pending = 0, pendingPay = 0, completed = 0, cancelled = 0;

  ApptCounts.from(List<Appt> list) {
    for (final a in list) {
      final f = ApptFlags(a);
      total++;
      if (f.isCompleted) {
        f.isPaid ? completed++ : pendingPay++;
      } else if (f.isWaiting || f.isInProgress) {
        pending++;
      } else if (f.isCancelled || f.isNoShow) {
        cancelled++;
      }
    }
  }
}

List<Appt> filterAppts(List<Appt> all, int tab) {
  switch (tab) {
    case 0:
      return all.where((a) {
        final f = ApptFlags(a);
        return f.isWaiting || f.isInProgress;
      }).toList();
    case 1:
      return all.where((a) => ApptFlags(a).isPendingPayment).toList();
    case 2:
      return all.where((a) {
        final f = ApptFlags(a);
        return f.isCompleted && f.isPaid;
      }).toList();
    case 3:
      return all.where((a) {
        final f = ApptFlags(a);
        return f.isCancelled || f.isNoShow;
      }).toList();
    default:
      return List<Appt>.from(all);
  }
}

String apptMoney(String symbol, num v) => '$symbol${v.toStringAsFixed(2)}';
double _n(Appt a, String k) => (a[k] as num?)?.toDouble() ?? 0.0;

Color _panel(bool dark) => dark ? const Color(0xFF1E1E1E) : Colors.white;
Color _subtle(bool dark) => dark ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
Color _fg(bool dark) => dark ? Colors.white : Colors.black87;
Color _muted(bool dark) => dark ? Colors.white60 : Colors.grey.shade600;

(String, Color, IconData) _statusInfo(String s) {
  switch (s) {
    case 'completed':
      return ('Completed', Colors.green, Icons.check_circle);
    case 'confirmed':
      return ('Confirmed', Colors.blue, Icons.event_available);
    case 'in_progress':
      return ('In Progress', Colors.deepPurple, Icons.hourglass_top);
    case 'cancelled':
      return ('Cancelled', Colors.red, Icons.cancel);
    case 'no_show':
      return ('No Show', Colors.red, Icons.person_off);
    default:
      return ('Pending', Colors.orange, Icons.schedule);
  }
}

// =====================================================================
// SMALL WIDGETS
// =====================================================================
class ApptChip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const ApptChip(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class ApptAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final bool isDark;
  const ApptAvatar({
    super.key,
    required this.url,
    required this.name,
    required this.size,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final letter = Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white60 : Colors.grey,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.grey[800] : Colors.grey[200],
      ),
      child: (url != null && url!.isNotEmpty)
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => letter,
              ),
            )
          : letter,
    );
  }
}

class ApptMessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;
  final String? buttonText;
  final VoidCallback? onPressed;
  const ApptMessageView({
    super.key,
    required this.icon,
    required this.message,
    required this.isDark,
    this.buttonText,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: isDark ? Colors.white30 : Colors.grey[400]),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted(isDark), fontSize: 14),
            ),
            if (buttonText != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(buttonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// STATS + TABS
// =====================================================================
class ApptStatsRow extends StatelessWidget {
  final ApptCounts counts;
  final bool isDark;
  final ValueChanged<int> onTap;
  const ApptStatsRow({
    super.key,
    required this.counts,
    required this.isDark,
    required this.onTap,
  });

  Widget _card(String title, int n, IconData icon, Color color, int tab) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _panel(isDark),
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
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: _muted(isDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _card('Pending', counts.pending, Icons.pending_actions, Colors.orange, 0),
        const SizedBox(width: 8),
        _card('Pay Due', counts.pendingPay, Icons.payments_outlined,
            Colors.teal.shade600, 1),
        const SizedBox(width: 8),
        _card('Complete', counts.completed, Icons.check_circle_outline,
            Colors.green, 2),
        const SizedBox(width: 8),
        _card('Cancel', counts.cancelled, Icons.cancel_outlined, Colors.red, 3),
      ],
    );
  }
}

Widget buildApptTabBar(TabController c, ApptCounts n, bool isDark) {
  Tab t(IconData i, String s) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(i, size: 16), const SizedBox(width: 6), Text(s)],
        ),
      );
  return Container(
    decoration: BoxDecoration(
      color: _panel(isDark),
      borderRadius: BorderRadius.circular(12),
    ),
    child: TabBar(
      controller: c,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppTheme.primary,
      unselectedLabelColor: _muted(isDark),
      indicatorColor: AppTheme.primary,
      indicatorWeight: 3,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
      tabs: [
        t(Icons.pending_actions, 'Pending (${n.pending})'),
        t(Icons.payments_outlined, 'Pending Payment (${n.pendingPay})'),
        t(Icons.check_circle_outline, 'Complete (${n.completed})'),
        t(Icons.cancel_outlined, 'Cancel (${n.cancelled})'),
        t(Icons.list_alt, 'All (${n.total})'),
      ],
    ),
  );
}

// =====================================================================
// LIST: 1 column on phones, 2-4 columns on web (cards keep their own height)
// =====================================================================
class ApptList extends StatelessWidget {
  final List<Appt> items;
  final Future<void> Function() onRefresh;
  final Widget Function(Appt) cardBuilder;
  final bool isDark;
  final String emptyText;
  final String emptySub;
  const ApptList({
    super.key,
    required this.items,
    required this.onRefresh,
    required this.cardBuilder,
    required this.isDark,
    required this.emptyText,
    required this.emptySub,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final pad = w < 700 ? 12.0 : 4.0;
        Widget content;

        if (items.isEmpty) {
          content = Padding(
            padding: const EdgeInsets.symmetric(vertical: 70),
            child: Column(
              children: [
                Icon(Icons.event_busy,
                    size: 60, color: isDark ? Colors.white30 : Colors.grey[400]),
                const SizedBox(height: 12),
                Text(emptyText,
                    style: TextStyle(fontSize: 16, color: _muted(isDark))),
                const SizedBox(height: 4),
                Text(emptySub,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _muted(isDark))),
                const SizedBox(height: 10),
                Text('Pull down to refresh',
                    style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white30 : Colors.grey[400])),
              ],
            ),
          );
        } else if (w < 700) {
          content = Column(
            children: [
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: cardBuilder(a),
                ),
            ],
          );
        } else {
          final inner = w - pad * 2;
          final cols = (inner / 400).floor().clamp(1, 4);
          final cardW = (inner - 16 * (cols - 1)) / cols;
          content = Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              for (final a in items) SizedBox(width: cardW, child: cardBuilder(a)),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          color: AppTheme.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 28),
            child: content,
          ),
        );
      },
    );
  }
}

// =====================================================================
// BUTTON BAR  (START/END, PAY/BILL, SERVICES, CANCEL) - 2 per row
// =====================================================================
class ApptHandlers {
  final VoidCallback onStart,
      onEnd,
      onPay,
      onBill,
      onServices,
      onCancel;
  const ApptHandlers({
    required this.onStart,
    required this.onEnd,
    required this.onPay,
    required this.onBill,
    required this.onServices,
    required this.onCancel,
  });
}

class ApptActionBar extends StatelessWidget {
  final Appt apt;
  final ApptHandlers h;
  final bool busy;
  const ApptActionBar({
    super.key,
    required this.apt,
    required this.h,
    required this.busy,
  });

  Widget _filled(String label, IconData icon, Color color, VoidCallback f) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: busy ? null : f,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _outlined(String label, IconData icon, Color color, VoidCallback f) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: busy ? null : f,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ApptFlags(apt);
    final items = <Widget>[
      if (f.canStart)
        _filled('START', Icons.play_arrow_rounded, Colors.green.shade600, h.onStart),
      if (f.canEnd)
        _filled('END', Icons.stop_circle_outlined, Colors.orange.shade800, h.onEnd),
      if (f.canPay)
        _filled('PAY', Icons.payments_rounded, Colors.teal.shade600, h.onPay),
      if (f.canBill)
        _filled('BILL', Icons.receipt_long_rounded, Colors.indigo, h.onBill),
      if (f.canEdit)
        _outlined('SERVICES', Icons.add_circle_outline, AppTheme.primary,
            h.onServices),
      if (f.canCancel)
        _outlined('CANCEL', Icons.close_rounded, Colors.red, h.onCancel),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Row(
            children: [
              Expanded(child: items[i]),
              if (i + 1 < items.length) ...[
                const SizedBox(width: 8),
                Expanded(child: items[i + 1]),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

// =====================================================================
// CARD
// =====================================================================
class ApptCard extends StatelessWidget {
  final Appt apt;
  final bool isDark;
  final bool busy;
  final bool showBarber;
  final ApptHandlers h;
  final VoidCallback onTap;
  const ApptCard({
    super.key,
    required this.apt,
    required this.isDark,
    required this.busy,
    required this.showBarber,
    required this.h,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = ApptFlags(apt);
    final sym = (apt['symbol'] as String?) ?? '';
    final isVip = apt['is_vip'] == true;
    final reg = apt['regular_queue_number'];
    final vq = apt['vip_queue_number'];
    final queueText = isVip
        ? (vq != null ? 'VIP-$vq' : null)
        : (reg != null ? 'Q$reg' : null);

    final vipColor = Colors.amber.shade700;
    final regColor = Colors.blue.shade600;
    final labelColor = isVip ? vipColor : regColor;

    final Color accent = (f.isCancelled || f.isNoShow)
        ? Colors.red
        : isVip
            ? Colors.amber.shade600
            : f.isPendingPayment
                ? Colors.orange
                : (f.isCompleted && f.isPaid)
                    ? Colors.green
                    : Colors.blue.shade400;

    final (statusText, statusColor, statusIcon) = _statusInfo(f.status);

    final customer = (apt['customer_name'] as String?) ?? 'Customer';
    final barber = (apt['barber_name'] as String?) ?? '';
    final child = (apt['child_name'] as String?) ?? '';
    final phone = (apt['customer_phone'] as String?) ?? '';
    final active = apt['customer_active'] != false;

    final services = List<Appt>.from(apt['services'] ?? const []);
    final duration = services.fold<int>(
        0, (a, s) => a + ((s['duration'] as num?)?.toInt() ?? 0));
    final total = _n(apt, 'price');
    final discount = _n(apt, 'total_discount');
    final extra = _n(apt, 'extra_charge');
    final extraNote = (apt['extra_charge_note'] as String?) ?? '';
    final paid = _n(apt, 'paid_amount');
    final balance = total - paid;
    final payNote = (apt['payment_note'] as String?) ?? '';
    final notes = (apt['notes'] as String?) ?? '';

    final est = (apt['est_display'] as String?) ?? '';
    final ls = (apt['local_start_time'] as String?) ?? '';
    final le = (apt['local_end_time'] as String?) ?? '';
    final timeText = (est.isNotEmpty && est != ls) ? '$est (Est)' : '$ls - $le';
    final userTime = (apt['user_time'] as String?) ?? '';

    final fg = _fg(isDark);
    final mu = _muted(isDark);

    return Card(
      margin: EdgeInsets.zero,
      color: _panel(isDark),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.4),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 5, color: accent),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (queueText != null)
                        ApptChip(queueText, labelColor,
                            icon: isVip ? Icons.star : Icons.confirmation_number),
                      ApptChip(isVip ? 'VIP' : 'REGULAR', labelColor),
                      ApptChip(statusText, statusColor, icon: statusIcon),
                      if (!active)
                        const ApptChip('INACTIVE', Colors.red,
                            icon: Icons.person_off),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // CUSTOMER
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ApptAvatar(
                        url: apt['customer_avatar'] as String?,
                        name: customer,
                        size: 44,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: fg,
                              ),
                            ),
                            if (showBarber && barber.isNotEmpty)
                              _line(Icons.content_cut, 'Barber: $barber', mu),
                            if (phone.isNotEmpty)
                              _line(Icons.phone_outlined, phone, mu),
                            if (child.isNotEmpty)
                              _line(Icons.child_care, 'For: $child', labelColor,
                                  bold: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (f.isLive || f.isRefunded) _paymentChip(f),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // DATE + TIME
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _subtle(isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: mu),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (apt['display_date'] as String?) ?? '',
                            style: TextStyle(fontSize: 12, color: fg),
                          ),
                        ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, size: 14, color: mu),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      timeText,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: fg,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (userTime.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Your: $userTime',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                      color: isDark
                                          ? Colors.blue[300]
                                          : Colors.blue[700],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // SERVICES
                  Row(
                    children: [
                      Icon(Icons.content_cut, size: 13, color: AppTheme.primary),
                      const SizedBox(width: 5),
                      Text(
                        'Services (${services.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                      const Spacer(),
                      if (duration > 0)
                        Text('$duration min',
                            style: TextStyle(fontSize: 12, color: mu)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (services.isEmpty)
                    Text('No services', style: TextStyle(fontSize: 12, color: mu))
                  else
                    for (final s in services) _serviceRow(s, sym, isDark),

                  const Divider(height: 18),

                  // TOTALS
                  if (discount > 0)
                    _moneyRow('Discount', '−${apptMoney(sym, discount)}',
                        Colors.green.shade700, icon: Icons.local_offer),
                  if (extra > 0)
                    _moneyRow(
                      extraNote.isNotEmpty ? 'Extra ($extraNote)' : 'Extra',
                      '+${apptMoney(sym, extra)}',
                      Colors.orange,
                      icon: Icons.add_circle,
                    ),
                  Row(
                    children: [
                      Text('Total',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: fg)),
                      const Spacer(),
                      Text(
                        apptMoney(sym, total),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isVip ? vipColor : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  if (f.isPartial) ...[
                    const SizedBox(height: 4),
                    _moneyRow('Paid', apptMoney(sym, paid), Colors.green.shade700),
                    _moneyRow('Balance due', apptMoney(sym, balance),
                        Colors.orange.shade800,
                        bold: true),
                  ],
                  if (f.isRefunded)
                    _moneyRow('Refund due', apptMoney(sym, paid),
                        Colors.red.shade600,
                        bold: true),
                  if (payNote.isNotEmpty && (f.isPaid || f.isPartial || f.isRefunded))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(payNote,
                          style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.orange.shade700)),
                    ),

                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note, size: 12, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ACTIONS
                  const SizedBox(height: 14),
                  if (f.canStart || f.canEnd || f.canPay || f.canBill || f.canEdit || f.canCancel)
                    ApptActionBar(apt: apt, h: h, busy: busy)
                  else
                    _footerBanner(f, sym, paid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData i, String t, Color c, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(i, size: 12, color: c),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: c,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _paymentChip(ApptFlags f) {
    if (f.isPaid) {
      return ApptChip('PAID', Colors.green.shade700, icon: Icons.check_circle);
    }
    if (f.isPartial) {
      return ApptChip('PARTIAL', Colors.orange.shade800, icon: Icons.timelapse);
    }
    if (f.isRefunded) {
      return ApptChip('REFUNDED', Colors.red.shade600, icon: Icons.undo);
    }
    return ApptChip('UNPAID', Colors.orange.shade800, icon: Icons.schedule);
  }

  Widget _moneyRow(String l, String v, Color c,
      {IconData? icon, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(l,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: c,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Text(v,
              style: TextStyle(
                  fontSize: 12,
                  color: c,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _footerBanner(ApptFlags f, String sym, double paid) {
    final bad = f.isCancelled || f.isNoShow;
    final color = bad ? Colors.red : Colors.green;
    final text = f.isCancelled
        ? (f.isRefunded ? 'Cancelled • Refund due ${apptMoney(sym, paid)}' : 'Cancelled')
        : f.isNoShow
            ? 'No Show'
            : 'Completed';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(bad ? Icons.cancel : Icons.check_circle, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}

Widget _serviceRow(Appt s, String sym, bool isDark) {
  final orig = _n(s, 'original_price');
  final disc = _n(s, 'discount_amount');
  final fin = _n(s, 'final_price');
  final variant = (s['variant_label'] as String?) ?? '';
  final offer = (s['offer_title'] as String?) ?? '';
  final has = disc > 0;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ${s['service_name'] ?? 'Service'}',
                  style: TextStyle(fontSize: 12, color: _fg(isDark))),
              if (variant.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(variant,
                      style: TextStyle(fontSize: 10, color: _muted(isDark))),
                ),
              if (has && offer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text('Offer: $offer',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.green.shade700)),
                ),
            ],
          ),
        ),
        if (has)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(apptMoney(sym, orig),
                style: TextStyle(
                    fontSize: 10,
                    decoration: TextDecoration.lineThrough,
                    color: _muted(isDark))),
          ),
        Text(
          apptMoney(sym, has ? fin : orig),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: has ? Colors.green.shade700 : _fg(isDark),
          ),
        ),
      ],
    ),
  );
}

// =====================================================================
// DETAILS SHEET (same buttons as the card)
// =====================================================================
void showApptDetails(
  BuildContext context, {
  required Appt apt,
  required bool isDark,
  required bool busy,
  required bool showBarber,
  required ApptHandlers h,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) {
      // close the sheet first, then run the action
      VoidCallback wrap(VoidCallback f) => () {
            Navigator.pop(ctx);
            f();
          };
      final wrapped = ApptHandlers(
        onStart: wrap(h.onStart),
        onEnd: wrap(h.onEnd),
        onPay: wrap(h.onPay),
        onBill: wrap(h.onBill),
        onServices: wrap(h.onServices),
        onCancel: wrap(h.onCancel),
      );
      return DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: _panel(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: _DetailsBody(
                    apt: apt,
                    isDark: isDark,
                    showBarber: showBarber,
                    busy: busy,
                    h: wrapped,
                    onClose: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailsBody extends StatelessWidget {
  final Appt apt;
  final bool isDark;
  final bool showBarber;
  final bool busy;
  final ApptHandlers h;
  final VoidCallback onClose;
  const _DetailsBody({
    required this.apt,
    required this.isDark,
    required this.showBarber,
    required this.busy,
    required this.h,
    required this.onClose,
  });

  Widget _row(String l, String v, {Color? color, bool italic = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(l, style: TextStyle(fontSize: 13, color: _muted(isDark))),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                color: color ?? _fg(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _price(String l, String v, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color ?? _muted(isDark))),
          Text(v,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: color ?? _fg(isDark))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ApptFlags(apt);
    final sym = (apt['symbol'] as String?) ?? '';
    final isVip = apt['is_vip'] == true;
    final (statusText, statusColor, statusIcon) = _statusInfo(f.status);
    final customer = (apt['customer_name'] as String?) ?? 'Customer';
    final phone = (apt['customer_phone'] as String?) ?? '';
    final email = (apt['customer_email'] as String?) ?? '';
    final child = (apt['child_name'] as String?) ?? '';
    final notes = (apt['notes'] as String?) ?? '';
    final services = List<Appt>.from(apt['services'] ?? const []);
    final duration = services.fold<int>(
        0, (a, s) => a + ((s['duration'] as num?)?.toInt() ?? 0));
    final subtotal = _n(apt, 'services_total');
    final discount = _n(apt, 'total_discount');
    final extra = _n(apt, 'extra_charge');
    final extraNote = (apt['extra_charge_note'] as String?) ?? '';
    final total = _n(apt, 'price');
    final paid = _n(apt, 'paid_amount');
    final reg = apt['regular_queue_number'];
    final vq = apt['vip_queue_number'];
    final pos = apt['queue_position'];
    final token = (apt['queue_token'] as String?) ?? '';
    final travel = (apt['travel_time_minutes'] as num?)?.toInt() ?? 0;
    final userTime = (apt['user_time'] as String?) ?? '';
    final est = (apt['est_display'] as String?) ?? '';
    final payNote = (apt['payment_note'] as String?) ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Booking #${apt['booking_number'] ?? 'N/A'}',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: _fg(isDark))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ApptChip(statusText, statusColor, icon: statusIcon),
            if (isVip) ApptChip('VIP', Colors.amber.shade700, icon: Icons.star),
            if (f.isLive || f.isRefunded)
              ApptChip(
                f.isPaid
                    ? 'PAID'
                    : f.isPartial
                        ? 'PARTIAL'
                        : f.isRefunded
                            ? 'REFUNDED'
                            : 'UNPAID',
                f.isPaid
                    ? Colors.green.shade700
                    : f.isRefunded
                        ? Colors.red.shade600
                        : Colors.orange.shade800,
              ),
          ],
        ),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ApptAvatar(
            url: apt['customer_avatar'] as String?,
            name: customer,
            size: 50,
            isDark: isDark,
          ),
          title: Text(customer,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _fg(isDark))),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phone.isNotEmpty)
                Text(phone, style: TextStyle(color: _muted(isDark))),
              if (email.isNotEmpty)
                Text(email, style: TextStyle(color: _muted(isDark))),
              if (child.isNotEmpty)
                Text('Booked for: $child',
                    style: TextStyle(fontSize: 12, color: _muted(isDark))),
            ],
          ),
        ),
        const Divider(),
        if (services.isNotEmpty) ...[
          Text('Services (${services.length})',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: _fg(isDark))),
          const SizedBox(height: 6),
          for (final s in services)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _subtle(isDark),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _serviceRow(s, sym, isDark),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text('${(s['duration'] as num?)?.toInt() ?? 30} min',
                        style: TextStyle(fontSize: 11, color: _muted(isDark))),
                  ),
                ],
              ),
            ),
          const Divider(),
        ],
        if (showBarber) _row('Barber', (apt['barber_name'] as String?) ?? ''),
        _row('Business', (apt['salon_name'] as String?) ?? ''),
        _row('Date', (apt['display_date'] as String?) ?? ''),
        _row('Time',
            '${apt['local_start_time'] ?? ''} - ${apt['local_end_time'] ?? ''}'),
        if (est.isNotEmpty) _row('Estimated start', est),
        if (userTime.isNotEmpty)
          _row('Your time', userTime,
              color: isDark ? Colors.blue[300] : Colors.blue[700], italic: true),
        _row('Duration', '$duration min'),
        if (reg != null) _row('Queue', 'Q$reg'),
        if (vq != null) _row('VIP queue', 'VIP-$vq'),
        if (pos != null) _row('Position', '#$pos'),
        if (token.isNotEmpty) _row('Queue token', token),
        if (travel > 0) _row('Travel time', '$travel min'),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Text('Notes: $notes',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
          ),
        ],
        const Divider(height: 24),
        _price('Services subtotal', apptMoney(sym, subtotal)),
        if (discount > 0)
          _price('Total discount', '−${apptMoney(sym, discount)}',
              color: Colors.green.shade700),
        if (extra > 0)
          _price(extraNote.isNotEmpty ? 'Extra ($extraNote)' : 'Extra charge',
              '+${apptMoney(sym, extra)}',
              color: Colors.orange),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _fg(isDark))),
              Text(apptMoney(sym, total),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ],
          ),
        ),
        if (f.isPartial) ...[
          const SizedBox(height: 6),
          _price('Paid', apptMoney(sym, paid), color: Colors.green.shade700),
          _price('Balance due', apptMoney(sym, total - paid),
              color: Colors.orange.shade800, bold: true),
        ],
        if (f.isRefunded)
          _price('Refund due', apptMoney(sym, paid),
              color: Colors.red.shade600, bold: true),
        if (payNote.isNotEmpty && (f.isPaid || f.isPartial || f.isRefunded))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(payNote,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange.shade700)),
          ),
        const SizedBox(height: 18),
        ApptActionBar(apt: apt, h: h, busy: busy),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Close'),
            style: TextButton.styleFrom(foregroundColor: _muted(isDark)),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// ACTIONS: start / end / pay / cancel / bill / services
// Each returns true when something changed (the screen then reloads).
//
// BuildContext rule used everywhere below: after every `await`, check
// `context.mounted` BEFORE touching the context again (snack / dialog).
// If the screen is gone but the server action already succeeded, we still
// return true so the caller can reload its data.
// =====================================================================
class ApptActions {
  static SupabaseClient get _sb => Supabase.instance.client;
  static const _defaultTz = 'Asia/Colombo';

  static void snack(BuildContext c, String m, Color color,
      {SnackBarAction? action}) {
    if (!c.mounted) return;
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: action,
      ),
    );
  }

  static Future<bool> _guarded(
      BuildContext c, Future<bool> Function()? guard) async {
    if (guard == null) return true;
    final ok = await guard();
    if (!c.mounted) return false;
    if (!ok) {
      snack(c, 'Your barber account is not active.', Colors.red);
      return false;
    }
    return true;
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String confirmLabel,
    List<(IconData, String)> rows = const [],
    String? note,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _fg(isDark))),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87)),
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _subtle(isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(row.$1, size: 16, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(row.$2,
                                      style: TextStyle(color: _fg(isDark))),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(note,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.orange.shade700)),
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ---------------- START ----------------
  static Future<bool> start(
    BuildContext context,
    Appt apt, {
    required bool isDark,
    Future<bool> Function()? guard,
  }) async {
    if (!await _guarded(context, guard)) return false;
    if (!context.mounted) return false;

    final ok = await _confirm(
      context,
      isDark: isDark,
      icon: Icons.play_circle_fill,
      color: Colors.green.shade600,
      title: 'Start appointment?',
      message: 'Are you ready to start ${apt['customer_name']}\'s appointment?',
      rows: [
        (Icons.access_time,
            'Time: ${apt['local_start_time'] ?? ''} - ${apt['local_end_time'] ?? ''}'),
        (Icons.person, 'Customer: ${apt['customer_name']}'),
        if ((apt['barber_name'] as String?)?.isNotEmpty == true)
          (Icons.content_cut, 'Barber: ${apt['barber_name']}'),
      ],
      note: 'If you start late, the next appointments are adjusted automatically.',
      confirmLabel: 'START NOW',
    );
    if (!ok || !context.mounted) return false;

    try {
      final res = await _sb.rpc('adjust_on_appointment_start', params: {
        'p_appointment_id': apt['id'],
        'p_actual_start_time': DateTime.now().toUtc().toIso8601String(),
        'p_country_timezone': (apt['timezone'] as String?) ?? _defaultTz,
      });
      if (res['success'] != true) {
        throw Exception(res['message'] ?? 'Failed to start appointment');
      }
      final d = (res['start_delay_minutes'] as num?)?.toInt() ?? 0;
      // server action succeeded; screen may be gone -> still report change
      if (!context.mounted) return true;
      snack(
        context,
        d > 0
            ? '⚠️ Started $d min late. Next appointments adjusted.'
            : d < 0
                ? '✅ Started ${d.abs()} min early.'
                : '✅ Appointment started!',
        d > 0 ? Colors.orange : Colors.green,
      );
      return true;
    } catch (e) {
      if (context.mounted) snack(context, 'Error: $e', Colors.red);
      return false;
    }
  }

  // ---------------- END ----------------
  static Future<bool> end(
    BuildContext context,
    Appt apt, {
    required bool isDark,
    Future<bool> Function()? guard,
  }) async {
    if (!await _guarded(context, guard)) return false;
    if (!context.mounted) return false;

    bool overflow = false;
    try {
      final r = await _sb
          .from('overflow_notifications')
          .select('id')
          .eq('appointment_id', apt['id'])
          .eq('status', 'PENDING')
          .maybeSingle();
      overflow = r != null;
    } catch (_) {}
    if (!context.mounted) return false;

    final sym = (apt['symbol'] as String?) ?? '';
    final total = _n(apt, 'price');
    final paid = apt['payment_status'] == 'paid';

    final ok = await _confirm(
      context,
      isDark: isDark,
      icon: Icons.stop_circle,
      color: Colors.orange.shade800,
      title: 'End appointment?',
      message: 'Mark ${apt['customer_name']}\'s appointment as completed?',
      rows: [
        (Icons.person, '${apt['customer_name']}'),
        (Icons.payments_outlined, 'Total: ${apptMoney(sym, total)}'),
        (paid ? Icons.check_circle : Icons.schedule,
            paid ? 'Payment: PAID' : 'Payment: not paid yet'),
      ],
      note: overflow
          ? '⚠️ This appointment has an overflow warning. Completing will notify the customer.'
          : paid
              ? 'Payment already received. The appointment will move to COMPLETE.'
              : 'The appointment will move to PENDING PAYMENT. Mark it as PAID after collecting payment.',
      confirmLabel: 'END APPOINTMENT',
    );
    if (!ok || !context.mounted) return false;

    try {
      final res = await _sb.rpc('adjust_queue_on_appointment_end', params: {
        'p_appointment_id': apt['id'],
        'p_actual_end_time': DateTime.now().toUtc().toIso8601String(),
        'p_customer_decision': null,
      });
      if (res['success'] != true) {
        throw Exception(res['message'] ?? 'Failed to complete appointment');
      }
      final late = (res['delay_minutes'] as num?)?.toInt() ?? 0;
      final newPrice = (res['new_price'] as num?)?.toDouble();
      final needsConfirmation = res['needs_confirmation'] == true;

      // server action succeeded; screen may be gone -> still report change
      if (!context.mounted) return true;

      final msg = late > 0
          ? '⚠️ Completed $late min late. Next appointments adjusted.'
          : paid
              ? '✅ Appointment completed'
              : newPrice != null
                  ? '✅ Completed. Total: ${apptMoney(sym, newPrice)} — Pending payment'
                  : '✅ Completed — Pending payment';
      snack(context, msg, late > 0 ? Colors.orange : Colors.green);

      if (needsConfirmation) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _panel(isDark),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Customer notified',
                    style: TextStyle(color: _fg(isDark))),
              ),
            ]),
            content: Text(
              'The next appointment may finish after closing time. The customer was notified and can MOVE or CANCEL. If there is no response in 30 minutes it is auto-cancelled.',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) snack(context, 'Error: $e', Colors.red);
      return false;
    }
  }

  // ---------------- PAY ----------------
  static Future<bool> pay(
    BuildContext context,
    Appt apt, {
    required bool isDark,
    Future<bool> Function()? guard,
  }) async {
    if (!await _guarded(context, guard)) return false;
    if (!context.mounted) return false;

    final sym = (apt['symbol'] as String?) ?? '';
    final price = _n(apt, 'price');
    final partial = apt['payment_status'] == 'partial';
    final toCollect = partial ? price - _n(apt, 'paid_amount') : price;
    final inProgress = apt['status'] == 'in_progress';

    final ok = await _confirm(
      context,
      isDark: isDark,
      icon: Icons.payments_rounded,
      color: Colors.teal.shade600,
      title: 'Confirm payment',
      message: partial
          ? 'Collect the remaining balance?'
          : 'Mark this appointment as PAID?',
      rows: [
        (Icons.person, '${apt['customer_name']}'),
        (Icons.receipt_long, 'Booking: ${apt['booking_number']}'),
        (Icons.payments_outlined,
            '${partial ? 'Balance' : 'Amount'}: ${apptMoney(sym, toCollect)}'),
      ],
      note: inProgress
          ? 'The service is still in progress. Marking as paid will also END it and move it to COMPLETE.'
          : null,
      confirmLabel: 'MARK AS PAID',
    );
    if (!ok || !context.mounted) return false;

    try {
      final res = await _sb.rpc('mark_appointment_payment', params: {
        'p_appointment_id': apt['id'],
        'p_payment_status': 'paid',
        'p_note': null,
      });
      if (res['success'] != true) {
        throw Exception(res['message'] ?? 'Failed to mark as paid');
      }
      final ended = res['auto_completed'] == true;
      final paidTotal = (res['paid_amount'] as num?)?.toDouble() ?? price;

      // server action succeeded; screen may be gone -> still report change
      if (!context.mounted) return true;

      // offer the bill straight away
      final billMap = <String, dynamic>{
        ...apt,
        'payment_status': 'paid',
        'price': paidTotal,
        'paid_amount': paidTotal,
        'payment_paid_at': DateTime.now().toUtc().toIso8601String(),
      };
      snack(
        context,
        ended
            ? '✅ Completed & paid — ${apptMoney(sym, toCollect)}'
            : '✅ Payment of ${apptMoney(sym, toCollect)} recorded',
        Colors.green.shade600,
        action: SnackBarAction(
          label: 'BILL',
          textColor: Colors.white,
          onPressed: () => bill(context, billMap),
        ),
      );
      return true;
    } catch (e) {
      if (context.mounted) snack(context, 'Error: $e', Colors.red);
      return false;
    }
  }

  // ---------------- CANCEL ----------------
  static Future<bool> cancel(
    BuildContext context,
    Appt apt, {
    required bool isDark,
    required String role, // 'owner' | 'barber'
    Future<bool> Function()? guard,
  }) async {
    if (!await _guarded(context, guard)) return false;
    if (!context.mounted) return false;

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CancelDialog(apt: apt, isDark: isDark),
    );
    if (reason == null || !context.mounted) return false;

    try {
      final user = _sb.auth.currentUser;
      if (user == null) throw Exception('User not found');
      final res = await _sb.rpc('cancel_booking_and_reorder', params: {
        'p_appointment_id': apt['id'],
        'p_cancelled_by': user.id,
        'p_cancel_reason': reason,
        'p_role': role,
      });
      if (res['success'] != true) {
        throw Exception(res['message'] ?? 'Cancellation failed');
      }
      final message = res['message']?.toString() ?? 'Appointment cancelled';

      // server action succeeded; screen may be gone -> still report change
      if (!context.mounted) return true;
      snack(context, message, Colors.orange);
      return true;
    } catch (e) {
      if (context.mounted) snack(context, 'Error: $e', Colors.red);
      return false;
    }
  }

  // ---------------- BILL ----------------
  static Future<void> bill(BuildContext context, Appt apt) async {
    try {
      await BillService.share(
        apt: apt,
        symbol: (apt['symbol'] as String?) ?? '',
        startTime: (apt['local_start_time'] as String?) ?? '',
        endTime: (apt['local_end_time'] as String?) ?? '',
      );
    } catch (e) {
      if (context.mounted) snack(context, 'Bill error: $e', Colors.red);
    }
  }

  // ---------------- SERVICES ----------------
  static Future<bool> editServices(
    BuildContext context,
    Appt apt, {
    Future<bool> Function()? guard,
  }) async {
    if (!await _guarded(context, guard)) return false;
    if (!context.mounted) return false;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => EditAppointmentServicesSheet(appointment: apt),
    );
    return changed == true;
  }
}

// =====================================================================
// CANCEL DIALOG (its own State, so the text controller is always disposed safely)
// =====================================================================
class _CancelDialog extends StatefulWidget {
  final Appt apt;
  final bool isDark;
  const _CancelDialog({required this.apt, required this.isDark});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  static const _reasons = <(String, String)>[
    ('Customer no show', '❌ Customer No Show'),
    ('Customer requested cancellation', '🙋 Customer Requested Cancellation'),
    ('Barber unavailable', '👤 Barber Unavailable'),
    ('Equipment issue', '🔧 Equipment Issue'),
    ('Schedule conflict', '📅 Schedule Conflict'),
    ('Other', '📝 Other'),
  ];

  String? _reason;
  String? _error;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _submit() {
    if (_reason == null) {
      setState(() => _error = 'Please select a reason');
      return;
    }
    if (_reason == 'Other' && _other.text.trim().isEmpty) {
      setState(() => _error = 'Please specify the reason');
      return;
    }
    Navigator.pop(context, _reason == 'Other' ? _other.text.trim() : _reason);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.isDark;
    final a = widget.apt;
    final sym = (a['symbol'] as String?) ?? '';
    final ps = a['payment_status'];
    final wasPaid = ps == 'paid' || ps == 'partial';
    final paid = _n(a, 'paid_amount');

    return AlertDialog(
      backgroundColor: _panel(d),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.red, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Cancel appointment',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _fg(d))),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _subtle(d),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a['customer_name']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: _fg(d))),
                    const SizedBox(height: 4),
                    Text(
                      '${a['display_date']} at ${a['local_start_time'] ?? ''}',
                      style: TextStyle(fontSize: 13, color: _muted(d)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Reason for cancellation',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: _fg(d))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                dropdownColor: d ? const Color(0xFF2A2A2A) : Colors.white,
                style: TextStyle(color: _fg(d)),
                decoration: InputDecoration(
                  hintText: 'Select a reason',
                  hintStyle: TextStyle(color: _muted(d)),
                  filled: true,
                  fillColor: d ? const Color(0xFF2A2A2A) : Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: [
                  for (final r in _reasons)
                    DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                ],
                onChanged: (v) => setState(() {
                  _reason = v;
                  _error = null;
                }),
              ),
              if (_reason == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _other,
                  maxLines: 2,
                  style: TextStyle(color: _fg(d)),
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    hintText: 'Please specify the reason...',
                    hintStyle: TextStyle(color: _muted(d)),
                    filled: true,
                    fillColor: d ? const Color(0xFF2A2A2A) : Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber,
                        size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        wasPaid
                            ? 'Customer already paid ${apptMoney(sym, paid)}. It will be marked REFUNDED. Give the money back to the customer. The customer will be notified.'
                            : 'This cannot be undone. The customer will be notified.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('KEEP BOOKING'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('YES, CANCEL'),
        ),
      ],
    );
  }
}