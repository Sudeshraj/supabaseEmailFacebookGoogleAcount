import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/screens/authantication/command/auth_callback_handler.dart';
import 'package:flutter_application_1/screens/authantication/command/clear_data_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/data_consent_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/finish_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/policy_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_confirm.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_form.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_request.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:url_strategy/url_strategy.dart';

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
  // Handle email verification errors
  // final uri = Uri.base;
  // if (uri.path.contains('auth/callback')) {
  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     final errorCode = uri.queryParameters['error_code'];
  //     final error = uri.queryParameters['error'];
  //     if (errorCode == 'otp_expired' || error == 'access_denied') {
  //       router.go('/verify-invalid');
  //     }
  //   });
  // }
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
        // App came to foreground
        appState.refreshState(silent: true);

        // ✅ Validate and refresh session if needed
        _validateSessionOnResume();
        break;

      case AppLifecycleState.paused:
        // App went to background
        print('📱 App backgrounded - saving session state');
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

Future<void> _validateSessionOnResume() async {
  try {
    // Wait a moment for Supabase to initialize
    await Future.delayed(const Duration(milliseconds: 300));

    // Validate and refresh session if needed
    await SessionManager.validateAndRefreshSession();

    // Check if auto-login should be attempted
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      // No user logged in, check if we should auto-login
      final rememberMe = await SessionManager.isRememberMeEnabled();
      if (rememberMe) {
        print('🔄 App resumed, attempting auto-login...');
        await appState.attemptAutoLogin();
      }
    }
  } catch (e) {
    print('❌ Error validating session on resume: $e');
  }
}

// ====================
// MAIN METHOD
// ====================
Future<void> main() async {
  // Web සඳහා # ඉවත් කිරීමට
  // if (kIsWeb) {
  //    setPathUrlStrategy();
  // }

  final uri = Uri.base;
  print('🚀 APP STARTING');
  print('   Initial URI: ${uri.toString()}');
  print('   Path: ${uri.path}');
  print('   Query: ${uri.query}');
  print('   Fragment: ${uri.fragment}');
  print('   Query Params: ${uri.queryParameters}');

  // Check if it's an auth callback
  if (uri.toString().contains('/auth/callback')) {
    print('🎯 AUTH CALLBACK DETECTED AT APP START!');
  }

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

    // ✅ SETUP AUTH STATE LISTENER(listner inna nisa current app ekath redirect venava reset form ekata)
    _setupAuthStateListener();

     // ========== PHASE 3.5: PLATFORM-SPECIFIC CONFIG ==========
    await _setupPlatformSpecificConfig(); // 🔥 NEW

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

// main.dart එකේ මෙම method එක එකතු කරන්න
Future<void> _setupPlatformSpecificConfig() async {
  print('🌐 Platform configuration...');
  print('   Is Web: $kIsWeb');
  print('   Initial URI: ${Uri.base.toString()}');
  
  if (kIsWeb) {
    // Web-specific setup
    await _setupWebConfig();
  } else {
    // Mobile-specific setup  
    await _setupMobileConfig();
  }
}

Future<void> _setupWebConfig() async {
  print('   Configuring for Web');
  
  try {
    // Use url_strategy package for web
    // Uncomment after adding url_strategy to pubspec.yaml
    // setPathUrlStrategy();
    
    // For now, handle URLs manually
    final uri = Uri.base;
    if (uri.toString().contains('/auth/callback')) {
      print('   🔥 Web auth callback detected');
    }
  } catch (e) {
    print('   ❌ Web config error: $e');
  }
}

Future<void> _setupMobileConfig() async {
  print('   Configuring for Mobile');
  
  // Mobile deep links setup
  await _setupMobileDeepLinks();
}

/// 🔥 CRITICAL FIX: Mobile deep links setup
Future<void> _setupMobileDeepLinks() async {
  print('   🔗 Setting up mobile deep links...');
  
  // Note: To enable full mobile deep links, add these to pubspec.yaml:
  // uni_links: ^0.5.1  # For deep links
  // app_links: ^3.2.1  # Alternative
  
  // For now, we'll handle basic deep links
  try {
    // Check initial URI for mobile
    final uri = Uri.base;
    if (uri.toString().isNotEmpty && uri.toString() != '/') {
      print('     Initial mobile URI: ${uri.toString()}');
      
      // Check if it's a deep link
      if (uri.toString().contains('myapp://') || 
          uri.toString().contains('/auth/callback')) {
        print('     📱 Mobile deep link detected!');
        
        // Store for later processing
        pendingDeepLink = uri.toString();
      }
    }
  } catch (e) {
    print('     ❌ Mobile deep link setup error: $e');
  }
  
  print('   ✅ Mobile deep links configured (basic)');
}

// Add this global variable at the top of main.dart
String? pendingDeepLink;

// ✅ SIMPLIFIED: Setup auth state listener
void _setupAuthStateListener() {
  final supabase = Supabase.instance.client;

  supabase.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    final session = data.session;

    if (kDebugMode) {
      print('🔐 Auth State Change: $event');
    }

    // Handle password recovery
    if (event == AuthChangeEvent.passwordRecovery) {
      print('✅ Password recovery detected!');

      // Navigate to password reset form
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (navigatorKey.currentContext != null) {
            print('📍 Navigating to /reset-password-form');
            router.go('/reset-password-form');
          }
        } catch (e) {
          print('❌ Navigation error: $e');
        }
      });
    }

    // Debug other auth events
    if (kDebugMode) {
      switch (event) {
        case AuthChangeEvent.signedIn:
          print('🎉 User signed in: ${session?.user.email}');
          break;
        case AuthChangeEvent.signedOut:
          print('👋 User signed out');
          break;
        case AuthChangeEvent.userUpdated:
          print('📝 User updated');
          break;
        default:
          break;
      }
    }
  });
}

// ====================
// SIMPLIFIED ROUTER CONFIGURATION
// ====================
GoRouter _createRouter() {
   String initialLocation = '/';
  final uri = Uri.base;
  
  print('📍 Router creation - Initial URI: ${uri.toString()}');
  
  // Check for auth callback in URL
  if (uri.toString().contains('/auth/callback')) {
    initialLocation = '/auth/callback';
    print('   🎯 Setting initial location to /auth/callback');
  }
  
  // Check for pending mobile deep link
  if (pendingDeepLink != null && pendingDeepLink!.contains('/auth/callback')) {
    initialLocation = '/auth/callback';
    print('   📱 Using mobile deep link as initial location');
  }
  return GoRouter(
    navigatorKey: navigatorKey,
    refreshListenable: appState,
    // initialLocation: '/',
    initialLocation: initialLocation, // 🔥 Use actual URL path
    debugLogDiagnostics: kDebugMode,
    observers: [if (kDebugMode) MyRouteObserver()],
    redirect: (context, state) async {
      final path = state.matchedLocation;
      final uriString = state.uri.toString();
      final queryParams = state.uri.queryParameters;
      
      print('🔄 REDIRECT CHECK: $path');
      print('   Full URL: $uriString');
      print('   Query params: $queryParams');
      
      // 🔥🔥🔥 MOST CRITICAL FIX: NEVER redirect auth callbacks
      if (path == '/auth/callback' || 
          uriString.contains('/auth/callback') ||
          queryParams.containsKey('code') ||
          queryParams.containsKey('error') ||
          queryParams.containsKey('access_token')) {
        
        print('   ✅ AUTH CALLBACK - SKIPPING ALL REDIRECTS');
        return null; // NO REDIRECT FOR AUTH CALLBACKS
      }
      
      // If app is still loading, wait
      if (appState.loading) {
        print('   ⏳ App loading, staying put');
        return null;
      }
      
      // Rest of your existing redirect logic...
      // But auth callbacks will never reach here
      
      // Public routes that should always be accessible
      final publicRoutes = [
        '/',
        '/login',
        '/signup',
        '/finish',
        '/data-consent',
        '/continue',
        '/verify-email',
        '/verify-invalid',
        '/privacy',
        '/terms',
        '/clear-data',
        '/reset-password',
        '/reset-password-confirm',
        '/reset-password-form',
        '/auth/callback', // ✅ Important for password reset/email verification
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
            final shouldShowContinue =
                await SessionManager.shouldShowContinueScreen();
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
        final shouldShowContinue =
            await SessionManager.shouldShowContinueScreen();
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

      // Login route
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final prefilledEmail = extra?['prefilledEmail'] as String?;
          final showMessage = extra?['showMessage'] as bool? ?? false;
          final message = extra?['message'] as String?;

          return SignInScreen(
            prefilledEmail: prefilledEmail,
            showMessage: showMessage,
            message: message,
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

      // Signup completion
      GoRoute(
        path: '/finish',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return MaterialPage(
            key: state.pageKey,
            child: FinishScreen(
              email: extra?['email'] ?? '',
              password: extra?['password'] ?? '',
            ),
          );
        },
      ),

      // Home screens
      GoRoute(path: '/customer', builder: (_, __) => const CustomerHome()),
      GoRoute(path: '/employee', builder: (_, __) => const EmployeeDashboard()),
      GoRoute(path: '/owner', builder: (_, __) => const OwnerDashboard()),

      // Policy screens
      GoRoute(
        path: '/privacy',
        name: 'privacy',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PolicyScreen(isPrivacyPolicy: true, extraData: extra);
        },
      ),
      GoRoute(
        path: '/terms',
        name: 'terms',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PolicyScreen(isPrivacyPolicy: false, extraData: extra);
        },
      ),

      // Data management
      GoRoute(
        path: '/clear-data',
        builder: (context, state) => const ClearDataScreen(),
      ),
      GoRoute(
        path: '/data-consent',
        name: 'data-consent',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final email = extra?['email'] as String? ?? '';
          final password = extra?['password'] as String? ?? '';
          final source = extra?['source'] as String?;

          return DataConsentScreen(
            email: email,
            password: password,
            source: source,
          );
        },
      ),

      // ✅ AUTH CALLBACK HANDLER - MOST IMPORTANT FOR PASSWORD RESET & OAuth
      GoRoute(
        path: '/auth/callback',
        name: 'auth-callback',
        pageBuilder: (context, state) {
          // PageBuilder භාවිතා කරන්න transitions සඳහා
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

      // ✅ PASSWORD RESET FLOW ROUTES
      GoRoute(
        path: '/reset-password',
        name: 'reset-password',
        builder: (_, __) => const ResetPasswordRequestScreen(),
      ),

      GoRoute(
        path: '/reset-password-form',
        name: 'reset-password-form',
        builder: (_, __) => const ResetPasswordFormScreen(),
      ),

      GoRoute(
        path: '/reset-password-confirm',
        name: 'reset-password-confirm',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final email = extra?['email'] ?? '';
          return MaterialPage(
            key: state.pageKey,
            child: ResetPasswordConfirmScreen(email: email),
          );
        },
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
  }

  void _initNetworkMonitoring() {
    _networkService = NetworkService();
    _networkSub = _networkService.onStatusChange.listen((online) {
      if (mounted) {
        setState(() => _offline = !online);
      }
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
