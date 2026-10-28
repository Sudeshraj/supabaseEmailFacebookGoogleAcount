import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/play_billing_service.dart';

/// Shown when Google Play could not charge the customer's payment method.
///   issue = 'grace'   -> access is still on, but the card failed
///   issue = 'on_hold' -> access is OFF until the payment method is fixed
/// The value comes from the server (`payment_issue`).
class PaymentIssueBanner extends StatelessWidget {
  final String issue;

  const PaymentIssueBanner({super.key, required this.issue});

  bool get _onHold => issue == 'on_hold';

  Future<void> _openGooglePlay(BuildContext context) async {
    final opened = await launchUrl(
      PlayBillingService.manageUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Play'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _onHold ? Colors.red : Colors.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _onHold ? 'Subscription on hold' : 'Payment problem',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _onHold
                ? 'Google Play could not charge your payment method, so your '
                      'plan is on hold. Update your payment method in Google Play '
                      'to restore it.'
                : 'Google Play could not charge your payment method. You still '
                      'have access for now, but please update your payment '
                      'method in Google Play to keep your plan.',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          if (PlayBillingService.isSupported)
            OutlinedButton.icon(
              onPressed: () => _openGooglePlay(context),
              icon: const Icon(Icons.payment),
              label: const Text('Fix in Google Play'),
              style: OutlinedButton.styleFrom(foregroundColor: color),
            )
          else
            const Text(
              'Open the Android app > Google Play > Subscriptions to fix it.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}