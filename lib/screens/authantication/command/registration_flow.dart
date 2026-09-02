import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/help_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/welcome.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/command/name_screen.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    debugPrint('📍 RegistrationFlow initState');
    _controller = PageController(initialPage: 0);
    _loadRoleIds();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
    if (!_didCheckQueryParams) {
      _didCheckQueryParams = true;
      _checkQueryParameters();
    }
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // 🔥 LOAD ROLE IDS
  // ============================================================
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

  // ============================================================
  // CHECK QUERY PARAMETERS
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

  // ============================================================
  // GET ROLE ID FROM CACHE OR DATABASE
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
  // CHECK IF USER ALREADY HAS THIS ROLE
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
  // GET USER'S EXISTING ROLES (Only active ones)
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
          .eq('status', 'active');

      return response.map((r) => r['roles']['name'] as String).toList();
    } catch (e) {
      debugPrint('Error getting user roles: $e');
      return [];
    }
  }

  // ============================================================
  // GET USER'S ALL ROLES WITH STATUS
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
  // CREATE PROFILE IN DATABASE
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

      final roleId = await _getRoleId(roles!);
      final fullName = "${firstName!.trim()} ${lastName!.trim()}";

      final Map<String, dynamic> extraData = {
        'full_name': fullName,
        'first_name': firstName!.trim(),
        'last_name': lastName!.trim(),
        'registered_at': DateTime.now().toIso8601String(),
        'role': roles,
        'profile_$roles': {
          'role': roles,
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
        },
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

      final existingProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
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
        debugPrint('🔄 Updating existing profile');

        final existingExtra =
            existingProfile['extra_data'] as Map<String, dynamic>? ?? {};

        final mergedExtra = {...existingExtra, ...extraData};

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

      final hasRole = await _userHasRole(user.id, roleId);

      if (!hasRole) {
        debugPrint('➕ Assigning role ${roles!} to user with status active');

        await supabase.from('user_roles').insert({
          'user_id': user.id,
          'role_id': roleId,
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

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

      final userRoles = await _getUserRoles(user.id);
      debugPrint('📝 Active user roles: $userRoles');

      final allRolesWithStatus = await _getAllUserRolesWithStatus(user.id);
      debugPrint('📝 All roles with status: $allRolesWithStatus');

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

      try {
        await SessionManager.syncProfileStatusWithDB(
          email: email,
          role: roles!,
        );
      } catch (e) {
        debugPrint('⚠️ syncProfileStatusWithDB error: $e');
      }

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

      await appState.refreshState();

      if (mounted) {
        LoadingOverlay.hide();
        setState(() => _isLoading = false);

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

        if (mounted) {
          if (userRoles.length > 1 && !_isNewProfile) {
            context.go(
              '/role-selector',
              extra: {'roles': userRoles, 'email': email, 'userId': user.id},
            );
          } else {
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

    final email = widget.user?.email ?? supabase.auth.currentUser?.email;

    if (email == null) {
      debugPrint('⚠️ No email found, redirecting to login');
      context.go('/login');
      return;
    }

    debugPrint('🎯 Redirecting based on role: $role for $email');

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

  // ============================================================
  // BUILD METHOD - With AppTheme & Context Extensions
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;

    debugPrint(
      '📍 RegistrationFlow build() - roles: $roles, isNewProfile: $_isNewProfile',
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: primaryColor,
              ),
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
}