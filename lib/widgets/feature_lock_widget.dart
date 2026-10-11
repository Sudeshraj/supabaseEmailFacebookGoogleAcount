import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/subscription_provider.dart';

/// Wrap any screen that requires a specific feature
class FeatureLock extends StatelessWidget {
  final String featureName; // 'reports', 'analytics', 'revenue', ...
  final Widget child;
  final String? upgradeMessage;

  const FeatureLock({
    super.key,
    required this.featureName,
    required this.child,
    this.upgradeMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (context, provider, _) {
        // Plan not known yet: do NOT show "upgrade" to someone who may have paid.
        if (!provider.isReady) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _RetryPrompt(
            message: provider.error ?? 'Could not load your subscription.',
            onRetry: provider.refresh,
          );
        }

        if (_isEnabled(provider, featureName)) return child;

        return _UpgradePrompt(
          featureName: featureName,
          message: upgradeMessage ?? _defaultMessage(featureName),
        );
      },
    );
  }

  bool _isEnabled(SubscriptionProvider p, String feature) {
    switch (feature) {
      case 'reports':
        return p.canViewReports;
      case 'analytics':
        return p.canViewAnalytics;
      case 'revenue':
        return p.canViewRevenue;
      case 'customers':
        return p.canViewCustomers;
      case 'offers':
        return p.canManageOffers;
      case 'history':
        return p.canViewHistory;
      case 'export':
        return p.canExportData;
      default:
        return false;
    }
  }

  String _defaultMessage(String feature) {
    switch (feature) {
      case 'reports':
        return 'Reports are available in the Platinum plan.';
      case 'analytics':
        return 'Analytics are available in the Platinum plan.';
      case 'revenue':
        return 'Revenue screen is available in Silver and above.';
      case 'customers':
        return 'Customers screen is available in Silver and above.';
      case 'offers':
        return 'Offers management is available in Silver and above.';
      case 'history':
        return 'Full appointment history is available in Silver and above.';
      case 'export':
        return 'Data export is available in the Platinum plan.';
      default:
        return 'Upgrade your plan to access this feature.';
    }
  }
}

class _RetryPrompt extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _RetryPrompt({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[500]),
            const SizedBox(height: 16),
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
}

class _UpgradePrompt extends StatelessWidget {
  final String featureName;
  final String message;

  const _UpgradePrompt({required this.featureName, required this.message});

  // FeatureLock names -> the "reason" keys PlansComparisonScreen understands
  String get _reason {
    switch (featureName) {
      case 'customers':
        return 'customers_screen';
      case 'offers':
        return 'manage_offers';
      default:
        return featureName;
    }
  }

  String get _requiredPlan {
    switch (featureName) {
      case 'reports':
      case 'analytics':
      case 'export':
        return 'Platinum';
      default:
        return 'Silver';
    }
  }

  void _openPlans(BuildContext context) {
    final salonId = context.read<SubscriptionProvider>().currentSalonId;
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    if (salonId == null || ownerId == null) return;

    context.pushNamed(
      'subscription_plans',
      queryParameters: {'reason': _reason, 'required': _requiredPlan},
      extra: {'salonId': salonId, 'ownerId': ownerId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.amber[700]),
            const SizedBox(height: 24),
            Text(
              'Upgrade Required',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openPlans(context),
              icon: const Icon(Icons.upgrade),
              label: const Text('View Plans'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
