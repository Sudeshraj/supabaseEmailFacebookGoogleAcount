import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../providers/subscription_provider.dart';

/// Where PayHere sends the user after the web *redirect* (hosted checkout)
/// payment. Everything it needs is in the URL, so a full page reload is fine:
///
///   /payment-return?payment=return|cancel&plan=silver&salon=1[&prev=<ms>]
///
/// The subscription is activated by the payhere-webhook function, so this
/// screen polls the capabilities until the new plan shows up.
class PaymentReturnScreen extends StatefulWidget {
  final int? salonId;
  final String? planName;
  final String status; // 'return' | 'cancel'
  final int? previousExpiryMs; // set for renewals

  /// Where "Done" goes. Make this your owner dashboard route.
  final String homePath;

  const PaymentReturnScreen({
    super.key,
    required this.salonId,
    required this.planName,
    required this.status,
    this.previousExpiryMs,
    this.homePath = '/',
  });

  @override
  State<PaymentReturnScreen> createState() => _PaymentReturnScreenState();
}

enum _ReturnState { checking, success, pending, cancelled, invalid }

class _PaymentReturnScreenState extends State<PaymentReturnScreen> {
  _ReturnState _state = _ReturnState.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (widget.status == 'cancel') {
      setState(() => _state = _ReturnState.cancelled);
      return;
    }
    final salonId = widget.salonId;
    final plan = widget.planName;
    if (salonId == null || plan == null) {
      setState(() => _state = _ReturnState.invalid);
      return;
    }

    setState(() => _state = _ReturnState.checking);

    final provider = context.read<SubscriptionProvider>();
    final previousExpiry = widget.previousExpiryMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.previousExpiryMs!);

    for (var i = 0; i < 20; i++) {
      // loadCapabilities (not refresh): after a page reload the provider has
      // no salon yet.
      await provider.loadCapabilities(salonId);
      if (!mounted) return;

      final planOk = provider.currentPlanName == plan;
      final expiryOk =
          previousExpiry == null ||
          (provider.expiresAt != null &&
              provider.expiresAt!.isAfter(previousExpiry));

      if (planOk && expiryOk) {
        setState(() => _state = _ReturnState.success);
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
    }

    setState(() => _state = _ReturnState.pending);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_state) {
      case _ReturnState.checking:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'Confirming your payment...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'This usually takes a few seconds.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        );

      case _ReturnState.success:
        return _result(
          icon: Icons.check_circle,
          color: Colors.green,
          title: 'Plan activated!',
          message:
              'Thank you. Your ${context.read<SubscriptionProvider>().currentPlanDisplay} plan is now active.',
          primary: 'Continue',
          onPrimary: _goHome,
        );

      case _ReturnState.pending:
        return _result(
          icon: Icons.hourglass_bottom,
          color: Colors.orange,
          title: 'Payment received',
          message:
              'Your payment is being processed. Your plan will be activated '
              'shortly — you will get a notification.',
          primary: 'Check again',
          onPrimary: _run,
          secondary: 'Go to dashboard',
          onSecondary: _goHome,
        );

      case _ReturnState.cancelled:
        return _result(
          icon: Icons.cancel_outlined,
          color: Colors.red,
          title: 'Payment cancelled',
          message: 'No money was taken. You can try again any time.',
          primary: 'Back',
          onPrimary: _goHome,
        );

      case _ReturnState.invalid:
        return _result(
          icon: Icons.error_outline,
          color: Colors.red,
          title: 'Something is missing',
          message:
              'We could not read the payment details. If you paid, your plan '
              'will still be activated automatically.',
          primary: 'Back',
          onPrimary: _goHome,
        );
    }
  }

  Widget _result({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String primary,
    required VoidCallback onPrimary,
    String? secondary,
    VoidCallback? onSecondary,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700]),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPrimary,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(primary),
          ),
        ),
        if (secondary != null && onSecondary != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onSecondary, child: Text(secondary)),
        ],
      ],
    );
  }

  void _goHome() => context.go(widget.homePath);
}
