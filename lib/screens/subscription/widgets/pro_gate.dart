import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/customer_pro_provider.dart';

/// Call this before a Pro-only customer action (e.g. VIP booking).
///
///   if (!await ensureCustomerPro(context, confirm: false)) return;
///
/// • Pro member      -> returns true straight away.
/// • Free customer   -> opens the Pro upgrade screen (/customer/pro).
///                      [confirm] = true asks "Pro members only" first.
///                      Returns true only if they became Pro, so the VIP
///                      booking continues automatically after upgrading.
///
/// This is the friendly part. The database refuses a VIP booking from a
/// non-Pro customer anyway.
Future<bool> ensureCustomerPro(
  BuildContext context, {
  String feature = 'VIP booking',
  bool confirm = true,
}) async {
  final provider = context.read<CustomerProProvider>();
  if (!provider.isReady) await provider.load();
  if (provider.isPro) return true;
  if (!context.mounted) return false;

  if (confirm) {
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.workspace_premium, color: Colors.amber, size: 44),
        title: const Text('Pro members only'),
        content: Text(
          '$feature is a Pro feature. Upgrade to Pro for VIP booking, '
          'double loyalty points and a Pro badge.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('See Pro'),
          ),
        ],
      ),
    );
    if (upgrade != true || !context.mounted) return false;
  }

  await context.push('/customer/pro');
  await provider.refresh();
  return provider.isPro;
}