import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';

// AUTH
import 'screens/authantication/command/splash.dart';
import 'screens/authantication/command/sign_in.dart';
import 'screens/authantication/command/signup_flow.dart';
import 'screens/authantication/command/registration_flow.dart';
import 'screens/authantication/command/email_verify_checker.dart';
import 'screens/authantication/command/multi_continue_screen.dart';

// HOME
import 'screens/home/customer_home.dart';
import 'screens/home/employee_dashboard.dart';
import 'screens/home/owner_dashboard.dart';

// NETWORK
import 'screens/net_disconnect/network_service.dart';
import 'screens/net_disconnect/network_banner.dart';
import 'screens/net_disconnect/verify_invalid.dart';

// UTILS
import 'screens/authantication/functions/loading_overlay.dart';
import 'router/auth_gate.dart';
// import 'router/session_manager.dart';
import 'package:flutter_application_1/screens/authantication/services/session_manager.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

late final GoRouter router;
late final AppState appState;

/// --------------------------------------------------
/// APP STATE (SINGLE SOURCE OF TRUTH) | logout veddi use krnna ->supabase.auth.signOut();appState.restore();

/// --------------------------------------------------
class AppState extends ChangeNotifier {
  bool loading = true;
  bool loggedIn = false;
  bool emailVerified = false;
  bool profileCompleted = false;
  bool hasLocalProfile = false;
  String? role;

  Future<void> restore() async {
    loading = true;
    notifyListeners();

    final supabase = Supabase.instance.client;

    try {
      // 1️⃣ LOCAL PROFILE
      hasLocalProfile = await SessionManager.hasProfile();

      final session = supabase.auth.currentSession;
      final user = session?.user;

      loggedIn = session != null;
      emailVerified = user?.emailConfirmedAt != null;

      if (loggedIn && user != null) {
        final profile = await supabase
            .from('profiles')
            .select('role, roles')
            .eq('id', user.id)
            .maybeSingle();

        profileCompleted = profile != null;

        if (profileCompleted) {
          role = await SessionManager.getUserRole();

          if (role == null) {
            role = AuthGate.pickRole(profile?['role'] ?? profile?['roles']);
            await SessionManager.saveUserRole(role!);
          }
        }
      } else {
        profileCompleted = false;
        role = null;
      }
    } catch (e) {
      // 🔥 FAIL SAFE
      loggedIn = false;
      emailVerified = false;
      profileCompleted = false;
      role = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// --------------------------------------------------
/// LIFECYCLE OBSERVER
/// --------------------------------------------------
class AppLifecycleObserver with WidgetsBindingObserver {
  final AppState state;
  AppLifecycleObserver(this.state);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      this.state.restore();
    }
  }
}

/// --------------------------------------------------
/// MAIN
/// --------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('otp_expired') ||
        msg.contains('access_denied') ||
        msg.contains('Email link is invalid')) {
      return;
    }
    FlutterError.presentError(details);
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://ifhenrgfpahandumdwmt.supabase.co',
    anonKey: 'YOUR_ANON_KEY',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  LoadingOverlay.setNavigatorKey(navigatorKey);

  appState = AppState();
  await appState.restore();

  WidgetsBinding.instance.addObserver(AppLifecycleObserver(appState));

  router = createRouter(appState);

  runApp(const MyApp());
}

/// --------------------------------------------------
/// ROUTER
/// --------------------------------------------------
GoRouter createRouter(AppState state) {
  return GoRouter(
    navigatorKey: navigatorKey,
    refreshListenable: state,
    initialLocation: '/',
    redirect: (context, s) {
      final path = s.matchedLocation;

      if (state.loading) return '/';

      // ❌ NOT LOGGED
      if (!state.loggedIn) {
        // Routes allowed without login
        const publicRoutes = {
          '/',
          '/login',
          '/signup',
          '/reg',
          '/verify-email',
          '/continue',
        };

        // If user has local profiles → force continue screen
        if (state.hasLocalProfile) {
          return path == '/continue' ? null : '/continue';
        }

        // Allow public routes
        if (publicRoutes.contains(path)) {
          return null;
        }

        // Otherwise → login
        return '/login';
      }

       // If user has local profiles → force continue screen if login
        if (state.hasLocalProfile) {
          return path == '/continue' ? null : '/continue';
        }

      // ❌ EMAIL NOT VERIFIED
      if (!state.emailVerified) {
        return path == '/verify-email' ? null : '/verify-email';
      }

      // ❌ PROFILE NOT CREATED
      if (!state.profileCompleted) {
        return path == '/reg' ? null : '/reg';
      }

      // ✅ ROLE BASED HOME
      switch (state.role) {
        case 'business':
          return path == '/owner' ? null : '/owner';
        case 'employee':
          return path == '/employee' ? null : '/employee';
        default:
          return path == '/customer' ? null : '/customer';
      }
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
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
    ],
  );
}

/// --------------------------------------------------
/// APP ROOT
/// --------------------------------------------------
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

    _networkService = NetworkService();
    _networkSub = _networkService.onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() => _offline = !online);
    });

    final uri = Uri.base;
    if (uri.path.contains('verify-email')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final errorCode = uri.queryParameters['error_code'];
        final error = uri.queryParameters['error'];
        if (errorCode == 'otp_expired' || error == 'access_denied') {
          router.go('/verify-invalid');
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      builder: (context, child) {
        return Stack(
          children: [
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
