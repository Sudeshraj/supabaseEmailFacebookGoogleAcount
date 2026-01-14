import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/screens/authantication/command/policy_screen.dart';
// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'config/environment_manager.dart';

// Screens
import 'screens/authantication/command/splash.dart';
import 'screens/authantication/command/sign_in.dart';
import 'screens/authantication/command/signup_flow.dart';
import 'screens/authantication/command/registration_flow.dart';
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

// ====================
// ERROR HANDLER
// ====================
void setupErrorHandling() {
  // Flutter framework errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);

    // Send to Crashlytics in production
    if (!kDebugMode) {
      // FirebaseCrashlytics.instance.recordFlutterError(details);
    }
  };

  // Uncaught errors
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      print('❌ Uncaught error: $error');
      print('Stack: $stack');
    }

    if (!kDebugMode) {
      // FirebaseCrashlytics.instance.recordError(error, stack);
    }

    return true; // Prevent app from closing
  };
}

// ====================
// APP LIFECYCLE
// ====================
class AppLifecycleObserver with WidgetsBindingObserver {
  AppLifecycleObserver(appState);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        appState.refreshState(silent: true);
        break;
      case AppLifecycleState.paused:
        // Save state if needed
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
}

// ====================
// MAIN METHOD
// ====================
Future<void> main() async {
  // Initialize Flutter engine
  WidgetsFlutterBinding.ensureInitialized();

  // Set up error handling
  setupErrorHandling();

  print('🚀 ${DateTime.now()}: Starting application...');

  try {
    // ========== PHASE 1: ENVIRONMENT ==========
    environment = EnvironmentManager();
    await environment.init(flavor: kDebugMode ? 'development' : 'production');

    if (kDebugMode) {
      environment.printInfo();
    }

    // ========== PHASE 2: FIREBASE ==========
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Configure Crashlytics
    if (!kDebugMode) {
      // await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    }

    // ========== PHASE 3: SUPABASE ==========
    await Supabase.initialize(
      url: environment.supabaseUrl,
      anonKey: environment.supabaseAnonKey,
      debug: kDebugMode,
    );

    // ========== PHASE 4: SERVICES ==========
    await SessionManager.init();

    // ========== PHASE 5: APP STATE ==========
    appState = AppState();
    await appState.initializeApp();

    // ========== PHASE 6: ROUTER ==========
    router = _createRouter();

    // ========== PHASE 7: LIFECYCLE ==========
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(appState));

    // ========== PHASE 8: RUN APP ==========
    print('✅ ${DateTime.now()}: Initialization complete');
    runApp(MyApp());
  } catch (e, stackTrace) {
    print('❌❌❌ CRITICAL ERROR DURING INITIALIZATION ❌❌❌');
    print('Error: $e');
    print('Stack: $stackTrace');

    if (!kDebugMode) {
      // FirebaseCrashlytics.instance.recordError(e, stackTrace);
    }

    // Show error screen
    runApp(_ErrorApp(error: e.toString()));
  }
}

// ====================
// ROUTER CONFIGURATION
// ====================
GoRouter _createRouter() {
  return GoRouter(
    navigatorKey: navigatorKey,
    refreshListenable: appState,
    initialLocation: '/',
    debugLogDiagnostics: true,
    observers: [
      if (kDebugMode) MyRouteObserver(), // Add this
    ],
    // debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final path = state.matchedLocation;

      // Splash screen logic - Only show splash at '/'
      if (path == '/') {
        if (appState.loading) return null; // Show splash while loading

        // Once loading is complete, redirect based on app state
        if (appState.loggedIn) {
          if (!appState.emailVerified) return '/verify-email';
          if (!appState.profileCompleted) return '/reg';
          print('✅ Profile completed: ${appState.profileCompleted}');
          // Role-based routing from splash
          switch (appState.role) {
            case 'business':
              return '/owner';
            case 'employee':
              return '/employee';
            default:
              return '/customer';
          }
        } else {
          // Not logged in

          // if (appState.continueSc) {
          //   if (path != '/continue') {
          //     print('🔐 Redirecting to /continue because continueSc is false');
          //     return '/continue';
          //   }
          // }
          // print(
          //   appState.hasLocalProfile
          //       ? '🔐 Redirecting to /continue from splash'
          //       : '🔐 Redirecting to /login from splash',
          // );
          print(appState.hasLocalProfile);
          if (appState.hasLocalProfile) return '/continue';
          return '/login';
        }
      }

      if (appState.loading) return '/';
      print('🔐 ${appState.loggedIn}');
      print('🔐 ${appState.emailVerified}');

      // Continue screen logic
      if (!appState.loggedIn && appState.hasLocalProfile) {
        final shouldShowContinue =
            path != '/login' && path != '/signup' && path != '/verify-email';

        // if (!appState.emailVerified) {
        //   return '/verify-email';
        // }
        // if (!appState.emailVerified) return '/verify-email';
        if (shouldShowContinue && path != '/continue') {
          return '/continue';
        }
      }

      // Authentication logic
      if (!appState.loggedIn) {
        if (path == '/login' ||
            path == '/signup' ||
            path == '/continue' ||
            path == '/verify-email' ||
            path == '/privacy' ||
            path == '/terms' ||
            path == '/verify-invalid') {
          return null;
        }
        return '/login';
      }

      // if (path == '/verify-invalid') {
      //   return null;
      // }

      // Email verification
      if (!appState.emailVerified && path != '/verify-email') {
        return '/verify-email';
      }
      print('🔐 ${appState.emailVerified}');
      if (!appState.emailVerified) return '/verify-email';

      // if (appState.loggedIn && appState.hasLocalProfile) {
      //   if (path != '/continue') {
      //     print('🔐 Redirecting to /continue because continueSc is false');
      //     return '/continue';
      //   }
      // }

      // Profile completion
      // if (!appState.profileCompleted && path != '/reg') {
      //   return '/reg';
      // }

      if (!appState.profileCompleted) {
        if (path != '/reg') {
          print('🔐 Redirecting to /reg because profile not completed');
          return '/reg';
        }
        // path == '/reg' නම් null return කරන්න (නැතිනම් infinite loop වෙයි)
        //  return null; // meka damme naththam pahala thiyena linuth wada karanava
      }

      print(
        'User Role: ${appState.role}, Profile Completed: ${appState.profileCompleted}',
      );
      // Role-based routing for other paths | ihata eka block ekkatavath giye naththam metanata enava
      if (appState.profileCompleted) {
        switch (appState.role) {
          case 'business':
            return path == '/owner' ? null : '/owner';
          case 'employee':
            return path == '/employee' ? null : '/employee';
          default:
            return path == '/customer' ? null : '/customer';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      // GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
      // routes.dart එකේ
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) {
          final extra = state.extra;

          // Check if extra is already a SignInScreen
          if (extra is SignInScreen) {
            return MaterialPage(key: state.pageKey, child: extra);
          }

          // Otherwise create new one
          final email = (extra is Map ? extra['email'] : null) as String?;
          return MaterialPage(
            key: state.pageKey,
            child: SignInScreen(prefilledEmail: email),
          );
        },
      ),
      GoRoute(path: '/signup', builder: (_, __) => const SignupFlow()),
      GoRoute(path: '/reg', builder: (_, __) => const RegistrationFlow()),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const EmailVerifyChecker(),
      ),
      GoRoute(
        path: '/verify-invalid',
        builder: (_, __) => const VerifyInvalidScreen(),
      ),
      GoRoute(path: '/continue', builder: (_, __) => const ContinueScreen()),
      GoRoute(path: '/customer', builder: (_, __) => const CustomerHome()),
      GoRoute(path: '/employee', builder: (_, __) => const EmployeeDashboard()),
      GoRoute(path: '/owner', builder: (_, __) => const OwnerDashboard()),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PolicyScreen(isPrivacyPolicy: true),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const PolicyScreen(isPrivacyPolicy: false),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 20),
            const Text(
              'Page Not Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Route: ${state.uri.toString()}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ====================
// MAIN APP WIDGET
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
    _handleEmailVerification();
  }

  void _initNetworkMonitoring() {
    _networkService = NetworkService();
    _networkSub = _networkService.onStatusChange.listen((online) {
      if (mounted) {
        setState(() => _offline = !online);
      }
    });
  }

  void _handleEmailVerification() {
    final uri = Uri.base;

    print('🔍 Full URL: $uri');
    print('🔍 Query params: ${uri.queryParameters}');
    print('🔍 Fragment: ${uri.fragment}');
    print('🔍 Has fragment: ${uri.hasFragment}');

    if (uri.path.contains('verify-email')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        String? errorCode = uri.queryParameters['error_code'];
        String? error = uri.queryParameters['error'];

        if (uri.hasFragment) {
          final fragmentParams = Uri.splitQueryString(uri.fragment);
          errorCode ??= fragmentParams['error_code'];
          error ??= fragmentParams['error'];
        }

        if (errorCode == 'otp_expired' || error == 'access_denied') {
          router.go('/verify-invalid');
        } else {
          router.go('/');
        }
      });
    }
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
      debugShowCheckedModeBanner: kDebugMode && environment.debugMode,
      theme: environment.enableDarkMode ? ThemeData.dark() : ThemeData.light(),
      builder: (context, child) {
        return Stack(
          children: [
            // Main content
            AbsorbPointer(
              absorbing: _offline,
              child: ColorFiltered(
                colorFilter: _offline
                    ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                    : const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      ),
                child: child ?? const SizedBox(),
              ),
            ),

            // Network status banner
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
// ERROR APP (FALLBACK)
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
            padding: const EdgeInsets.all(20.0),
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
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => main(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                  ),
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

// Create route observer
class MyRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('🚀 Pushed route: ${_getRouteName(route)}');
    debugPrint('   Previous route: ${_getRouteName(previousRoute)}');
    debugPrint('   Route settings: ${route.settings}');
    debugPrint('   Route runtimeType: ${route.runtimeType}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('🔙 Popped route: ${_getRouteName(route)}');
    debugPrint('   Returning to: ${_getRouteName(previousRoute)}');
    debugPrint('   Full route: $route');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    debugPrint(
      '🔄 Replaced route: ${_getRouteName(oldRoute)} -> ${_getRouteName(newRoute)}',
    );
  }

  String _getRouteName(Route<dynamic>? route) {
    if (route == null) return 'null';

    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      return name;
    }

    // Try to get name from toString()
    final routeStr = route.toString();
    final match = RegExp(r'"(.*?)"').firstMatch(routeStr);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }

    return route.runtimeType.toString();
  }
}
