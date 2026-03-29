import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/common_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/welcome.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/business_reg/company_name_screen.dart';
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
  String? companyName;
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
        for (var role in response) role['name'] as String: role['id'] as int
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
      debugPrint('📍 GoRouterState full URI: ${state.uri.toString()}');
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
          
          _controller.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.ease,
          ).then((_) {
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
    debugPrint('📍 RegistrationFlow build() - roles: $roles, isNewProfile: $_isNewProfile');
    
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF6B8B),
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
                
                // PAGE 1: ROLE-SPECIFIC FORMS
                if (roles == 'customer') ...[
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
                
                if (roles == 'owner') ...[
                  CompanyNameScreen(
                    onNext: (n) {
                      setState(() {
                        companyName = n;
                      });
                      _createProfile();
                    },
                    controller: _controller,
                    onBack: _handleBack,
                  ),
                ],
                
                if (roles == 'barber') ...[
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
              ],
            ),
    );
  }

  // ============================================================
  // 🔥 GET ROLE ID FROM CACHE OR DATABASE
  // ============================================================
  Future<int> _getRoleId(String roleName) async {
    // Check cache first
    if (_roleIds != null && _roleIds!.containsKey(roleName)) {
      return _roleIds![roleName]!;
    }
    
    // If not in cache, fetch from database
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
  // 🔥 GET USER'S EXISTING ROLES
  // ============================================================
  Future<List<String>> _getUserRoles(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('user_id', userId);

      return response
          .map((r) => r['roles']['name'] as String)
          .toList();
    } catch (e) {
      debugPrint('Error getting user roles: $e');
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

    // Role-specific validation
    if (roles == 'owner') {
      if (companyName == null || companyName!.isEmpty) {
        if (mounted) {
          await showCustomAlert(
            context: context,
            title: "Error",
            message: "Please enter your company name.",
            isError: true,
          );
        }
        return;
      }
    } else if (roles == 'barber' || roles == 'customer') {
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
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    LoadingOverlay.show(context, message: "Setting up your profile...");

    try {
      final supabase = Supabase.instance.client;

      // 🔥 Get role ID
      final roleId = await _getRoleId(roles!);

      // 🔥 Generate full name
      String? fullName;
      Map<String, dynamic> extraData = {};
      
      if (roles == 'owner') {
        fullName = companyName!.trim();
        extraData = {
          'company_name': companyName!.trim(),
          'business_type': 'salon',
          'registration_date': DateTime.now().toIso8601String(),
          'role': 'owner',
        };
        if (phone != null && phone!.isNotEmpty) extraData['phone'] = phone;
      } else {
        fullName = "${firstName!.trim()} ${lastName!.trim()}";
        extraData = {
          'full_name': fullName,
          'first_name': firstName!.trim(),
          'last_name': lastName!.trim(),
          'registered_at': DateTime.now().toIso8601String(),
          'role': roles,
        };
        if (phone != null && phone!.isNotEmpty) extraData['phone'] = phone;
      }

      String platform = isWeb ? 'web' : (isAndroid ? 'android' : (isIOS ? 'ios' : 'mobile'));

      // 🔥 STEP 1: Check if profile exists
      final existingProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
        // 🔥 NEW USER - Create profile first
        debugPrint('➕ Creating new profile for user');
        
        await supabase.from('profiles').insert({
          'id': user.id,
          'email': email,
          'full_name': fullName,
          'avatar_url': user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
          'extra_data': extraData,
          'platform': platform,
          'is_active': true,
          'is_blocked': false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        // 🔥 EXISTING USER - Update profile
        debugPrint('🔄 Updating existing profile');
        
        final existingExtra = existingProfile['extra_data'] as Map<String, dynamic>? ?? {};
        
        await supabase
            .from('profiles')
            .update({
              'email': email,
              'full_name': fullName,
              'avatar_url': user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
              'extra_data': {
                ...existingExtra,
                ...extraData,
                'updated_at': DateTime.now().toIso8601String(),
              },
              'platform': platform,
              'is_active': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      }

      // 🔥 STEP 2: Check if user already has this role
      final hasRole = await _userHasRole(user.id, roleId);
      
      if (!hasRole) {
        // 🔥 Assign role to user
        debugPrint('➕ Assigning role ${roles!} to user');
        
        await supabase.from('user_roles').insert({
          'user_id': user.id,
          'role_id': roleId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // 🔥 STEP 3: Get all user roles
      final userRoles = await _getUserRoles(user.id);
      
      debugPrint('📝 User roles after update: $userRoles');

      // 🔥 STEP 4: Update user metadata
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

      // 🔥 STEP 5: Save to SessionManager
      debugPrint('📱 Saving profile to SessionManager');

      String? photoUrl = user.userMetadata?['avatar_url'] ?? 
                         user.userMetadata?['picture'];

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
      await appState.refreshState();

      if (mounted) {
        LoadingOverlay.hide();
        setState(() => _isLoading = false);

        // Show success message
        String title;
        String message;
        
        if (roles == 'owner') {
          title = "🎉 Business Created!";
          message = "Your business profile has been created successfully.";
        } else if (roles == 'barber') {
          title = "👋 Welcome Barber!";
          message = "Your barber profile has been created successfully.";
        } else {
          title = "🎉 Welcome!";
          message = "Your profile has been created successfully.";
        }

        await showCustomAlert(
          context: context,
          title: title,
          message: message,
          isError: false,
        );

        // 🔥 STEP 6: Navigate based on roles
        if (mounted) {
          if (userRoles.length > 1 && !_isNewProfile) {
            // Multiple roles - show role selector
            context.go('/role-selector', extra: {
              'roles': userRoles,
              'email': email,
              'userId': user.id,
            });
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

    switch (role) {
      case 'owner':
        context.go('/owner');
        break;
      case 'barber':
        context.go('/barber');
        break;
      default:
        context.go('/customer');
        break;
    }
  }

  void _nextPage() => _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
}