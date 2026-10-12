import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription_plan.dart';
import '../providers/subscription_provider.dart';
import '../services/payment_service.dart';
import '../services/subscription_service.dart';
import 'reduce_salons_screen.dart';

// ============================================================
// PLANS COMPARISON SCREEN
// ------------------------------------------------------------
//   • Upgrade / Renew  → PayHere payment (price decided by the SERVER)
//       - Mobile: native PayHere SDK
//       - Web:    iframe popup; if it can't start, a same-tab redirect and
//                 PayHere returns the user to /payment-return
//                 (PaymentReturnScreen)
//   • Downgrade (with salon-count validation)
//   • "Reason" banner when redirected from a locked route
// ============================================================
class PlansComparisonScreen extends StatefulWidget {
  final int salonId;
  final String ownerId;

  const PlansComparisonScreen({
    super.key,
    required this.salonId,
    required this.ownerId,
  });

  @override
  State<PlansComparisonScreen> createState() => _PlansComparisonScreenState();
}

class _PlansComparisonScreenState extends State<PlansComparisonScreen> {
  final SubscriptionService _service = SubscriptionService();
  final PaymentService _payment = PaymentService();

  List<SubscriptionPlan> _plans = [];
  bool _loading = true;
  bool _processing = false;
  String? _error;

  // Set from the route's query params when redirected here from a locked route
  String? _reason;
  String? _requiredPlan;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    // make sure the provider is looking at THIS salon
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SubscriptionProvider>();
      if (provider.currentSalonId != widget.salonId || !provider.isReady) {
        provider.loadCapabilities(widget.salonId);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final uri = GoRouterState.of(context).uri;
      _reason = uri.queryParameters['reason'];
      _requiredPlan = uri.queryParameters['required'];
    } catch (_) {
      // Not routed through GoRouter — no reason banner.
    }
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final plans = await _service.getAllPlans();
      if (mounted) {
        setState(() {
          _plans = plans;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  SubscriptionPlan? get _currentPlan {
    if (_plans.isEmpty) return null;
    final provider = context.read<SubscriptionProvider>();
    return _plans.firstWhere(
      (p) => p.name == provider.currentPlanName,
      orElse: () => _plans.first,
    );
  }

  // ============================================================
  // PLAN SELECTION
  // ============================================================

  Future<void> _handlePlanSelection(SubscriptionPlan plan) async {
    final provider = context.read<SubscriptionProvider>();
    final currentPlan = _currentPlan;

    if (currentPlan == null) return;

    final isRenewal = plan.id == currentPlan.id;

    if (isRenewal && !provider.canRenew) {
      _showSnack('You are already on the ${plan.displayName} plan');
      return;
    }

    final confirmed = await _showConfirmDialog(
      plan,
      currentPlan,
      isRenewal: isRenewal,
    );
    if (confirmed != true) return;

    final previousExpiry = isRenewal ? provider.expiresAt : null;

    setState(() => _processing = true);

    try {
      final result = await provider.requestPlanChange(
        newPlanName: plan.name,
        ownerId: widget.ownerId,
        salonId: widget.salonId,
      );

      if (!mounted) return;

      final actionRequired = result['action_required'] as String?;

      switch (actionRequired) {
        case 'PAYMENT_REQUIRED':
          await _handlePaymentFlow(plan, previousExpiry: previousExpiry);
          break;

        case 'REDUCE_SALONS':
          await _handleReduceSalons(plan, result);
          break;

        case 'NONE':
          _showSnack(result['message'] ?? 'Already on this plan');
          break;

        default:
          if (result['success'] == true) {
            _showSuccessDialog(
              plan.displayName,
              result['message'] ?? 'Plan changed successfully',
            );
          } else {
            _showSnack(
              result['message'] ?? 'Failed to change plan',
              isError: true,
            );
          }
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  // ============================================================
  // PAYMENT FLOW
  // ============================================================

  /// PayHere sends the user here after a web redirect payment.
  /// It carries everything PaymentReturnScreen needs (no router `extra`).
  String _buildReturnUrl(
    String status,
    String planName,
    DateTime? previousExpiry,
  ) {
    final params = <String, String>{
      'payment': status,
      'plan': planName,
      'salon': '${widget.salonId}',
      if (previousExpiry != null)
        'prev': '${previousExpiry.millisecondsSinceEpoch}',
    };
    return Uri.parse(
      Uri.base.origin,
    ).replace(path: '/payment-return', queryParameters: params).toString();
  }

  Future<void> _handlePaymentFlow(
    SubscriptionPlan plan, {
    DateTime? previousExpiry,
  }) async {
    // Customer info from Supabase auth
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final name =
        user?.userMetadata?['full_name'] as String? ?? email.split('@').first;
    final phone = user?.userMetadata?['phone'] as String? ?? '0770000000';

    debugPrint(
      '💳 Starting payment — platform=${_payment.isWeb ? "web" : "mobile"}, '
      'plan=${plan.name}',
    );

    final paymentId = await _payment.startSubscriptionPayment(
      salonId: widget.salonId,
      planName: plan.name,
      customerEmail: email,
      customerName: name,
      customerPhone: phone,
      returnUrl: _payment.isWeb
          ? _buildReturnUrl('return', plan.name, previousExpiry)
          : null,
      cancelUrl: _payment.isWeb
          ? _buildReturnUrl('cancel', plan.name, previousExpiry)
          : null,
    );

    if (!mounted) return;

    if (paymentId == null) {
      _showSnack('Payment cancelled or failed', isError: true);
      return;
    }

    // WEB fallback: this tab is navigating to PayHere. The result is shown by
    // PaymentReturnScreen when PayHere redirects back.
    if (paymentId == PaymentService.redirectSentinel) return;

    // Mobile SDK / web iframe popup: payment submitted — the webhook
    // activates the plan, so wait for it.
    _showSnack('Payment received. Activating plan...');
    final activated = await _waitForPlan(
      plan.name,
      previousExpiry: previousExpiry,
    );

    if (!mounted) return;

    if (activated) {
      _showSuccessDialog(
        plan.displayName,
        'Payment successful. Your ${plan.displayName} plan is now active!',
      );
    } else {
      _showSnack('Payment received. Your plan will be activated shortly.');
    }
  }

  /// Polls until the webhook has activated [planName]
  /// (for a renewal: until expires_at moved past [previousExpiry]).
  Future<bool> _waitForPlan(String planName, {DateTime? previousExpiry}) async {
    final provider = context.read<SubscriptionProvider>();
    for (var i = 0; i < 15; i++) {
      await provider.loadCapabilities(widget.salonId);
      if (!mounted) return false;

      final planOk = provider.currentPlanName == planName;
      final expiryOk =
          previousExpiry == null ||
          (provider.expiresAt != null &&
              provider.expiresAt!.isAfter(previousExpiry));
      if (planOk && expiryOk) return true;

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return false;
    }
    return false;
  }

  // ============================================================
  // DOWNGRADE FLOW (reduce salons first)
  // ============================================================

  Future<void> _handleReduceSalons(
    SubscriptionPlan plan,
    Map<String, dynamic> result,
  ) async {
    final mustDeactivate = result['must_deactivate'] as int? ?? 0;
    final currentSalons = result['current_salons'] as int? ?? 0;
    final allowedSalons = result['allowed_salons'] as int? ?? 0;

    final reduced = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReduceSalonsScreen(
          ownerId: widget.ownerId,
          targetCount: allowedSalons,
          currentCount: currentSalons,
        ),
      ),
    );

    if (reduced == true && mounted) {
      await _handlePlanSelection(plan);
    } else if (mounted) {
      _showSnack(
        'Please deactivate $mustDeactivate salon(s) to continue',
        isError: true,
      );
    }
  }

  // ============================================================
  // DIALOGS
  // ============================================================

  Future<bool?> _showConfirmDialog(
    SubscriptionPlan newPlan,
    SubscriptionPlan currentPlan, {
    required bool isRenewal,
  }) {
    final isUpgrade = newPlan.planRank > currentPlan.planRank;
    final title = isRenewal
        ? 'Renew Plan?'
        : (isUpgrade ? 'Upgrade Plan?' : 'Downgrade Plan?');

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRenewal
                  ? 'Renew ${newPlan.displayName} for another month? '
                        'The new month is added after your current period ends.'
                  : 'Change from ${currentPlan.displayName} to ${newPlan.displayName}?',
            ),
            const SizedBox(height: 12),
            if ((isUpgrade || isRenewal) && newPlan.price > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payment, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text(
                      'Amount: LKR ${newPlan.price.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
            if (!isUpgrade && !isRenewal) ...[
              const SizedBox(height: 8),
              const Text(
                'You will lose access to features not included in the lower plan.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isRenewal ? 'Renew' : (isUpgrade ? 'Continue' : 'Confirm'),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String planName, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: Text('$planName Active!'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (Navigator.canPop(context)) {
                Navigator.pop(context); // Back to subscription screen
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Plan')),
      body: Stack(
        children: [
          _buildBody(),
          if (_processing)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Failed to load plans'),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadPlans,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_reason != null && _requiredPlan != null) ...[
          _buildReasonBanner(),
          const SizedBox(height: 16),
        ],
        const Text(
          'Select your plan',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Upgrade anytime. Downgrade takes effect immediately.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),
        ..._plans.map((plan) => _buildPlanCard(plan)),
      ],
    );
  }

  // ============================================================
  // REASON BANNER
  // ============================================================

  Widget _buildReasonBanner() {
    final reason = _reason ?? '';
    final required = _requiredPlan ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_featureDisplayName(reason)} requires $required',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Upgrade to $required or higher to unlock this feature.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _featureDisplayName(String reason) {
    switch (reason) {
      case 'reports':
        return 'Reports';
      case 'analytics':
        return 'Analytics';
      case 'revenue':
        return 'Revenue';
      case 'customers_screen':
        return 'Customers';
      case 'manage_offers':
        return 'Offers';
      case 'export':
        return 'Data export';
      case 'salons':
        return 'Creating more salons';
      default:
        return 'This feature';
    }
  }

  // ============================================================
  // PLAN CARD
  // ============================================================

  Widget _buildPlanCard(SubscriptionPlan plan) {
    final provider = context.watch<SubscriptionProvider>();
    final isCurrent = plan.name == provider.currentPlanName;
    final isUpgrade = plan.planRank > provider.currentPlanRank;
    final canRenewThis = isCurrent && provider.canRenew;

    final borderColor = isCurrent
        ? Colors.green
        : plan.planRank == 4
        ? Colors.amber
        : Colors.grey[300]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: isCurrent ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _parseColor(plan.badgeColor).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    plan.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _parseColor(plan.badgeColor),
                    ),
                  ),
                ),
                const Spacer(),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'CURRENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plan.price == 0
                      ? 'Free'
                      : 'Rs. ${plan.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (plan.price > 0) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '/month',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              plan.maxSalons == -1
                  ? 'Unlimited salons'
                  : '${plan.maxSalons} salon${plan.maxSalons > 1 ? "s" : ""}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isCurrent &&
                provider.isPaidPlan &&
                provider.daysRemaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${provider.daysRemaining} day(s) left',
                  style: TextStyle(
                    fontSize: 12,
                    color: canRenewThis ? Colors.orange[800] : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (plan.description != null) ...[
              const SizedBox(height: 8),
              Text(
                plan.description!,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _featureRow('Appointment History', plan.canViewAppointmentHistory),
            _featureRow('Offers Management', plan.canManageOffers),
            _featureRow('Revenue Screen', plan.canViewRevenue),
            _featureRow('Customers Screen', plan.canViewCustomersScreen),
            _featureRow('Reports', plan.canViewReports),
            _featureRow('Analytics', plan.canViewAnalytics),
            _featureRow('Data Export (Excel/PDF)', plan.canExportData),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: (isCurrent && !canRenewThis)
                  ? OutlinedButton(
                      onPressed: null,
                      child: const Text('Current Plan'),
                    )
                  : ElevatedButton(
                      onPressed: _processing
                          ? null
                          : () => _handlePlanSelection(plan),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (isUpgrade || canRenewThis)
                            ? Colors.amber[700]
                            : Colors.grey[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        canRenewThis
                            ? 'Renew ${plan.displayName}'
                            : (isUpgrade
                                  ? 'Upgrade to ${plan.displayName}'
                                  : 'Downgrade to ${plan.displayName}'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: enabled ? Colors.green : Colors.red[300],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: enabled ? Colors.black87 : Colors.grey[500],
                decoration: enabled ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return Colors.grey;
    try {
      final cleaned = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }
}
