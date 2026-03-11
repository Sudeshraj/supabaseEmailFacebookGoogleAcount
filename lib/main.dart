import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/firebase_options.dart';
import 'package:flutter_application_1/screens/authantication/command/auth_callback_handler.dart';
import 'package:flutter_application_1/screens/authantication/command/clear_data_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/common_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/data_consent_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/policy_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/registration_flow.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_confirm.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_form.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_request.dart';
import 'package:flutter_application_1/screens/authantication/command/role_selector_screen.dart';
import 'package:flutter_application_1/screens/owner/add_barber_screen.dart';
import 'package:flutter_application_1/screens/owner/add_category_screen.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/environment_manager.dart';

// Screens
import 'screens/authantication/command/splash.dart';
import 'screens/authantication/command/sign_in.dart';
import 'screens/authantication/command/signup_flow.dart';
import 'screens/authantication/command/email_verify_checker.dart';
import 'screens/authantication/command/multi_continue_screen.dart';
import 'screens/dashboard/customer_dashboard.dart';
import 'screens/dashboard/employee_dashboard.dart';
import 'screens/dashboard/owner_dashboard.dart';

// Services
import 'services/network_service.dart';
import 'services/app_state.dart';
import 'services/session_manager.dart';

// Utils
import 'screens/net_disconnect/network_banner.dart';
import 'screens/net_disconnect/verify_invalid.dart';

// ====================
// GLOBAL VARIABLES
// ====================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
late final GoRouter router;
late final AppState appState;
late final EnvironmentManager environment;
String? pendingDeepLink;

// ====================
// ERROR HANDLER
// ====================
void setupErrorHandling() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      print('Uncaught error: $error');
      print('Stack: $stack');
    }
    return true;
  };
}

// ====================
// APP LIFECYCLE
// ====================
class AppLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        appState.refreshState(silent: true);
        _validateSessionOnResume();
        break;
      case AppLifecycleState.paused:
        debugPrint('App backgrounded');
        break;
      default:
        break;
    }
  }
}

Future<void> _validateSessionOnResume() async {
  try {
    await Future.delayed(const Duration(milliseconds: 300));
    await SessionManager.validateAndRefreshSession();

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      final rememberMe = await SessionManager.isRememberMeEnabled();
      if (rememberMe) {
        debugPrint('Attempting auto-login...');
        await appState.attemptAutoLogin();
      }
    }
  } catch (e) {
    debugPrint('Error: $e');
  }
}

// ====================
// 🔥 NEW HELPER FUNCTION - Check local profile
// ====================
// Future<bool> _hasLocalProfile(String? email) async {
//   if (email == null) return false;

//   try {
//     // Check if profile exists in SessionManager
//     final profile = await SessionManager.getProfileByEmail(email);
//     final hasProfile = profile != null && profile.isNotEmpty;

//     debugPrint('📱 Checking local profile for $email: $hasProfile');
//     return hasProfile;
//   } catch (e) {
//     debugPrint('❌ Error checking local profile: $e');
//     return false;
//   }
// }

// ====================
// MAIN METHOD
// ====================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupErrorHandling();

  debugPrint('${DateTime.now()}: Starting application...');

  try {
    // ========== PHASE 1: ENVIRONMENT ==========
    environment = EnvironmentManager();
    await environment.init(flavor: kDebugMode ? 'development' : 'production');

    // ========== PHASE 2: SUPABASE ==========
    await Supabase.initialize(
      url: environment.supabaseUrl,
      anonKey: environment.supabaseAnonKey,
      debug: kDebugMode,
    );

    // ========== PHASE 3: FIREBASE ==========
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ========== PHASE 4: NOTIFICATION SERVICE ==========
    await NotificationService().init();

    // ========== PHASE 5: PLATFORM CONFIG ==========
    await _setupPlatformSpecificConfig();

    // ========== PHASE 6: SERVICES ==========
    await SessionManager.init();

    // ========== PHASE 7: APP STATE ==========
    appState = AppState();
    await appState.initializeApp();

    // ========== PHASE 8: AUTH LISTENER ==========
    _setupAuthStateListener();

    // ========== PHASE 9: ROUTER ==========
    router = _createRouter();

    // ========== PHASE 10: LIFECYCLE ==========
    WidgetsBinding.instance.addObserver(AppLifecycleObserver());

    debugPrint('${DateTime.now()}: Initialization complete');
    runApp(MyApp());
  } catch (e, stackTrace) {
    debugPrint('CRITICAL ERROR: $e');
    debugPrint('Stack: $stackTrace');
    runApp(_ErrorApp(error: e.toString()));
  }
}

// ====================
// FIXED AUTH STATE LISTENER - UPDATED
// ====================

void _setupAuthStateListener() {
  final supabase = Supabase.instance.client;

  supabase.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    // final session = data.session;

    debugPrint('🔐 Auth State Change: $event');

    // Always refresh app state on auth changes
    if (event == AuthChangeEvent.signedIn ||
        event == AuthChangeEvent.signedOut ||
        event == AuthChangeEvent.userUpdated ||
        event == AuthChangeEvent.tokenRefreshed) {
      debugPrint('🔄 Refreshing app state...');
      appState.refreshState();
    }

    // Handle password recovery
    if (event == AuthChangeEvent.passwordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateTo('/reset-password-form');
      });
    }
  });
}

// void _setupAuthStateListener() {
//   final supabase = Supabase.instance.client;
//   bool? lastKnownEmailVerified;
//   bool isRedirecting = false;

//   supabase.auth.onAuthStateChange.listen((data) {
//     final event = data.event;
//     final session = data.session;

//     if (kDebugMode) print('🔐 Auth State Change: $event');

//     if (event == AuthChangeEvent.signedIn && session != null) {
//       final user = session.user;
//       final isEmailVerified = user.emailConfirmedAt != null;

//       debugPrint('User signed in: ${user.email}');
//       lastKnownEmailVerified = isEmailVerified;

//       if (isEmailVerified && !isRedirecting) {
//         isRedirecting = true;
//         WidgetsBinding.instance.addPostFrameCallback((_) async {
//           try {
//             // 🔥 STEP 1: Check if local profile exists
//             final hasLocalProfile = await SessionManager.hasProfile();
//             debugPrint('📱 Has local profile: $hasLocalProfile');

//             // 🔥 STEP 2: If local profile exists, go to continue screen
//             if (hasLocalProfile) {
//               debugPrint('Local profile exists → /continue');
//               _navigateTo('/');
//               return;
//             }

//             // 🔥 STEP 3: No local profile - check database
//             debugPrint('No local profile - checking database...');

//             final profiles = await supabase
//                 .from('profiles')
//                 .select('''
//                   role_id,
//                   is_active,
//                   is_blocked,
//                   roles!inner (
//                     name
//                   )
//                 ''')
//                 .eq('id', user.id)
//                 .eq('is_active', true)
//                 .eq('is_blocked', false);

//             // 🔥 STEP 4: No profiles in DB - go to registration
//             if (profiles.isEmpty) {
//               debugPrint('❌ No profiles in DB - redirecting to /reg');
//               _navigateTo('/reg', extra: user);
//               return;
//             }

//             // 🔥 STEP 5: Extract role names from profiles
//             final List<String> roleNames = [];
//             for (var profile in profiles) {
//               final role = profile['roles'] as Map?;
//               if (role != null && role['name'] != null) {
//                 roleNames.add(role['name'].toString());
//               }
//             }

//             debugPrint('📋 Database roles found: $roleNames');

//             // Save roles to SessionManager
//             await SessionManager.saveUserRoles(
//               email: user.email!,
//               roles: roleNames,
//             );

//             // 🔥 STEP 6: Check if roles exist
//             if (roleNames.isEmpty) {
//               debugPrint('❌ No roles in profiles - redirecting to /reg');
//               _navigateTo('/reg', extra: user);
//               return;
//             }

//             // 🔥 STEP 7: Single role - direct to dashboard
//             if (roleNames.length == 1) {
//               final singleRole = roleNames.first;
//               debugPrint('✅ Single role: $singleRole → /$singleRole');

//               await SessionManager.saveCurrentRole(singleRole);
//               await appState.refreshState();

//               switch (singleRole) {
//                 case 'owner':
//                   _navigateTo('/owner');
//                   break;
//                 case 'barber':
//                   _navigateTo('/barber');
//                   break;
//                 default:
//                   _navigateTo('/customer');
//                   break;
//               }
//               return;
//             }

//             // 🔥 STEP 8: Multiple roles - go to role selector
//             if (roleNames.length > 1) {
//               debugPrint('🔄 Multiple roles: $roleNames → /role-selector');

//               // Don't save any role yet
//               await SessionManager.saveCurrentRole(null);

//               _navigateTo(
//                 '/role-selector',
//                 extra: {
//                   'roles': roleNames,
//                   'email': user.email,
//                   'userId': user.id,
//                 },
//               );
//               return;
//             }

//             _navigateTo('/');
//           } catch (e) {
//             debugPrint('❌ Error checking profile: $e');
//             _navigateTo('/reg', extra: user);
//           } finally {
//             isRedirecting = false;
//           }
//         });
//       }
//     }

//     if (event == AuthChangeEvent.userUpdated && session != null) {
//       final user = session.user;
//       final isEmailVerified = user.emailConfirmedAt != null;

//       if (!(lastKnownEmailVerified ?? false) &&
//           isEmailVerified &&
//           !isRedirecting) {
//         debugPrint('Email just verified!');
//         isRedirecting = true;

//         WidgetsBinding.instance.addPostFrameCallback((_) async {
//           try {
//             // Same logic as above
//             final hasLocalProfile = await SessionManager.hasProfile();

//             if (hasLocalProfile) {
//               _navigateTo('/continue');
//               return;
//             }

//             final profiles = await supabase
//                 .from('profiles')
//                 .select('''
//                   role_id,
//                   is_active,
//                   is_blocked,
//                   roles!inner (
//                     name
//                   )
//                 ''')
//                 .eq('id', user.id)
//                 .eq('is_active', true)
//                 .eq('is_blocked', false);

//             if (profiles.isEmpty) {
//               debugPrint('No profiles in DB - redirecting to /reg');
//               _navigateTo('/reg', extra: user);
//               return;
//             }

//             final List<String> roleNames = [];
//             for (var profile in profiles) {
//               final role = profile['roles'] as Map?;
//               if (role != null && role['name'] != null) {
//                 roleNames.add(role['name'].toString());
//               }
//             }

//             await SessionManager.saveUserRoles(
//               email: user.email!,
//               roles: roleNames,
//             );

//             if (roleNames.isEmpty) {
//               _navigateTo('/reg', extra: user);
//               return;
//             }

//             if (roleNames.length == 1) {
//               final singleRole = roleNames.first;
//               await SessionManager.saveCurrentRole(singleRole);
//               await appState.refreshState();

//               switch (singleRole) {
//                 case 'owner':
//                   _navigateTo('/owner');
//                   break;
//                 case 'barber':
//                   _navigateTo('/barber');
//                   break;
//                 default:
//                   _navigateTo('/customer');
//                   break;
//               }
//               return;
//             }

//             if (roleNames.length > 1) {
//               debugPrint('Multiple roles - showing role selector');
//               await SessionManager.saveCurrentRole(null);
//               _navigateTo(
//                 '/role-selector',
//                 extra: {
//                   'roles': roleNames,
//                   'email': user.email,
//                   'userId': user.id,
//                 },
//               );
//               return;
//             }

//             _navigateTo('/');
//           } catch (e) {
//             debugPrint('Error: $e');
//             _navigateTo('/reg', extra: user);
//           } finally {
//             isRedirecting = false;
//           }
//         });
//       }
//       lastKnownEmailVerified = isEmailVerified;
//     }

//     if (event == AuthChangeEvent.passwordRecovery) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _navigateTo('/reset-password-form');
//       });
//     }

//     if (event == AuthChangeEvent.signedOut) {
//       debugPrint('User signed out');
//       lastKnownEmailVerified = null;
//       isRedirecting = false;
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         appState.refreshState();
//       });
//     }
//   });

//   // Check current user on app start

//   final currentUser = supabase.auth.currentUser;
//   if (currentUser != null && !isRedirecting) {
//     lastKnownEmailVerified = currentUser.emailConfirmedAt != null;
//     if (lastKnownEmailVerified == true) {
//       isRedirecting = true;
//       WidgetsBinding.instance.addPostFrameCallback((_) async {
//         try {
//           // 🔥 IMPORTANT: Check current route first
//           final currentRoute =
//               router.routerDelegate.currentConfiguration.last.matchedLocation;

//           // If already on a dashboard, don't redirect
//           if (currentRoute == '/owner' ||
//               currentRoute == '/barber' ||
//               currentRoute == '/customer') {
//             debugPrint(
//               'Already on dashboard: $currentRoute - skipping app start check',
//             );
//             isRedirecting = false;
//             return;
//           }

//           // If already on continue screen, don't redirect again
//           if (currentRoute == '/continue') {
//             debugPrint('Already on continue screen - skipping app start check');
//             isRedirecting = false;
//             return;
//           }

//           final hasLocalProfile = await SessionManager.hasProfile();

//           if (hasLocalProfile) {
//             debugPrint('App start - local profile exists → /continue');
//             debugPrint(currentRoute);
//             if (currentRoute == '/reg') {
//               final savedRole = await SessionManager.getCurrentRole();
//               switch (savedRole) {
//                 case 'owner':
//                   _navigateTo('/owner');
//                   break;
//                 case 'barber':
//                   _navigateTo('/barber');
//                   break;
//                 default:
//                   _navigateTo('/customer');
//                   break;
//               }
//               return;
//             }
//             _navigateTo('/continue');
//             return;
//           }

//           final profiles = await supabase
//               .from('profiles')
//               .select('''
//               role_id,
//               is_active,
//               is_blocked,
//               roles!inner (
//                 name
//               )
//             ''')
//               .eq('id', currentUser.id)
//               .eq('is_active', true)
//               .eq('is_blocked', false);

//           if (profiles.isEmpty) {
//             debugPrint('App start - No profiles in DB → /reg');
//             _navigateTo('/reg', extra: currentUser);
//             return;
//           }

//           final List<String> roleNames = [];
//           for (var profile in profiles) {
//             final role = profile['roles'] as Map?;
//             if (role != null && role['name'] != null) {
//               roleNames.add(role['name'].toString());
//             }
//           }

//           await SessionManager.saveUserRoles(
//             email: currentUser.email!,
//             roles: roleNames,
//           );

//           if (roleNames.isEmpty) {
//             debugPrint('App start - No roles in profiles → /reg');
//             _navigateTo('/reg', extra: currentUser);
//             return;
//           }

//           if (roleNames.length == 1) {
//             final singleRole = roleNames.first;
//             debugPrint('App start - Single role: $singleRole → /$singleRole');
//             await SessionManager.saveCurrentRole(singleRole);
//             await appState.refreshState();

//             switch (singleRole) {
//               case 'owner':
//                 _navigateTo('/owner');
//                 break;
//               case 'barber':
//                 _navigateTo('/barber');
//                 break;
//               default:
//                 _navigateTo('/customer');
//                 break;
//             }
//             return;
//           }

//           if (roleNames.length > 1) {
//             debugPrint(
//               'App start - Multiple roles: $roleNames → /role-selector',
//             );
//             await SessionManager.saveCurrentRole(null);
//             _navigateTo(
//               '/role-selector',
//               extra: {
//                 'roles': roleNames,
//                 'email': currentUser.email,
//                 'userId': currentUser.id,
//               },
//             );
//             return;
//           }

//           _navigateTo('/');
//         } catch (e) {
//           debugPrint('Error checking profile on start: $e');
//           _navigateTo('/reg', extra: currentUser);
//         } finally {
//           isRedirecting = false;
//         }
//       });
//     }
//   }
// }

// Helper method for navigation
// Helper method for navigation
void _navigateTo(String location, {Object? extra}) {
  // Check if we're already on this route
  try {
    final currentRoute =
        router.routerDelegate.currentConfiguration.last.matchedLocation;

    // Don't navigate if already on the same route
    if (currentRoute == location) {
      debugPrint('Already on $location - skipping navigation');
      return;
    }

    // Don't redirect if already on a dashboard
    if ((currentRoute == '/owner' ||
            currentRoute == '/barber' ||
            currentRoute == '/customer') &&
        (location == '/continue' || location == '/role-selector')) {
      debugPrint('Already on dashboard - staying here');
      return;
    }
  } catch (e) {
    // Ignore error
  }

  if (router.canPop()) {
    router.go(location, extra: extra);
  } else {
    router.pushReplacement(location, extra: extra);
  }
}

// ====================
// PLATFORM CONFIG
// ====================
Future<void> _setupPlatformSpecificConfig() async {
  if (kIsWeb) {
    debugPrint('Configuring for Web');
    final uri = Uri.base;
    if (uri.toString().contains('/auth/callback')) {
      debugPrint('Web auth callback detected');
    }
  } else {
    debugPrint('Configuring for Mobile');
    await _setupMobileDeepLinks();
  }
}

Future<void> _setupMobileDeepLinks() async {
  try {
    final uri = Uri.base;
    if (uri.toString().isNotEmpty && uri.toString() != '/') {
      if (uri.toString().contains('myapp://') ||
          uri.toString().contains('/auth/callback')) {
        debugPrint('Mobile deep link detected!');
        pendingDeepLink = uri.toString();
      }
    }
  } catch (e) {
    debugPrint('Mobile deep link error: $e');
  }
}

// ====================
// FIXED ROUTER - UPDATED
// ====================
GoRouter _createRouter() {
  return GoRouter(
    navigatorKey: navigatorKey,
    refreshListenable: appState,
    initialLocation: '/',
    debugLogDiagnostics: kDebugMode,
    observers: [if (kDebugMode) MyRouteObserver()],
    redirect: (context, state) async {
      final path = state.matchedLocation;
      final queryParams = state.uri.queryParameters;

      debugPrint('REDIRECT CHECK - Path: $path');
      debugPrint(
        'AppState: loading=${appState.loading}, loggedIn=${appState.loggedIn}',
      );

      // 🔥 PREVENT REDIRECT LOOPS - If already on the target route, don't redirect again
      if (path == '/owner' || path == '/barber' || path == '/customer') {
        debugPrint('Already on dashboard route: $path - no redirect');
        return null;
      }

      // 🔥 NEVER redirect auth callbacks
      if (path == '/auth/callback' ||
          queryParams.containsKey('code') ||
          queryParams.containsKey('access_token')) {
        debugPrint('Auth callback - no redirect');
        return null;
      }

      // AppState loading නම්, කිසිම redirect එකක් එපා
      if (appState.loading) {
        debugPrint('AppState loading - no redirect');
        return null;
      }

      // Clear data screen is always accessible
      if (path == '/clear-data') {
        debugPrint('Clear data screen - allowing access');
        return null;
      }

      final publicRoutes = [
        '/',
        '/login',
        '/signup',
        '/finish',
        '/help',
        '/about',
        '/contact',
        '/data-consent',
        '/continue',
        '/verify-email',
        '/verify-invalid',
        '/privacy',
        '/terms',
        '/reset-password',
        '/reset-password-confirm',
        '/reset-password-form',
        '/auth/callback',
        '/reg',
        '/role-selector',
      ];

      // Role selector route
      if (path == '/role-selector') {
        if (!appState.loggedIn) {
          return '/login';
        }
        return null;
      }

      if (publicRoutes.contains(path)) {
        if (path == '/') {
          // SPLASH SCREEN
          if (appState.loggedIn) {
            // User logged in
            if (!appState.emailVerified) {
              debugPrint('Email not verified → /verify-email');
              return '/verify-email';
            }

            if (!appState.profileCompleted) {
              debugPrint('Profile not completed → /reg');
              return '/reg';
            }

            // Check roles
            if (appState.roles.isEmpty) {
              debugPrint('No roles found → /reg');
              return '/reg';
            }

            if (appState.roles.length > 1) {
              // return '/role-selector';
              // final hasLocalProfile = await _hasLocalProfile(
              //   appState.currentUser?.email,
              // );

              final locationcontinueSc =
                  await SessionManager.isLocationContinuesc();
              if (locationcontinueSc) {
                debugPrint('aa');
                final savedRole = await SessionManager.getCurrentRole();
                switch (savedRole) {
                  case 'owner':
                    return '/owner';

                  case 'barber':
                    return '/barber';

                  default:
                    return '/customer';
                }
              }
              // if (!hasLocalProfile) {
              debugPrint('No local profile found → /role-selector');
              return '/role-selector';
              // } else {
              //   // Has local profile - use saved role
              //   final savedRole = appState.currentRole;
              //   if (savedRole != null && appState.roles.contains(savedRole)) {
              //     debugPrint('Using saved role: $savedRole → /$savedRole');
              //     return '/$savedRole';
              //   }
              // }
            }

            if (appState.roles.length == 1) {
              // Single role - direct redirect
              final role = appState.roles.first;
              debugPrint('Single role: $role → /$role');
              return '/$role';
            }

            //  else {
            //   // Multiple roles - check if local profile exists
            //   final hasLocalProfile = await _hasLocalProfile(
            //     appState.currentUser?.email,
            //   );

            //   if (!hasLocalProfile) {
            //     debugPrint('No local profile found → /role-selector');
            //     return '/role-selector';
            //   } else {
            //     // Has local profile - use saved role
            //     final savedRole = appState.currentRole;
            //     if (savedRole != null && appState.roles.contains(savedRole)) {
            //       debugPrint('Using saved role: $savedRole → /$savedRole');
            //       return '/$savedRole';
            //     } else {
            //       // Fallback to role selector
            //       debugPrint('No saved role → /role-selector');
            //       return '/role-selector';
            //     }
            //   }
            // }
          } else {
            // Not logged in
            final hasProfile = await SessionManager.hasProfile();
            if (hasProfile) {
              debugPrint('Has saved profiles → /continue');
              return '/continue';
            } else {
              debugPrint('No saved profiles → /login');
              return '/login';
            }
          }
        }

        // 🔥 SPECIAL HANDLING FOR /reg
        if (path == '/reg') {
          if (!appState.loggedIn) {
            debugPrint('/reg requires login → redirecting to /login');
            return '/login';
          }
          debugPrint('Allowing access to /reg');
          return null;
        }

        return null;
      }

      // Protected routes
      if (!appState.loggedIn) {
        final hasProfile = await SessionManager.hasProfile();
        if (hasProfile && path != '/continue') {
          return '/continue';
        }
        return '/login';
      }

      if (appState.loggedIn) {
        if (!appState.emailVerified && path != '/verify-email') {
          return '/verify-email';
        }
        if (!appState.profileCompleted && path != '/reg') {
          return '/reg';
        }

        // 🔥 CHECK IF ALREADY ON CORRECT DASHBOARD
        if (path == '/owner' && appState.currentRole == 'owner') {
          debugPrint('Already on owner dashboard - no redirect');
          return null;
        }
        if (path == '/barber' && appState.currentRole == 'barber') {
          debugPrint('Already on barber dashboard - no redirect');
          return null;
        }
        if (path == '/customer' && appState.currentRole == 'customer') {
          debugPrint('Already on customer dashboard - no redirect');
          return null;
        }

        // Wrong dashboard for current role
        if (path == '/owner' && appState.currentRole != 'owner') {
          debugPrint(
            'Wrong dashboard - redirecting to /${appState.currentRole}',
          );
          return '/${appState.currentRole}';
        }
        if (path == '/barber' && appState.currentRole != 'barber') {
          debugPrint(
            'Wrong dashboard - redirecting to /${appState.currentRole}',
          );
          return '/${appState.currentRole}';
        }
        if (path == '/customer' &&
            appState.currentRole != 'customer' &&
            appState.currentRole != null) {
          debugPrint(
            'Wrong dashboard - redirecting to /${appState.currentRole}',
          );
          return '/${appState.currentRole}';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SignInScreen(
            prefilledEmail: extra?['prefilledEmail'] as String?,
            showMessage: extra?['showMessage'] as bool? ?? false,
            message: extra?['message'] as String?,
          );
        },
      ),
      GoRoute(path: '/signup', builder: (_, __) => const SignupFlow()),
      GoRoute(
        path: '/reg',
        name: 'registration',
        pageBuilder: (context, state) {
          debugPrint('📍 /registration route called');

          // Get user from Supabase
          final user = appState.currentUser;

          return MaterialPage(child: RegistrationFlow(user: user));
        },
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const EmailVerifyChecker(),
      ),
      GoRoute(
        path: '/verify-invalid',
        builder: (_, __) => const VerifyInvalidScreen(),
      ),
      GoRoute(path: '/continue', builder: (_, __) => const ContinueScreen()),
      GoRoute(
        path: '/role-selector',
        name: 'roleSelector',
        builder: (context, state) {
          final extra = state.extra as Map?;

          // 🔥 Safely convert roles to List<String>
          final dynamic rolesFromExtra = extra?['roles'];
          List<String> roles = [];

          if (rolesFromExtra != null) {
            if (rolesFromExtra is List<String>) {
              roles = rolesFromExtra;
            } else if (rolesFromExtra is List) {
              // Convert List<dynamic> to List<String>
              roles = rolesFromExtra.map((e) => e.toString()).toList();
            }
          }

          // If no roles in extra, use appState.roles
          if (roles.isEmpty) {
            roles = appState.roles;
          }

          final email =
              extra?['email'] as String? ?? appState.currentEmail ?? '';
          final userId =
              extra?['userId'] as String? ?? appState.currentUser?.id ?? '';

          return RoleSelectorScreen(roles: roles, email: email, userId: userId);
        },
      ),
      GoRoute(path: '/customer', builder: (_, __) => const CustomerDashboard()),
      GoRoute(path: '/barber', builder: (_, __) => const EmployeeDashboard()),
      GoRoute(path: '/owner', builder: (_, __) => const OwnerDashboard()),
      GoRoute(
        path: '/privacy',
        builder: (context, state) {
          return const PolicyScreen(isPrivacyPolicy: true);
        },
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) {
          return const PolicyScreen(isPrivacyPolicy: false);
        },
      ),
      GoRoute(
        path: '/help',
        builder: (_, __) => const HelpScreen(screenType: 'help'),
      ),
      GoRoute(
        path: '/contact',
        builder: (_, __) => const HelpScreen(screenType: 'contact'),
      ),
      GoRoute(
        path: '/about',
        builder: (_, __) => const HelpScreen(screenType: 'about'),
      ),
      GoRoute(path: '/clear-data', builder: (_, __) => const ClearDataScreen()),
      GoRoute(
        path: '/data-consent',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return DataConsentScreen(
            email: extra?['email'] as String? ?? '',
            password: extra?['password'] as String? ?? '',
            source: extra?['source'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (context, state) {
          return MaterialPage(
            key: state.pageKey,
            child: AuthCallbackHandlerScreen(
              code: state.uri.queryParameters['code'],
              error: state.uri.queryParameters['error'],
              errorCode: state.uri.queryParameters['error_code'],
              errorDescription: state.uri.queryParameters['error_description'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => const ResetPasswordRequestScreen(),
      ),
      GoRoute(
        path: '/reset-password-form',
        builder: (_, __) => const ResetPasswordFormScreen(),
      ),
      GoRoute(
        path: '/reset-password-confirm',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResetPasswordConfirmScreen(email: extra?['email'] ?? '');
        },
      ),
      GoRoute(
        path: '/owner/add-barber',
        name: 'addBarber',
        pageBuilder: (context, state) =>
            MaterialPage(child: const AddBarberScreen()),
      ),
      GoRoute(
        path: '/owner/categories/add',
        name: 'addCategory',
        pageBuilder: (context, state) =>
            MaterialPage(child: const AddCategoryScreen()),
      ),
    ],
  );
}

// ====================
// MAIN APP
// ====================
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final NetworkService _networkService;
  StreamSubscription<bool>? _networkSub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _initNetworkMonitoring();
  }

  void _initNetworkMonitoring() {
    _networkService = NetworkService();
    _networkSub = _networkService.onStatusChange.listen((online) {
      if (mounted) setState(() => _offline = !online);
    });
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _networkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            AbsorbPointer(
              absorbing: _offline,
              child: child ?? const SizedBox(),
            ),
            if (_offline)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: NetworkBanner(offline: _offline)),
              ),
          ],
        );
      },
    );
  }
}

// ====================
// ERROR APP
// ====================
class _ErrorApp extends StatelessWidget {
  final String error;
  const _ErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  'Unable to Start App',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Text('Restart App'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ====================
// ROUTE OBSERVER
// ====================
class MyRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) debugPrint('🚀 Pushed: ${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) debugPrint('🔙 Popped: ${route.settings.name}');
  }
}
