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

    // ========== PHASE 5: AUTH LISTENER ==========
    _setupAuthStateListener();

    // ========== PHASE 6: PLATFORM CONFIG ==========
    await _setupPlatformSpecificConfig();

    // ========== PHASE 7: SERVICES ==========
    await SessionManager.init();

    // ========== PHASE 8: APP STATE ==========
    appState = AppState();
    await appState.initializeApp();

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
// AUTH STATE LISTENER
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
            // Check if user has any profile (any role)
            final profiles = await supabase
                .from('profiles')
                .select('role_id')
                .eq('id', user.id)
                .limit(1);

            if (profiles.isEmpty) {
              print('📍 First time login - redirecting to /reg');
              _navigateTo('/reg', extra: user);
            } else {
              print('📍 Existing user with profile(s) - checking roles');

              // Get user's roles
              final userRoles = await supabase
                  .from('profiles')
                  .select('roles!inner(name)')
                  .eq('id', user.id)
                  .eq('is_active', true);

              if (userRoles.isNotEmpty) {
                // Navigate based on primary/most recent role
                await _navigateBasedOnRoles(userRoles, user);
              } else {
                // No active roles, go to registration
                _navigateTo('/reg', extra: user);
              }
            }
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
                .select('role_id')
                .eq('id', user.id)
                .limit(1);

            if (profiles.isEmpty) {
              _navigateTo('/reg', extra: user);
            } else {
              final userRoles = await supabase
                  .from('profiles')
                  .select('roles!inner(name)')
                  .eq('id', user.id)
                  .eq('is_active', true);

              if (userRoles.isNotEmpty) {
                await _navigateBasedOnRoles(userRoles, user);
              } else {
                _navigateTo('/reg', extra: user);
              }
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
              .select('role_id')
              .eq('id', currentUser.id)
              .limit(1);

          if (profiles.isNotEmpty) {
            final userRoles = await supabase
                .from('profiles')
                .select('roles!inner(name)')
                .eq('id', currentUser.id)
                .eq('is_active', true);

            if (userRoles.isNotEmpty) {
              await _navigateBasedOnRoles(userRoles, currentUser);
            } else {
              _navigateTo('/reg', extra: currentUser);
            }
          } else {
            _navigateTo('/reg', extra: currentUser);
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

// New helper method to navigate based on user roles
Future<void> _navigateBasedOnRoles(List<dynamic> userRoles, User user) async {
  // Extract role names
  final roleNames = userRoles
      .map((p) => p['roles']?['name'] as String?)
      .where((name) => name != null)
      .cast<String>()
      .toList();

  print('📋 User roles: $roleNames');

  if (roleNames.isEmpty) {
    _navigateTo('/reg', extra: user);
    return;
  }

  // Priority based navigation
  if (roleNames.contains('owner')) {
    print('👑 Redirecting to owner dashboard');
    _navigateTo('/owner', extra: user);
  } else if (roleNames.contains('employee')) {
    print('💇 Redirecting to employee dashboard');
    _navigateTo('/employee', extra: user);
  } else if (roleNames.contains('customer')) {
    print('👤 Redirecting to customer home');
    _navigateTo('/customer', extra: user);
  } else {
    // Unknown role, go to role selection
    print('❓ Unknown role, redirecting to registration');
    _navigateTo('/reg', extra: user);
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
// ROUTER - FIXED VERSION
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

      // 🔥 SPECIAL HANDLING FOR /reg - REMOVED FROM PUBLIC ROUTES
      if (path == '/reg') {
        final user = state.extra as User?;
        if (user == null) {
          print('⚠️ /reg accessed without user → redirecting to /login');
          return '/login';
        }
        return null; // Allow /reg with user
      }

      if (publicRoutes.contains(path)) {
        if (path == '/') {
          if (appState.loggedIn) {
            if (!appState.emailVerified) return '/verify-email';
            if (!appState.profileCompleted) {
              // 🔥 Get current user
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                return '/reg?user=${user.id}'; // Pass user ID via query
              }
              return '/reg';
            }

            switch (appState.role) {
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
          // AppState එකෙන් user ගන්න
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
