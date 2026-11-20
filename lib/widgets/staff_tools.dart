// lib/widgets/staff_tools.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/staff_access_provider.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// "Book" + "VIP" buttons (walk-in / phone booking for a customer).
/// Owner dashboard: showBook = true, showVip = true,
///   vipLocked = (plan rank < 2), onVipLocked = existing _showUpgradeDialog.
/// Employee dashboard: pass the real permissions, vipLocked = false.
class StaffBookButtons extends StatelessWidget {
  final int salonId;
  final bool showBook;
  final bool showVip;
  final bool vipLocked;
  final bool bookLocked;
  final VoidCallback? onVipLocked;
  final VoidCallback? onBookLocked;
  final VoidCallback? onBooked;

  const StaffBookButtons({
    super.key,
    required this.salonId,
    this.showBook = true,
    this.showVip = true,
    this.vipLocked = false,
    this.bookLocked = false,
    this.onVipLocked,
    this.onBookLocked,
    this.onBooked,
  });

  /// Opens the EXISTING customer screens (same as the salon profile
  /// buttons) with the salon preloaded, so the salon step is skipped.
  Future<void> _open(BuildContext context, {required bool vip}) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final salon = await Supabase.instance.client
          .from('salons')
          .select(
            'id, name, address, logo_url, cover_url, phone, email, '
            'description, open_time, close_time, timezone, '
            'currency_code, currency_symbol',
          )
          .eq('id', salonId)
          .maybeSingle();

      if (salon == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Salon not found')),
        );
        return;
      }

      await router.push<bool>(
        vip ? '/customer/vip-booking' : '/customer/booking-flow',
        extra: Map<String, dynamic>.from(salon),
      );
      onBooked?.call();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!showBook && !showVip) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (showBook)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: bookLocked
                    ? onBookLocked
                    : () => _open(context, vip: false),
                icon: Icon(
                    bookLocked ? Icons.lock_outline : Icons.calendar_today,
                    size: 18),
                label: const Text('Book'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: bookLocked
                      ? AppTheme.primary.withValues(alpha: 0.55)
                      : AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (showBook && showVip) const SizedBox(width: 12),
          if (showVip)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: vipLocked
                    ? onVipLocked
                    : () => _open(context, vip: true),
                icon: Icon(
                  vipLocked ? Icons.lock_outline : Icons.star,
                  size: 18,
                  color: Colors.amber,
                ),
                label: const Text(
                  'VIP',
                  style: TextStyle(color: Colors.amber),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile {
  final String perm; // permission that unlocks this tile
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  const _Tile(this.perm, this.icon, this.label, this.color, this.route);
}

/// Shared "locked" dialog: the employee cannot upgrade, the OWNER does.
void showStaffUpgradeDialog(BuildContext context,
    {required String feature, required String plan}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text('$feature is locked')),
        ],
      ),
      content: Text(
        'This feature is not included in the salon\'s current '
        '${plan.isEmpty ? '' : '${plan[0].toUpperCase()}${plan.substring(1)} '}'
        'package.\n\nAsk the salon owner to upgrade the package to unlock it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Put this on the employee (barber) dashboard, ABOVE the barber's own
/// appointments tile. It renders nothing for a plain barber.
/// Works for several salons (chips) - the owner's screens are reused.
class StaffToolsSection extends StatefulWidget {
  final List<SalonAccess> salons; // provider.staffSalons
  final VoidCallback? onBooked;

  /// space above the card (the desk-only dashboard passes a small value)
  final double topMargin;
  const StaffToolsSection({
    super.key,
    required this.salons,
    this.onBooked,
    this.topMargin = 8,
  });

  @override
  State<StaffToolsSection> createState() => _StaffToolsSectionState();
}

class _StaffToolsSectionState extends State<StaffToolsSection> {
  int _index = 0;

  /// ALL tiles the role is entitled to. Each one is open or LOCKED on its
  /// own, according to the owner's current package (a.can / a.isLocked).
  List<_Tile> _tiles(SalonAccess a) {
    final id = a.salonId;
    final name = Uri.encodeComponent(a.salonName);
    final all = <_Tile>[
      _Tile('all_appointments', Icons.event_note, 'All Appointments',
          Colors.blue, '/owner/appointments?salonId=$id'),
      _Tile('view_customers', Icons.people, 'Customers', Colors.purple,
          '/owner/customers?salonId=$id'),
      _Tile('manage_services', Icons.build, 'Add Service', Colors.green,
          '/owner/services/add?salonId=$id'),
      _Tile('manage_services', Icons.list, 'Service List', Colors.cyan,
          '/owner/services?salonId=$id&salonName=$name'),
      _Tile('manage_barbers', Icons.person_add, 'Add Barber', Colors.purple,
          '/owner/add-barber?salonId=$id'),
      _Tile('manage_barbers', Icons.calendar_month, 'Schedule', Colors.teal,
          '/owner/barber-schedule?salonId=$id'),
      _Tile('manage_barbers', Icons.beach_access, 'Leaves', Colors.orange,
          '/owner/barber-leaves?salonId=$id'),
      _Tile('manage_barbers', Icons.list, 'Barber List', Colors.indigo,
          '/owner/barbers?salonId=$id'),
      _Tile('manage_holidays', Icons.wb_sunny, 'Salon Holidays', Colors.teal,
          '/owner/salon/holidays?salonId=$id'),
      _Tile('manage_offers', Icons.local_offer, 'Offers & Promotions',
          AppTheme.primary, '/owner/offers/$id'),
      _Tile('view_revenue', Icons.attach_money, 'Revenue', Colors.orange,
          '/owner/revenue?salonId=$id'),
      _Tile('view_reports', Icons.bar_chart, 'Reports', Colors.deepOrange,
          '/owner/reports?salonId=$id'),
      _Tile('view_analytics', Icons.analytics, 'Analytics',
          Colors.indigoAccent, '/owner/analytics?salonId=$id'),
    ];
    return all
        .where((t) => a.can(t.perm) || a.isLocked(t.perm))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.salons.isEmpty) return const SizedBox.shrink();
    if (_index >= widget.salons.length) _index = 0;

    final a = widget.salons[_index];
    final tiles = _tiles(a);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.fromLTRB(16, widget.topMargin, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Staff tools (${a.staffRole})',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (widget.salons.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (int i = 0; i < widget.salons.length; i++)
                  ChoiceChip(
                    label: Text(widget.salons[i].salonName),
                    selected: i == _index,
                    onSelected: (_) => setState(() => _index = i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          StaffBookButtons(
            salonId: a.salonId,
            showBook: a.can('book') || a.isLocked('book'),
            showVip: a.can('vip_book') || a.isLocked('vip_book'),
            bookLocked: a.isLocked('book'),
            vipLocked: a.isLocked('vip_book'),
            onBookLocked: () => showStaffUpgradeDialog(context,
                feature: 'Book', plan: a.plan),
            onVipLocked: () => showStaffUpgradeDialog(context,
                feature: 'VIP booking', plan: a.plan),
            onBooked: widget.onBooked,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in tiles)
                SizedBox(
                  width: 104,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: a.isLocked(t.perm)
                        ? () => showStaffUpgradeDialog(context,
                            feature: t.label, plan: a.plan)
                        : () => context.push(t.route),
                    child: Opacity(
                      opacity: a.isLocked(t.perm) ? 0.55 : 1,
                      child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 6),
                      decoration: BoxDecoration(
                        color: t.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: t.color.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                              a.isLocked(t.perm) ? Icons.lock_outline : t.icon,
                              color: t.color,
                              size: 22),
                          const SizedBox(height: 6),
                          Text(
                            t.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}