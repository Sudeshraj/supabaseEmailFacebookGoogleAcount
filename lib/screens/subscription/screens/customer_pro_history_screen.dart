import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/subscription/services/customer_pro_service.dart';


/// Pro membership payment history of the logged-in customer.
/// (Owner subscription payments are a different thing and are not shown here.)
class CustomerProHistoryScreen extends StatefulWidget {
  const CustomerProHistoryScreen({super.key});

  @override
  State<CustomerProHistoryScreen> createState() =>
      _CustomerProHistoryScreenState();
}

class _CustomerProHistoryScreenState extends State<CustomerProHistoryScreen> {
  final CustomerProService _service = CustomerProService();

  List<CustomerProPayment> _payments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payments = await _service.getMyPayments();
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _date(DateTime? d) => d == null
      ? '-'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _amount(CustomerProPayment p) {
    if (p.amount == null) return 'Google Play';
    final code = p.currencyCode ?? 'LKR';
    final symbol = code == 'LKR' ? 'Rs.' : code;
    return '$symbol ${p.amount!.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pro Payment History')),
      body: _buildBody(),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_payments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'No Pro payments yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final hasPlay = _payments.any((p) => p.isGooglePlay);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length + (hasPlay ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _payments.length) {
            return Text(
              'Google Play payments are billed by Google. Your receipts are in '
              'Google Play > Payments & subscriptions.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            );
          }
          return _buildTile(_payments[index]);
        },
      ),
    );
  }

  Widget _buildTile(CustomerProPayment p) {
    final refunded = p.status == 'refunded';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.isGooglePlay ? Icons.android : Icons.credit_card,
                  color: Colors.amber[800],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.planName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  _amount(p),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Paid: ${_date(p.paidAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            Text(
              'Valid: ${_date(p.periodStart)} → ${_date(p.periodEnd)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.reference,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (refunded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Refunded',
                      style: TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}