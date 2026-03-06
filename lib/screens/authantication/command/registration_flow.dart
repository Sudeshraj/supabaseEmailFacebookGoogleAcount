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

  @override
  void initState() {
    super.initState();
    debugPrint('📍 RegistrationFlow initState');
    
    _controller = PageController(initialPage: 0);
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
  // 🔥 CHECK QUERY PARAMETERS (from side menu)
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
        // 🔥 CASE 1: New profile creation from side menu
        setState(() {
          roles = role;
          _isNewProfile = isNew;
        });
        
        debugPrint('📱 New profile creation for role: $role');
        
        // Jump to page 1 (skip welcome)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          debugPrint('📍 Jumping to page 1 (skip welcome)');
          _controller.jumpToPage(1);
        });
      } else {
        // 🔥 CASE 2: First time registration
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
  // 🔥 HANDLE BACK BUTTON (Called from child screens)
  // ============================================================
// ============================================================
// 🔥 HANDLE BACK BUTTON (Called from child screens)
// ============================================================
void _handleBack() {
  debugPrint('📍 _handleBack called');
  debugPrint('📍 _isNewProfile: $_isNewProfile');
  debugPrint('📍 Current page: ${_controller.page}');
  debugPrint('📍 Current role: $roles');
  
  if (_isNewProfile) {
    // New profile creation - go back to appropriate dashboard
    debugPrint('📍 New profile - going to ${roles} dashboard');
    
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
    // First time registration - use PageController
    if (_controller.hasClients) {
      if (_controller.page! > 0) {
        debugPrint('📍 Going to previous page in flow');
        
        // 🔥 IMPORTANT: Clear the role when going back to WelcomeScreen
        setState(() {
          roles = null; // Clear role to show WelcomeScreen
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
                // =====================================================
                // PAGE 0: WELCOME SCREEN (Role Selection)
                // =====================================================
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
                
                // =====================================================
                // PAGE 1: ROLE-SPECIFIC FORMS
                // =====================================================
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
  // 🔥 CREATE PROFILE IN DATABASE
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

      Map<String, dynamic> extraData = {};

      if (roles == 'owner') {
        extraData = {
          'company_name': companyName!.trim(),
          'business_type': 'salon',
          'registration_date': DateTime.now().toIso8601String(),
          'role': 'owner',
        };
        if (phone != null && phone!.isNotEmpty) extraData['phone'] = phone;
      } else if (roles == 'barber') {
        extraData = {
          'full_name': "${firstName!.trim()} ${lastName!.trim()}",
          'first_name': firstName!.trim(),
          'last_name': lastName!.trim(),
          'role': 'barber',
        };
        if (phone != null && phone!.isNotEmpty) extraData['phone'] = phone;
      } else {
        extraData = {
          'full_name': "${firstName!.trim()} ${lastName!.trim()}",
          'first_name': firstName!.trim(),
          'last_name': lastName!.trim(),
          'registered_at': DateTime.now().toIso8601String(),
          'role': 'customer',
        };
        if (phone != null && phone!.isNotEmpty) extraData['phone'] = phone;
      }

      String dbRole;
      if (roles == 'owner') {
        dbRole = 'owner';
      } else if (roles == 'barber') {
        dbRole = 'barber';
      } else {
        dbRole = 'customer';
      }

      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', dbRole)
          .maybeSingle();

      if (roleResponse == null) {
        throw Exception('Role "$dbRole" not found in database');
      }

      final roleId = roleResponse['id'];

      String platform = 'mobile';
      if (isWeb) {
        platform = 'web';
      } else if (isAndroid) {
        platform = 'android';
      } else if (isIOS) {
        platform = 'ios';
      }

      final existingCombination = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .eq('role_id', roleId)
          .maybeSingle();

      final allProfiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('id', user.id)
          .eq('is_active', true);

      List<String> existingRoleNames = [];
      for (var profile in allProfiles) {
        final role = profile['roles'] as Map?;
        if (role != null && role['name'] != null) {
          existingRoleNames.add(role['name'].toString());
        }
      }

      if (existingCombination != null) {
        debugPrint('🔄 Updating existing profile for role: $dbRole');

        final existingExtraData =
            existingCombination['extra_data'] as Map<String, dynamic>? ?? {};

        final mergedExtraData = {
          ...existingExtraData,
          ...extraData,
          'updated_at': DateTime.now().toIso8601String(),
        };

        await supabase
            .from('profiles')
            .update({
              'extra_data': mergedExtraData,
              'platform': platform,
              'is_active': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id)
            .eq('role_id', roleId);

        if (!existingRoleNames.contains(dbRole)) {
          existingRoleNames.add(dbRole);
        }
      } else {
        debugPrint('➕ Creating new profile for role: $dbRole');

        await supabase.from('profiles').insert({
          'id': user.id,
          'role_id': roleId,
          'extra_data': {
            ...extraData,
            'created_at': DateTime.now().toIso8601String(),
          },
          'platform': platform,
          'is_active': true,
          'is_blocked': false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        existingRoleNames.add(dbRole);
      }

      debugPrint('📝 Updating user metadata with roles: $existingRoleNames');

      final currentMetadata = user.userMetadata ?? {};
      Map<String, dynamic> metadataUpdate = {
        ...currentMetadata,
        'roles': existingRoleNames,
        'current_role': dbRole,
        'profile_created_at': DateTime.now().toIso8601String(),
        'profile_created': true,
        'needs_profile': false,
        'registration_complete': true,
      };

      await supabase.auth.updateUser(UserAttributes(data: metadataUpdate));

      debugPrint('📱 Saving profile to SessionManager');

      String? photoUrl = user.userMetadata?['avatar_url'] ?? 
                         user.userMetadata?['picture'];

      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: roles == 'owner' 
            ? companyName 
            : "${firstName ?? ''} ${lastName ?? ''}".trim(),
        photo: photoUrl,
        roles: existingRoleNames,
        rememberMe: true,
        provider: await _getUserProvider(user, photoUrl),
      );

      await SessionManager.saveCurrentRole(dbRole);
      await appState.refreshState();

      if (mounted) {
        LoadingOverlay.hide();
        setState(() => _isLoading = false);

        String title;
        String message;
        
        if (roles == 'owner') {
          title = "🎉 Business Created!";
          message = "Your business profile has been created.";
        } else if (roles == 'barber') {
          title = "👋 Welcome Barber!";
          message = "Welcome to the team!";
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

        if (mounted) {
          if (existingRoleNames.length > 1 && !_isNewProfile) {
            context.go('/role-selector', extra: {
              'roles': existingRoleNames,
              'email': email,
              'userId': user.id,
            });
          } else {
            _redirectBasedOnRole(dbRole);
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

  Future<String> _getUserProvider(User user, String? photoUrl) async {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.contains('googleusercontent.com')) return 'google';
      if (photoUrl.contains('fbcdn.net') || 
          photoUrl.contains('facebook.com') ||
          photoUrl.contains('platform-lookaside.fbsbx.com')) return 'facebook';
      if (photoUrl.contains('apple.com')) return 'apple';
    }
    
    final provider = user.appMetadata?['provider'];
    if (provider != null) return provider.toString();
    
    return 'email';
  }

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