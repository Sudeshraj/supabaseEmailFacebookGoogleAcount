import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/utils/app_version.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SideMenu extends StatefulWidget {
  final String userRole;
  final String userName;
  final String? userEmail;
  final String? profileImageUrl;
  final String? selectedSalonId;
  final VoidCallback? onMenuItemSelected;
  // ✅ NEW: lets the parent (e.g. OwnerDashboard) know exactly which salon
  // was picked from the side menu, so it can update its own selected-salon
  // state and reload the correct data. Without this the menu only knew
  // about its own local selection and the dashboard never found out.
  final void Function(String salonId)? onSalonChanged;

  const SideMenu({
    super.key,
    required this.userRole,
    required this.userName,
    this.userEmail,
    this.profileImageUrl,
    this.selectedSalonId,
    this.onMenuItemSelected,
    this.onSalonChanged,
  });

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  bool _showProfileSwitcher = false;
  List<Map<String, dynamic>> _availableProfiles = [];
  List<String> _allUserRoles = [];
  bool _isLoading = false;

  // ✅ Notification counts
  int _unreadNotificationCount = 0;
  int _pendingBookingsCount = 0;

  // ✅ Owner salons
  List<Map<String, dynamic>> _ownerSalons = [];
  
  // ✅ Barber salons (multiple salon support for barber)
  List<Map<String, dynamic>> _barberSalons = [];
  
  String? _selectedSalonId;
  String? _selectedSalonName;

  // ✅ Android 16: Screen size tracking
  bool _isTablet = false;
  bool _isLargeScreen = false;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _selectedSalonId = widget.selectedSalonId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkScreenSize();
        _loadUserRolesFromDatabase();
        _loadNotificationCounts();
        if (widget.userRole == 'owner') {
          _loadOwnerSalons();
        } else if (widget.userRole == 'barber') {
          _loadBarberSalons();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  @override
  void didUpdateWidget(SideMenu oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedSalonId != oldWidget.selectedSalonId) {
      setState(() {
        _selectedSalonId = widget.selectedSalonId;
      });
      _loadNotificationCounts();
    }

    if (widget.userRole != oldWidget.userRole) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadUserRolesFromDatabase();
          _loadNotificationCounts();
          if (widget.userRole == 'owner') {
            _loadOwnerSalons();
          } else if (widget.userRole == 'barber') {
            _loadBarberSalons();
          }
        }
      });
    }
  }

  // ✅ Android 16: Check screen size
  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isLarge = size.width > 800 || size.height > 800;

    if (_isTablet != isTablet || _isLargeScreen != isLarge) {
      setState(() {
        _isTablet = isTablet;
        _isLargeScreen = isLarge;
      });
    }
  }

  // ============================================================
  // 🔥 LOAD BARBER SALONS (Multiple salons support)
  // ============================================================
  Future<void> _loadBarberSalons() async {
    if (widget.userRole != 'barber') return;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      debugPrint('📋 Loading barber salons for user: ${currentUser.id}');

      final response = await supabase
          .from('salon_barbers')
          .select('''
            id,
            salon_id,
            status,
            salons!inner (
              id,
              name,
              logo_url,
              address,
              open_time,
              close_time,
              is_active
            )
          ''')
          .eq('barber_id', currentUser.id)
          .eq('status', 'active');

      debugPrint('📊 Found ${response.length} assigned salons for barber');

      if (response.isNotEmpty) {
        final List<Map<String, dynamic>> salons = [];
        for (var item in response) {
          final salon = item['salons'] as Map?;
          if (salon != null && salon['is_active'] == true) {
            salons.add({
              'id': salon['id'].toString(),
              'name': salon['name']?.toString() ?? 'Unknown Salon',
              'logo_url': salon['logo_url'],
              'address': salon['address'],
              'open_time': salon['open_time'],
              'close_time': salon['close_time'],
            });
          }
        }

        setState(() {
          _barberSalons = salons;
        });

        // Set selected salon
        if (_selectedSalonId == null && salons.isNotEmpty) {
          _selectedSalonId = salons[0]['id'];
          _selectedSalonName = salons[0]['name'];
        } else if (salons.isNotEmpty) {
          final selected = salons.firstWhere(
            (s) => s['id'] == _selectedSalonId,
            orElse: () => {},
          );
          if (selected.isNotEmpty) {
            _selectedSalonName = selected['name'];
          } else {
            _selectedSalonId = salons[0]['id'];
            _selectedSalonName = salons[0]['name'];
          }
        }

        if (_selectedSalonId != null) {
          await SessionManager.saveSalonId(_selectedSalonId!);
        }
        if (_selectedSalonName != null) {
          await SessionManager.saveSalonName(_selectedSalonName!);
        }

        debugPrint('✅ Selected barber salon: $_selectedSalonName (ID: $_selectedSalonId)');
        debugPrint('✅ Total barber salons: ${_barberSalons.length}');
      } else {
        setState(() {
          _barberSalons = [];
          _selectedSalonId = null;
          _selectedSalonName = null;
        });
        debugPrint('⚠️ No active salons assigned to this barber');
      }
    } catch (e) {
      debugPrint('❌ Error loading barber salons: $e');
      setState(() {
        _barberSalons = [];
      });
    }
  }

  // ============================================================
  // 🔥 LOAD OWNER SALONS
  // ============================================================
  Future<void> _loadOwnerSalons() async {
    if (widget.userRole != 'owner') return;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase
          .from('salons')
          .select('id, name, logo_url, address')
          .eq('owner_id', currentUser.id)
          .eq('is_active', true)
          .order('name');

      if (response.isNotEmpty) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
        });

        if (widget.selectedSalonId != null &&
            _ownerSalons.any(
              (s) => s['id'].toString() == widget.selectedSalonId,
            )) {
          _selectedSalonId = widget.selectedSalonId;
          _selectedSalonName = _ownerSalons
              .firstWhere(
                (s) => s['id'].toString() == widget.selectedSalonId,
              )['name']
              ?.toString();
        } else {
          final savedId = await SessionManager.getSalonId();
          if (savedId != null &&
              _ownerSalons.any((s) => s['id'].toString() == savedId)) {
            _selectedSalonId = savedId;
            _selectedSalonName = _ownerSalons
                .firstWhere((s) => s['id'].toString() == savedId)['name']
                ?.toString();
          } else {
            _selectedSalonId = _ownerSalons.first['id'].toString();
            _selectedSalonName = _ownerSalons.first['name']?.toString();
          }
        }

        if (_selectedSalonId != null) {
          await SessionManager.saveSalonId(_selectedSalonId!);
        }
        if (_selectedSalonName != null) {
          await SessionManager.saveSalonName(_selectedSalonName!);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading owner salons: $e');
    }
  }

  // ============================================================
  // 🔥 ON SALON CHANGED - Owner
  // ============================================================
  void _onOwnerSalonChanged(String? newSalonId) async {
    if (widget.userRole != 'owner') return;
    if (newSalonId == null || newSalonId == _selectedSalonId) return;

    final selectedSalon = _ownerSalons.firstWhere(
      (s) => s['id'].toString() == newSalonId,
    );

    setState(() {
      _selectedSalonId = newSalonId;
      _selectedSalonName = selectedSalon['name']?.toString();
    });

    await SessionManager.saveSalonId(_selectedSalonId!);
    if (_selectedSalonName != null) {
      await SessionManager.saveSalonName(_selectedSalonName!);
    }

    await _loadNotificationCounts();

    if (widget.onSalonChanged != null) {
      widget.onSalonChanged!(newSalonId);
    } else if (widget.onMenuItemSelected != null) {
      widget.onMenuItemSelected!();
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ============================================================
  // 🔥 ON SALON CHANGED - Barber
  // ============================================================
  void _onBarberSalonChanged(String? newSalonId) async {
    if (widget.userRole != 'barber') return;
    if (newSalonId == null || newSalonId == _selectedSalonId) return;

    final selectedSalon = _barberSalons.firstWhere(
      (s) => s['id'] == newSalonId,
      orElse: () => {},
    );

    if (selectedSalon.isEmpty) return;

    setState(() {
      _selectedSalonId = newSalonId;
      _selectedSalonName = selectedSalon['name'];
    });

    await SessionManager.saveSalonId(_selectedSalonId!);
    if (_selectedSalonName != null) {
      await SessionManager.saveSalonName(_selectedSalonName!);
    }

    await _loadNotificationCounts();

    // Notify parent dashboard
    if (widget.onSalonChanged != null) {
      widget.onSalonChanged!(newSalonId);
    } else if (widget.onMenuItemSelected != null) {
      widget.onMenuItemSelected!();
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ============================================================
  // 🔥 LOAD NOTIFICATION COUNTS
  // ============================================================
  Future<void> _loadNotificationCounts() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final notificationResponse = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', currentUser.id)
          .eq('is_read', false);

      final unreadCount = notificationResponse.length;
      int pendingBookings = 0;

      if (widget.userRole == 'customer') {
        final bookingsResponse = await supabase
            .from('appointments')
            .select('id')
            .eq('customer_id', currentUser.id)
            .inFilter('status', ['pending', 'confirmed']);
        pendingBookings = bookingsResponse.length;
      } else if (widget.userRole == 'barber') {
        final bookingsResponse = await supabase
            .from('appointments')
            .select('id')
            .eq('barber_id', currentUser.id)
            .inFilter('status', ['pending', 'confirmed']);
        pendingBookings = bookingsResponse.length;
      } else if (widget.userRole == 'owner') {
        if (_selectedSalonId != null) {
          final bookingsResponse = await supabase
              .from('appointments')
              .select('id')
              .eq('salon_id', int.parse(_selectedSalonId!))
              .inFilter('status', ['pending', 'confirmed']);
          pendingBookings = bookingsResponse.length;
        } else {
          final salonsResponse = await supabase
              .from('salons')
              .select('id')
              .eq('owner_id', currentUser.id);

          final List<int> salonIds = salonsResponse
              .map<int>((s) => s['id'] as int)
              .toList();

          if (salonIds.isNotEmpty) {
            final bookingsResponse = await supabase
                .from('appointments')
                .select('id')
                .inFilter(
                  'salon_id',
                  salonIds.map((e) => e.toString()).toList(),
                )
                .inFilter('status', ['pending', 'confirmed']);
            pendingBookings = bookingsResponse.length;
          }
        }
      }

      if (mounted) {
        setState(() {
          _unreadNotificationCount = unreadCount;
          _pendingBookingsCount = pendingBookings;
        });
      }

      debugPrint(
        '📬 Unread: $_unreadNotificationCount, Pending: $_pendingBookingsCount',
      );
    } catch (e) {
      debugPrint('❌ Error loading notification counts: $e');
    }
  }

  // ============================================================
  // 🔥 LOAD USER ROLES FROM DATABASE
  // ============================================================
  Future<void> _loadUserRolesFromDatabase() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('📋 Loading roles for user: ${currentUser.id}');

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (
              id,
              name,
              description
            ),
            status
          ''')
          .eq('user_id', currentUser.id)
          .eq('status', 'active');

      final List<String> roleNames = [];
      final List<Map<String, dynamic>> roleData = [];

      for (var roleEntry in userRolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          final roleName = role['name'].toString();
          roleNames.add(roleName);
          roleData.add({
            'role_id': roleEntry['role_id'],
            'name': roleName,
            'status': roleEntry['status'] ?? 'active',
          });
        }
      }

      _allUserRoles = roleNames.toSet().toList();
      debugPrint('📋 Active user roles: $_allUserRoles');

      final profileResponse = await supabase
          .from('profiles')
          .select('''
            id,
            full_name,
            avatar_url,
            email,
            extra_data,
            is_active,
            is_blocked
          ''')
          .eq('id', currentUser.id)
          .maybeSingle();

      final List<Map<String, dynamic>> profiles = [];

      if (profileResponse != null) {
        final extraData =
            profileResponse['extra_data'] as Map<String, dynamic>? ?? {};

        for (var roleName in _allUserRoles) {
          final roleKey = 'profile_$roleName';
          final roleStatus =
              extraData[roleKey]?['status'] as String? ?? 'active';

          String displayName = profileResponse['full_name'] ?? widget.userName;
          if (displayName.isEmpty) {
            displayName = extraData['full_name'] ?? widget.userName;
          }

          final isCurrent = roleName == widget.userRole;

          profiles.add({
            'id': profileResponse['id'],
            'email':
                profileResponse['email'] ??
                widget.userEmail ??
                currentUser.email,
            'role': roleName,
            'role_id': roleData.firstWhere(
              (r) => r['name'] == roleName,
              orElse: () => {'role_id': 0},
            )['role_id'],
            'name': displayName,
            'photo': profileResponse['avatar_url'] ?? widget.profileImageUrl,
            'is_current': isCurrent,
            'is_active': roleStatus == 'active',
            'is_blocked': profileResponse['is_blocked'] ?? false,
            'status': roleStatus,
            'extra_data': extraData,
          });
        }
      }

      if (mounted) {
        setState(() {
          _availableProfiles = profiles;
        });

        await SessionManager.saveUserRoles(
          email: widget.userEmail ?? currentUser.email ?? '',
          roles: _allUserRoles,
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading user roles: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🔥 SWITCH PROFILE
  // ============================================================
  Future<void> _switchProfile(Map<String, dynamic> profile) async {
    if (!mounted) return;

    if (profile['is_current'] == true) {
      setState(() => _showProfileSwitcher = false);
      return;
    }

    if (profile['is_active'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This profile is inactive'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (profile['is_blocked'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This profile is blocked'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔄 Switching to profile: ${profile['role']}');

      final currentUser = supabase.auth.currentUser;
      final email = widget.userEmail ?? currentUser?.email;

      if (email == null) throw Exception('No email found');

      await SessionManager.updateUserRole(profile['role']);
      debugPrint('✅ Role saved to SessionManager: ${profile['role']}');

      if (currentUser != null) {
        final currentMetadata = currentUser.userMetadata ?? {};
        await supabase.auth.updateUser(
          UserAttributes(
            data: {...currentMetadata, 'current_role': profile['role']},
          ),
        );
        debugPrint('✅ User metadata updated with role: ${profile['role']}');
      }

      if (!mounted) return;

      Navigator.pop(context);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        try {
          switch (profile['role']) {
            case 'owner':
              debugPrint('👑 Navigating to owner dashboard');
              context.go('/owner');
              break;
            case 'barber':
              debugPrint('💇 Navigating to barber dashboard');
              context.go('/barber');
              break;
            case 'customer':
              debugPrint('👤 Navigating to customer dashboard');
              context.go('/customer');
              break;
            default:
              context.go('/');
          }
        } catch (e) {
          debugPrint('❌ Navigation error: $e');
        }
      });

      appState
          .refreshState()
          .then((_) {
            debugPrint('✅ App state refreshed in background');
          })
          .catchError((e) {
            debugPrint('❌ Background refresh error: $e');
          });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    } catch (e) {
      debugPrint('❌ Error switching profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🔥 CREATE NEW PROFILE
  // ============================================================
  Future<void> _createNewProfile() async {
    if (!mounted) return;

    setState(() => _showProfileSwitcher = false);

    final allRoles = ['owner', 'barber', 'customer'];
    final availableRoles = allRoles
        .where((role) => !_allUserRoles.contains(role))
        .toList();

    if (availableRoles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have all profile types'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final selectedRole = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor:
            Theme.of(context).dialogTheme.backgroundColor ?? Colors.white,
        title: const Text('Create New Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('What type of profile would you like to create?'),
              const SizedBox(height: 20),
              ...availableRoles.map(
                (role) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildProfileTypeOption(
                    icon: _getRoleIcon(role),
                    color: _getRoleColor(role),
                    title: _getRoleDisplayName(role),
                    description: _getRoleDescription(role),
                    role: role,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedRole == null || !mounted) return;

    debugPrint('🔄 Creating new profile for role: $selectedRole');

    await _createProfileDirectly(selectedRole);
  }

  // ============================================================
  // 🔥 CREATE PROFILE DIRECTLY
  // ============================================================
  Future<void> _createProfileDirectly(String role) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      final email = currentUser.email;
      if (email == null) throw Exception('No email found');

      debugPrint('📝 Creating new $role profile for user: ${currentUser.id}');

      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', role)
          .single();

      final roleId = roleResponse['id'];

      final existingProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', currentUser.id)
          .maybeSingle();

      Map<String, dynamic> extraData = {};
      String fullName = widget.userName;

      if (existingProfile != null) {
        extraData =
            existingProfile['extra_data'] as Map<String, dynamic>? ?? {};
        fullName = existingProfile['full_name'] ?? widget.userName;
        debugPrint('📋 Existing profile found, updating extra_data');
      } else {
        debugPrint('📋 No existing profile, creating new');
      }

      final roleKey = 'profile_$role';
      extraData[roleKey] = {
        'role': role,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      };

      if (!extraData.containsKey('full_name')) {
        extraData['full_name'] = fullName;
      }

      debugPrint('📝 Extra data updated: ${extraData.keys}');

      if (existingProfile == null) {
        await supabase.from('profiles').insert({
          'id': currentUser.id,
          'email': email,
          'full_name': fullName,
          'avatar_url':
              currentUser.userMetadata?['avatar_url'] ??
              currentUser.userMetadata?['picture'],
          'extra_data': extraData,
          'is_active': true,
          'is_blocked': false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ New profile created');
      } else {
        await supabase
            .from('profiles')
            .update({
              'full_name': fullName,
              'extra_data': extraData,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', currentUser.id);
        debugPrint('✅ Profile updated with new role');
      }

      final existingRole = await supabase
          .from('user_roles')
          .select()
          .eq('user_id', currentUser.id)
          .eq('role_id', roleId)
          .maybeSingle();

      if (existingRole == null) {
        await supabase.from('user_roles').insert({
          'user_id': currentUser.id,
          'role_id': roleId,
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Role assigned: $role (status: active)');
      } else {
        if (existingRole['status'] != 'active') {
          await supabase
              .from('user_roles')
              .update({
                'status': 'active',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('user_id', currentUser.id)
              .eq('role_id', roleId);
          debugPrint('✅ Role reactivated: $role');
        } else {
          debugPrint('⚠️ Role already exists: $role');
        }
      }

      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (name),
            status
          ''')
          .eq('user_id', currentUser.id)
          .eq('status', 'active');

      final List<String> userRoles = userRolesResponse
          .map((r) => r['roles']['name'] as String)
          .toList();

      debugPrint('📝 Active user roles after update: $userRoles');

      final currentMetadata = currentUser.userMetadata ?? {};
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            ...currentMetadata,
            'roles': userRoles,
            'current_role': role,
            'profile_updated_at': DateTime.now().toIso8601String(),
          },
        ),
      );
      debugPrint('✅ User metadata updated');

      debugPrint('📱 Saving to SessionManager');

      final photoUrl =
          currentUser.userMetadata?['avatar_url'] ??
          currentUser.userMetadata?['picture'];

      await SessionManager.saveUserProfile(
        email: email,
        userId: currentUser.id,
        name: fullName,
        photo: photoUrl,
        roles: userRoles,
        rememberMe: true,
        provider: await _getUserProvider(currentUser, photoUrl),
      );

      await SessionManager.saveCurrentRole(role);

      await _loadUserRolesFromDatabase();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${_getRoleDisplayName(role)} profile created successfully!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        debugPrint('🎯 Navigating directly to dashboard: $role');

        try {
          switch (role) {
            case 'owner':
              context.go('/owner');
              break;
            case 'barber':
              context.go('/barber');
              break;
            case 'customer':
              context.go('/customer');
              break;
            default:
              context.go('/');
          }
        } catch (e) {
          debugPrint('❌ Navigation error: $e');
        }
      });

      appState
          .refreshState()
          .then((_) {
            debugPrint('✅ App state refreshed in background');
          })
          .catchError((e) {
            debugPrint('❌ Background refresh error: $e');
          });

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    } catch (e) {
      debugPrint('❌ Error creating profile directly: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🔥 HELPER: Get user provider
  // ============================================================
  Future<String> _getUserProvider(User user, String? photoUrl) async {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.contains('googleusercontent.com')) return 'google';
      if (photoUrl.contains('fbcdn.net') ||
          photoUrl.contains('facebook.com') ||
          photoUrl.contains('platform-lookaside.fbsbx.com')) {
        return 'facebook';
      }
      if (photoUrl.contains('apple.com')) return 'apple';
    }

    final provider = user.appMetadata['provider'];
    if (provider != null) return provider.toString();

    return 'email';
  }

  // ============================================================
  // 🔥 HELPER METHODS
  // ============================================================
  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.work_outline;
      case 'barber':
        return Icons.content_cut;
      case 'customer':
        return Icons.person_outline;
      default:
        return Icons.error_outline;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.blue;
      case 'barber':
        return Colors.orange;
      case 'customer':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDescription(String role) {
    switch (role) {
      case 'owner':
        return 'Manage your salon';
      case 'barber':
        return 'Work as a barber';
      case 'customer':
        return 'Book appointments';
      default:
        return '';
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'barber':
        return 'Barber';
      case 'customer':
        return 'Customer';
      default:
        return role;
    }
  }

  // ============================================================
  // 🔥 BUILD PROFILE TYPE OPTION
  // ============================================================
  Widget _buildProfileTypeOption({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required String role,
  }) {
    final isDark = context.isDarkMode;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => Navigator.pop(context, role),
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : color,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ Android 16: Responsive Profile Header
  // ============================================================
  Widget _buildProfileHeader() {
    final hasMultipleProfiles = _availableProfiles.length > 1;
    final otherProfilesCount = _availableProfiles
        .where((p) => p['is_current'] != true && p['is_active'] == true)
        .length;
    final canCreateNewProfile = _allUserRoles.length < 3;
    final isDark = context.isDarkMode;

    // ✅ Responsive sizes
    final avatarSize = _isTablet ? 80.0 : 70.0;
    final fontSize = _isTablet ? 20.0 : 18.0;
    final padding = _isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? AppTheme.primaryDark : AppTheme.primary,
            isDark
                ? AppTheme.primaryDark.withValues(alpha: 0.7)
                : AppTheme.primaryLight,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding, padding, padding, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: hasMultipleProfiles
                        ? () {
                            if (mounted) {
                              setState(() {
                                _showProfileSwitcher = !_showProfileSwitcher;
                              });
                            }
                          }
                        : null,
                    child: Stack(
                      children: [
                        Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.grey[300]! : Colors.white,
                              width: 3,
                            ),
                          ),
                          child:
                              (widget.profileImageUrl == null ||
                                  widget.profileImageUrl!.isEmpty)
                              ? CircleAvatar(
                                  backgroundColor: isDark
                                      ? Colors.grey[800]
                                      : Colors.white,
                                  child: Text(
                                    widget.userName.isNotEmpty
                                        ? widget.userName[0].toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      fontSize: _isTablet ? 32 : 28,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : AppTheme.primary,
                                    ),
                                  ),
                                )
                              : ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: widget.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    width: avatarSize,
                                    height: avatarSize,
                                    placeholder: (context, url) => CircleAvatar(
                                      backgroundColor: isDark
                                          ? Colors.grey[800]
                                          : Colors.white,
                                      child: SizedBox(
                                        width: 25,
                                        height: 25,
                                        child: CircularProgressIndicator(
                                          color: isDark
                                              ? Colors.white
                                              : AppTheme.primary,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        CircleAvatar(
                                          backgroundColor: isDark
                                              ? Colors.grey[800]
                                              : Colors.white,
                                          child: Text(
                                            widget.userName.isNotEmpty
                                                ? widget.userName[0]
                                                      .toUpperCase()
                                                : 'U',
                                            style: TextStyle(
                                              fontSize: _isTablet ? 32 : 28,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                        ),
                        if (hasMultipleProfiles)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.blue[700] : Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[300]!
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '+$otherProfilesCount',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.userName,
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasMultipleProfiles)
                              GestureDetector(
                                onTap: () {
                                  if (mounted) {
                                    setState(() {
                                      _showProfileSwitcher =
                                          !_showProfileSwitcher;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _showProfileSwitcher
                                        ? Icons.keyboard_arrow_up
                                        : Icons.swap_horiz,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            if (!hasMultipleProfiles && canCreateNewProfile)
                              GestureDetector(
                                onTap: () {
                                  if (mounted) {
                                    setState(() {
                                      _showProfileSwitcher =
                                          !_showProfileSwitcher;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _showProfileSwitcher
                                        ? Icons.keyboard_arrow_up
                                        : Icons.add,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (widget.userEmail != null &&
                            widget.userEmail!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.userEmail!,
                            style: TextStyle(
                              fontSize: _isTablet ? 14 : 13,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.white.withValues(alpha: 0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getRoleDisplayName(widget.userRole),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_showProfileSwitcher &&
                  (hasMultipleProfiles || canCreateNewProfile))
                _buildProfileSwitcherSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ Android 16: Responsive Profile Switcher
  // ============================================================
  Widget _buildProfileSwitcherSection() {
    final otherProfiles = _availableProfiles
        .where((p) => p['is_current'] != true && p['is_active'] == true)
        .toList();

    final hasMultipleProfiles = _availableProfiles.length > 1;
    final canCreateNewProfile = _allUserRoles.length < 3;
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMultipleProfiles && otherProfiles.isNotEmpty)
            ...otherProfiles.map(
              (profile) => _buildProfileSwitcherItem(profile),
            ),
          if (canCreateNewProfile) _buildCreateNewProfileItem(),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ Android 16: Responsive Profile Switcher Item
  // ============================================================
  Widget _buildProfileSwitcherItem(Map<String, dynamic> profile) {
    final bool isActive =
        profile['is_active'] == true && profile['is_blocked'] == false;
    final Color roleColor = _getRoleColor(profile['role']);
    final avatarSize = _isTablet ? 56.0 : 50.0;
    final fontSize = _isTablet ? 16.0 : 15.0;
    final isDark = context.isDarkMode;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isActive ? () => _switchProfile(profile) : null,
        borderRadius: BorderRadius.circular(12),
        splashColor: roleColor.withValues(alpha: 0.1),
        highlightColor: roleColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: roleColor.withValues(alpha: 0.1),
                ),
                child:
                    profile['photo'] != null &&
                        profile['photo'].toString().isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: profile['photo'],
                          fit: BoxFit.cover,
                          width: avatarSize,
                          height: avatarSize,
                          placeholder: (context, url) => Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: roleColor,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Center(
                            child: Text(
                              profile['name'][0].toUpperCase(),
                              style: TextStyle(
                                fontSize: _isTablet ? 22 : 20,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          profile['name'][0].toUpperCase(),
                          style: TextStyle(
                            fontSize: _isTablet ? 22 : 20,
                            fontWeight: FontWeight.bold,
                            color: roleColor,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          profile['name'],
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getRoleDisplayName(profile['role']),
                            style: TextStyle(
                              fontSize: 10,
                              color: roleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (profile['is_current'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              profile['is_blocked'] == true
                                  ? 'Blocked'
                                  : 'Inactive',
                              style: const TextStyle(
                                fontSize: 8,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile['email'] ?? '',
                      style: TextStyle(
                        fontSize: _isTablet ? 13 : 12,
                        color: isDark ? Colors.white60 : Colors.grey[500],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isActive && profile['is_current'] != true)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFFFF6B8B),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🔥 BUILD SALON SELECTOR ITEM - Works for both Owner and Barber
  // ============================================================
  Widget _buildSalonSelectorItem(Map<String, dynamic> item) {
    final salons = item['salons'] as List<Map<String, dynamic>>;
    final selectedId = item['selectedSalonId'] as String?;
    final onChanged = item['onSalonChanged'] as Function(String?)?;
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.store_outlined,
                color: isDark ? Colors.white60 : Colors.grey[600],
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                'Select Salon',
                style: TextStyle(
                  fontSize: _isTablet ? 14 : 13,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...salons.map((salon) {
            final isSelected = salon['id'].toString() == selectedId;
            final salonName = salon['name']?.toString() ?? 'Salon';

            return Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? const Color(0xFFFF6B8B)
                      : Colors.grey[400],
                  size: 18,
                ),
                title: Text(
                  salonName,
                  style: TextStyle(
                    fontSize: _isTablet ? 15 : 14,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFFFF6B8B)
                        : (isDark ? Colors.white70 : Colors.grey[800]),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isSelected
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  if (onChanged != null) {
                    onChanged(salon['id'].toString());
                  }
                },
                dense: true,
              ),
            );
          }),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 BUILD SALON INFO ITEM
  // ============================================================
  Widget _buildSalonInfoItem(Map<String, dynamic> item) {
    final salonId = item['salonId'] as String?;
    final subtitle = item['subtitle'] as String? ?? 'No salon assigned';
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: isDark ? Colors.white12 : Colors.grey, thickness: 0.5),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item['icon'] as IconData? ?? Icons.store,
                  color: salonId != null ? const Color(0xFFFF6B8B) : Colors.grey,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] as String? ?? 'Salon',
                      style: TextStyle(
                        fontSize: _isTablet ? 14 : 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: _isTablet ? 13 : 12,
                              color: salonId != null
                                  ? const Color(0xFFFF6B8B)
                                  : (isDark
                                        ? Colors.white70
                                        : Colors.grey[500]),
                              fontWeight: salonId != null
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (salonId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 GET MENU ITEMS - Owner
  // ============================================================
  List<Map<String, dynamic>> _getOwnerMenuItems() {
    return [
      {
        'icon': Icons.dashboard_outlined,
        'title': 'Dashboard',
        'route': '/owner',
        'color': Colors.blue,
      },
      if (_ownerSalons.length > 1)
        {
          'icon': Icons.swap_horiz,
          'title': 'Switch Salon',
          'isSalonSelector': true,
          'salons': _ownerSalons,
          'selectedSalonId': _selectedSalonId,
          'onSalonChanged': _onOwnerSalonChanged,
          'color': Colors.blueGrey,
        },
      {
        'icon': Icons.calendar_month_outlined,
        'title': 'Appointments',
        'route': _selectedSalonId != null
            ? '/owner/appointments?salonId=$_selectedSalonId'
            : '/owner/appointments',
        'color': Colors.green,
        'badge': _pendingBookingsCount > 0 ? _pendingBookingsCount : null,
      },
      {
        'icon': Icons.people_outline,
        'title': 'Customers',
        'route': _selectedSalonId != null
            ? '/owner/customers?salonId=$_selectedSalonId'
            : '/owner/customers',
        'color': Colors.purple,
      },
      {
        'icon': Icons.content_cut_outlined,
        'title': 'Barbers',
        'route': _selectedSalonId != null
            ? '/owner/barbers?salonId=$_selectedSalonId'
            : '/owner/barbers',
        'color': Colors.orange,
      },
      {
        'icon': Icons.inventory_2_outlined,
        'title': 'Services',
        'route': _selectedSalonId != null
            ? '/owner/services?salonId=$_selectedSalonId'
            : '/owner/services',
        'color': Colors.teal,
      },
      {
        'icon': Icons.attach_money_outlined,
        'title': 'Revenue',
        'route': _selectedSalonId != null
            ? '/owner/revenue?salonId=$_selectedSalonId'
            : '/owner/revenue',
        'color': Colors.green,
      },
      {
        'icon': Icons.notifications_outlined,
        'title': 'Notifications',
        'route': '/notifications?role=owner',
        'color': Colors.purple,
        'badge': _unreadNotificationCount > 0 ? _unreadNotificationCount : null,
      },
      {'divider': true},
    ];
  }

  // ============================================================
  // 🔥 GET MENU ITEMS - Barber (with Salon Selector)
  // ============================================================
  List<Map<String, dynamic>> _getBarberMenuItems() {
    final List<Map<String, dynamic>> items = [
      {
        'icon': Icons.dashboard_outlined,
        'title': 'My Dashboard',
        'route': '/barber',
        'color': Colors.blue,
      },
    ];

    // ✅ Salon Selector - if barber has multiple salons
    if (_barberSalons.length > 1) {
      items.add({
        'icon': Icons.swap_horiz,
        'title': 'Switch Salon',
        'isSalonSelector': true,
        'salons': _barberSalons,
        'selectedSalonId': _selectedSalonId,
        'onSalonChanged': _onBarberSalonChanged,
        'color': Colors.blueGrey,
      });
    } 
    // ✅ Single Salon Info - if barber has exactly one salon
    else if (_barberSalons.length == 1 && _selectedSalonName != null) {
      items.add({
        'icon': Icons.store_outlined,
        'title': 'My Salon',
        'subtitle': _selectedSalonName,
        'color': const Color(0xFFFF6B8B),
        'isSalonInfo': true,
        'salonId': _selectedSalonId,
      });
    } 
    // ✅ No Salon Assigned
    else {
      items.add({
        'icon': Icons.store_outlined,
        'title': 'No Salon Assigned',
        'subtitle': 'Contact your owner',
        'color': Colors.grey,
        'isSalonInfo': true,
        'salonId': null,
      });
    }

    // ✅ Add remaining menu items
    items.addAll([
      {
        'icon': Icons.calendar_month_outlined,
        'title': 'My Schedule',
        'route': _selectedSalonId != null
            ? '/barber/schedule?salonId=$_selectedSalonId'
            : '/barber/schedule',
        'color': Colors.green,
      },
      {
        'icon': Icons.pending_actions_outlined,
        'title': 'My Appointments',
        'route': _selectedSalonId != null
            ? '/barber/appointments?salonId=$_selectedSalonId'
            : '/barber/appointments',
        'color': Colors.orange,
        'badge': _pendingBookingsCount > 0 ? _pendingBookingsCount : null,
      },
      {
        'icon': Icons.star_outline,
        'title': 'My Reviews',
        'route': _selectedSalonId != null
            ? '/barber/reviews?salonId=$_selectedSalonId'
            : '/barber/reviews',
        'color': Colors.amber,
      },
      {
        'icon': Icons.notifications_outlined,
        'title': 'Notifications',
        'route': '/notifications?role=barber',
        'color': Colors.purple,
        'badge': _unreadNotificationCount > 0 ? _unreadNotificationCount : null,
      },
      {'divider': true},
    ]);

    return items;
  }

  // ============================================================
  // 🔥 GET MENU ITEMS - Customer
  // ============================================================
  List<Map<String, dynamic>> _getCustomerMenuItems() {
    return [
      {
        'icon': Icons.home_outlined,
        'title': 'Home',
        'route': '/customer',
        'color': Colors.blue,
      },
      {
        'icon': Icons.calendar_month_outlined,
        'title': 'My Bookings',
        'route': '/customer/my-bookings',
        'color': Colors.green,
        'badge': _pendingBookingsCount > 0 ? _pendingBookingsCount : null,
      },
      {
        'icon': Icons.history_outlined,
        'title': 'History',
        'route': '/customer/history',
        'color': Colors.orange,
      },
      {
        'icon': Icons.favorite_outline,
        'title': 'My Salons',
        'route': '/customer/my-salons',
        'color': Colors.red,
      },
      {
        'icon': Icons.notifications_outlined,
        'title': 'Notifications',
        'route': '/notifications?role=customer',
        'color': Colors.purple,
        'badge': _unreadNotificationCount > 0 ? _unreadNotificationCount : null,
      },
      {'divider': true},
    ];
  }

  // ============================================================
  // 🔥 GET COMMON MENU ITEMS
  // ============================================================
  List<Map<String, dynamic>> _getCommonMenuItems() {
    return [
      {
        'icon': Icons.info_outline,
        'title': 'About Us',
        'route': '/about',
        'color': Colors.blueGrey,
      },
      {
        'icon': Icons.help_outline,
        'title': 'Help & Support',
        'route': '/help',
        'color': Colors.grey,
      },
      {
        'icon': Icons.privacy_tip_outlined,
        'title': 'Privacy Policy',
        'route': '/privacy',
        'color': Colors.grey,
      },
      {
        'icon': Icons.description_outlined,
        'title': 'Terms & Conditions',
        'route': '/terms',
        'color': Colors.grey,
      },
    ];
  }

  // ============================================================
  // 🔥 BOTTOM SECTION
  // ============================================================
  Widget _buildBottomSection() {
    final isDark = context.isDarkMode;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white12
                : Colors.grey.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () {
                Navigator.pop(context);
                _navigateToSettings(context);
              },
              borderRadius: BorderRadius.circular(8),
              splashColor: Colors.grey.withValues(alpha: 0.1),
              highlightColor: Colors.grey.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey[800]
                            : Colors.grey.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.settings_outlined,
                        color: isDark ? Colors.white60 : Colors.grey,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: _isTablet ? 16 : 15,
                        color: isDark ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          ),

          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _logout(context),
              borderRadius: BorderRadius.circular(8),
              splashColor: Colors.red.withValues(alpha: 0.1),
              highlightColor: Colors.red.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.logout,
                        color: isDark ? Colors.red[300] : Colors.red,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: _isTablet ? 16 : 15,
                        color: isDark ? Colors.red[300] : Colors.red,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Version ${AppVersion.version}',
              style: TextStyle(
                fontSize: _isTablet ? 13 : 12,
                color: isDark ? Colors.white70 : Colors.grey[400],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 BUILD MENU ITEMS
  // ============================================================
  List<Widget> _buildMenuItems() {
    final List<Map<String, dynamic>> items = [];
    final isDark = context.isDarkMode;

    switch (widget.userRole) {
      case 'owner':
        items.addAll(_getOwnerMenuItems());
        break;
      case 'barber':
        items.addAll(_getBarberMenuItems());
        break;
      case 'customer':
        items.addAll(_getCustomerMenuItems());
        break;
    }

    items.addAll(_getCommonMenuItems());

    return items.map((item) {
      // ✅ Salon Selector - Works for both Owner and Barber
      if (item['isSalonSelector'] == true) {
        return _buildSalonSelectorItem(item);
      }

      // ✅ Salon Info - Works for both Owner and Barber
      if (item['isSalonInfo'] == true) {
        return _buildSalonInfoItem(item);
      }

      Color itemColor = isDark ? Colors.white60 : Colors.grey.shade700;
      if (item['color'] != null) {
        itemColor = item['color'] as Color;
      }

      if (item['divider'] == true) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(
            color: isDark
                ? Colors.white12
                : Colors.grey.withValues(alpha: 0.15),
            height: 1,
          ),
        );
      }

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: itemColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item['icon'] as IconData? ?? Icons.error,
              color: itemColor,
              size: _isTablet ? 24 : 22,
            ),
          ),
          title: Text(
            item['title'] as String? ?? 'Unknown',
            style: TextStyle(
              fontSize: _isTablet ? 16 : 15,
              color: isDark ? Colors.white : const Color(0xFF333333),
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: item['badge'] != null
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item['badge'].toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark ? Colors.white30 : Colors.grey[400],
                ),
          onTap: () {
            Navigator.pop(context);
            if (widget.onMenuItemSelected != null) {
              widget.onMenuItemSelected!();
            }
            if (item['route'] != null) {
              _navigateToScreen(context, item['route'] as String);
            }
          },
          tileColor: Colors.transparent,
          splashColor: itemColor.withValues(alpha: 0.1),
          hoverColor: itemColor.withValues(alpha: 0.05),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }).toList();
  }

  // ============================================================
  // 🔥 NAVIGATION METHODS
  // ============================================================
  void _navigateToScreen(BuildContext context, String route) {
    try {
      context.push(route);
    } catch (e) {
      debugPrint('Navigation error: $e');
    }
  }

  void _navigateToSettings(BuildContext context) {
    try {
      context.push('/settings');
    } catch (e) {
      debugPrint('Settings navigation error: $e');
    }
  }

  // ============================================================
  // 🔥 LOGOUT
  // ============================================================
  Future<void> _logout(BuildContext context) async {
    showLogoutConfirmation(
      context,
      onLogoutConfirmed: () async {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.all(0),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        );

        try {
          await appState.logoutForContinue();

          if (context.mounted) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }

          if (context.mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.go('/');
              }
            });
          }
        } catch (e) {
          if (context.mounted) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Logout failed: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }

  // ============================================================
  // ✅ Android 16: CREATE NEW PROFILE ITEM
  // ============================================================
  Widget _buildCreateNewProfileItem() {
    final isDark = context.isDarkMode;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            _showProfileSwitcher = false;
          });
          _createNewProfile();
        },
        borderRadius: BorderRadius.circular(12),
        splashColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
        highlightColor: const Color(0xFFFF6B8B).withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  size: 18,
                  color: Color(0xFFFF6B8B),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Create New Profile',
                style: TextStyle(
                  fontSize: _isTablet ? 15 : 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFFFF6B8B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ Android 16: MAIN BUILD METHOD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    // ✅ Check screen size on every build
    _checkScreenSize();

    final isDark = context.isDarkMode;

    return Drawer(
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : Container(
              color: isDark ? const Color(0xFF121212) : Colors.white,
              child: Column(
                children: [
                  _buildProfileHeader(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      physics: const BouncingScrollPhysics(),
                      children: _buildMenuItems(),
                    ),
                  ),
                  _buildBottomSection(),
                ],
              ),
            ),
    );
  }
}