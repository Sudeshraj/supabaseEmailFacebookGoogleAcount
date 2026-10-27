import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/providers/subscription_provider.dart';
import 'package:flutter_application_1/screens/subscription/screens/payment_history_screen.dart';
import 'package:flutter_application_1/screens/subscription/screens/plans_comparison_screen.dart';
import 'package:flutter_application_1/screens/subscription/services/play_billing_service.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionScreen extends StatefulWidget {
  final int salonId;
  final String ownerId;

  const SubscriptionScreen({
    super.key,
    required this.salonId,
    required this.ownerId,
  });

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().loadCapabilities(widget.salonId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
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
      body: Consumer<SubscriptionProvider>(
        builder: (context, provider, _) {
          if (!provider.isReady) {
            if (provider.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      provider.error ?? 'Could not load subscription details',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          provider.loadCapabilities(widget.salonId),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCurrentPlanCard(provider),
                const SizedBox(height: 24),
                _buildFeatureList(provider),
                const SizedBox(height: 24),
                _buildActionButtons(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentPlanCard(SubscriptionProvider provider) {
    final expiresAt = provider.expiresAt;
    final isPaid = provider.isPaidPlan;
    final days = provider.daysRemaining;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPaid ? Icons.workspace_premium : Icons.star_border,
                  color: isPaid ? Colors.amber : Colors.grey,
                  size: 32,
                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureList(SubscriptionProvider provider) {
    final features = [
      _Feature('Appointment History', provider.canViewHistory),
      _Feature('Offers Management', provider.canManageOffers),
      _Feature('Revenue Screen', provider.canViewRevenue),
      _Feature('Customers Screen', provider.canViewCustomers),
      _Feature('Reports', provider.canViewReports),
      _Feature('Analytics', provider.canViewAnalytics),
      _Feature('Data Export', provider.canExportData),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Features',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...features.map(
          (f) => ListTile(
            leading: Icon(
              f.enabled ? Icons.check_circle : Icons.cancel,
              color: f.enabled ? Colors.green : Colors.red,
            ),
            title: Text(f.name),
            dense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(SubscriptionProvider provider) {
    final isPaid = provider.isPaidPlan;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlansComparisonScreen(
                    salonId: widget.salonId,
                    ownerId: widget.ownerId,
                  ),
                ),
              ).then((_) => provider.refresh());
            },
            icon: const Icon(Icons.upgrade),
            label: Text(
              provider.canRenew
                  ? 'Renew / Change Plan'
                  : (isPaid ? 'Change Plan' : 'Upgrade Plan'),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),

        // Google Play subscriptions are cancelled in Google Play
        if (provider.isPlaySource) ...[
          const SizedBox(height: 12),
          if (PlayBillingService.isSupported)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final opened = await launchUrl(
                    PlayBillingService.manageUri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!opened && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open Google Play'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
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

        // PayHere (web) subscriptions: cancel here. Already cancelled -> nothing left.
        if (isPaid &&
            !provider.isPlaySource &&
            !provider.cancelAtPeriodEnd) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmCancel(provider),
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
    );
  }

  void _confirmCancel(SubscriptionProvider provider) {
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
              final result = await provider.cancelSubscription(
                ownerId: widget.ownerId,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message'] ?? 'Done'),
                    backgroundColor: result['success'] == true
                        ? null
                        : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _Feature {
  final String name;
  final bool enabled;
  _Feature(this.name, this.enabled);
}
