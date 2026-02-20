import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/common_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/business_reg/company_name_screen.dart';
import 'package:flutter_application_1/screens/authantication/customer_reg/name_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/welcome.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/main.dart'; // For router & appState
import 'package:flutter_application_1/services/session_manager.dart';

class RegistrationFlow extends StatefulWidget {
  final User? user;

  const RegistrationFlow({super.key, this.user});

  @override
  State<RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends State<RegistrationFlow> {
  final PageController _controller = PageController();

  // ---- PLATFORM DETECTION ----
  bool get isWeb => UniversalPlatform.isWeb;
  bool get isMobile => !isWeb;
  bool get isAndroid => UniversalPlatform.isAndroid;
  bool get isIOS => UniversalPlatform.isIOS;

  // ---- SELECTED ROLE ----
  String? roles; // 'owner' or 'employee'

  // ---- NAME FIELDS ----
  String? firstName;
  String? lastName;

  // ---- BUSINESS FIELD ----
  String? companyName;
  String? phone;

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  void _checkUser() {
    if (widget.user != null) {
      print('📱 RegistrationFlow for: ${widget.user!.email}');
    } else {
      print('⚠️ No user passed to RegistrationFlow');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/login');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // ===============================================================
          // STEP 1: SELECT ROLE
          // ===============================================================
          WelcomeScreen(
            onNext: (selectedRole) {
              setState(() {
                roles = selectedRole;
              });
              _nextPage();
            },
          ),

          // ===============================================================
          // CUSTOMER FLOW
          // ===============================================================
          if (roles == 'employee') ..._buildCustomerFlow(),

          // ===============================================================
          // BUSINESS FLOW
          // ===============================================================
          if (roles == 'owner') ..._buildBusinessFlow(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // CUSTOMER FLOW
  // -----------------------------------------------------------------------
  List<Widget> _buildCustomerFlow() => [
    NameEntry(
      onNext: (f, l) {
        setState(() {
          firstName = f;
          lastName = l;
        });
        _createProfile();
      },
      controller: _controller,
    ),
  ];

  // -----------------------------------------------------------------------
  // BUSINESS FLOW
  // -----------------------------------------------------------------------
  List<Widget> _buildBusinessFlow() => [
    CompanyNameScreen(
      onNext: (n) {
        setState(() => companyName = n);
        _createProfile();
      },
      controller: _controller,
    ),
  ];

  // ===============================================================
  // 🔥 CREATE PROFILE IN DATABASE (UPDATED FOR MULTIPLE ROLES)
  // ===============================================================
  Future<void> _createProfile() async {
    // Early exit if widget is unmounted
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

    // ✅ Check required fields based on role
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
    } else if (roles == 'employee') {
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

    // Check if mounted before showing overlay
    if (!mounted) return;
    LoadingOverlay.show(context, message: "Setting up your profile...");

    try {
      final supabase = Supabase.instance.client;

      // 🔥 Prepare extra_data based on role
      Map<String, dynamic> extraData = {};

      if (roles == 'owner') {
        extraData = {
          'company_name': companyName!.trim(),
          'business_type': 'salon',
          'registration_date': DateTime.now().toIso8601String(),
        };

        if (phone != null && phone!.isNotEmpty) {
          extraData['phone'] = phone;
        }
      } else if (roles == 'employee') {
        extraData = {
          'full_name': "${firstName!.trim()} ${lastName!.trim()}",
          'first_name': firstName!.trim(),
          'last_name': lastName!.trim(),
        };

        if (phone != null && phone!.isNotEmpty) {
          extraData['phone'] = phone;
        }
      } else {
        // Customer role
        extraData = {
          'full_name': firstName != null && lastName != null
              ? "${firstName!.trim()} ${lastName!.trim()}"
              : 'Customer',
          'registered_at': DateTime.now().toIso8601String(),
        };

        if (phone != null && phone!.isNotEmpty) {
          extraData['phone'] = phone;
        }
      }

      // 🔥 Map selected role to database role
      String dbRole;
      if (roles == 'owner') {
        dbRole = 'owner';
      } else if (roles == 'employee') {
        dbRole = 'employee';
      } else {
        dbRole = 'customer';
      }

      print('🔍 Selected role: $roles → Database role: $dbRole');
      print('📦 Extra data: $extraData');

      // 🔥 Get role ID from roles table
      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', dbRole)
          .maybeSingle();

      if (roleResponse == null) {
        throw Exception('Role "$dbRole" not found in database');
      }

      final roleId = roleResponse['id'];

      // 🔥 Platform detection
      String platform = 'mobile';
      if (isWeb) {
        platform = 'web';
      } else if (isAndroid) {
        platform = 'android';
      } else if (isIOS) {
        platform = 'ios';
      }

      print(
        '🔍 Checking if profile exists for User ID: ${user.id} and Role ID: $roleId',
      );

      // Check if profile with this specific role already exists
      final existingProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .eq('role_id', roleId)
          .maybeSingle();

      print('📊 Existing profile query result: $existingProfile');

      // ============================================================
      // 🔥🔥🔥 STEP 1: Get all existing roles for this user 🔥🔥🔥
      // ============================================================
      final allProfiles = await supabase
          .from('profiles')
          .select('''
            role_id,
            roles!inner (
              name
            )
          ''')
          .eq('id', user.id)
          .eq('is_active', true)
          .eq('is_blocked', false);

      // Extract existing role names
      List<String> existingRoleNames = [];
      for (var profile in allProfiles) {
        final role = profile['roles'] as Map?;
        if (role != null && role['name'] != null) {
          existingRoleNames.add(role['name'].toString());
        }
      }

      print('📋 Existing roles before registration: $existingRoleNames');

      if (existingProfile != null) {
        // ============================================================
        // 🔄 UPDATE EXISTING PROFILE
        // ============================================================
        print(
          '⚠️ Profile already exists for this user and role - updating instead',
        );

        final existingExtraData =
            existingProfile['extra_data'] as Map<String, dynamic>? ?? {};

        existingExtraData.addAll(extraData);

        await supabase
            .from('profiles')
            .update({
              'extra_data': existingExtraData,
              'platform': platform,
              'is_active': true,
            })
            .eq('id', user.id)
            .eq('role_id', roleId);

        print('✅ Profile updated for ${user.email} with role: $dbRole');
        
        // Add to existing role names if not already present
        if (!existingRoleNames.contains(dbRole)) {
          existingRoleNames.add(dbRole);
        }
      } else {
        // ============================================================
        // 🆕 CREATE NEW PROFILE
        // ============================================================
        print(
          '🆕 No profile found for this user and role - creating new profile',
        );

        // Insert new profile
        await supabase.from('profiles').insert({
          'id': user.id,
          'extra_data': extraData,
          'role_id': roleId,
          'fcm_token': null,
          'platform': platform,
          'is_active': true,
          'is_blocked': false,
        });

        print('✅ New profile created for ${user.email} with role: $dbRole');
        
        // Add to existing role names
        existingRoleNames.add(dbRole);
      }

      // ============================================================
      // 🔥🔥🔥 STEP 2: Update auth.users metadata with ALL roles 🔥🔥🔥
      // ============================================================
      
      // Get current metadata
      final currentMetadata = user.userMetadata ?? {};
      
      // Prepare metadata update with all roles
      Map<String, dynamic> metadataUpdate = {
        ...currentMetadata,
        'roles': existingRoleNames, // 👈 Store ALL roles
        'current_role': dbRole,      // 👈 Store current role
        'profile_created_at': DateTime.now().toIso8601String(),
        'profile_created': true,
        'needs_profile': false,
        'registration_complete': true,
      };

      print('📝 Updating auth metadata with ALL roles: $metadataUpdate');

      await supabase.auth.updateUser(UserAttributes(data: metadataUpdate));

      print('✅ Auth user metadata updated with roles: $existingRoleNames');

      // ============================================================
      // 🔥🔥🔥 STEP 3: Update SessionManager 🔥🔥🔥
      // ============================================================
      
      // Save all roles to SessionManager
      await SessionManager.saveUserRoles(
        email: email,
        roles: existingRoleNames,
      );

      // Save current role
      await SessionManager.saveCurrentRole(dbRole);

      // ============================================================
      // 🔥🔥🔥 STEP 4: Refresh app state 🔥🔥🔥
      // ============================================================
      
      await appState.refreshState();

      // Check if mounted before showing success message and redirecting
      if (mounted) {
        // Hide loading overlay first
        LoadingOverlay.hide();

        // Show role-specific success message
        String message;
        if (roles == 'owner') {
          message = isWeb
              ? "Your business profile has been created. You can now manage your salon."
              : "Welcome to MySalon Business! Start managing your salon today.";
        } else if (roles == 'employee') {
          message =
              "Welcome to the team! Your employee profile has been created.";
        } else {
          message = isWeb
              ? "Your profile has been created. You can now enable notifications."
              : "Welcome to MySalon! Your profile has been created successfully.";
        }

        await showCustomAlert(
          context: context,
          title: roles == 'owner'
              ? "🎉 Business Created!"
              : roles == 'employee'
              ? "👋 Welcome Employee!"
              : "🎉 Welcome to MySalon!",
          message: message,
          isError: false,
        );

        // 🔥 ROLE-BASED REDIRECT
        if (mounted) {
          // Check if user has multiple roles
          if (existingRoleNames.length > 1) {
            // Show role selector for multiple roles
            print('🔄 Multiple roles detected - showing role selector');
            context.go('/role-selector', extra: {
              'roles': existingRoleNames,
              'email': email,
              'userId': user.id,
            });
          } else {
            // Single role - direct redirect
            _redirectBasedOnRole(dbRole);
          }
        }
      }
    } catch (e) {
      print('❌ Profile creation error: $e');

      // If profile creation fails, update metadata to indicate incomplete
      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'registration_complete': false,
              'registration_error': e.toString(),
            },
          ),
        );
      } catch (metaError) {
        print('❌ Failed to update error metadata: $metaError');
      }

      if (mounted) {
        LoadingOverlay.hide();
        await showCustomAlert(
          context: context,
          title: "Error",
          message: "Failed to create profile: ${e.toString()}",
          isError: true,
        );
      }
    } finally {
      // Ensure overlay is hidden
      if (mounted) {
        LoadingOverlay.hide();
      }
    }
  }

  // Updated redirect method
  void _redirectBasedOnRole(String role) {
    if (!mounted) return;

    switch (role) {
      case 'owner':
        context.go('/owner');
        break;
      case 'employee':
        context.go('/employee');
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