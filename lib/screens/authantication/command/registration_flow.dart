import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/common_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/welcome.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/customer_reg/name_screen.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class RegistrationFlow extends StatefulWidget {
  final User? user;

  const RegistrationFlow({super.key, this.user});

  @override
  State<RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends State<RegistrationFlow> {
  late final PageController _controller;

  // Platform detection
  bool get isWeb => UniversalPlatform.isWeb;
  bool get isMobile => !isWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;

  // Form data
  String? roles;
  String? firstName;
  String? lastName;
  String? phone;

  // Flags
  bool _isNewProfile = false;
  bool _isLoading = false;
  bool _didCheckQueryParams = false;

  // Cache role IDs
  Map<String, int>? _roleIds;

  @override
  void initState() {
    super.initState();
    debugPrint('📍 RegistrationFlow initState');
    _controller = PageController(initialPage: 0);
    _loadRoleIds();
  }

  // 🔥 Load role IDs from database
  Future<void> _loadRoleIds() async {
    try {
      final response = await Supabase.instance.client
          .from('roles')
          .select('id, name');

      _roleIds = {
        for (var role in response) role['name'] as String: role['id'] as int,
      };

      debugPrint('✅ Role IDs loaded: $_roleIds');
    } catch (e) {
      debugPrint('❌ Error loading role IDs: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didCheckQueryParams) {
      _didCheckQueryParams = true;
      _checkQueryParameters();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // CHECK QUERY PARAMETERS (from side menu)
  // ============================================================
  void _checkQueryParameters() {
    try {
      final GoRouterState state = GoRouterState.of(context);
      debugPrint('📍 GoRouterState path: ${state.path}');
      debugPrint('📍 GoRouterState query params: ${state.uri.queryParameters}');

      final role = state.uri.queryParameters['role'];
      final isNew = state.uri.queryParameters['new'] == 'true';

      debugPrint('📱 Extracted - role: $role, isNew: $isNew');

      if (role != null && role.isNotEmpty) {
        setState(() {
          roles = role;
          _isNewProfile = isNew;
        });

        debugPrint('📱 New profile creation for role: $role');

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          debugPrint('📍 Jumping to page 1 (skip welcome)');
          _controller.jumpToPage(1);
        });
      } else {
        setState(() {
          roles = null;
          _isNewProfile = false;
        });
        debugPrint('📱 First time registration - showing welcome screen');
      }
    } catch (e) {
      debugPrint('❌ Error reading query parameters: $e');
      setState(() {
        roles = null;
        _isNewProfile = false;
      });
    }
  }

  // ============================================================
  // HANDLE BACK BUTTON
  // ============================================================
  void _handleBack() {
    debugPrint('📍 _handleBack called');
    debugPrint('📍 _isNewProfile: $_isNewProfile');
    debugPrint('📍 Current page: ${_controller.page}');
    debugPrint('📍 Current role: $roles');

    if (_isNewProfile) {
      debugPrint('📍 New profile - going to $roles dashboard');
      if (context.canPop()) {
        context.pop();
      } else {
        switch (roles) {
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
      }
    } else {
      if (_controller.hasClients) {
        if (_controller.page! > 0) {
          debugPrint('📍 Going to previous page in flow');
          setState(() {
            roles = null;
          });
          _controller
              .previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.ease,
              )
              .then((_) {
                debugPrint('📍 Navigation complete, roles cleared');
              });
        } else {
          debugPrint('📍 At page 0 - going back to login');
          context.go('/login');
        }
      } else {
        debugPrint('📍 No clients - using pop');
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '📍 RegistrationFlow build() - roles: $roles, isNewProfile: $_isNewProfile',
    );

    return Scaffold(
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // PAGE 0: WELCOME SCREEN
                if (roles == null)
                  WelcomeScreen(
                    onNext: (selectedRole) {
                      debugPrint('📍 WelcomeScreen onNext: $selectedRole');
                      setState(() {
                        roles = selectedRole;
                      });
                      _nextPage();
                    },
                    onBack: _handleBack,
                  )
                else
                  const SizedBox.shrink(),

                // PAGE 1: NAME ENTRY
                NameEntry(
                  onNext: (f, l) {
                    setState(() {
                      firstName = f;
                      lastName = l;
                    });
                    _createProfile();
                  },
                  controller: _controller,
                  onBack: _handleBack,
                ),
              ],
            ),
    );
  }

  // ============================================================
  // 🔥 GET ROLE ID FROM CACHE OR DATABASE
  // ============================================================
  Future<int> _getRoleId(String roleName) async {
    if (_roleIds != null && _roleIds!.containsKey(roleName)) {
      return _roleIds![roleName]!;
    }

    final response = await Supabase.instance.client
        .from('roles')
        .select('id')
        .eq('name', roleName)
        .single();

    return response['id'];
  }

  // ============================================================
  // 🔥 CHECK IF USER ALREADY HAS THIS ROLE
  // ============================================================
  Future<bool> _userHasRole(String userId, int roleId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_roles')
          .select()
          .eq('user_id', userId)
          .eq('role_id', roleId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Error checking user role: $e');
      return false;
    }
  }

  // ============================================================
  // 🔥 GET USER'S EXISTING ROLES (Only active ones)
  // ============================================================
  Future<List<String>> _getUserRoles(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (name),
            status
          ''')
          .eq('user_id', userId)
          .eq('status', 'active'); // ✅ Only get active roles

      return response.map((r) => r['roles']['name'] as String).toList();
    } catch (e) {
      debugPrint('Error getting user roles: $e');
      return [];
    }
  }

  // ============================================================
  // 🔥 GET USER'S ALL ROLES (Including inactive)
  // ============================================================
  Future<List<Map<String, dynamic>>> _getAllUserRolesWithStatus(
    String userId,
  ) async {
    try {
      final response = await Supabase.instance.client
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (name),
            status
          ''')
          .eq('user_id', userId);

      return response
          .map(
            (r) => {
              'role': r['roles']['name'] as String,
              'status': r['status'] as String? ?? 'active',
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Error getting all user roles: $e');
      return [];
    }
  }

  // ============================================================
  // 🔥 CREATE PROFILE IN DATABASE (UPDATED FOR NEW SCHEMA)
  // ============================================================
  Future<void> _createProfile() async {
    if (!mounted) return;

    final user = widget.user ?? supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "Error",
          message: "User not found. Please login again.",
          isError: true,
        );
        if (mounted) context.go('/login');
      }
      return;
    }

    final email = user.email;
    if (email == null) {
      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "Error",
          message: "User email not found.",
          isError: true,
        );
      }
      return;
    }

    if (roles == null) {
      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "Error",
          message: "Please select a role.",
          isError: true,
        );
      }
      return;
    }

    // ✅ Validation
    if (firstName == null ||
        lastName == null ||
        firstName!.isEmpty ||
        lastName!.isEmpty) {
      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "Error",
          message: "Please enter your full name.",
          isError: true,
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    LoadingOverlay.show(context, message: "Setting up your profile...");

    try {
      final supabase = Supabase.instance.client;

      // 🔥 Get role ID
      final roleId = await _getRoleId(roles!);

      // 🔥 Generate full name
      final fullName = "${firstName!.trim()} ${lastName!.trim()}";

      // 🔥 Build extra_data with role and status
      final Map<String, dynamic> extraData = {
        'full_name': fullName,
        'first_name': firstName!.trim(),
        'last_name': lastName!.trim(),
        'registered_at': DateTime.now().toIso8601String(),
        'role': roles,
        // ✅ Store role with status in extra_data (Role Level Status)
        'profile_$roles': {
          'role': roles,
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
        },
        // ✅ Also set profile level status to active
        'profile_status': {
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      };

      if (phone != null && phone!.isNotEmpty) extraData['phone'] = phone;

      final platform = isWeb
          ? 'web'
          : (isAndroid ? 'android' : (isIOS ? 'ios' : 'mobile'));

      // 🔥 STEP 1: Check if profile exists
      final existingProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
        // 🔥 NEW USER - Create profile
        debugPrint('➕ Creating new profile for user');

        await supabase.from('profiles').insert({
          'id': user.id,
          'email': email,
          'full_name': fullName,
          'avatar_url':
              user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
          'extra_data': extraData,
          'platform': platform,
          'is_active': true,
          'is_blocked': false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        // ✅ Verify profile creation
        final verifyProfile = await supabase
            .from('profiles')
            .select('id, is_active')
            .eq('id', user.id)
            .maybeSingle();

        if (verifyProfile == null) {
          throw Exception('Profile creation failed - verification failed');
        }
        debugPrint(
          '✅ Profile verified: id=${verifyProfile['id']}, is_active=${verifyProfile['is_active']}',
        );
      } else {
        // 🔥 EXISTING USER - Update profile
        debugPrint('🔄 Updating existing profile');

        final existingExtra =
            existingProfile['extra_data'] as Map<String, dynamic>? ?? {};

        // ✅ Merge extra_data keeping existing profile data
        final mergedExtra = {...existingExtra, ...extraData};

        // ✅ Update profile level status if exists
        if (!mergedExtra.containsKey('profile_status')) {
          mergedExtra['profile_status'] = {
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
        } else {
          final profileStatus =
              mergedExtra['profile_status'] as Map<String, dynamic>;
          profileStatus['status'] = 'active';
          profileStatus['updated_at'] = DateTime.now().toIso8601String();
        }

        await supabase
            .from('profiles')
            .update({
              'email': email,
              'full_name': fullName,
              'avatar_url':
                  user.userMetadata?['avatar_url'] ??
                  user.userMetadata?['picture'],
              'extra_data': mergedExtra,
              'platform': platform,
              'is_active': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      }

      // 🔥 STEP 2: Check if user already has this role
      final hasRole = await _userHasRole(user.id, roleId);

      if (!hasRole) {
        // 🔥 Assign role to user with status 'active'
        debugPrint('➕ Assigning role ${roles!} to user with status active');

        await supabase.from('user_roles').insert({
          'user_id': user.id,
          'role_id': roleId,
          'status': 'active', // ✅ New: status column
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        // ✅ Verify role assignment
        final verifyRole = await supabase
            .from('user_roles')
            .select('id, status')
            .eq('user_id', user.id)
            .eq('role_id', roleId)
            .maybeSingle();

        if (verifyRole == null) {
          debugPrint('⚠️ Role assignment may have failed');
        } else {
          debugPrint('✅ Role verified: status=${verifyRole['status']}');
        }
      } else {
        // ✅ If role exists but might be inactive, update status to active
        debugPrint('🔄 Updating existing role status to active');
        await supabase
            .from('user_roles')
            .update({
              'status': 'active',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', user.id)
            .eq('role_id', roleId);
      }

      // 🔥 STEP 3: Get all active user roles
      final userRoles = await _getUserRoles(user.id);
      debugPrint('📝 Active user roles: $userRoles');

      // 🔥 STEP 4: Get all user roles with status (for SessionManager)
      final allRolesWithStatus = await _getAllUserRolesWithStatus(user.id);
      debugPrint('📝 All roles with status: $allRolesWithStatus');

      // 🔥 STEP 5: Update user metadata
      final currentMetadata = user.userMetadata ?? {};
      Map<String, dynamic> metadataUpdate = {
        ...currentMetadata,
        'roles': userRoles,
        'current_role': roles,
        'profile_created_at': DateTime.now().toIso8601String(),
        'profile_created': true,
        'needs_profile': false,
        'registration_complete': true,
      };

      await supabase.auth.updateUser(UserAttributes(data: metadataUpdate));

      // 🔥 STEP 6: Save to SessionManager
      debugPrint('📱 Saving profile to SessionManager');

      final photoUrl =
          user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'];

      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: fullName,
        photo: photoUrl,
        roles: userRoles,
        rememberMe: true,
        provider: await _getUserProvider(user, photoUrl),
      );

      await SessionManager.saveCurrentRole(roles!);

      // ✅ Sync profile status with SessionManager
      try {
        await SessionManager.syncProfileStatusWithDB(
          email: email,
          role: roles!,
        );
      } catch (e) {
        debugPrint('⚠️ syncProfileStatusWithDB error: $e');
        // Continue even if sync fails
      }

      // ✅ Check if any roles need auto-restore
      for (String role in userRoles) {
        try {
          await SessionManager.autoRestoreProfileOnLogin(
            email: email,
            role: role,
          );
        } catch (e) {
          debugPrint('⚠️ autoRestoreProfileOnLogin error for $role: $e');
        }
      }

      // ✅ Refresh app state
      await appState.refreshState();

      if (mounted) {
        LoadingOverlay.hide();
        setState(() => _isLoading = false);

        // Show success message
        final title = roles == 'owner'
            ? "🎉 Business Created!"
            : roles == 'barber'
            ? "👋 Welcome Barber!"
            : "🎉 Welcome!";

        final message = roles == 'owner'
            ? "Your business profile has been created successfully."
            : roles == 'barber'
            ? "Your barber profile has been created successfully."
            : "Your profile has been created successfully.";

        await showCustomAlert(
          context: context,
          title: title,
          message: message,
          isError: false,
        );

        // 🔥 STEP 7: Navigate based on roles
        if (mounted) {
          if (userRoles.length > 1 && !_isNewProfile) {
            // Multiple roles - show role selector
            context.go(
              '/role-selector',
              extra: {'roles': userRoles, 'email': email, 'userId': user.id},
            );
          } else {
            // Single role - go to appropriate dashboard
            _redirectBasedOnRole(roles!);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Profile creation error: $e');

      if (mounted) {
        LoadingOverlay.hide();
        setState(() => _isLoading = false);

        await showCustomAlert(
          context: context,
          title: "Error",
          message: "Failed to create profile: ${e.toString()}",
          isError: true,
        );
      }
    }
  }

  // ============================================================
  // HELPER: Get user provider
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
  // REDIRECT BASED ON ROLE
  // ============================================================
  void _redirectBasedOnRole(String role) {
    if (!mounted) return;

    // ✅ Registration flow complete - user is logged in
    final email = widget.user?.email ?? supabase.auth.currentUser?.email;

    if (email == null) {
      debugPrint('⚠️ No email found, redirecting to login');
      context.go('/login');
      return;
    }

    debugPrint('🎯 Redirecting based on role: $role for $email');

    // ✅ Role එක අනුව redirect කරන්න
    switch (role) {
      case 'owner':
        debugPrint('👑 Going to owner dashboard');
        context.go('/owner');
        break;
      case 'barber':
        debugPrint('💇 Going to barber dashboard');
        context.go('/barber');
        break;
      default:
        debugPrint('👤 Going to customer dashboard');
        context.go('/customer');
        break;
    }
  }

  void _nextPage() => _controller.nextPage(
    duration: const Duration(milliseconds: 300),
    curve: Curves.ease,
  );
}