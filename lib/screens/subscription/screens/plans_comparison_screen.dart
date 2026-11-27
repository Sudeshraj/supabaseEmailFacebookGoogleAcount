import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/models/subscription_plan.dart';
import 'package:flutter_application_1/screens/subscription/providers/subscription_provider.dart';
import 'package:flutter_application_1/screens/subscription/screens/payment_history_screen.dart';
import 'package:flutter_application_1/screens/subscription/services/play_billing_service.dart';
import 'package:flutter_application_1/screens/subscription/services/payment_service.dart';
import 'package:flutter_application_1/screens/subscription/services/subscription_service.dart';
import 'package:flutter_application_1/screens/subscription/widgets/payment_issue_banner.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reduce_salons_screen.dart';

// ============================================================
// SUBSCRIPTION SCREEN (current plan + all plans in one place)
// ------------------------------------------------------------
//   • WEB: plans side by side (see _buildPlanList).
//   • Opened with ?reason=...&required=... (locked feature): the plan that
//     unlocks it is highlighted and scrolled into view.
//   • ANDROID: paid plans are bought with Google Play Billing (required by
//     the Google Play policy for digital features). The app never opens a
//     PayHere payment on Android.
//   • WEB: PayHere (iframe popup; same-tab redirect as a fallback, PayHere
//     then returns the user to /payment-return)
//   • Downgrade to the free plan of a PayHere plan: through the server, no
//     payment involved.
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

class _PlansComparisonScreenState extends State<PlansComparisonScreen>
    with SingleTickerProviderStateMixin {
  final SubscriptionService _service = SubscriptionService();
  final PaymentService _payment = PaymentService(); // web only

  List<SubscriptionPlan> _plans = [];
  bool _loading = true;
  bool _processing = false;
  String? _error;

  // Set from the route's query params when redirected here from a locked route
  String? _reason;
  String? _requiredPlan;

  // auto scroll to the highlighted plan (only once)
  final GlobalKey _targetKey = GlobalKey();
  bool _didScroll = false;

  // pulse of the selected plan card (like the customer dashboard offer cards)
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ---- Google Play (Android) ----
  Map<String, GooglePlayProductDetails> _playProducts = {};
  StreamSubscription<PlayPurchaseEvent>? _playSub;
  Timer? _playTimeout;
  SubscriptionPlan? _awaitingPlan;

  bool get _isAndroid => PlayBillingService.isSupported;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadPlans();

    if (_isAndroid) {
      _playSub = PlayBillingService.instance.events.listen(_onPlayEvent);
    }

    // always show a fresh current plan for THIS salon
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SubscriptionProvider>().loadCapabilities(widget.salonId);
    });
  }

  @override
  void dispose() {
    _playSub?.cancel();
    _playTimeout?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
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
        if (_isAndroid) _loadPlayProducts();
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

  Future<void> _loadPlayProducts() async {
    final ids = _plans.map((p) => p.playProductId).whereType<String>().toSet();
    try {
      final products = await PlayBillingService.instance.loadProducts(ids);
      if (mounted) setState(() => _playProducts = products);
    } catch (e) {
      debugPrint('❌ loading Google Play products failed: $e');
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
  // AUTO SELECTED PLAN
  // ============================================================

  /// The cheapest plan that unlocks [_reason]. Features without a flag in
  /// SubscriptionPlan (e.g. VIP booking) are matched by [_requiredPlan].
  /// Returns null when there is nothing to upgrade to.
  SubscriptionPlan? _findTargetPlan(SubscriptionProvider provider) {
    if (_reason == null && _requiredPlan == null) return null;

    final required = _requiredPlan?.toLowerCase();
    final sorted = [..._plans]
      ..sort((a, b) => a.planRank.compareTo(b.planRank));

    bool unlocks(SubscriptionPlan p) {
      switch (_reason) {
        case 'manage_offers':
          return p.canManageOffers;
        case 'customers_screen':
          return p.canViewCustomersScreen;
        case 'revenue':
          return p.canViewRevenue;
        case 'reports':
          return p.canViewReports;
        case 'analytics':
          return p.canViewAnalytics;
        case 'export':
          return p.canExportData;
        case 'salons':
          return p.planRank > provider.currentPlanRank &&
              (p.maxSalons == -1 || p.maxSalons > provider.currentSalons);
        default:
          return p.name.toLowerCase() == required;
      }
    }

    for (final plan in sorted) {
      if (unlocks(plan)) {
        return plan.planRank > provider.currentPlanRank ? plan : null;
      }
    }
    return null;
  }

  void _scrollToTargetOnce() {
    if (_didScroll) return;
    _didScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _targetKey.currentContext;
      if (!mounted || targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        alignment: 0.05,
      );
    });
  }

  // ============================================================
  // GOOGLE PLAY EVENTS (result of the purchase sheet)
  // ============================================================

  void _onPlayEvent(PlayPurchaseEvent event) {
    _playTimeout?.cancel();
    if (!mounted) return;

    switch (event.type) {
      case PlayEventType.verified:
        // only celebrate a purchase that was started on THIS screen
        final plan = _awaitingPlan;
        if (plan == null) return;
        _awaitingPlan = null;
        setState(() => _processing = false);
        _showSuccessDialog(
          plan.displayName,
          'Thank you! Your ${plan.displayName} plan is now active.',
        );
        break;

      case PlayEventType.pending:
        setState(() => _processing = false);
        _showSnack(
          'Your payment is pending. The plan activates as soon as it completes.',
        );
        break;

      case PlayEventType.canceled:
        _awaitingPlan = null;
        setState(() => _processing = false);
        _showSnack('Purchase cancelled');
        break;

      case PlayEventType.error:
        if (_awaitingPlan == null && !_processing) return;
        _awaitingPlan = null;
        setState(() => _processing = false);
        _showSnack(event.message ?? 'Purchase failed', isError: true);
        break;
    }
  }

  Future<void> _openPlaySubscriptions() async {
    final opened = await launchUrl(
      PlayBillingService.manageUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _showSnack('Could not open Google Play', isError: true);
  }

  // ============================================================
  // PLAN SELECTION
  // ============================================================

  Future<void> _handlePlanSelection(SubscriptionPlan plan) async {
    if (_isAndroid) {
      await _handleAndroidSelection(plan);
      return;
    }
    if (!kIsWeb) {
      _showSnack('Subscriptions are not available on this platform yet');
      return;
    }
    await _handleWebSelection(plan);
  }

  // ---------------- ANDROID ----------------

  Future<void> _handleAndroidSelection(SubscriptionPlan plan) async {
    final provider = context.read<SubscriptionProvider>();
    final current = _currentPlan;
    if (current == null) return;

    final isCurrent = plan.id == current.id;

    // ---- free plan ----
    if (plan.price == 0) {
      if (isCurrent) {
        _showSnack('You are already on the ${plan.displayName} plan');
        return;
      }
      if (provider.isPlaySource) {
        // a Google Play subscription is cancelled in Google Play
        await _openPlaySubscriptions();
        return;
      }
      // plan that was NOT bought with Google Play: downgrade, no payment
      final confirmed = await _showConfirmDialog(
        plan,
        current,
        isRenewal: false,
      );
      if (confirmed != true) return;
      setState(() => _processing = true);
      try {
        await _changePlanOnServer(plan);
      } finally {
        if (mounted) setState(() => _processing = false);
      }
      return;
    }

    // ---- paid plan ----
    if (isCurrent) {
      if (provider.isPlaySource) {
        await _openPlaySubscriptions();
      } else {
        _showSnack('You are already on the ${plan.displayName} plan');
      }
      return;
    }

    final product = plan.playProductId == null
        ? null
        : _playProducts[plan.playProductId];
    if (product == null) {
      _showSnack('This plan is not available in Google Play yet', isError: true);
      return;
    }

    final isUpgrade = plan.planRank > current.planRank;
    final hasPlaySub = provider.isPlaySource;
    final deferred = hasPlaySub && !isUpgrade; // downgrade: next renewal

    final confirmed = await _showPlayConfirmDialog(
      plan,
      product,
      isUpgrade: isUpgrade,
      hasPlaySub: hasPlaySub,
    );
    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      GooglePlayPurchaseDetails? oldPurchase;
      if (hasPlaySub) {
        final ids = _plans
            .map((p) => p.playProductId)
            .whereType<String>()
            .toSet();
        oldPurchase = await PlayBillingService.instance.findCurrentPurchase(
          ids,
        );
        if (oldPurchase == null) {
          if (mounted) setState(() => _processing = false);
          _showSnack(
            'Could not find your current Google Play subscription. Please try again.',
            isError: true,
          );
          return;
        }
      }

      _awaitingPlan = plan;
      final started = await PlayBillingService.instance.buy(
        product: product,
        ownerId: widget.ownerId,
        oldPurchase: oldPurchase,
        deferred: deferred,
      );

      if (!started) {
        _awaitingPlan = null;
        if (mounted) setState(() => _processing = false);
        _showSnack('Could not start the purchase', isError: true);
        return;
      }

      if (deferred) {
        // Google applies a downgrade at the next renewal, so there is no
        // purchase event to wait for.
        _awaitingPlan = null;
        if (mounted) setState(() => _processing = false);
        _showSnack(
          'If you confirmed, your plan changes to ${plan.displayName} at the '
          'end of the current billing period.',
        );
        return;
      }

      // safety net in case no event ever arrives
      _playTimeout?.cancel();
      _playTimeout = Timer(const Duration(seconds: 120), () {
        if (mounted && _processing) setState(() => _processing = false);
      });
    } catch (e) {
      _awaitingPlan = null;
      if (mounted) setState(() => _processing = false);
      _showSnack('Error: $e', isError: true);
    }
  }

  // ---------------- WEB (PayHere) ----------------

  Future<void> _handleWebSelection(SubscriptionPlan plan) async {
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
      await _changePlanOnServer(plan, previousExpiry: previousExpiry);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// request_plan_change RPC (+ PayHere payment on web)
  Future<void> _changePlanOnServer(
    SubscriptionPlan plan, {
    DateTime? previousExpiry,
  }) async {
    final provider = context.read<SubscriptionProvider>();

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
          if (_isAndroid || !kIsWeb) {
            _showSnack(
              'Paid plans on Android are bought with Google Play.',
              isError: true,
            );
          } else {
            await _handlePaymentFlow(plan, previousExpiry: previousExpiry);
          }
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
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  // ============================================================
  // PAYHERE PAYMENT FLOW (WEB ONLY)
  // ============================================================

  /// PayHere sends the user here after a web redirect payment.
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
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final name =
        user?.userMetadata?['full_name'] as String? ?? email.split('@').first;
    final phone = user?.userMetadata?['phone'] as String? ?? '0770000000';

    final paymentId = await _payment.startSubscriptionPayment(
      salonId: widget.salonId,
      planName: plan.name,
      customerEmail: email,
      customerName: name,
      customerPhone: phone,
      returnUrl: _buildReturnUrl('return', plan.name, previousExpiry),
      cancelUrl: _buildReturnUrl('cancel', plan.name, previousExpiry),
    );

    if (!mounted) return;

    if (paymentId == null) {
      _showSnack('Payment cancelled or failed', isError: true);
      return;
    }

    // redirect fallback: PaymentReturnScreen shows the result
    if (paymentId == PaymentService.redirectSentinel) return;

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

  /// Subscription terms are shown BEFORE the purchase (Google Play policy):
  /// price, billing period, auto-renewal and how to cancel.
  Future<bool?> _showPlayConfirmDialog(
    SubscriptionPlan plan,
    GooglePlayProductDetails product, {
    required bool isUpgrade,
    required bool hasPlaySub,
  }) {
    final deferred = hasPlaySub && !isUpgrade;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          hasPlaySub
              ? (isUpgrade ? 'Upgrade plan?' : 'Downgrade plan?')
              : 'Subscribe to ${plan.displayName}?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  Expanded(
                    child: Text(
                      '${product.price} / month',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (deferred)
              Text(
                'Your plan changes to ${plan.displayName} at the end of your '
                'current billing period. You keep your current features until then.',
                style: const TextStyle(fontSize: 13),
              )
            else if (hasPlaySub)
              const Text(
                'You are charged now for the difference, prorated for the '
                'remaining time of your current period.',
                style: TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 8),
            const Text(
              'Billed monthly through Google Play. The subscription renews '
              'automatically until you cancel it in Google Play > Subscriptions.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasPlaySub ? 'Confirm' : 'Subscribe'),
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
          // stay here: the current plan card above shows the new plan
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription?'),
        content: const Text(
          'Your plan will remain active until the end of the current billing period, '
          'then it will automatically downgrade to Bronze (Free).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Plan'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _cancelSubscription();
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelSubscription() async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final result = await context
          .read<SubscriptionProvider>()
          .cancelSubscription(ownerId: widget.ownerId);
      _showSnack(
        result['message']?.toString() ?? 'Done',
        isError: result['success'] != true,
      );
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
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
    final provider = context.watch<SubscriptionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Payment history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentHistoryScreen(ownerId: widget.ownerId),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(provider),
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

  Widget _buildBody(SubscriptionProvider provider) {
    final isThisSalon = provider.currentSalonId == widget.salonId;
    // never show another salon's plan (or "Bronze" before it is loaded)
    final ready = provider.isReady && isThisSalon;

    if (!ready && (provider.loading || !isThisSalon)) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!ready) {
      return _buildErrorState(
        provider.error ?? 'Could not load subscription details',
        () => provider.loadCapabilities(widget.salonId),
      );
    }

    final target = _findTargetPlan(provider);
    if (target != null) {
      _scrollToTargetOnce();
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else if (_pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }

    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      // not a ListView: the target card must be built to scroll to it
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        // wide browser windows: keep the content centred and readable
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (provider.paymentIssue != null)
                  PaymentIssueBanner(issue: provider.paymentIssue!),
                _buildCurrentPlanCard(provider),
                const SizedBox(height: 24),
                const Text(
                  'Select your plan',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _isAndroid
                      ? 'Plans are billed monthly through Google Play.'
                      : 'Upgrade anytime. Downgrade takes effect immediately.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                // only this section waits for the plans list: the current plan
                // card and Cancel / Manage above stay usable
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _buildErrorState('Failed to load plans\n\n$_error', _loadPlans),
                _buildPlanList(provider, target),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PLAN LIST
  // ============================================================

  /// Web: all plans in one row (2 x 2 in a medium sized window).
  /// Mobile app and narrow windows: one under the other.
  Widget _buildPlanList(
    SubscriptionProvider provider,
    SubscriptionPlan? target,
  ) {
    if (_plans.isEmpty) return const SizedBox.shrink();

    final plans = [..._plans]
      ..sort((a, b) => a.planRank.compareTo(b.planRank));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = !kIsWeb || width < 560
            ? 1
            : (width < 960 ? 2 : plans.length);

        // ---- one under the other ----
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final plan in plans)
                if (plan.id == target?.id)
                  Column(
                    key: _targetKey,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_reason != null) ...[
                        _buildReasonBanner(plan),
                        const SizedBox(height: 12),
                      ],
                      // narrower by the pulse scale, so it never gets clipped
                      FractionallySizedBox(
                        widthFactor: 1 / 1.03,
                        child: _pulse(
                          _buildPlanCard(plan, provider, isTarget: true),
                        ),
                      ),
                    ],
                  )
                else
                  _buildPlanCard(plan, provider),
            ],
          );
        }

        // ---- side by side ----
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < plans.length; start += columns)
              _buildPlanRow(
                plans.skip(start).take(columns).toList(),
                columns,
                provider,
                target,
              ),
          ],
        );
      },
    );
  }

  /// One row of equally wide and equally tall plan cards.
  Widget _buildPlanRow(
    List<SubscriptionPlan> rowPlans,
    int columns,
    SubscriptionProvider provider,
    SubscriptionPlan? target,
  ) {
    final hasTarget = rowPlans.any((p) => p.id == target?.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        key: hasTarget ? _targetKey : null,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasTarget && _reason != null) ...[
            _buildReasonBanner(target!),
            const SizedBox(height: 16),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    child: i >= rowPlans.length
                        ? const SizedBox.shrink()
                        : rowPlans[i].id == target?.id
                        ? _pulse(
                            _buildPlanCard(
                              rowPlans[i],
                              provider,
                              isTarget: true,
                              inRow: true,
                            ),
                          )
                        : _buildPlanCard(rowPlans[i], provider, inRow: true),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pulse(Widget card) {
    return ScaleTransition(
      scale: _pulseAnim,
      child: RepaintBoundary(child: card),
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PLAN STYLE (same icon and colours as the owner dashboard badge)
  // ============================================================

  static const IconData _planIcon = Icons.workspace_premium;

  Color _planColor(int rank) {
    return rank == 4
        ? Colors.amber
        : rank == 3
        ? Colors.orange
        : rank == 2
        ? Colors.blueGrey
        : Colors.brown;
  }

  /// Readable text / icon colour on top of a solid plan colour.
  Color _onPlanColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  /// Same look as the offer cards on the customer dashboard.
  BoxDecoration _planDecoration(
    Color color, {
    required Color borderColor,
    double borderWidth = 1,
    bool glow = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return BoxDecoration(
      // blended on the surface, so the shadow never shows through the card
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            color.withValues(alpha: isDark || glow ? 0.18 : 0.1),
            surface,
          ),
          surface,
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: glow
              ? color.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.05),
          blurRadius: glow ? 16 : 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _planIconBox(Color color) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_planIcon, color: color, size: 28),
    );
  }

  // ============================================================
  // CURRENT PLAN CARD
  // ============================================================

  Widget _buildCurrentPlanCard(SubscriptionProvider provider) {
    final expiresAt = provider.expiresAt;
    final isPaid = provider.isPaidPlan;
    final days = provider.daysRemaining;
    final color = _planColor(provider.currentPlanRank);

    return Container(
      decoration: _planDecoration(
        color,
        borderColor: color.withValues(alpha: 0.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _planIconBox(color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${provider.currentPlanDisplay} Plan',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isPaid && expiresAt != null) ...[
              Text(
                provider.cancelAtPeriodEnd
                    ? 'Ends on: ${_formatDate(expiresAt)}'
                    : 'Renews / expires: ${_formatDate(expiresAt)}',
                style: TextStyle(color: Colors.grey[700]),
              ),
              if (days != null)
                Text(
                  '$days day${days == 1 ? "" : "s"} left',
                  style: TextStyle(
                    color: days <= 3 ? Colors.red : Colors.grey[700],
                    fontWeight: days <= 3 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              const SizedBox(height: 4),
            ],
            if (provider.cancelAtPeriodEnd)
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cancelled. You keep your features until the date above, '
                        'then the salon moves to Bronze (Free).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (provider.isPlaySource)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  provider.cancelAtPeriodEnd
                      ? 'Billed through Google Play (will not renew)'
                      : 'Billed through Google Play (renews automatically)',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            Text(
              'Salons: ${provider.currentSalons} / ${provider.maxSalons == -1 ? "∞" : provider.maxSalons}',
              style: TextStyle(color: Colors.grey[700]),
            ),

            // Google Play subscriptions are cancelled in Google Play
            if (provider.isPlaySource) ...[
              const SizedBox(height: 12),
              if (_isAndroid)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openPlaySubscriptions,
                    icon: const Icon(Icons.manage_accounts),
                    label: const Text('Manage in Google Play'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                )
              else if (kIsWeb)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'This subscription is billed through Google Play. Change or '
                    'cancel it in the Android app (Google Play > Subscriptions).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],

            // PayHere (web) subscriptions: cancel here
            if (isPaid &&
                !provider.isPlaySource &&
                !provider.cancelAtPeriodEnd) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _processing ? null : _confirmCancel,
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  label: const Text(
                    'Cancel Subscription',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // REASON BANNER
  // ============================================================

  Widget _buildReasonBanner(SubscriptionPlan target) {
    final reason = _reason ?? '';
    final required = target.displayName;

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
      case 'vip_booking':
        return 'VIP Booking';
      default:
        return 'This feature';
    }
  }

  // ============================================================
  // PLAN CARD
  // ============================================================

  /// On Android the price shown MUST be the one Google Play will charge
  String _priceText(SubscriptionPlan plan) {
    if (plan.price == 0) return 'Free';
    if (_isAndroid && plan.playProductId != null) {
      final product = _playProducts[plan.playProductId];
      if (product != null) return product.price;
    }
    return 'Rs. ${plan.price.toStringAsFixed(0)}';
  }

  /// [inRow]: the side by side (web) version. Everything is centred and the
  /// button sits right under the price, so cards are easy to compare.
  Widget _buildPlanCard(
    SubscriptionPlan plan,
    SubscriptionProvider provider, {
    bool isTarget = false,
    bool inRow = false,
  }) {
    final isCurrent = plan.name == provider.currentPlanName;
    final isUpgrade = plan.planRank > provider.currentPlanRank;
    // PayHere renewals exist on the web only
    final canRenewThis = isCurrent && provider.canRenew && !_isAndroid;
    final unavailableOnAndroid =
        _isAndroid &&
        plan.price > 0 &&
        !isCurrent &&
        (plan.playProductId == null ||
            !_playProducts.containsKey(plan.playProductId));

    final color = _planColor(plan.planRank);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? Colors.white60 : Colors.grey[600];

    final borderColor = isTarget
        ? color
        : isCurrent
        ? Colors.green.shade400
        : color.withValues(alpha: 0.3);

    final name = Text(
      plan.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        // a little darker, so amber is readable on white
        color: isDark ? Colors.white : Color.lerp(color, Colors.black, 0.3),
      ),
    );

    // SELECTED and CURRENT never show together (a selected plan is an upgrade)
    final Widget? chip = isTarget
        ? _statusChip(
            'SELECTED',
            color,
            _onPlanColor(color),
            icon: Icons.check_circle,
          )
        : isCurrent
        ? _statusChip('CURRENT', Colors.green, Colors.white)
        : null;

    final price = Row(
      mainAxisAlignment: inRow
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            _priceText(plan),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (plan.price > 0) ...[
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '/month',
              style: TextStyle(color: secondaryColor, fontSize: 14),
            ),
          ),
        ],
      ],
    );

    final description = Text(
      plan.description ?? '',
      textAlign: inRow ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 13, color: secondaryColor),
    );

    final features = [
      _featureRow('Appointment History', plan.canViewAppointmentHistory),
      _featureRow('Offers Management', plan.canManageOffers),
      _featureRow('Revenue Screen', plan.canViewRevenue),
      _featureRow('Customers Screen', plan.canViewCustomersScreen),
      _featureRow('Reports', plan.canViewReports),
      _featureRow('Analytics', plan.canViewAnalytics),
      _featureRow('Data Export (Excel/PDF)', plan.canExportData),
    ];

    final button = SizedBox(
      width: double.infinity,
      child: _buildActionButton(
        plan: plan,
        provider: provider,
        isCurrent: isCurrent,
        isUpgrade: isUpgrade,
        canRenewThis: canRenewThis,
        unavailable: unavailableOnAndroid,
      ),
    );

    return Container(
      // in a row the spacing comes from the row itself
      margin: inRow ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
      decoration: _planDecoration(
        color,
        borderColor: borderColor,
        borderWidth: isTarget ? 2.5 : (isCurrent ? 1.5 : 1),
        glow: isTarget,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: inRow
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (inRow) ...[
              // same height with or without a chip, so the cards line up
              SizedBox(height: 28, child: Center(child: chip)),
              const SizedBox(height: 8),
              _planIconBox(color),
              const SizedBox(height: 10),
              name,
            ] else
              Row(
                children: [
                  _planIconBox(color),
                  const SizedBox(width: 12),
                  Expanded(child: name),
                  ?chip,
                ],
              ),
            const SizedBox(height: 12),
            price,
            const SizedBox(height: 4),
            Text(
              plan.maxSalons == -1
                  ? 'Unlimited salons'
                  : '${plan.maxSalons} salon${plan.maxSalons > 1 ? "s" : ""}',
              style: TextStyle(
                fontSize: 13,
                color: secondaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            // (side by side: the current plan card above already shows this)
            if (!inRow &&
                isCurrent &&
                provider.isPaidPlan &&
                provider.daysRemaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${provider.daysRemaining} day(s) left',
                  style: TextStyle(
                    fontSize: 12,
                    color: canRenewThis ? Colors.orange[800] : secondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (inRow) ...[
              const SizedBox(height: 8),
              // room for three lines, so buttons and features line up
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: description,
              ),
              const SizedBox(height: 12),
              button,
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              ...features,
            ] else ...[
              if (plan.description != null) ...[
                const SizedBox(height: 8),
                description,
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              ...features,
              const SizedBox(height: 16),
              button,
            ],
            if (_isAndroid && plan.price > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Auto-renews monthly until cancelled. '
                  'Cancel any time in Google Play > Subscriptions.',
                  style: TextStyle(fontSize: 11, color: secondaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(
    String label,
    Color background,
    Color foreground, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: foreground, size: 13),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required SubscriptionPlan plan,
    required SubscriptionProvider provider,
    required bool isCurrent,
    required bool isUpgrade,
    required bool canRenewThis,
    required bool unavailable,
  }) {
    final color = _planColor(plan.planRank);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    // Current plan bought with Google Play -> manage it there
    if (isCurrent && _isAndroid && provider.isPlaySource && plan.price > 0) {
      return OutlinedButton(
        onPressed: _openPlaySubscriptions,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 1.4),
          shape: shape,
        ),
        child: const Text('Manage in Google Play'),
      );
    }

    if (isCurrent && !canRenewThis) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(shape: shape),
        child: const Text('Current Plan'),
      );
    }

    final String label;
    if (canRenewThis) {
      label = 'Renew ${plan.displayName}';
    } else if (_isAndroid && plan.price == 0 && provider.isPlaySource) {
      label = 'Cancel in Google Play';
    } else if (isUpgrade) {
      label = 'Upgrade to ${plan.displayName}';
    } else {
      label = 'Downgrade to ${plan.displayName}';
    }

    return ElevatedButton(
      onPressed: (_processing || unavailable)
          ? null
          : () => _handlePlanSelection(plan),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: _onPlanColor(color),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: shape,
      ),
      child: Text(
        unavailable ? 'Not available yet' : label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _featureRow(String label, bool enabled) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                color: enabled
                    ? (isDark ? Colors.white : Colors.black87)
                    : Colors.grey[500],
                decoration: enabled ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ),
    );
  }
}