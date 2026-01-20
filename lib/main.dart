import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/screens/authantication/command/policy_screen.dart';
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
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (!kDebugMode) {
      // FirebaseCrashlytics.instance.recordFlutterError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      print('❌ Uncaught error: $error');
      print('Stack: $stack');
    }

    if (!kDebugMode) {
      // FirebaseCrashlytics.instance.recordError(error, stack);
    }

    return true;
  };
}

// ====================
// APP LIFECYCLE
// ====================
class AppLifecycleObserver with WidgetsBindingObserver {
  AppLifecycleObserver();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        appState.refreshState(silent: true);
        break;
      case AppLifecycleState.paused:
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
  WidgetsFlutterBinding.ensureInitialized();
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
    WidgetsBinding.instance.addObserver(AppLifecycleObserver());

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

    runApp(_ErrorApp(error: e.toString()));
  }
}

// ====================
// ROUTER CONFIGURATION
// ====================
// ====================
// ROUTER CONFIGURATION
// ====================
GoRouter _createRouter() {
  return GoRouter(
    navigatorKey: navigatorKey,
    refreshListenable: appState,
    initialLocation: '/',
    debugLogDiagnostics: kDebugMode,
    observers: [
      if (kDebugMode) MyRouteObserver(),
    ],
    redirect: (context, state) async {
      final path = state.matchedLocation;

      // Public routes that should always be accessible
      final publicRoutes = [
        '/',
        '/login',
        '/signup',
        '/continue',
        '/verify-email',
        '/verify-invalid',
        '/privacy',
        '/terms',
        '/clear-data',
      ];

      // Always allow public routes regardless of auth state
      if (publicRoutes.contains(path)) {
        // Splash screen logic
        if (path == '/') {
          if (appState.loading) return null;

          if (appState.loggedIn) {
            if (!appState.emailVerified) return '/verify-email';
            if (!appState.profileCompleted) return '/reg';
            
            print('✅ Profile completed: ${appState.profileCompleted}');
            switch (appState.role) {
              case 'business':
                return '/owner';
              case 'employee':
                return '/employee';
              default:
                return '/customer';
            }
          } else {
            // Check if should show continue screen
            final shouldShowContinue = await SessionManager.shouldShowContinueScreen();
            final hasProfile = await SessionManager.hasProfile();
            
            if (shouldShowContinue && hasProfile) {
              return '/continue';
            }
            return '/login';
          }
        }
        
        // Other public routes don't need redirection
        return null;
      }

      if (appState.loading) return '/';

      // Continue screen logic - only for logged out users with profiles
      if (!appState.loggedIn) {
        final shouldShowContinue = await SessionManager.shouldShowContinueScreen();
        final hasProfile = await SessionManager.hasProfile();
        
        if (shouldShowContinue && hasProfile && path != '/continue') {
          return '/continue';
        }
        
        // If not logged in and trying to access protected route, go to login
        if (!publicRoutes.contains(path)) {
          return '/login';
        }
      }

      // Authentication logic for logged in users
      if (appState.loggedIn) {
        // Email verification check
        if (!appState.emailVerified && path != '/verify-email') {
          return '/verify-email';
        }

        // Profile completion check
        if (!appState.profileCompleted && path != '/reg') {
          return '/reg';
        }

        // Role-based routing
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
      }
      
      // Default - allow access
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is SignInScreen) {
            return MaterialPage(key: state.pageKey, child: extra);
          }
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
      GoRoute(
        path: '/clear-data',
        builder: (context, state) => const ClearDataScreen(),
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

    if (kDebugMode) {
      debugPrint('🔍 Full URL: $uri');
      debugPrint('🔍 Query params: ${uri.queryParameters}');
      debugPrint('🔍 Fragment: ${uri.fragment}');
      debugPrint('🔍 Has fragment: ${uri.hasFragment}');
    }

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

// ====================
// CLEAR DATA SCREEN
// ====================
class ClearDataScreen extends StatelessWidget {
  const ClearDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Calculate responsive width
    double calculateContainerWidth() {
      if (isMobile) {
        return screenWidth * 0.95; // 95% width on mobile
      } else {
        final calculatedWidth = screenWidth * 0.45;
        return calculatedWidth < 500 ? calculatedWidth : 500.0;
      }
    }
    
    final containerWidth = calculateContainerWidth();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Container(
              width: containerWidth,
              margin: EdgeInsets.all(isMobile ? 16.0 : 20.0),
              padding: EdgeInsets.all(isMobile ? 20.0 : 24.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_forever,
                    size: isMobile ? 50.0 : 60.0,
                    color: Colors.red.withOpacity(0.8),
                  ),
                  SizedBox(height: isMobile ? 16.0 : 20.0),
                  Text(
                    'Clear All Data',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 22.0 : 24.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isMobile ? 12.0 : 16.0),
                  Text(
                    'This will remove all saved accounts, preferences, and login information from this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: isMobile ? 14.0 : 16.0,
                    ),
                  ),
                  SizedBox(height: isMobile ? 24.0 : 32.0),
                  // Responsive button layout
                  if (isMobile) ...[
                    // Mobile: vertical buttons
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => context.go('/'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 15.0 : 16.0,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 12.0),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              await SessionManager.clearAll();
                              final supabase = Supabase.instance.client;
                              await supabase.auth.signOut();
                              appState.refreshState();
                              context.go('/');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              backgroundColor: Colors.red,
                            ),
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 15.0 : 16.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Desktop/Web: horizontal buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.go('/'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              side: const BorderSide(color: Colors.white24),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 15.0 : 16.0,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16.0),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await SessionManager.clearAll();
                              final supabase = Supabase.instance.client;
                              await supabase.auth.signOut();
                              appState.refreshState();
                              context.go('/');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              backgroundColor: Colors.red,
                            ),
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 15.0 : 16.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Add extra bottom padding for mobile
                  if (isMobile) SizedBox(height: 8.0),
                ],
              ),
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
    if (kDebugMode) {
      debugPrint('🚀 Pushed route: ${_getRouteName(route)}');
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) {
      debugPrint('🔙 Popped route: ${_getRouteName(route)}');
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (kDebugMode) {
      debugPrint(
        '🔄 Replaced route: ${_getRouteName(oldRoute)} -> ${_getRouteName(newRoute)}',
      );
    }
  }

  String _getRouteName(Route<dynamic>? route) {
    if (route == null) return 'null';
    return route.settings.name ?? route.runtimeType.toString();
  }
}