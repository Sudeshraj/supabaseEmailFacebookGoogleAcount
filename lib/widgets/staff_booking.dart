// lib/widgets/staff_booking.dart
//
// Shared by BookingFlowScreen and VIPBookingScreen when an OWNER or a BARBER
// books for a customer ("staff mode").
//
// The database decides who may book and what a package allows. It needs:
//   staff_search_customers(p_salon_id, p_query)  -> id, full_name, email
//   staff_create_booking(...)                    -> same JSON as customer booking
//   staff_create_vip_booking(...)                -> same JSON as VIP booking
//   Both create functions: p_customer_id (null for a walk-in), p_guest_name.
//   Package not enough: success=false, error_code='PLAN_REQUIRED',
//   is_owner (bool), plan (text).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/staff_tools.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST error code: the database function does not exist.
const String _kFunctionMissing = 'PGRST202';

/// The customer an owner / barber is booking for.
class StaffCustomer {
  /// null = walk-in / phone customer without an account
  final String? id;
  final String name;
  final String? email;

  const StaffCustomer.walkIn(this.name) : id = null, email = null;

  const StaffCustomer.account({
    required this.id,
    required this.name,
    this.email,
  });

  bool get hasAccount => id != null;

  String get description =>
      hasAccount ? (email ?? 'Account customer') : 'Walk-in (no account)';
}

/// Creates a booking for [customer]. [params] are the same parameters the
/// customer booking function gets; the customer related ones are replaced.
Future<Map<String, dynamic>> createStaffBooking({
  required bool vip,
  required StaffCustomer customer,
  required Map<String, dynamic> params,
}) async {
  final staffParams = Map<String, dynamic>.from(params)
    ..remove('p_child_name')
    ..remove('p_is_vip')
    ..remove('p_vip_booking_id');
  staffParams['p_customer_id'] = customer.id;
  staffParams['p_guest_name'] = customer.hasAccount ? null : customer.name;

  try {
    final result = await Supabase.instance.client.rpc(
      vip ? 'staff_create_vip_booking' : 'staff_create_booking',
      params: staffParams,
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'success': false, 'message': 'Booking failed'};
  } on PostgrestException catch (e) {
    if (e.code != _kFunctionMissing) rethrow;
    return {
      'success': false,
      'error_code': 'NOT_SET_UP',
      'message': 'Staff booking is not set up in the database yet',
    };
  }
}

/// The salon's package does not allow this booking.
/// Owner -> plans screen. Barber -> "ask the owner to upgrade".
Future<void> handleStaffPlanRequired(
  BuildContext context, {
  required Map<String, dynamic> result,
  required int salonId,
  required bool vip,
}) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;

  if (result['is_owner'] == true && userId != null) {
    await context.pushNamed(
      'subscription_plans',
      queryParameters: {
        'reason': vip ? 'vip_booking' : 'booking',
        'required': 'Silver',
      },
      extra: {'salonId': salonId, 'ownerId': userId},
    );
    return;
  }

  showStaffUpgradeDialog(
    context,
    feature: vip ? 'VIP booking' : 'Booking',
    plan: result['plan']?.toString() ?? '',
  );
}

/// "Who is this booking for?" for owners and barbers:
/// type a walk-in customer's name, or find a customer who has an account.
class StaffCustomerPicker extends StatefulWidget {
  final int? salonId;
  final ValueChanged<StaffCustomer?> onChanged;

  const StaffCustomerPicker({
    super.key,
    required this.salonId,
    required this.onChanged,
  });

  @override
  State<StaffCustomerPicker> createState() => _StaffCustomerPickerState();
}

class _StaffCustomerPickerState extends State<StaffCustomerPicker> {
  static const int _kMinSearchLength = 3;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _useAccount = false;
  StaffCustomer? _account;

  Timer? _debounce;
  int _requestId = 0;
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _searchError;
  List<StaffCustomer> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  StaffCustomer? get _walkIn {
    final name = _nameController.text.trim();
    return name.isEmpty ? null : StaffCustomer.walkIn(name);
  }

  void _setMode(bool useAccount) {
    setState(() => _useAccount = useAccount);
    widget.onChanged(useAccount ? _account : _walkIn);
  }

  void _selectAccount(StaffCustomer? customer) {
    FocusScope.of(context).unfocus();
    setState(() => _account = customer);
    widget.onChanged(customer);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final requestId = ++_requestId; // older answers are ignored

    setState(() {
      _results = [];
      _searchError = null;
      _hasSearched = false;
      _isSearching = query.length >= _kMinSearchLength;
    });
    if (query.length < _kMinSearchLength) return;

    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query, requestId),
    );
  }

  Future<void> _search(String query, int requestId) async {
    final salonId = widget.salonId;
    if (salonId == null) return;

    var results = <StaffCustomer>[];
    String? error;

    try {
      final rows = await Supabase.instance.client.rpc(
        'staff_search_customers',
        params: {'p_salon_id': salonId, 'p_query': query},
      );
      results = [
        for (final row in (rows as List? ?? []))
          StaffCustomer.account(
            id: row['id'].toString(),
            name: row['full_name']?.toString() ?? 'Customer',
            email: row['email']?.toString(),
          ),
      ];
    } on PostgrestException catch (e) {
      error = e.code == _kFunctionMissing
          ? 'Customer search is not set up in the database yet'
          : e.message;
    } catch (e) {
      error = 'Search failed. Check your connection.';
      debugPrint('⚠️ staff customer search failed: $e');
    }

    if (!mounted || requestId != _requestId) return;
    setState(() {
      _results = results;
      _searchError = error;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? Colors.white60 : Colors.grey[600];

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Who is this booking for?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.directions_walk, size: 18),
                  label: const Text('Walk-in / Phone'),
                  selected: !_useAccount,
                  onSelected: (_) => _setMode(false),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.person_search, size: 18),
                  label: const Text('Has an account'),
                  selected: _useAccount,
                  onSelected: (_) => _setMode(true),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_useAccount)
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: _inputDecoration(
                  label: 'Customer name',
                  icon: Icons.edit_outlined,
                ),
                onChanged: (_) {
                  setState(() {});
                  widget.onChanged(_walkIn);
                },
              )
            else if (_account != null)
              _customerTile(
                _account!,
                selected: true,
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Choose another customer',
                  onPressed: () => _selectAccount(null),
                ),
              )
            else ...[
              TextField(
                controller: _searchController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  label: 'Search by name or email',
                  icon: Icons.search,
                ),
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 8),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_searchError != null)
                Text(_searchError!, style: const TextStyle(color: Colors.red))
              else if (_results.isNotEmpty)
                for (final customer in _results)
                  _customerTile(customer, onTap: () => _selectAccount(customer))
              else
                Text(
                  _hasSearched
                      ? 'No customer found. Check the name, or type the full '
                            'email address.'
                      : 'Type at least $_kMinSearchLength letters.',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      counterText: '',
      prefixIcon: Icon(icon, color: AppTheme.primary, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }

  Widget _customerTile(
    StaffCustomer customer, {
    bool selected = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedTileColor: AppTheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: AppTheme.primary.withValues(alpha: selected ? 0.6 : 0.2),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: Icon(
            selected ? Icons.check : Icons.person,
            color: AppTheme.primary,
          ),
        ),
        title: Text(
          customer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          customer.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing,
      ),
    );
  }
}
