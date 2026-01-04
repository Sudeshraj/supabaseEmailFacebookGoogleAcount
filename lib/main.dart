import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/screens/authantication/command/signup_flow.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';

// AUTH SCREENS
import 'screens/authantication/command/splash.dart';
import 'screens/authantication/command/sign_in.dart';
import 'screens/authantication/command/email_verify_checker.dart';
import 'screens/authantication/command/multi_continue_screen.dart';

// HOME SCREENS
import 'screens/home/customer_home.dart';
import 'screens/home/employee_dashboard.dart';
import 'screens/home/owner_dashboard.dart';

// NETWORK
import 'screens/net_disconnect/network_service.dart';
import 'screens/net_disconnect/network_banner.dart';

// UTILS
import 'screens/authantication/functions/loading_overlay.dart';
import 'router/auth_gate.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

late final GoRouter router;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------- FIREBASE INIT ----------------
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  // ---------------- SUPABASE INIT ----------------
  await Supabase.initialize(
    url: 'https://ifhenrgfpahandumdwmt.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmaGVucmdmcGFoYW5kdW1kd210Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY0NTY5OTcsImV4cCI6MjA4MjAzMjk5N30.HgiUZJkXCtzXpl0zfheAx2l4qcdFLMmzOwjSYMcYkp0',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  LoadingOverlay.setNavigatorKey(navigatorKey);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final NetworkService _networkService;
  StreamSubscription<bool>? _networkSub;
  StreamSubscription<AuthState>? _authSub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();

    // --------------------------------------------------
    // NETWORK LISTENER
    // --------------------------------------------------
    _networkService = NetworkService();
    _networkSub = _networkService.onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() => _offline = !online);
    });

    // --------------------------------------------------
    // ROUTER (with AuthGate redirect)
    // --------------------------------------------------
    router = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/',
      debugLogDiagnostics: false,
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
        GoRoute(
          path: '/verify-email',
          builder: (_, __) => const EmailVerifyChecker(),
        ),
        GoRoute(path: '/continue', builder: (_, __) => const ContinueScreen()),
        GoRoute(path: '/customer', builder: (_, __) => const CustomerHome()),
        GoRoute(
          path: '/employee',
          builder: (_, __) => const EmployeeDashboard(),
        ),
        GoRoute(path: '/owner', builder: (_, __) => const OwnerDashboard()),
        GoRoute(path: '/signup', builder: (_, __) => const SignupFlow()),
      ],
      // redirect: (context, state) async {
      //   // 👇 async redirect for Supabase auth state
      //   final next = await AuthGate.redirect(state.matchedLocation);
      //   return next;
      // },
      redirect: (context, state) async {
        return AuthGate.redirect(state.uri.path);
      },
    );

    // --------------------------------------------------
    // SUPABASE AUTH STATE HANDLER
    // --------------------------------------------------
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      router.refresh(); // 👈 re-run redirect logic
    });
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _authSub?.cancel();
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
            // 👇 Dim screen when offline
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
            // 👇 Offline banner
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
