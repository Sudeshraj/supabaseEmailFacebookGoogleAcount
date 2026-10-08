import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/payment_history_screen.dart';
import 'package:flutter_application_1/screens/subscription/plans_comparison_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/subscription_provider.dart';
// import '../../providers/subscription_provider.dart';
// import 'plans_comparison_screen.dart';
// import 'payment_history_screen.dart';

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
          if (provider.loading && provider.capabilities == null) {
            return const Center(child: CircularProgressIndicator());
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
    final expiresAt = provider.capabilities?['plan']?['expires_at'];
    final isPaid = provider.currentPlanName != 'bronze';

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
                Text(
                  '${provider.currentPlanDisplay} Plan',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isPaid && expiresAt != null) ...[
              Text(
                'Expires: ${_formatDate(expiresAt)}',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
            ],
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
        ...features.map((f) => ListTile(
          leading: Icon(
            f.enabled ? Icons.check_circle : Icons.cancel,
            color: f.enabled ? Colors.green : Colors.red,
          ),
          title: Text(f.name),
          dense: true,
        )),
      ],
    );
  }

  Widget _buildActionButtons(SubscriptionProvider provider) {
    final isPaid = provider.currentPlanName != 'bronze';

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
            label: Text(isPaid ? 'Change Plan' : 'Upgrade Plan'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (isPaid) ...[
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
                  SnackBar(content: Text(result['message'] ?? 'Done')),
                );
                provider.refresh();
              }
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _Feature {
  final String name;
  final bool enabled;
  _Feature(this.name, this.enabled);
}