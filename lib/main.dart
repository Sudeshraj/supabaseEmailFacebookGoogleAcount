import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';

// CONFIG
import 'config/environment_manager.dart';

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
import 'services/network_service.dart';
import 'screens/net_disconnect/network_banner.dart';
import 'screens/net_disconnect/verify_invalid.dart';

// UTILS
import 'screens/authantication/functions/loading_overlay.dart';
import 'router/auth_gate.dart';
import 'services/session_manager.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

late final GoRouter router;
late final AppState appState;

/// --------------------------------------------------
/// APP STATE (SINGLE SOURCE OF TRUTH)
/// --------------------------------------------------
class AppState extends ChangeNotifier {
  bool _loading = true;
  bool get loading => _loading;

  set loading(bool value) {
    if (_loading != value) {
      _loading = value;
      notifyListeners();
    }
  }

  bool _loggedIn = false;
  bool get loggedIn => _loggedIn;

  set loggedIn(bool value) {
    if (_loggedIn != value) {
      _loggedIn = value;
      notifyListeners();
    }
  }

  bool _emailVerified = false;
  bool get emailVerified => _emailVerified;

  set emailVerified(bool value) {
    if (_emailVerified != value) {
      _emailVerified = value;
      notifyListeners();
    }
  }

  bool _profileCompleted = false;
  bool get profileCompleted => _profileCompleted;

  set profileCompleted(bool value) {
    if (_profileCompleted != value) {
      _profileCompleted = value;
      notifyListeners();
    }
  }

  bool _hasLocalProfile = false;
  bool get hasLocalProfile => _hasLocalProfile;

  set hasLocalProfile(bool value) {
    if (_hasLocalProfile != value) {
      _hasLocalProfile = value;
      notifyListeners();
    }
  }

  String? _role;
  String? get role => _role;

  set role(String? value) {
    if (_role != value) {
      _role = value;
      notifyListeners();
    }
  }

  // ✅ Auto login from continue screen
  // 📍 USE: main() method එකේ පමණක්
  // 📍 CALLED: ✅ Yes (in main())
  Future<void> restoreWithAutoLogin() async {
    loading = true;

    print('🔄 Starting restoreWithAutoLogin...');

    try {
      // 1️⃣ Check for saved profiles
      hasLocalProfile = await SessionManager.hasProfile();

      if (hasLocalProfile) {
        print('🔄 Found saved profiles, checking auto login...');

        // Get most recent profile
        final recentProfile = await SessionManager.getMostRecentProfile();
        if (recentProfile != null && recentProfile.isNotEmpty) {
          final email = recentProfile['email'] as String?;

          if (email != null) {
            // Check if Supabase has valid session
            final hasValidSession =
                await SessionManager.hasValidSupabaseSession(email);

            if (hasValidSession) {
              print('✅ Valid Supabase session found for: $email');

              // Restore app state
              await restore();

              loading = false;
              return;
            } else {
              // Try auto login with refresh token
              final autoLoginSuccess = await SessionManager.tryAutoLogin(email);

              if (autoLoginSuccess) {
                print('✅ Auto login successful via refresh token');

                // Restore app state
                await restore();

                loading = false;
                return;
              }
            }
          }
        }
      }

      // 2️⃣ Fallback to normal restore
      print('🔍 No auto login available, using normal restore');
      await restore();
    } catch (e) {
      print('❌ Auto login failed: $e');
      // Fall back to normal restore
      await restore();
    } finally {
      loading = false;
      print('✅ restoreWithAutoLogin completed');
    }
  }

  // ✅ Helper method to get user profile
    // 📍 USE: Internal use only (by restore())
    // 📍 CALLED: ✅ Yes (by restore())
  Future<Map<String, dynamic>?> _getUserProfile(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('profiles')
          .select('role, roles')
          .eq('id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Error getting profile: $e');
      return null;
    }
  }

  // 📍 USE: Anywhere after login/logout
  // 📍 CALLED: ✅ Yes (by restoreWithAutoLogin(), router)
  Future<void> restore() async {
    loading = true;
    print('🔄 Starting restore...');

    final supabase = Supabase.instance.client;

    try {
      // Check local profiles
      hasLocalProfile = await SessionManager.hasProfile();

      // ✅ In Supabase 2.12.0, session is auto-restored
      final session = supabase.auth.currentSession;
      final user = session?.user;

      loggedIn = session != null;
      emailVerified = user?.emailConfirmedAt != null;

      print('📊 Restore State:');
      print('   - Has session: ${session != null}');
      print('   - User email: ${user?.email}');
      print('   - Email verified: $emailVerified');

      if (loggedIn && user != null) {
        // Save user profile for continue screen
        await SessionManager.saveUserProfile(
          email: user.email!,
          userId: user.id,
          name: user.userMetadata?['full_name'],
        );

        // Get profile from database
        final profile = await _getUserProfile(user.id);

        profileCompleted = profile != null;

        if (profileCompleted) {
          // Get role from SessionManager or database
          role = await SessionManager.getUserRole();

          if (role == null) {
            role = AuthGate.pickRole(profile?['role'] ?? profile?['roles']);
            if (role != null) {
              await SessionManager.saveUserRole(role!);
            }
          }
        }

        print('   - Profile completed: $profileCompleted');
        print('   - Role: $role');
      } else {
        profileCompleted = false;
        role = null;
        print('   - Not logged in or no user');
      }
    } catch (e) {
      // FAIL SAFE
      print('❌ Restore error: $e');
      loggedIn = false;
      emailVerified = false;
      profileCompleted = false;
      role = null;
    } finally {
      loading = false;
      print('✅ Restore completed');
    }
  }

  // ✅ Logout and prepare for continue screen
  // 📍 USE: ContinueScreen වලදී
  // 📍 CALLED: ❌ NO (not implemented anywhere)
  Future<void> logoutForContinueScreen() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      // Save user info for continue screen before logout
      await SessionManager.saveUserProfile(
        email: user.email!,
        userId: user.id,
        name: user.userMetadata?['full_name'] ?? user.email?.split('@').first,
      );
    }

    await supabase.auth.signOut();

    // Update app state
    loggedIn = false;
    emailVerified = false;
    profileCompleted = false;
    role = null;

    print('✅ Logged out, profile saved for continue screen');
  }

  // ✅ Direct auto login for a specific email
  // 📍 USE: ContinueScreen වලදී
  // 📍 CALLED: ❌ NO (not implemented anywhere)
  Future<bool> tryAutoLogin(String email) async {
    try {
      loading = true;

      // Get profile to check if user exists
      final profile = await SessionManager.getProfileByEmail(email);
      if (profile == null) {
        print('❌ No profile found for: $email');
        return false;
      }

      // Check if Supabase has a valid session
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session != null && supabase.auth.currentUser?.email == email) {
        // User already logged in
        await restore();
        return true;
      }

      // If no session, auto login not possible
      print('❌ No active session for: $email');
      return false;
    } catch (e) {
      print('❌ Try auto login error: $e');
      return false;
    } finally {
      loading = false;
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
      print('🔄 App resumed, checking auto login...');
      this.state.restoreWithAutoLogin();
    }
  }
}

/// --------------------------------------------------
/// MAIN
/// --------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 Starting app initialization...');

  try {
    // Initialize Environment Manager FIRST
    final env = EnvironmentManager();
    await env.init(flavor: 'development'); // or 'production'

    // Validate environment
    try {
      env.validate();
    } catch (e) {
      print('❌ Environment validation failed: $e');
      print('💡 Please check your .env file');
      return;
    }

    // Print environment info
    if (env.debugMode) {
      env.printInfo();
    }

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ CORRECT: Initialize Supabase 2.12.0
    print('🔄 Initializing Supabase 2.12.0...');

    // Configure Supabase
    await Supabase.initialize(
      url: env.supabaseUrl,
      anonKey: env.supabaseAnonKey,
      // authOptions is optional in 2.12.0
      // Session persistence is enabled by default
    );

    print('✅ Supabase initialized');

    // ✅ IMPORTANT: Check if session persistence is working
    final supabase = Supabase.instance.client;
    print('🔍 Supabase Configuration:');
    print('   - URL: ${env.supabaseUrl.substring(0, 30)}...');
    print('   - Has session: ${supabase.auth.currentSession != null}');
    print('   - Current user: ${supabase.auth.currentUser?.email ?? "None"}');
    print(
      '   - Session expires at: ${supabase.auth.currentSession?.expiresAt}',
    );

    // Initialize SessionManager
    await SessionManager.init();
    print('✅ SessionManager initialized');

    // Set up error handling
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('otp_expired') ||
          msg.contains('access_denied') ||
          msg.contains('Email link is invalid')) {
        return;
      }
      FlutterError.presentError(details);
    };

    LoadingOverlay.setNavigatorKey(navigatorKey);

    // Initialize app state and router
    appState = AppState();
    router = createRouter(appState);

    // Now restore app state
    await appState.restoreWithAutoLogin();
    print('✅ App state restored');

    // Set up lifecycle observer
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(appState));

    // Run the app
    runApp(MyApp(env: env));
  } catch (e, stackTrace) {
    print('❌❌❌ CRITICAL INITIALIZATION ERROR ❌❌❌');
    print('Error: $e');
    print('Stack trace: $stackTrace');

    // Show error screen
    runApp(
      MaterialApp(
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
                    'Initialization Failed',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Error: ${e.toString()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      // Retry initialization
                      main();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// --------------------------------------------------
/// ROUTER
/// --------------------------------------------------
GoRouter createRouter(AppState state) {
  return GoRouter(
    navigatorKey: navigatorKey,
    refreshListenable: state,
    initialLocation: '/',
    redirect: (context, s) async {
      final path = s.matchedLocation;

      print('🔄 Router redirect called:');
      print('   - Path: $path');
      print('   - State loading: ${state.loading}');
      print('   - State loggedIn: ${state.loggedIn}');
      print('   - State emailVerified: ${state.emailVerified}');
      print('   - State profileCompleted: ${state.profileCompleted}');
      print('   - State role: ${state.role}');

      // Show splash screen while loading
      if (state.loading) {
        print('   ➡️ Still loading, staying at splash screen');
        return '/';
      }

      // ✅ FIX: Check if should show continue screen FIRST
      if (!state.loggedIn) {
        print('   ➡️ User not logged in, checking for continue screen...');

        final shouldShowContinue =
            await SessionManager.shouldShowContinueScreen();
        final hasProfiles = await SessionManager.hasProfile();

        print('   ➡️ Should show continue: $shouldShowContinue');
        print('   ➡️ Has profiles: $hasProfiles');

        // If we have profiles and should show continue, go to continue screen
        if (shouldShowContinue && hasProfiles) {
          if (path == '/continue') {
            print('   ➡️ Redirecting to continue screen...');
            return '/continue';
          }
          print('   ➡️ Already at continue screen');
          return null;
        }
      }

      // ❌ NOT LOGGED IN
      if (!state.loggedIn) {
        print('   ➡️ User not logged in and no continue screen needed');

        // Routes allowed without login
        const publicRoutes = {
          // '/',
          '/login',
          '/signup',
          '/reg',
          '/verify-email',
          '/continue',
        };

        // Allow public routes
        if (publicRoutes.contains(path)) {
          print('   ➡️ Allowing public route: $path');
          return null;
        }

        // Otherwise → login
        print('   ➡️ Redirecting to login');
        return '/login';
      }

      // ❌ EMAIL NOT VERIFIED
      if (!state.emailVerified) {
        print('   ➡️ Email not verified');
        return path == '/verify-email' ? null : '/verify-email';
      }

      // ❌ PROFILE NOT CREATED
      if (!state.profileCompleted) {
        print('   ➡️ Profile not completed');
        return path == '/reg' ? null : '/reg';
      }

      // ✅ ROLE BASED HOME
      print('   ➡️ Profile completed, checking role...');
      switch (state.role) {
        case 'business':
          print('   ➡️ Redirecting to owner dashboard');
          return path == '/owner' ? null : '/owner';
        case 'employee':
          print('   ➡️ Redirecting to employee dashboard');
          return path == '/employee' ? null : '/employee';
        default:
          print('   ➡️ Redirecting to customer home');
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
  final EnvironmentManager env;

  const MyApp({super.key, required this.env});

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

    // Handle email verification errors
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
      debugShowCheckedModeBanner: widget.env.debugMode,
      theme: widget.env.enableDarkMode ? ThemeData.dark() : ThemeData.light(),
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
