import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/providers/customer_pro_provider.dart';
import 'package:flutter_application_1/screens/subscription/services/customer_pro_service.dart';
import 'package:flutter_application_1/screens/subscription/services/payment_service.dart';
import 'package:flutter_application_1/screens/subscription/services/play_billing_service.dart';
import 'package:flutter_application_1/screens/subscription/widgets/payment_issue_banner.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'customer_pro_history_screen.dart';

// ============================================================
// CUSTOMER PRO SCREEN  (route: /customer/pro)
// ------------------------------------------------------------
//   • Monthly AND yearly plans (the list comes from the database)
//   • WEB      -> PayHere (price from the server). One-time payment: it
//                 EXTENDS the membership by one month / one year.
//   • ANDROID  -> Google Play Billing (required by Google Play policy).
//                 Monthly <-> yearly switching uses Google's replacement flow.
// The membership belongs to the CUSTOMER role only. It never changes the
// owner subscription of the same account, and vice versa.
// ============================================================
class CustomerProScreen extends StatefulWidget {
  /// 'return' / 'cancel' when PayHere sent the browser back here
  final String? returnStatus;

  const CustomerProScreen({super.key, this.returnStatus});

  @override
  State<CustomerProScreen> createState() => _CustomerProScreenState();
}

class _CustomerProScreenState extends State<CustomerProScreen> {
  final PaymentService _payment = PaymentService(); // web only

  bool _processing = false;
  bool _awaitingPlay = false;

  String? _selectedPlanName;
  Map<String, GooglePlayProductDetails> _products = {};
  StreamSubscription<PlayPurchaseEvent>? _playSub;
  Timer? _playTimeout;

  bool get _isAndroid => PlayBillingService.isSupported;

  @override
  void initState() {
    super.initState();

    if (_isAndroid) {
      _playSub = PlayBillingService.instance.events.listen(_onPlayEvent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<CustomerProProvider>();
      await provider.load();
      if (!mounted) return;

      if (_isAndroid) _loadProducts();

      if (widget.returnStatus == 'return') {
        _waitForPro();
      } else if (widget.returnStatus == 'cancel') {
        _showSnack('Payment cancelled');
      }
    });
  }

  @override
  void dispose() {
    _playSub?.cancel();
    _playTimeout?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final status = context.read<CustomerProProvider>().status;
    if (status == null || status.playProductIds.isEmpty) return;
    try {
      final products = await PlayBillingService.instance.loadProducts(
        status.playProductIds,
      );
      if (mounted) setState(() => _products = products);
    } catch (e) {
      debugPrint('❌ loading Pro products failed: $e');
    }
  }

  // ============================================================
  // PLAN HELPERS
  // ============================================================

  /// The plan chosen in the selector (default: yearly = best value)
  CustomerProPlanOption? _selected(CustomerProStatus status) {
    final chosen = status.planByName(_selectedPlanName);
    if (chosen != null) return chosen;
    for (final p in status.plans) {
      if (!p.isMonthly) return p;
    }
    return status.plans.isNotEmpty ? status.plans.first : null;
  }

  GooglePlayProductDetails? _productOf(CustomerProPlanOption plan) {
    final id = plan.playProductId;
    return id == null ? null : _products[id];
  }

  /// On Android the price shown MUST be the one Google Play will charge
  String _priceOf(CustomerProPlanOption plan) {
    if (_isAndroid) {
      final product = _productOf(plan);
      if (product != null) return product.price;
    }
    return plan.priceText;
  }

  // ============================================================
  // BUY / RENEW
  // ============================================================

  Future<void> _onBuyPressed(CustomerProPlanOption plan) async {
    if (_isAndroid) {
      await _buyOnAndroid(plan);
    } else if (kIsWeb) {
      await _buyOnWeb(plan);
    } else {
      _showSnack('Pro membership is not available on this platform yet');
    }
  }

  // ---------------- ANDROID (Google Play) ----------------

  Future<bool?> _confirmPlay({
    required String title,
    required String price,
    required String confirmLabel,
    required String info,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      price,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              info,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _buyOnAndroid(CustomerProPlanOption plan) async {
    final product = _productOf(plan);
    final user = Supabase.instance.client.auth.currentUser;
    if (product == null || user == null) {
      _showSnack('Pro is not available in Google Play yet', isError: true);
      return;
    }

    // subscription terms BEFORE the purchase (Google Play policy)
    final confirmed = await _confirmPlay(
      title: 'Subscribe to ${plan.displayName}?',
      price: '${product.price} / ${plan.periodWord}',
      confirmLabel: 'Subscribe',
      info:
          'Billed ${plan.periodAdjective} through Google Play. The subscription '
          'renews automatically until you cancel it in Google Play > Subscriptions.',
    );
    if (confirmed != true) return;

    setState(() {
      _processing = true;
      _awaitingPlay = true;
    });

    try {
      final started = await PlayBillingService.instance.buy(
        product: product,
        ownerId: user.id, // = the obfuscated account id the server checks
      );
      if (!started) {
        _awaitingPlay = false;
        if (mounted) setState(() => _processing = false);
        _showSnack('Could not start the purchase', isError: true);
        return;
      }
      _startPlayTimeout();
    } catch (e) {
      _awaitingPlay = false;
      if (mounted) setState(() => _processing = false);
      _showSnack('Error: $e', isError: true);
    }
  }

  /// Monthly <-> yearly while a Google Play Pro is active.
  ///   monthly -> yearly : now, the unused time is credited
  ///   yearly  -> monthly: at the end of the current year
  Future<void> _switchOnAndroid(
    CustomerProStatus status,
    CustomerProPlanOption target,
  ) async {
    final product = _productOf(target);
    final user = Supabase.instance.client.auth.currentUser;
    if (product == null || user == null) {
      _showSnack('This plan is not available in Google Play yet', isError: true);
      return;
    }

    final immediate = !target.isMonthly;

    final confirmed = await _confirmPlay(
      title: 'Switch to ${target.displayName}?',
      price: '${product.price} / ${target.periodWord}',
      confirmLabel: 'Switch',
      info: immediate
          ? 'The switch happens now. Google credits the unused time of your '
                'current plan against the new price.'
          : 'The switch happens at the end of your current billing period. '
                'You keep Pro until then.',
    );
    if (confirmed != true) return;

    setState(() => _processing = true);

    try {
      final old = await PlayBillingService.instance.findCurrentPurchase(
        status.playProductIds,
      );
      if (old == null) {
        if (mounted) setState(() => _processing = false);
        _showSnack(
          'Could not find your current Google Play subscription. Please try again.',
          isError: true,
        );
        return;
      }

      _awaitingPlay = immediate; // a deferred switch has no purchase event now

      final started = await PlayBillingService.instance.buy(
        product: product,
        ownerId: user.id,
        oldPurchase: old,
        replacementMode: immediate
            ? ReplacementMode.withTimeProration
            : ReplacementMode.deferred,
      );

      if (!started) {
        _awaitingPlay = false;
        if (mounted) setState(() => _processing = false);
        _showSnack('Could not start the change', isError: true);
        return;
      }

      if (!immediate) {
        if (mounted) setState(() => _processing = false);
        _showSnack(
          'If you confirmed, your plan changes to ${target.displayName} at the '
          'end of the current billing period.',
        );
        return;
      }

      _startPlayTimeout();
    } catch (e) {
      _awaitingPlay = false;
      if (mounted) setState(() => _processing = false);
      _showSnack('Error: $e', isError: true);
    }
  }

  void _startPlayTimeout() {
    _playTimeout?.cancel();
    _playTimeout = Timer(const Duration(seconds: 120), () {
      if (mounted && _processing) setState(() => _processing = false);
    });
  }

  void _onPlayEvent(PlayPurchaseEvent event) {
    if (!mounted || !_awaitingPlay) return;
    _playTimeout?.cancel();

    switch (event.type) {
      case PlayEventType.verified:
        _awaitingPlay = false;
        setState(() => _processing = false);
        context.read<CustomerProProvider>().refresh();
        _showSuccessDialog(
          'Your Pro membership is active. VIP booking and double points are on.',
        );
        break;
      case PlayEventType.pending:
        _awaitingPlay = false;
        setState(() => _processing = false);
        _showSnack('Your payment is pending. Pro activates when it completes.');
        break;
      case PlayEventType.canceled:
        _awaitingPlay = false;
        setState(() => _processing = false);
        _showSnack('Purchase cancelled');
        break;
      case PlayEventType.error:
        _awaitingPlay = false;
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

  // ---------------- WEB (PayHere) ----------------

  String _returnUrl(String status) => Uri.parse(Uri.base.origin)
      .replace(path: '/customer/pro', queryParameters: {'payment': status})
      .toString();

  Future<void> _buyOnWeb(CustomerProPlanOption plan) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final email = user.email ?? '';
    final name =
        user.userMetadata?['full_name'] as String? ?? email.split('@').first;
    final phone = user.userMetadata?['phone'] as String? ?? '0770000000';

    setState(() => _processing = true);
    try {
      final paymentId = await _payment.startCustomerProPayment(
        planName: plan.name,
        customerEmail: email,
        customerName: name,
        customerPhone: phone,
        returnUrl: _returnUrl('return'),
        cancelUrl: _returnUrl('cancel'),
      );

      if (!mounted) return;

      if (paymentId == null) {
        _showSnack('Payment cancelled or failed', isError: true);
        return;
      }

      // redirect fallback: this screen is opened again with ?payment=return
      if (paymentId == PaymentService.redirectSentinel) return;

      _showSnack('Payment received. Activating Pro...');
      await _waitForPro();
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// The PayHere webhook activates Pro on the server; wait until it did.
  Future<void> _waitForPro() async {
    final provider = context.read<CustomerProProvider>();
    final before = provider.status?.expiresAt;

    for (var i = 0; i < 15; i++) {
      await provider.load();
      if (!mounted) return;

      final status = provider.status;
      final extended =
          before == null ||
          (status?.expiresAt != null && status!.expiresAt!.isAfter(before));
      if (provider.isPro && extended) {
        _showSuccessDialog(
          'Payment successful. Your Pro membership is active!',
        );
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
    }
    _showSnack('Payment received. Pro will be activated shortly.');
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProProvider>();
    final status = provider.status;

    return Scaffold(
      appBar: AppBar(title: const Text('Pro Membership')),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(provider, status)),
          if (_processing)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(CustomerProProvider provider, CustomerProStatus? status) {
    if (status == null) {
      if (provider.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text(provider.error ?? 'Could not load your membership'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: provider.load,
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
        if (status.paymentIssue != null) ...[
          PaymentIssueBanner(issue: status.paymentIssue!),
          const SizedBox(height: 12),
        ],
        _buildHeader(status),
        const SizedBox(height: 16),
        if (_showsPlanSelector(status)) ...[
          _buildPlanSelector(status),
          const SizedBox(height: 16),
        ],
        _buildBenefits(),
        const SizedBox(height: 20),
        _buildAction(status),
        const SizedBox(height: 12),
        _buildHistoryButton(),
      ],
    );
  }

  /// Plan cards are shown when the customer can BUY something now:
  /// not Pro yet, or a PayHere Pro in its last 30 days (renew / extend).
  bool _showsPlanSelector(CustomerProStatus status) {
    if (status.plans.isEmpty) return false;
    if (!status.isPro) return true;
    return status.isPayHere && kIsWeb && (status.daysRemaining ?? 999) <= 30;
  }

  Widget _buildHeader(CustomerProStatus status) {
    final isPro = status.isPro;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isPro ? Colors.green : Colors.amber, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              const Icon(
                Icons.workspace_premium,
                size: 54,
                color: Colors.amber,
              ),
              const SizedBox(height: 8),
              Text(
                isPro ? "You're a Pro member" : 'Go Pro',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (isPro) ...[
                if (status.currentPlan != null)
                  Text(
                    status.currentPlan!.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber[800],
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  status.expiresAt == null
                      ? 'Active'
                      : 'Active until ${_formatDate(status.expiresAt!)} '
                            '(${status.daysRemaining} day(s) left)',
                  style: TextStyle(color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
                if (status.isGooglePlay)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      status.cancelAtPeriodEnd
                          ? 'Billed through Google Play (will not renew)'
                          : 'Billed through Google Play (renews automatically)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ] else
                Text(
                  'Choose the plan that suits you',
                  style: TextStyle(color: Colors.grey[600]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanSelector(CustomerProStatus status) {
    final selected = _selected(status);

    // IntrinsicHeight: ListView ඇතුළේ Row + stretch = infinite height error.
    // මේකෙන් cards දෙකම උසම card එකේ උසට සමාන වෙනවා.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < status.plans.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _buildPlanCard(
                status,
                status.plans[i],
                selected?.name == status.plans[i].name,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    CustomerProStatus status,
    CustomerProPlanOption plan,
    bool selected,
  ) {
    final saving = status.savingPercent(plan);
    final borderRadius = BorderRadius.circular(14);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? Colors.amber.withValues(alpha: 0.12) : null,
          borderRadius: borderRadius,
          border: Border.all(
            color: selected ? Colors.amber[700]! : Colors.grey.shade400,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: _processing
              ? null
              : () => setState(() => _selectedPlanName = plan.name),
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 20,
                  child: saving == null
                      ? null
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              'Save $saving%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  plan.isMonthly ? 'Monthly' : 'Yearly',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _priceOf(plan),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '/ ${plan.periodWord}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefits() {
    Widget row(IconData icon, String title, String subtitle) => ListTile(
      leading: Icon(icon, color: Colors.amber[800]),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      dense: true,
    );

    return Card(
      child: Column(
        children: [
          row(
            Icons.bolt,
            'VIP booking',
            'Book VIP slots with priority in the queue',
          ),
          const Divider(height: 1),
          row(
            Icons.stars,
            'Double loyalty points',
            'Earn 2x points on every completed booking',
          ),
          const Divider(height: 1),
          row(
            Icons.verified,
            'Pro badge',
            'A Pro Member badge on your profile',
          ),
        ],
      ),
    );
  }

  Widget _buildAction(CustomerProStatus status) {
    // ---------- Pro is active ----------
    if (status.isPro) {
      // bought with Google Play
      if (status.isGooglePlay) {
        if (!_isAndroid) {
          return _info(
            'Your Pro membership is billed through Google Play. Manage or '
            'cancel it in the Android app (Google Play > Subscriptions).',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _openPlaySubscriptions,
              icon: const Icon(Icons.manage_accounts),
              label: const Text('Manage in Google Play'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            for (final other in status.otherPlans) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: (_processing || _productOf(other) == null)
                    ? null
                    : () => _switchOnAndroid(status, other),
                icon: const Icon(Icons.swap_horiz),
                label: Text(
                  'Switch to ${other.isMonthly ? 'Monthly' : 'Yearly'} '
                  '(${_priceOf(other)} / ${other.periodWord})',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ],
        );
      }

      // bought with PayHere (web): one-time payment, extend by hand
      if (kIsWeb) {
        final plan = _selected(status);
        if (!_showsPlanSelector(status) || plan == null) {
          return _info('You can renew in the last 30 days of your membership.');
        }
        return ElevatedButton.icon(
          onPressed: _processing ? null : () => _onBuyPressed(plan),
          icon: const Icon(Icons.autorenew),
          label: Text('Renew: add 1 ${plan.periodWord} (${_priceOf(plan)})'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        );
      }

      return _info('Your Pro membership is active.');
    }

    // ---------- not Pro yet ----------
    final plan = _selected(status);
    if (plan == null) return _info('Pro is not available right now.');

    final unavailable = _isAndroid && _productOf(plan) == null;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_processing || unavailable)
                ? null
                : () => _onBuyPressed(plan),
            icon: const Icon(Icons.workspace_premium),
            label: Text(
              unavailable
                  ? 'Not available yet'
                  : 'Get Pro for ${_priceOf(plan)} / ${plan.periodWord}',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_isAndroid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Billed ${plan.periodAdjective} through Google Play. Auto-renews '
              'until cancelled. Cancel any time in Google Play > Subscriptions.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomerProHistoryScreen()),
        ),
        icon: const Icon(Icons.receipt_long),
        label: const Text('Payment History'),
      ),
    );
  }

  Widget _info(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12)),
  );

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _showSuccessDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Pro Active!'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
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
}