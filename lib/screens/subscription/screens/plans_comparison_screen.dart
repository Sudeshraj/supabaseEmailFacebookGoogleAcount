import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/models/subscription_plan.dart';
import 'package:flutter_application_1/screens/subscription/providers/subscription_provider.dart';
import 'package:flutter_application_1/screens/subscription/screens/play_billing_service.dart';
import 'package:flutter_application_1/screens/subscription/services/payment_service.dart';
import 'package:flutter_application_1/screens/subscription/services/subscription_service.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reduce_salons_screen.dart';

// ============================================================
// PLANS COMPARISON SCREEN
// ------------------------------------------------------------
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

class _PlansComparisonScreenState extends State<PlansComparisonScreen> {
  final SubscriptionService _service = SubscriptionService();
  final PaymentService _payment = PaymentService(); // web only

  List<SubscriptionPlan> _plans = [];
  bool _loading = true;
  bool _processing = false;
  String? _error;

  // Set from the route's query params when redirected here from a locked route
  String? _reason;
  String? _requiredPlan;

  // ---- Google Play (Android) ----
  Map<String, GooglePlayProductDetails> _playProducts = {};
  StreamSubscription<PlayPurchaseEvent>? _playSub;
  Timer? _playTimeout;
  SubscriptionPlan? _awaitingPlan;

  bool get _isAndroid => PlayBillingService.isSupported;

  @override
  void initState() {
    super.initState();
    _loadPlans();

    if (_isAndroid) {
      _playSub = PlayBillingService.instance.events.listen(_onPlayEvent);
    }

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
  void dispose() {
    _playSub?.cancel();
    _playTimeout?.cancel();
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
          _isAndroid
              ? 'Plans are billed monthly through Google Play.'
              : 'Upgrade anytime. Downgrade takes effect immediately.',
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

  /// On Android the price shown MUST be the one Google Play will charge
  String _priceText(SubscriptionPlan plan) {
    if (plan.price == 0) return 'Free';
    if (_isAndroid && plan.playProductId != null) {
      final product = _playProducts[plan.playProductId];
      if (product != null) return product.price;
    }
    return 'Rs. ${plan.price.toStringAsFixed(0)}';
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    final provider = context.watch<SubscriptionProvider>();
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
                Flexible(
                  child: Text(
                    _priceText(plan),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
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
              child: _buildActionButton(
                plan: plan,
                provider: provider,
                isCurrent: isCurrent,
                isUpgrade: isUpgrade,
                canRenewThis: canRenewThis,
                unavailable: unavailableOnAndroid,
              ),
            ),
            if (_isAndroid && plan.price > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Auto-renews monthly until cancelled. '
                  'Cancel any time in Google Play > Subscriptions.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
          ],
        ),
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
    // Current plan bought with Google Play -> manage it there
    if (isCurrent && _isAndroid && provider.isPlaySource && plan.price > 0) {
      return OutlinedButton(
        onPressed: _openPlaySubscriptions,
        child: const Text('Manage in Google Play'),
      );
    }

    if (isCurrent && !canRenewThis) {
      return OutlinedButton(onPressed: null, child: const Text('Current Plan'));
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
        backgroundColor: (isUpgrade || canRenewThis)
            ? Colors.amber[700]
            : Colors.grey[700],
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        unavailable ? 'Not available yet' : label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
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