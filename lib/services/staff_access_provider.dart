// lib/services/staff_access_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One salon + what the logged-in user may do there.
class SalonAccess {
  final int salonId;
  final String salonName;
  final bool isOwner; // true = own salon, false = employee
  final String staffRole; // owner | barber | cashier | admin
  final String plan; // bronze | silver | gold | platinum
  final Set<String> permissions;

  const SalonAccess({
    required this.salonId,
    required this.salonName,
    required this.isOwner,
    required this.staffRole,
    required this.plan,
    required this.permissions,
  });

  bool can(String permission) => permissions.contains(permission);

  /// cashier / admin with at least one extra permission
  bool get hasStaffTools => !isOwner && permissions.isNotEmpty;

  factory SalonAccess.fromJson(Map<String, dynamic> j) => SalonAccess(
        salonId: (j['salon_id'] as num).toInt(),
        salonName: (j['salon_name'] ?? 'Salon').toString(),
        isOwner: j['access'] == 'owner',
        staffRole: (j['staff_role'] ?? 'barber').toString(),
        plan: (j['plan'] ?? 'bronze').toString(),
        permissions: ((j['permissions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
      );
}

/// Registered in main.dart (MultiProvider). It loads itself on sign-in and
/// clears itself on sign-out. The dashboards also call load() in
/// initState / didPopNext so a plan change or role change shows up at once.
class StaffAccessProvider extends ChangeNotifier {
  final _db = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  StaffAccessProvider() {
    _authSub = _db.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedOut:
          clear();
          break;
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
          if (data.session != null) load();
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  List<SalonAccess> _salons = [];
  bool _loading = false;
  bool _loaded = false;

  List<SalonAccess> get salons => _salons;
  bool get loading => _loading;
  bool get loaded => _loaded;

  /// salons where I am cashier/admin and actually have extra access
  List<SalonAccess> get staffSalons =>
      _salons.where((s) => s.hasStaffTools).toList();

  bool get hasStaffAccess => staffSalons.isNotEmpty;

  SalonAccess? forSalon(int salonId) {
    for (final s in _salons) {
      if (s.salonId == salonId) return s;
    }
    return null;
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await _db.rpc('get_my_staff_access');
      _salons = (res as List)
          .map((e) => SalonAccess.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _loaded = true;
    } catch (e) {
      debugPrint('❌ StaffAccessProvider.load: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _salons = [];
    _loaded = false;
    notifyListeners();
  }
}