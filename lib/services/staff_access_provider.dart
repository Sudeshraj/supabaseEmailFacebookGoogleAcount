// lib/services/staff_access_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Same as the staff_role_permissions seed. Only used when the server
/// (old SQL) does not send role_permissions yet.
Set<String> _defaultRolePerms(String role) {
  const cashier = {
    'all_appointments',
    'manage_appointments',
    'book',
    'vip_book',
    'view_customers',
  };
  const admin = {
    ...cashier,
    'manage_services',
    'manage_barbers',
    'manage_offers',
    'manage_holidays',
    'view_revenue',
    'view_reports',
    'view_analytics',
  };
  if (role == 'admin') return admin;
  if (role == 'cashier') return cashier;
  return const {};
}

/// One salon + what the logged-in user may do there.
class SalonAccess {
  final int salonId;
  final String salonName;
  final bool isOwner; // true = own salon, false = employee
  final String staffRole; // owner | barber | cashier | admin
  final String plan; // bronze | silver | gold | platinum
  final Set<String> permissions; // GRANTED right now (role + owner's plan)

  /// What the ROLE is entitled to whatever the plan is. A permission that is
  /// in rolePermissions but not in permissions is shown LOCKED (the owner
  /// must upgrade the package).
  final Set<String> rolePermissions;

  const SalonAccess({
    required this.salonId,
    required this.salonName,
    required this.isOwner,
    required this.staffRole,
    required this.plan,
    required this.permissions,
    required this.rolePermissions,
  });

  /// Used when the server access list could not be read but salon_barbers
  /// says I am cashier / admin: the section still shows (tiles locked, the
  /// database still checks everything when something is saved).
  factory SalonAccess.fallback({
    required int salonId,
    required String salonName,
    required String staffRole,
  }) => SalonAccess(
    salonId: salonId,
    salonName: salonName,
    isOwner: false,
    staffRole: staffRole,
    plan: '',
    permissions: const {},
    rolePermissions: _defaultRolePerms(staffRole),
  );

  bool can(String permission) => permissions.contains(permission);

  /// role has it, but the owner's current plan does not unlock it yet
  bool isLocked(String permission) =>
      rolePermissions.contains(permission) && !permissions.contains(permission);

  /// cashier / admin (even when everything is still locked). A plain
  /// barber has no role permissions, so sees nothing.
  bool get hasStaffTools => !isOwner && rolePermissions.isNotEmpty;

  factory SalonAccess.fromJson(Map<String, dynamic> j) {
    Set<String> toSet(dynamic v) =>
        ((v as List?) ?? const []).map((e) => e.toString()).toSet();
    final granted = toSet(j['permissions']);
    // old SQL (no role_permissions yet) -> fall back to granted ones
    final staffRole = (j['staff_role'] ?? 'barber').toString();
    // server list + granted + built-in defaults (so an empty / missing
    // staff_role_permissions seed can never hide the locked tiles)
    final isOwnerRow = j['access'] == 'owner';
    final role = {
      ...toSet(j['role_permissions']),
      ...granted,
      if (!isOwnerRow) ..._defaultRolePerms(staffRole),
    };
    return SalonAccess(
      salonId: (j['salon_id'] as num).toInt(),
      salonName: (j['salon_name'] ?? 'Salon').toString(),
      isOwner: j['access'] == 'owner',
      staffRole: (j['staff_role'] ?? 'barber').toString(),
      plan: (j['plan'] ?? 'bronze').toString(),
      permissions: granted,
      rolePermissions: role,
    );
  }
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
  String? _error;

  List<SalonAccess> get salons => _salons;

  /// why the last load() failed (null = it worked)
  String? get error => _error;
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
      for (final s in _salons) {
        debugPrint(
          '🔐 staff access: salon ${s.salonId} role=${s.staffRole} '
          'plan=${s.plan} granted=${s.permissions} role=${s.rolePermissions}',
        );
      }
      _loaded = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ StaffAccessProvider.load: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _salons = [];
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
