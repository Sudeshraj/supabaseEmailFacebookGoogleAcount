import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/screens/authantication/business_reg/company_name_screen.dart';
import 'package:flutter_application_1/screens/authantication/customer_reg/name_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/welcome.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/screens/authantication/functions/loading_overlay.dart';
import 'package:flutter_application_1/main.dart'; // For router & appState

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
  String? roles; // 'Owner' or 'Employee'
  // List<String> roles = [];

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

  // @override
  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     body: PageView(
  //       controller: _controller,
  //       physics: const NeverScrollableScrollPhysics(),
  //       children: [
  //         // STEP 1: SELECT ROLE
  //         WelcomeScreen(
  //           onNext: (role) {
  //             setState(() {
  //               selectedRole = role;
  //             });
  //             _nextPage();
  //           },
  //         ),

  //         // STEP 2: NAME ENTRY
  //         NameEntry(
  //           onNext: (f, l) {
  //             setState(() {
  //               firstName = f;
  //               lastName = l;
  //             });

  //             // If Owner, go to company name
  //             if (selectedRole == 'employee') {
  //               _nextPage();
  //             } else {
  //               // If Employee, directly create profile
  //               _createProfile();
  //             }
  //           },
  //           controller: _controller,
  //         ),

  //         // STEP 3: COMPANY NAME (Only for Owner)
  //         if (selectedRole == 'owner')
  //           CompanyNameScreen(
  //             onNext: (n) {
  //               setState(() {
  //                 companyName = n;
  //               });
  //               _createProfile();
  //             },
  //             controller: _controller,
  //           ),
  //       ],
  //     ),
  //   );
  // }

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
        // _nextPage();
        _createProfile();
      },
      controller: _controller,
    ),
    // EmailScreen(
    //   onNext: (e) {
    //     setState(() => email = e);
    //     _nextPage();
    //   },
    //   controller: _controller,
    // ),

    // FinishScreen(
    //   controller: _controller,
    //   onSignUp: () async => _handleRegistration(),
    // ),
  ];

  // -----------------------------------------------------------------------
  // BUSINESS FLOW
  // -----------------------------------------------------------------------
  List<Widget> _buildBusinessFlow() => [
    CompanyNameScreen(
      onNext: (n) {
        setState(() => companyName = n);
        // _nextPage();
        _createProfile();
      },
      controller: _controller,
    ),

    // FinishScreen(
    //   controller: _controller,
    //   onSignUp: () async => _handleRegistration(),
    // ),
  ];

  // ===============================================================
  // 🔥 CREATE PROFILE IN DATABASE (NO EMAIL FIELD)
  // ===============================================================
  Future<void> _createProfile() async {
    // Early exit if widget is unmounted
    if (!mounted) return;

    final user = widget.user;
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

      final existingProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .eq('role_id', roleId)
          .maybeSingle();

      print('📊 Existing profile query result: $existingProfile');

      if (existingProfile != null) {
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
      } else {
        print(
          '🆕 No profile found for this user and role - creating new profile',
        );

        final anyProfile = await supabase
            .from('profiles')
            .select('role_id')
            .eq('id', user.id)
            .maybeSingle();

        if (anyProfile != null) {
          print(
            '⚠️ User already has a profile with different role: ${anyProfile['role_id']}',
          );
        }

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
      }

      // 🔥 Update app state with new role
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
        } else {
          message = isWeb
              ? "Your profile has been created. You can now enable notifications."
              : "Welcome to MySalon! Your profile has been created successfully.";
        }

        await showCustomAlert(
          context: context,
          title: roles == 'owner'
              ? "🎉 Business Created!"
              : "🎉 Welcome to MySalon!",
          message: message,
          isError: false,
        );

        // 🔥 REDIRECT BASED ON ROLE (pass User object, not Map)
        if (mounted) {
          _redirectBasedOnRole(dbRole, user); // Pass the user object
        }
      }
    } catch (e) {
      print('❌ Profile creation error: $e');
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

  // Updated redirect method to accept User object
  void _redirectBasedOnRole(String role, User user) {
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
