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
import 'screens/home/customer_home.dart';
import 'screens/home/employee_dashboard.dart';
import 'screens/home/owner_dashboard.dart';

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
      print('❌ Uncaught error: $error');
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
        print('📱 App backgrounded');
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
        print('🔄 Attempting auto-login...');
        await appState.attemptAutoLogin();
      }
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}

// ====================
// MAIN METHOD
// ====================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupErrorHandling();

  print('🚀 ${DateTime.now()}: Starting application...');

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

    print('✅ ${DateTime.now()}: Initialization complete');
    runApp(MyApp());
  } catch (e, stackTrace) {
    print('❌❌❌ CRITICAL ERROR: $e');
    print('Stack: $stackTrace');
    runApp(_ErrorApp(error: e.toString()));
  }
}

// ====================
// ✅ FIXED AUTH STATE LISTENER
// ====================
void _setupAuthStateListener() {
  final supabase = Supabase.instance.client;
  bool? lastKnownEmailVerified;
  bool _isRedirecting = false; // Prevent multiple redirects

  supabase.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    final session = data.session;

    if (kDebugMode) print('🔐 Auth State Change: $event');

    if (event == AuthChangeEvent.signedIn && session != null) {
      final user = session.user;
      final isEmailVerified = user.emailConfirmedAt != null;

      print('🎉 User signed in: ${user.email}');
      lastKnownEmailVerified = isEmailVerified;

      if (isEmailVerified && !_isRedirecting) {
        _isRedirecting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            // ✅ FIXED: Get ALL profiles with role names
            final profiles = await supabase
                .from('profiles')
                .select('''
                  role_id,
                  is_active,
                  is_blocked,
                  roles!inner (
                    name
                  )
                ''')
                .eq('id', user.id)
                .eq('is_active', true)
                .eq('is_blocked', false);

            if (profiles.isEmpty) {
              print('📍 No active profiles - redirecting to /reg');
              _navigateTo('/reg', extra: user);
              return;
            }

            // ✅ Extract ALL role names
            final List<String> roleNames = [];
            for (var profile in profiles) {
              final role = profile['roles'] as Map?;
              if (role != null && role['name'] != null) {
                roleNames.add(role['name'].toString());
              }
            }

            print('📋 User roles: $roleNames');

            // ✅ Save to SessionManager
            await SessionManager.saveUserRoles(
              email: user.email!,
              roles: roleNames,
            );

            if (roleNames.isEmpty) {
              _navigateTo('/reg', extra: user);
              return;
            }

            // ✅ Get saved current role if any
            String? savedRole = await SessionManager.getCurrentRole();

            // ✅ If single role, redirect directly
            if (roleNames.length == 1) {
              final singleRole = roleNames.first;
              await SessionManager.saveCurrentRole(singleRole);
              await appState.refreshState();
              
              switch (singleRole) {
                case 'owner':
                  _navigateTo('/owner');
                  break;
                case 'employee':
                  _navigateTo('/employee');
                  break;
                default:
                  _navigateTo('/customer');
                  break;
              }
              return;
            }

            // ✅ If multiple roles
            if (roleNames.length > 1) {
              // If saved role exists and is valid, use it
              if (savedRole != null && roleNames.contains(savedRole)) {
                print('📌 Using saved role: $savedRole');
                await SessionManager.saveCurrentRole(savedRole);
                await appState.refreshState();
                
                switch (savedRole) {
                  case 'owner':
                    _navigateTo('/owner');
                    break;
                  case 'employee':
                    _navigateTo('/employee');
                    break;
                  default:
                    _navigateTo('/customer');
                    break;
                }
                return;
              }
              
              // Otherwise show role selector
              print('🔄 Multiple roles - showing role selector');
              _navigateTo('/role-selector', extra: {
                'roles': roleNames,
                'email': user.email,
                'userId': user.id,
              });
              return;
            }

            // Fallback
            _navigateTo('/');
            
          } catch (e) {
            print('❌ Error checking profile: $e');
            _navigateTo('/reg', extra: user);
          } finally {
            _isRedirecting = false;
          }
        });
      }
    }

    if (event == AuthChangeEvent.userUpdated && session != null) {
      final user = session.user;
      final isEmailVerified = user.emailConfirmedAt != null;

      if (!(lastKnownEmailVerified ?? false) &&
          isEmailVerified &&
          !_isRedirecting) {
        print('✅ Email just verified!');
        _isRedirecting = true;

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final profiles = await supabase
                .from('profiles')
                .select('''
                  role_id,
                  is_active,
                  is_blocked,
                  roles!inner (
                    name
                  )
                ''')
                .eq('id', user.id)
                .eq('is_active', true)
                .eq('is_blocked', false);

            if (profiles.isEmpty) {
              _navigateTo('/reg', extra: user);
              return;
            }

            final List<String> roleNames = [];
            for (var profile in profiles) {
              final role = profile['roles'] as Map?;
              if (role != null && role['name'] != null) {
                roleNames.add(role['name'].toString());
              }
            }

            await SessionManager.saveUserRoles(
              email: user.email!,
              roles: roleNames,
            );

            if (roleNames.isEmpty) {
              _navigateTo('/reg', extra: user);
            } else if (roleNames.length == 1) {
              final singleRole = roleNames.first;
              await SessionManager.saveCurrentRole(singleRole);
              await appState.refreshState();
              
              switch (singleRole) {
                case 'owner':
                  _navigateTo('/owner');
                  break;
                case 'employee':
                  _navigateTo('/employee');
                  break;
                default:
                  _navigateTo('/customer');
                  break;
              }
            } else {
              _navigateTo('/role-selector', extra: {
                'roles': roleNames,
                'email': user.email,
                'userId': user.id,
              });
            }
          } catch (e) {
            print('❌ Error: $e');
            _navigateTo('/reg', extra: user);
          } finally {
            _isRedirecting = false;
          }
        });
      }
      lastKnownEmailVerified = isEmailVerified;
    }

    if (event == AuthChangeEvent.passwordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateTo('/reset-password-form');
      });
    }

    if (event == AuthChangeEvent.signedOut) {
      print('👋 User signed out');
      lastKnownEmailVerified = null;
      _isRedirecting = false;
    }
  });

  // Check current user on app start
  final currentUser = supabase.auth.currentUser;
  if (currentUser != null && !_isRedirecting) {
    lastKnownEmailVerified = currentUser.emailConfirmedAt != null;
    if (lastKnownEmailVerified == true) {
      _isRedirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('''
                role_id,
                is_active,
                is_blocked,
                roles!inner (
                  name
                )
              ''')
              .eq('id', currentUser.id)
              .eq('is_active', true)
              .eq('is_blocked', false);

          if (profiles.isEmpty) {
            _navigateTo('/reg', extra: currentUser);
            return;
          }

          final List<String> roleNames = [];
          for (var profile in profiles) {
            final role = profile['roles'] as Map?;
            if (role != null && role['name'] != null) {
              roleNames.add(role['name'].toString());
            }
          }

          await SessionManager.saveUserRoles(
            email: currentUser.email!,
            roles: roleNames,
          );

          if (roleNames.isEmpty) {
            _navigateTo('/reg', extra: currentUser);
          } else if (roleNames.length == 1) {
            final singleRole = roleNames.first;
            await SessionManager.saveCurrentRole(singleRole);
            await appState.refreshState();
            
            switch (singleRole) {
              case 'owner':
                _navigateTo('/owner');
                break;
              case 'employee':
                _navigateTo('/employee');
                break;
              default:
                _navigateTo('/customer');
                break;
            }
          } else {
            _navigateTo('/role-selector', extra: {
              'roles': roleNames,
              'email': currentUser.email,
              'userId': currentUser.id,
            });
          }
        } catch (e) {
          print('❌ Error checking profile on start: $e');
          _navigateTo('/reg', extra: currentUser);
        } finally {
          _isRedirecting = false;
        }
      });
    }
  }
}

// Helper method for navigation
void _navigateTo(String location, {Object? extra}) {
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
    print('🌐 Configuring for Web');
    final uri = Uri.base;
    if (uri.toString().contains('/auth/callback')) {
      print('   🔥 Web auth callback detected');
    }
  } else {
    print('📱 Configuring for Mobile');
    await _setupMobileDeepLinks();
  }
}

Future<void> _setupMobileDeepLinks() async {
  try {
    final uri = Uri.base;
    if (uri.toString().isNotEmpty && uri.toString() != '/') {
      if (uri.toString().contains('myapp://') ||
          uri.toString().contains('/auth/callback')) {
        print('   📱 Mobile deep link detected!');
        pendingDeepLink = uri.toString();
      }
    }
  } catch (e) {
    print('   ❌ Mobile deep link error: $e');
  }
}

// ====================
// ✅ FIXED ROUTER
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

      // 🔥 NEVER redirect auth callbacks
      if (path == '/auth/callback' ||
          queryParams.containsKey('code') ||
          queryParams.containsKey('access_token')) {
        return null;
      }

      if (appState.loading) return null;

      final publicRoutes = [
        '/',
        '/login',
        '/signup',
        '/continue',
        '/verify-email',
        '/verify-invalid',
        '/privacy',
        '/terms',
        '/reset-password',
        '/reset-password-form',
        '/reset-password-confirm',
        '/auth/callback',
        '/help',
        '/about',
        '/contact',
        '/data-consent',
      ];

      // ✅ FIXED: Role selector route
      final roleRoutes = ['/role-selector', '/owner', '/employee', '/customer'];

      // 🔥 SPECIAL HANDLING FOR /reg
      if (path == '/reg') {
        final user = state.extra as User?;
        if (user == null) {
          print('⚠️ /reg accessed without user → redirecting to /login');
          return '/login';
        }
        return null;
      }

      // ✅ FIXED: Role selector route
      if (path == '/role-selector') {
        // Only allow if logged in and has multiple roles
        if (!appState.loggedIn) {
          return '/login';
        }
        if (appState.roles.length <= 1) {
          // If only one role, redirect to that role's dashboard
          if (appState.roles.isNotEmpty) {
            final role = appState.roles.first;
            switch (role) {
              case 'owner': return '/owner';
              case 'employee': return '/employee';
              default: return '/customer';
            }
          }
          return '/';
        }
        return null;
      }

      if (publicRoutes.contains(path)) {
        if (path == '/') {
          if (appState.loggedIn) {
            if (!appState.emailVerified) return '/verify-email';
            if (!appState.profileCompleted) {
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                return '/reg';
              }
              return '/reg';
            }

            // ✅ FIXED: Use currentRole from AppState
            switch (appState.currentRole) {
              case 'owner':
                return '/owner';
              case 'employee':
                return '/employee';
              default:
                return '/customer';
            }
          } else {
            final hasProfile = await SessionManager.hasProfile();
            if (hasProfile) {
              return '/continue';
            }
            return '/login';
          }
        }
        return null;
      }

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
        
        // ✅ FIXED: Role-based route access
        if (path == '/owner' && appState.currentRole != 'owner') {
          return '/';
        }
        if (path == '/employee' && appState.currentRole != 'employee') {
          return '/';
        }
        if (path == '/customer' && 
            appState.currentRole != 'customer' && 
            appState.currentRole != null) {
          return '/';
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
        builder: (context, state) {
          final user = appState.currentUser;
          print('📱 RegistrationFlow with user from AppState: ${user?.email}');
          return RegistrationFlow(user: user);
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
          final roles = extra?['roles'] as List<String>? ?? appState.roles;
          final email = extra?['email'] as String? ?? appState.currentEmail ?? '';
          final userId = extra?['userId'] as String? ?? appState.currentUser?.id ?? '';

          return RoleSelectorScreen(
            roles: roles,
            email: email,
            userId: userId,
          );
        },
      ),
      GoRoute(path: '/customer', builder: (_, __) => const CustomerHome()),
      GoRoute(path: '/employee', builder: (_, __) => const EmployeeDashboard()),
      GoRoute(path: '/owner', builder: (_, __) => const OwnerDashboard()),
      GoRoute(
        path: '/privacy',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PolicyScreen(isPrivacyPolicy: true, extraData: extra);
        },
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PolicyScreen(isPrivacyPolicy: false, extraData: extra);
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