import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/subscription_provider.dart';

/// Wrap any screen that requires a specific feature
class FeatureLock extends StatelessWidget {
  final String featureName;      // 'reports', 'analytics', 'revenue', etc.
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
        final enabled = _isEnabled(provider, featureName);
        
        if (enabled) return child;
        
        return _UpgradePrompt(
          featureName: featureName,
          message: upgradeMessage ?? _defaultMessage(featureName),
        );
      },
    );
  }

  bool _isEnabled(SubscriptionProvider p, String feature) {
    switch (feature) {
      case 'reports':      return p.canViewReports;
      case 'analytics':    return p.canViewAnalytics;
      case 'revenue':      return p.canViewRevenue;
      case 'customers':    return p.canViewCustomers;
      case 'offers':       return p.canManageOffers;
      case 'history':      return p.canViewHistory;
      case 'export':       return p.canExportData;
      default:             return false;
    }
  }

  String _defaultMessage(String feature) {
    switch (feature) {
      case 'reports':   return 'Reports are available in the Platinum plan.';
      case 'analytics': return 'Analytics are available in the Platinum plan.';
      case 'revenue':   return 'Revenue screen is available in Silver and above.';
      case 'customers': return 'Customers screen is available in Silver and above.';
      case 'offers':    return 'Offers management is available in Silver and above.';
      case 'history':   return 'Full appointment history is available in Silver and above.';
      case 'export':    return 'Data export is available in the Platinum plan.';
      default:          return 'Upgrade your plan to access this feature.';
    }
  }
}

class _UpgradePrompt extends StatelessWidget {
  final String featureName;
  final String message;

  const _UpgradePrompt({
    required this.featureName,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.amber[700],
            ),
            const SizedBox(height: 24),
            Text(
              'Upgrade Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to subscription screen
                // Navigator.push(context, MaterialPageRoute(...));
              },
              icon: const Icon(Icons.upgrade),
              label: const Text('View Plans'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}