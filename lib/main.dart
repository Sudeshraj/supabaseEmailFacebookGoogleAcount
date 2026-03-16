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
import 'package:flutter_application_1/screens/owner/create_salon.dart';
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
// AUTH STATE LISTENER - FIXED
// ====================
void _setupAuthStateListener() {
  final supabase = Supabase.instance.client;

  supabase.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    final session = data.session;

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

// ====================
// HELPER: Has Local Profile
// ====================
Future<bool> _hasLocalProfile(String? email) async {
  if (email == null) return false;

  try {
    final profile = await SessionManager.getProfileByEmail(email);
    final hasProfile = profile != null && profile.isNotEmpty;

    debugPrint('📱 Checking local profile for $email: $hasProfile');
    return hasProfile;
  } catch (e) {
    debugPrint('❌ Error checking local profile: $e');
    return false;
  }
}

// ====================
// HELPER: Navigate
// ====================
void _navigateTo(String location, {Object? extra}) {
  try {
    final currentRoute =
        router.routerDelegate.currentConfiguration.last.matchedLocation;

    if (currentRoute == location) {
      debugPrint('Already on $location - skipping navigation');
      return;
    }

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
// FIXED ROUTER - WITH PROPER ROLE HANDLING
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

      debugPrint('🔍 REDIRECT CHECK - Path: $path');
      debugPrint(
        '📊 AppState: loading=${appState.loading}, loggedIn=${appState.loggedIn}',
      );
      debugPrint('📊 AppState roles: ${appState.roles}');
      debugPrint('📊 AppState currentRole: ${appState.currentRole}');

      // 🔥 NEVER redirect auth callbacks
      if (path == '/auth/callback' ||
          queryParams.containsKey('code') ||
          queryParams.containsKey('access_token')) {
        debugPrint('✅ Auth callback - no redirect');
        return null;
      }

      // AppState loading නම්, කිසිම redirect එකක් එපා
      if (appState.loading) {
        debugPrint('⏳ AppState loading - no redirect');
        return null;
      }

      // Clear data screen is always accessible
      if (path == '/clear-data') {
        debugPrint('✅ Clear data screen - allowing access');
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

      // ====================================================
      // ROLE SELECTOR ROUTE
      // ====================================================
      if (path == '/role-selector') {
        if (!appState.loggedIn) {
          return '/login';
        }
        return null;
      }

      // ====================================================
      // PUBLIC ROUTES
      // ====================================================
      if (publicRoutes.contains(path)) {
        if (path == '/') {
          // SPLASH SCREEN LOGIC
          if (appState.loggedIn) {
            // User logged in
            if (!appState.emailVerified) {
              debugPrint('📧 Email not verified → /verify-email');
              return '/verify-email';
            }

            if (!appState.profileCompleted) {
              debugPrint('📝 Profile not completed → /reg');
              return '/reg';
            }

            // Check roles
            if (appState.roles.isEmpty) {
              debugPrint('⚠️ No roles found → /reg');
              return '/reg';
            }

            // 🔥 FIX: Check if current role is valid
            if (appState.currentRole != null) {
              final targetRoute = '/${appState.currentRole}';
              debugPrint('✅ Has current role: ${appState.currentRole} → $targetRoute');
              return targetRoute;
            }

            // No current role but has multiple roles
            if (appState.roles.length > 1) {
              debugPrint('🔄 Multiple roles, no current role → /role-selector');
              return '/role-selector';
            }

            // Single role - direct redirect
            if (appState.roles.length == 1) {
              final role = appState.roles.first;
              debugPrint('✅ Single role: $role → /$role');
              await SessionManager.saveCurrentRole(role);
              return '/$role';
            }
          } else {
            // Not logged in
            final hasProfile = await SessionManager.hasProfile();
            if (hasProfile) {
              debugPrint('💾 Has saved profiles → /continue');
              return '/continue';
            } else {
              debugPrint('🔐 No saved profiles → /login');
              return '/login';
            }
          }
        }

        // 🔥 SPECIAL HANDLING FOR /reg
        if (path == '/reg') {
          if (!appState.loggedIn) {
            debugPrint('⚠️ /reg requires login → redirecting to /login');
            return '/login';
          }
          debugPrint('✅ Allowing access to /reg');
          return null;
        }

        return null;
      }

      // ====================================================
      // PROTECTED ROUTES
      // ====================================================
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

        // 🔥 FIX: If no current role but has roles, go to role selector
        if (appState.currentRole == null && appState.roles.isNotEmpty) {
          debugPrint('⚠️ No current role but has roles → /role-selector');
          return '/role-selector';
        }

        // 🔥 FIX: Role-specific dashboard access
        final roleToPath = {
          'owner': '/owner',
          'barber': '/barber',
          'customer': '/customer',
        };

        // Check if current path matches any dashboard
        for (var entry in roleToPath.entries) {
          if (path == entry.value) {
            // Already on correct dashboard
            if (appState.currentRole == entry.key) {
              debugPrint('✅ Already on correct dashboard: $path');
              return null;
            } else {
              // Wrong dashboard - redirect to correct one
              final correctPath = '/${appState.currentRole ?? appState.roles.first}';
              debugPrint('⚠️ Wrong dashboard - redirecting to $correctPath');
              return correctPath;
            }
          }
        }

        // 🔥 FIX: Special case for customer dashboard
        if (path == '/customer' && appState.currentRole == null) {
          // Customer dashboard is default
          return null;
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

          // Safely convert roles to List<String>
          final dynamic rolesFromExtra = extra?['roles'];
          List<String> roles = [];

          if (rolesFromExtra != null) {
            if (rolesFromExtra is List<String>) {
              roles = rolesFromExtra;
            } else if (rolesFromExtra is List) {
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

          return RoleSelectorScreen(
            roles: roles,
            email: email,
            userId: userId,
          );
        },
      ),
      GoRoute(
        path: '/customer',
        builder: (_, __) {
          debugPrint('🏠 Navigating to CustomerDashboard');
          return const CustomerDashboard();
        },
      ),
      GoRoute(
        path: '/barber',
        builder: (_, __) {
          debugPrint('💇 Navigating to EmployeeDashboard');
          return const EmployeeDashboard();
        },
      ),
      GoRoute(
        path: '/owner',
        builder: (_, __) {
          debugPrint('👑 Navigating to OwnerDashboard');
          return const OwnerDashboard();
        },
      ),
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
      GoRoute(
        path: '/clear-data',
        builder: (_, __) => const ClearDataScreen(),
      ),
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
        builder: (context, state) {
          final refresh = state.uri.queryParameters['refresh'] == 'true';
          return AddBarberScreen(refresh: refresh);
        },
      ),
      GoRoute(
        path: '/owner/categories/add',
        name: 'addCategory',
        pageBuilder: (context, state) =>
            MaterialPage(child: const AddCategoryScreen()),
      ),
      GoRoute(
        path: '/owner/salon/create',
        name: 'createSalon',
        builder: (context, state) => const CreateSalonScreen(),
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
      title: 'Salon Management',
      theme: ThemeData(
        primaryColor: const Color(0xFFFF6B8B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B8B),
          primary: const Color(0xFFFF6B8B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
        ),
      ),
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