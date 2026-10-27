import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/providers/customer_pro_provider.dart';
import 'package:flutter_application_1/screens/subscription/services/customer_pro_service.dart';
import 'package:flutter_application_1/screens/subscription/services/payment_service.dart';
import 'package:flutter_application_1/screens/subscription/services/play_billing_service.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// CUSTOMER PRO SCREEN  (route: /customer/pro)
// ------------------------------------------------------------
//   • WEB      -> PayHere (price from the server)
//   • ANDROID  -> Google Play Billing (required by Google Play policy)
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

  GooglePlayProductDetails? _product;
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

      if (_isAndroid) _loadProduct();

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

  Future<void> _loadProduct() async {
    final productId = context.read<CustomerProProvider>().status?.playProductId;
    if (productId == null) return;
    try {
      final products = await PlayBillingService.instance.loadProducts({
        productId,
      });
      if (mounted) setState(() => _product = products[productId]);
    } catch (e) {
      debugPrint('❌ loading Pro product failed: $e');
    }
  }

  // ============================================================
  // BUY
  // ============================================================

  Future<void> _onBuyPressed() async {
    if (_isAndroid) {
      await _buyOnAndroid();
    } else if (kIsWeb) {
      await _buyOnWeb();
    } else {
      _showSnack('Pro membership is not available on this platform yet');
    }
  }

  // ---------------- ANDROID (Google Play) ----------------

  Future<void> _buyOnAndroid() async {
    final product = _product;
    final user = Supabase.instance.client.auth.currentUser;
    if (product == null || user == null) {
      _showSnack('Pro is not available in Google Play yet', isError: true);
      return;
    }

    // subscription terms BEFORE the purchase (Google Play policy)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscribe to Pro?'),
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
                      '${product.price} / year',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Billed yearly through Google Play. The subscription renews '
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
            child: const Text('Subscribe'),
          ),
        ],
      ),
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

      // safety net in case no event ever arrives
      _playTimeout?.cancel();
      _playTimeout = Timer(const Duration(seconds: 120), () {
        if (mounted && _processing) setState(() => _processing = false);
      });
    } catch (e) {
      _awaitingPlay = false;
      if (mounted) setState(() => _processing = false);
      _showSnack('Error: $e', isError: true);
    }
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
          'Welcome to Pro! VIP booking and double points are on.',
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

  Future<void> _buyOnWeb() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final email = user.email ?? '';
    final name =
        user.userMetadata?['full_name'] as String? ?? email.split('@').first;
    final phone = user.userMetadata?['phone'] as String? ?? '0770000000';

    setState(() => _processing = true);
    try {
      final paymentId = await _payment.startCustomerProPayment(
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
    for (var i = 0; i < 15; i++) {
      await provider.load();
      if (!mounted) return;
      if (provider.isPro) {
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
          _buildBody(provider, status),
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
        _buildHeader(status),
        const SizedBox(height: 16),
        _buildBenefits(),
        const SizedBox(height: 20),
        _buildAction(status),
      ],
    );
  }

  String _priceText(CustomerProStatus status) {
    if (_isAndroid && _product != null) return _product!.price;
    final symbol = status.currencyCode == 'LKR' ? 'Rs.' : status.currencyCode;
    return '$symbol ${status.price.toStringAsFixed(0)}';
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
        child: Column(
          children: [
            const Icon(Icons.workspace_premium, size: 54, color: Colors.amber),
            const SizedBox(height: 8),
            Text(
              isPro ? "You're a Pro member" : 'Go Pro',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isPro) ...[
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
            ] else ...[
              Text(
                '${_priceText(status)} / year',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'One membership for all salons',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ],
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
    // ---- Pro is active ----
    if (status.isPro) {
      // bought with Google Play
      if (status.isGooglePlay) {
        if (_isAndroid) {
          return OutlinedButton.icon(
            onPressed: _openPlaySubscriptions,
            icon: const Icon(Icons.manage_accounts),
            label: const Text('Manage in Google Play'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          );
        }
        return _info(
          'Your Pro membership is billed through Google Play. Manage or cancel '
          'it in the Android app (Google Play > Subscriptions).',
        );
      }

      // bought with PayHere (web): one-time yearly payment, renew by hand
      if (kIsWeb) {
        final canRenew = (status.daysRemaining ?? 999) <= 30;
        if (!canRenew) {
          return _info('You can renew in the last 30 days of your membership.');
        }
        return ElevatedButton.icon(
          onPressed: _processing ? null : _onBuyPressed,
          icon: const Icon(Icons.autorenew),
          label: Text('Renew for 1 year (${_priceText(status)})'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        );
      }

      return _info('Your Pro membership is active.');
    }

    // ---- not Pro yet ----
    final unavailable = _isAndroid && _product == null;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_processing || unavailable) ? null : _onBuyPressed,
            icon: const Icon(Icons.workspace_premium),
            label: Text(
              unavailable
                  ? 'Not available yet'
                  : 'Get Pro for ${_priceText(status)} / year',
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
              'Billed yearly through Google Play. Auto-renews until cancelled. '
              'Cancel any time in Google Play > Subscriptions.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
      ],
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
