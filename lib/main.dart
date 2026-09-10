import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_application_1/firebase_options.dart';
import 'package:flutter_application_1/screens/authantication/command/auth_callback_handler.dart';
import 'package:flutter_application_1/screens/authantication/command/clear_data_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/help_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/data_consent_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/email_verify_checker.dart';
import 'package:flutter_application_1/screens/authantication/command/policy_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/registration_flow.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_confirm.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_form.dart';
import 'package:flutter_application_1/screens/authantication/command/reset_password_request.dart';
import 'package:flutter_application_1/screens/authantication/command/role_selector_screen.dart';
import 'package:flutter_application_1/screens/baber/barber_appointments_screen.dart';
import 'package:flutter_application_1/screens/baber/barber_reviews_screen.dart';
import 'package:flutter_application_1/screens/baber/barber_schedule_screen.dart';
import 'package:flutter_application_1/screens/customer/booking_flow_screen.dart';
import 'package:flutter_application_1/screens/customer/customer_history_screen.dart';
import 'package:flutter_application_1/screens/customer/followed_salons_screen.dart';
import 'package:flutter_application_1/screens/customer/my_bookings_screen.dart';
import 'package:flutter_application_1/screens/customer/offers_screen.dart';
import 'package:flutter_application_1/screens/customer/salon_profile_screen.dart';
import 'package:flutter_application_1/screens/customer/search_salons_screen.dart';
import 'package:flutter_application_1/screens/customer/vip_booking_screen.dart';
import 'package:flutter_application_1/screens/owner/analytics_screen.dart';
import 'package:flutter_application_1/screens/owner/appointments_screen.dart';
import 'package:flutter_application_1/screens/owner/customer_list_screen.dart';
import 'package:flutter_application_1/screens/owner/reports_screen.dart';
import 'package:flutter_application_1/screens/owner/revenue_screen.dart';
import 'package:flutter_application_1/screens/settings/auth_settings_screen.dart';
import 'package:flutter_application_1/screens/settings/change_password_screen.dart';
import 'package:flutter_application_1/screens/settings/delete_account_screen.dart';
import 'package:flutter_application_1/screens/settings/notification_screen.dart';
import 'package:flutter_application_1/screens/owner/add_barber_screen.dart';
import 'package:flutter_application_1/screens/owner/add_barber_service_screen.dart';
import 'package:flutter_application_1/screens/owner/add_services.dart';
import 'package:flutter_application_1/screens/owner/barber_leaves_screen.dart';
import 'package:flutter_application_1/screens/owner/barber_list_screen.dart';
import 'package:flutter_application_1/screens/owner/barber_schedule_screen.dart';
import 'package:flutter_application_1/screens/owner/create_salon.dart';
import 'package:flutter_application_1/screens/owner/edit_barber_services_screen.dart';
import 'package:flutter_application_1/screens/owner/edit_salon.dart';
import 'package:flutter_application_1/screens/owner/owner_offers_screen.dart';
import 'package:flutter_application_1/screens/owner/salon_holidays_screen.dart';
import 'package:flutter_application_1/screens/owner/service_management.dart';
import 'package:flutter_application_1/screens/settings/profile_management_screen.dart';
import 'package:flutter_application_1/screens/settings/profile_screen.dart';
import 'package:flutter_application_1/screens/settings/settings_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/timezone_service.dart';
import 'package:flutter_application_1/utils/app_version.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'config/environment_manager.dart';

import 'package:flutter_application_1/theme/theme_notifier.dart';

// Screens
import 'screens/authantication/command/splash.dart';
import 'screens/authantication/command/sign_in.dart';
import 'screens/authantication/command/signup_flow.dart';
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

// Deep link handling (mobile)
final AppLinks _appLinks = AppLinks();
StreamSubscription<Uri>? _linkSubscription;

//command eken flavor eka ganima
const String cmdFlavor = String.fromEnvironment('flavor', defaultValue: '');

// ✅ Global ThemeNotifier instance එක define කරන්න
final ThemeNotifier themeNotifier = ThemeNotifier();

// ==========================================
// FIREBASE BACKGROUND MESSAGE HANDLER | BACKGROUND TOOLCHAIN (TOP-LEVEL FUNCTIONS)
// ==========================================

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final notificationService = NotificationService();
  // Show notification in background
  if (!notificationService.isWeb) {
    await notificationService.showMobileNotification(message);
  }
}

// ==========================================
// WORKMANAGER CALLBACK DISPATCHER
// ==========================================

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("⚙️ Workmanager background task started: $task");

    if (task == "supabaseDataSyncTask") {
      try {
        debugPrint("📥 Syncing data with Supabase...");
        return Future.value(true);
      } catch (e) {
        debugPrint("❌ Sync error: $e");
        return Future.value(false);
      }
    }

    if (task == "periodic_sync") {
      debugPrint("📅 Periodic sync task executed");
      return Future.value(true);
    }

    return Future.value(true);
  });
}

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
      String? currentPath;
      try {
        currentPath =
            router.routerDelegate.currentConfiguration.last.matchedLocation;
      } catch (_) {
        currentPath = null;
      }

      if (currentPath == '/continue' || currentPath == '/login') {
        debugPrint(
          '⏭️ On $currentPath - skipping background auto-login (avoiding wrong-profile race)',
        );
        return;
      }

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
// flover / build mode set kirima
// ====================

String getFlavor() {
  if (cmdFlavor.isNotEmpty) {
    return cmdFlavor;
  }

  if (kDebugMode) {
    return 'development';
  } else if (kProfileMode) {
    return 'staging';
  } else {
    return 'production';
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
    final flavor = getFlavor();
    await environment.init(flavor: flavor);

    // ========== PHASE 2: SUPABASE ==========
    await Supabase.initialize(
      url: environment.supabaseUrl,
      publishableKey: environment.supabaseAnonKey,
      debug: kDebugMode,
    );

    // ========== PHASE 3: FIREBASE ==========
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await Workmanager().initialize(callbackDispatcher);
      debugPrint('💼 Workmanager initialized successfully');

      await Workmanager().registerPeriodicTask(
        "periodic_sync",
        "supabaseDataSyncTask",
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
          requiresStorageNotLow: true,
        ),
      );
      debugPrint('📅 Periodic sync task registered');
    } else {
      debugPrint('🌐 Web: Skipping Workmanager and background handler');
    }

    // ========== PHASE 4: NOTIFICATION SERVICE ==========
    final notificationService = NotificationService();

    await notificationService.initWithoutPermission();
    debugPrint(
      '🔔 Notification service initialized WITHOUT permission (Web + Mobile)',
    );

    // ========== PHASE 5: PLATFORM CONFIG ==========
    // ⚠️ MOVED: deep link setup (_setupPlatformSpecificConfig) is no
    // longer called here. It's moved to PHASE 9B, AFTER the router
    // is created - see the note there for why.

    // ========== PHASE 6: SERVICES ==========
    await SessionManager.init();

    // ========== PHASE 7: APP STATE ==========
    appState = AppState();
    await appState.initializeApp();

    await TimezoneService.initialize();

    // ========== PHASE 8: AUTH LISTENER ==========
    _setupAuthStateListener();

    // ========== PHASE 9: ROUTER ==========
    router = _createRouter();

    // ========== PHASE 9B: PLATFORM CONFIG (deep links) ==========
    await _setupPlatformSpecificConfig();

    // ========== PHASE 10: LIFECYCLE ==========
    WidgetsBinding.instance.addObserver(AppLifecycleObserver());

    // ========== PHASE 11: APP VERSION ==========
    await AppVersion.init();

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

  supabase.auth.onAuthStateChange.listen((data) async {
    final event = data.event;

    if (event == AuthChangeEvent.tokenRefreshed) {
      final session = data.session;
      final user = supabase.auth.currentUser;
      if (session != null && user?.email != null) {
        await SessionManager.saveRefreshToken(
          user!.email!,
          session.refreshToken,
        );
      }
    }

    if (event == AuthChangeEvent.signedIn) {
      await SessionManager.setPendingQuickLogout(false);
      appState.refreshState();
      await NotificationService().syncPendingToken();
    }

    if (event == AuthChangeEvent.signedOut ||
        event == AuthChangeEvent.userUpdated ||
        event == AuthChangeEvent.tokenRefreshed) {
      appState.refreshState();
    }

    if (event == AuthChangeEvent.passwordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateTo('/reset-password-form');
      });
    }
  });
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
// ROLE RECOVERY CHECK
// ====================
Future<bool> _hasRecoverableRoles() async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await Supabase.instance.client
        .from('user_roles')
        .select('id')
        .eq('user_id', userId)
        .inFilter('status', ['inactive', 'scheduled_for_deletion'])
        .limit(1);

    return response.isNotEmpty;
  } catch (e) {
    debugPrint('❌ Error checking recoverable roles: $e');
    return false;
  }
}

// ============================================================
// ✅ NEW: SHARED SESSION-FROM-URL PROCESSOR
// ------------------------------------------------------------
// Single source of truth for turning a raw auth redirect URI
// (from either a mobile deep link OR the web's initial page URL)
// into an established Supabase session, using Supabase's own
// getSessionFromUrl() — which correctly reads BOTH query params
// (?code=...) AND the URL fragment (#access_token=...), unlike
// manual uri.queryParameters checks which silently miss fragment
// tokens.
//
// Previously this logic was duplicated (and each copy was
// incomplete) in two places:
//   1. main.dart's old _handleDeepLink() — only checked
//      queryParameters, so it NEVER caught fragment-based tokens
//      (which is how Supabase actually sends them for email
//      confirmation / magic link / recovery).
//   2. AuthCallbackHandlerScreen's old _processAuthCallback() —
//      used Uri.base, which is a WEB-ONLY concept. On mobile,
//      Uri.base is meaningless, so session processing there
//      silently no-op'd every time.
//
// Now there is exactly one place this happens. Callers just get
// back a clean, already-classified result map and never touch
// raw URIs again.
// ============================================================
Future<Map<String, dynamic>> _establishSessionFromUri(Uri uri) async {
  final fragParams = uri.fragment.isNotEmpty
      ? Uri.splitQueryString(uri.fragment)
      : <String, String>{};

  final hasQueryToken =
      uri.queryParameters.containsKey('code') ||
      uri.queryParameters.containsKey('access_token');
  final hasFragmentToken = fragParams.containsKey('access_token');

  final error = uri.queryParameters['error'] ?? fragParams['error'];
  final errorCode =
      uri.queryParameters['error_code'] ?? fragParams['error_code'];
  final errorDescription =
      uri.queryParameters['error_description'] ??
      fragParams['error_description'];

  // ✅ An explicit error in the URL (e.g. expired link) always wins,
  // regardless of whether a token is also present.
  if (error != null || errorCode != null) {
    debugPrint('⚠️ Auth URL contains an error: $error / $errorCode');
    return {
      'status': 'error',
      'error': error,
      'errorCode': errorCode,
      'errorDescription': errorDescription,
    };
  }

  if (!hasQueryToken && !hasFragmentToken) {
    debugPrint('ℹ️ Auth URL has no recognizable token, skipping');
    return {'status': 'none'};
  }

  try {
    debugPrint('🔐 Establishing session from URL: $uri');
    final response = await Supabase.instance.client.auth.getSessionFromUrl(uri);
    final user = response.session.user;

    debugPrint('✅ Session established for: ${user.email}');

    // ✅ Refresh global app state immediately so router redirect
    // logic (emailVerified, loggedIn, roles, etc.) reflects the new
    // session right away, without waiting for the next auth event.
    appState.refreshState();

    final type = uri.queryParameters['type'] ?? fragParams['type'];

    return {
      'status': 'success',
      'type': type,
      'userId': user.id,
      'email': user.email,
    };
  } catch (e) {
    debugPrint('❌ Error establishing session from URL: $e');
    return {
      'status': 'error',
      'error': e.toString(),
      'errorCode': null,
      'errorDescription': null,
    };
  }
}

Future<void> _setupPlatformSpecificConfig() async {
  if (kIsWeb) {
    debugPrint('Configuring for Web');
    final uri = Uri.base;
    final uriString = uri.toString();

    final looksLikeAuthCallback =
        uriString.contains('/auth/callback') ||
        uri.fragment.contains('access_token') ||
        uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error');

    if (looksLikeAuthCallback) {
      debugPrint('Web auth callback detected, establishing session...');
      final result = await _establishSessionFromUri(uri);
      try {
        router.go('/auth/callback', extra: result);
      } catch (e) {
        debugPrint('❌ Error navigating to auth callback on web: $e');
      }
    }
  } else {
    debugPrint('Configuring for Mobile');
    await _setupMobileDeepLinks();
  }
}

// ✅ app_links package පාවිච්චි කරලා, Android/iOS වලට reliable
// deep link handling (Uri.base වෙනුවට)
Future<void> _setupMobileDeepLinks() async {
  try {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      debugPrint('📱 Initial deep link: $initialUri');
      pendingDeepLink = initialUri.toString();
      _handleDeepLink(initialUri);
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('📱 Deep link received: $uri');
        pendingDeepLink = uri.toString();
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('❌ Deep link stream error: $err');
      },
    );
  } catch (e) {
    debugPrint('Mobile deep link error: $e');
  }
}

// ============================================================
// ✅ FIX: previously only checked uri.queryParameters, which is
// always empty for Supabase's fragment-based redirects
// (myapp://auth/callback#access_token=...) — so this handler
// silently never fired for email verification / magic link /
// recovery links, only for OAuth-code-style links.
//
// Now delegates entirely to _establishSessionFromUri(), which
// checks both query AND fragment, then forwards a clean status
// result to the /auth/callback route via `extra`.
// ============================================================
void _handleDeepLink(Uri uri) async {
  final uriString = uri.toString();

  if (uriString.contains('myapp://') || uriString.contains('/auth/callback')) {
    debugPrint('🔗 Auth deep link detected: $uriString');

    final result = await _establishSessionFromUri(uri);

    if (result['status'] == 'none') {
      // No recognizable auth token in this link at all — nothing to
      // navigate for (e.g. some other custom-scheme deep link).
      debugPrint('ℹ️ Deep link had no auth token, ignoring');
      return;
    }

    try {
      router.go('/auth/callback', extra: result);
    } catch (e) {
      debugPrint('❌ Error navigating to auth callback: $e');
    }
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

      // ============================================
      // 1. NEVER REDIRECT - Auth callbacks
      // ============================================
      if (path == '/auth/callback' ||
          queryParams.containsKey('code') ||
          queryParams.containsKey('access_token')) {
        debugPrint('✅ Auth callback - no redirect');
        return null;
      }

      // ============================================
      // 2. APPSTATE LOADING - Wait
      // ============================================
      if (appState.loading) {
        debugPrint('⏳ AppState loading - no redirect');
        return null;
      }

      // ============================================
      // 2B. PENDING DELETION-RESTORE / REACTIVATION
      // ============================================
      if (appState.loggedIn &&
          (appState.pendingDeletionRestore || appState.pendingReactivation) &&
          path != '/account-restore-pending' &&
          path != '/clear-data') {
        debugPrint(
          '⏸️ Pending restore/reactivation confirmation → /account-restore-pending',
        );
        return '/account-restore-pending';
      }

      // ============================================
      // 3. ALWAYS ACCESSIBLE ROUTES
      // ============================================
      if (path == '/clear-data') {
        debugPrint('✅ Clear data screen - allowing access');
        return null;
      }

      // ============================================
      // 4. PUBLIC ROUTES
      // ============================================
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

      if (path == '/role-selector') {
        if (!appState.loggedIn) {
          debugPrint('❌ Not logged in → /login');
          return '/login';
        }
        debugPrint('✅ Role selector - allowing access');
        return null;
      }

      if (publicRoutes.contains(path)) {
        if (path == '/') {
          if (appState.loggedIn) {
            if (!appState.emailVerified) {
              debugPrint('📧 Email not verified → /verify-email');
              return '/verify-email';
            }
            if (!appState.profileCompleted) {
              if (appState.roles.isEmpty) {
                final recoverable = await _hasRecoverableRoles();
                if (recoverable) {
                  debugPrint(
                    '⏸️ No active roles but has recoverable roles → /settings/profiles',
                  );
                  return '/settings/profiles';
                }
              }
              debugPrint('📝 Profile not completed → /reg');
              return '/reg';
            }
            if (appState.roles.isEmpty) {
              final recoverable = await _hasRecoverableRoles();
              if (recoverable) {
                debugPrint(
                  '⏸️ No roles found but has recoverable roles → /settings/profiles',
                );
                return '/settings/profiles';
              }
              debugPrint('⚠️ No roles found → /reg');
              return '/reg';
            }

            if (appState.currentRole != null) {
              final targetRoute = '/${appState.currentRole}';
              debugPrint(
                '✅ Has current role: ${appState.currentRole} → $targetRoute',
              );
              return targetRoute;
            }

            if (appState.roles.length > 1) {
              debugPrint('🔄 Multiple roles, no current role → /role-selector');
              return '/role-selector';
            }

            if (appState.roles.length == 1) {
              final role = appState.roles.first;
              debugPrint('✅ Single role: $role → /$role');
              await SessionManager.saveCurrentRole(role);
              return '/$role';
            }
          } else {
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

        if (path == '/reg') {
          if (!appState.loggedIn) {
            debugPrint('⚠️ /reg requires login → /login');
            return '/login';
          }
          debugPrint('✅ Allowing access to /reg');
          return null;
        }

        debugPrint('✅ Public route: $path');
        return null;
      }

      // ============================================
      // 5. PROTECTED ROUTES - Login Required
      // ============================================
      if (!appState.loggedIn) {
        final hasProfile = await SessionManager.hasProfile();
        if (hasProfile && path != '/continue') {
          debugPrint('❌ Not logged in but has profile → /continue');
          return '/continue';
        }
        debugPrint('❌ Not logged in → /login');
        return '/login';
      }

      if (!appState.emailVerified && path != '/verify-email') {
        debugPrint('❌ Email not verified → /verify-email');
        return '/verify-email';
      }

      if (!appState.profileCompleted &&
          path != '/reg' &&
          path != '/settings/profiles') {
        debugPrint('❌ Profile not completed → /reg');
        return '/reg';
      }

      if (appState.currentRole == null && appState.roles.isNotEmpty) {
        debugPrint('⚠️ No current role but has roles → /role-selector');
        return '/role-selector';
      }

      // ============================================
      // 6. CUSTOMER ROUTES - FIXED
      // ============================================
      final customerRoutes = [
        '/customer',
        '/customer/my-bookings',
        '/customer/booking-flow',
        '/customer/book',
        '/customer/vip-booking',
        '/customer/salon-profile',
      ];

      final isCustomerRoute = customerRoutes.any(
        (route) => path.startsWith('/customer'),
      );

      if (isCustomerRoute) {
        debugPrint('🛍️ Customer route accessed: $path');

        if (appState.currentRole != 'customer' &&
            !appState.roles.contains('customer')) {
          debugPrint('❌ Not a customer role, redirecting...');
          if (appState.currentRole != null) {
            return '/${appState.currentRole}';
          }
          if (appState.roles.isNotEmpty) {
            return '/role-selector';
          }
          return '/reg';
        }

        if (appState.currentRole != 'customer' &&
            appState.roles.contains('customer')) {
          debugPrint(
            '⚠️ Current role ${appState.currentRole} but has customer role → /role-selector',
          );
          return '/role-selector';
        }

        debugPrint('✅ Customer route access granted: $path');
        return null;
      }

      // ============================================
      // 7. OWNER ROUTES
      // ============================================
      final ownerRoutes = [
        '/owner',
        '/owner/add-barber',
        '/owner/services/add',
        '/owner/services',
        '/owner/barber-schedule',
        '/owner/barber-leaves',
        '/owner/barbers',
        '/owner/edit-barber-services',
        '/owner/vip-requests',
        '/owner/genders/add',
        '/owner/age-categories/add',
        '/owner/salon/holidays',
        '/owner/salon/create',
        '/owner/salon/edit',
        '/owner/categories/add',
        '/owner/salon/:salonId/barber/:barberId/add-service',
      ];

      final isOwnerRoute = ownerRoutes.any(
        (route) => path.startsWith('/owner'),
      );

      if (isOwnerRoute) {
        debugPrint('👑 Owner route accessed: $path');

        if (appState.currentRole != 'owner' &&
            !appState.roles.contains('owner')) {
          debugPrint('❌ Not an owner role, redirecting...');
          if (appState.currentRole != null) {
            return '/${appState.currentRole}';
          }
          if (appState.roles.isNotEmpty) {
            return '/role-selector';
          }
          return '/reg';
        }

        if (appState.currentRole != 'owner' &&
            appState.roles.contains('owner')) {
          debugPrint(
            '⚠️ Current role ${appState.currentRole} but has owner role → /role-selector',
          );
          return '/role-selector';
        }

        debugPrint('✅ Owner route access granted: $path');
        return null;
      }

      // ============================================
      // 8. BARBER ROUTES
      // ============================================
      final barberRoutes = ['/barber'];
      final isBarberRoute = barberRoutes.any(
        (route) => path.startsWith('/barber'),
      );

      if (isBarberRoute) {
        debugPrint('💇 Barber route accessed: $path');

        if (appState.currentRole != 'barber' &&
            !appState.roles.contains('barber')) {
          debugPrint('❌ Not a barber role, redirecting...');
          if (appState.currentRole != null) {
            return '/${appState.currentRole}';
          }
          if (appState.roles.isNotEmpty) {
            return '/role-selector';
          }
          return '/reg';
        }

        if (appState.currentRole != 'barber' &&
            appState.roles.contains('barber')) {
          debugPrint(
            '⚠️ Current role ${appState.currentRole} but has barber role → /role-selector',
          );
          return '/role-selector';
        }

        debugPrint('✅ Barber route access granted: $path');
        return null;
      }

      // ============================================
      // 9. DASHBOARD REDIRECTS
      // ============================================
      final roleToPath = {
        'owner': '/owner',
        'barber': '/barber',
        'customer': '/customer',
      };

      for (var entry in roleToPath.entries) {
        if (path == entry.value) {
          if (appState.currentRole == entry.key) {
            debugPrint('✅ Already on correct dashboard: $path');
            return null;
          } else {
            final correctPath =
                '/${appState.currentRole ?? appState.roles.first}';
            debugPrint('⚠️ Wrong dashboard - redirecting to $correctPath');
            return correctPath;
          }
        }
      }

      // ============================================
      // 10. DEFAULT - Allow access
      // ============================================
      debugPrint('✅ Allowing access to: $path');
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
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
      GoRoute(path: '/signup', builder: (_, _) => const SignupFlow()),
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
        builder: (_, _) => const EmailVerifyChecker(),
      ),
      GoRoute(
        path: '/verify-invalid',
        builder: (_, _) => const VerifyInvalidScreen(),
      ),
      GoRoute(path: '/continue', builder: (_, _) => const ContinueScreen()),
      GoRoute(
        path: '/account-restore-pending',
        builder: (_, _) => const _PendingRestoreScreen(),
      ),
      GoRoute(
        path: '/role-selector',
        name: 'roleSelector',
        builder: (context, state) {
          final extra = state.extra as Map?;
          List<String> roles = [];

          if (extra?['roles'] != null) {
            final dynamic rolesFromExtra = extra!['roles'];
            if (rolesFromExtra is List<String>) {
              roles = rolesFromExtra;
            } else if (rolesFromExtra is List) {
              roles = rolesFromExtra.map((e) => e.toString()).toList();
            }
          }

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
      GoRoute(
        path: '/barber',
        builder: (_, _) {
          debugPrint('💇 Navigating to EmployeeDashboard');
          return const EmployeeDashboard();
        },
      ),
      GoRoute(
        path: '/owner',
        builder: (_, _) {
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
        builder: (_, _) => const HelpScreen(screenType: 'help'),
      ),
      GoRoute(
        path: '/contact',
        builder: (_, _) => const HelpScreen(screenType: 'contact'),
      ),
      GoRoute(
        path: '/about',
        builder: (_, _) => const HelpScreen(screenType: 'about'),
      ),
      GoRoute(path: '/clear-data', builder: (_, _) => const ClearDataScreen()),
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
      // ============================================================
      // ✅ FIX: this route now also reads `state.extra`, which is
      // where main.dart's _establishSessionFromUri() result lands
      // (status/type/userId/email). Query params are still read as
      // a fallback for direct-link cases (e.g. an error-only link
      // opened with no prior processing).
      // ============================================================
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          return MaterialPage(
            key: state.pageKey,
            child: AuthCallbackHandlerScreen(
              code: state.uri.queryParameters['code'],
              error:
                  extra?['error'] as String? ??
                  state.uri.queryParameters['error'],
              errorCode:
                  extra?['errorCode'] as String? ??
                  state.uri.queryParameters['error_code'],
              errorDescription:
                  extra?['errorDescription'] as String? ??
                  state.uri.queryParameters['error_description'],
              preProcessedStatus: extra?['status'] as String?,
              preProcessedType: extra?['type'] as String?,
              preProcessedUserId: extra?['userId'] as String?,
              preProcessedEmail: extra?['email'] as String?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordRequestScreen(),
      ),
      GoRoute(
        path: '/reset-password-form',
        builder: (_, _) => const ResetPasswordFormScreen(),
      ),
      GoRoute(
        path: '/reset-password-confirm',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ResetPasswordConfirmScreen(email: extra?['email'] ?? '');
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) {
          final role = state.uri.queryParameters['role'] ?? 'customer';
          return NotificationScreen(role: role);
        },
      ),
      // Settings Routes
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/profiles',
        builder: (context, state) => const ProfileManagementScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings/auth',
        builder: (context, state) => const AuthSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/settings/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),

      // ============================================
      // OWNER ROUTES
      // ============================================
      GoRoute(
        path: '/owner/customers',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return CustomerListScreen(salonId: salonId, role: 'owner');
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
        path: '/owner/services/add',
        name: 'addService',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          final salonBarberId = state.uri.queryParameters['salonBarberId'];
          final barberName = state.uri.queryParameters['barberName'];
          final isEditing = state.uri.queryParameters['isEditing'] == 'true';
          final serviceId = state.uri.queryParameters['serviceId'];

          if (salonId == null || salonId.isEmpty) {
            debugPrint('❌ Error: salonId is required for adding service');
            return const OwnerDashboard();
          }

          int? parsedSalonId;
          try {
            parsedSalonId = int.parse(salonId);
          } catch (e) {
            debugPrint('❌ Error parsing salonId: $e');
            return const OwnerDashboard();
          }

          int? parsedSalonBarberId;
          if (salonBarberId != null && salonBarberId.isNotEmpty) {
            try {
              parsedSalonBarberId = int.parse(salonBarberId);
            } catch (e) {
              debugPrint('❌ Error parsing salonBarberId: $e');
            }
          }

          int? parsedServiceId;
          if (serviceId != null && serviceId.isNotEmpty && isEditing) {
            try {
              parsedServiceId = int.parse(serviceId);
            } catch (e) {
              debugPrint('❌ Error parsing serviceId: $e');
            }
          }

          final decodedBarberName = barberName != null
              ? Uri.decodeComponent(barberName)
              : null;

          debugPrint(
            '📍 Navigating to Add Service - Salon ID: $parsedSalonId, Barber: $decodedBarberName, Edit: $isEditing',
          );

          return AddServiceScreen(
            salonId: parsedSalonId,
            salonBarberId: parsedSalonBarberId,
            barberName: decodedBarberName,
            isEditing: isEditing,
            serviceId: parsedServiceId,
          );
        },
      ),
      GoRoute(
        path: '/owner/services',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          final salonName = state.uri.queryParameters['salonName'];

          if (salonId == null || salonId.isEmpty) {
            debugPrint('❌ Error: salonId is required for service management');
            return const OwnerDashboard();
          }

          int? parsedSalonId;
          try {
            parsedSalonId = int.parse(salonId);
          } catch (e) {
            debugPrint('❌ Error parsing salonId: $e');
            return const OwnerDashboard();
          }

          final decodedSalonName = salonName != null
              ? Uri.decodeComponent(salonName)
              : 'Salon';

          debugPrint(
            '📍 Navigating to Service Management - Salon ID: $parsedSalonId, Name: $decodedSalonName',
          );

          return ServiceManagementScreen(
            salonId: parsedSalonId,
            salonName: decodedSalonName,
          );
        },
      ),
      GoRoute(
        path: '/owner/salon/:salonId/barber/:barberId/add-service',
        name: 'addBarberService',
        pageBuilder: (context, state) {
          final salonId = state.pathParameters['salonId']!;
          final barberId = state.pathParameters['barberId']!;
          final extra = state.extra as Map<String, dynamic>?;

          return MaterialPage(
            key: state.pageKey,
            child: AddBarberServiceScreen(
              salonId: salonId,
              barberId: barberId,
              salonBarberId: extra?['salonBarberId'],
              barberName: extra?['barberName'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/owner/salon/create',
        name: 'createSalon',
        builder: (context, state) => const CreateSalonScreen(),
      ),
      GoRoute(
        path: '/owner/salon/edit',
        builder: (context, state) {
          final salonIdStr = state.uri.queryParameters['salonId'];
          if (salonIdStr == null) {
            return const OwnerDashboard();
          }
          final salonId = int.parse(salonIdStr);
          return EditSalonScreen(salonId: salonId);
        },
      ),
      GoRoute(
        path: '/owner/barber-schedule',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return BarberScheduleScreen(salonId: salonId);
        },
      ),
      GoRoute(
        path: '/owner/barber-leaves',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return BarberLeavesScreen(salonId: salonId);
        },
      ),
      GoRoute(
        path: '/owner/barbers',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return BarberListScreen(salonId: salonId);
        },
      ),
      GoRoute(
        path: '/owner/edit-barber-services',
        builder: (context, state) {
          final barberId = state.uri.queryParameters['barberId']!;
          final salonId = state.uri.queryParameters['salonId']!;
          return EditBarberServicesScreen(barberId: barberId, salonId: salonId);
        },
      ),
      GoRoute(
        path: '/owner/salon/holidays',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          final salonName = state.uri.queryParameters['salonName'] ?? 'Salon';
          if (salonId == null) return const OwnerDashboard();
          return SalonHolidaysScreen(
            salonId: int.parse(salonId),
            salonName: salonName,
          );
        },
      ),
      GoRoute(
        path: '/owner/offers/:salonId',
        name: 'owner-offers',
        builder: (context, state) {
          final salonId = state.pathParameters['salonId'];
          return OwnerOffersScreen(salonId: salonId);
        },
      ),
      GoRoute(
        path: '/owner/appointments',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          final filter = state.uri.queryParameters['filter'];
          return AppointmentsScreen(salonId: salonId, filter: filter);
        },
      ),
      GoRoute(
        path: '/owner/revenue',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return RevenueScreen(salonId: salonId, role: 'owner');
        },
      ),
      GoRoute(
        path: '/owner/reports',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return ReportsScreen(salonId: salonId, role: 'owner');
        },
      ),
      GoRoute(
        path: '/owner/analytics',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return AnalyticsScreen(salonId: salonId, role: 'owner');
        },
      ),

      // ============================================
      // CUSTOMER ROUTES
      // ============================================
      GoRoute(
        path: '/customer',
        builder: (_, _) {
          debugPrint('🏠 Navigating to CustomerDashboard');
          return const CustomerDashboard();
        },
      ),
      GoRoute(
        path: '/customer/booking-flow',
        name: 'booking-flow',
        builder: (context, state) {
          final salon = state.extra as Map<String, dynamic>?;
          return BookingFlowScreen(initialSalon: salon);
        },
      ),
      GoRoute(
        path: '/customer/vip-booking',
        builder: (context, state) => const VIPBookingScreen(),
      ),
      GoRoute(
        path: '/customer/salon-profile',
        name: 'salon-profile',
        builder: (context, state) {
          final salon = state.extra as Map<String, dynamic>;
          return SalonProfileScreen(salon: salon);
        },
      ),
      GoRoute(
        path: '/customer/my-bookings',
        name: 'my-bookings',
        builder: (context, state) => const MyBookingsScreen(),
      ),
      GoRoute(
        path: '/customer/offers',
        name: 'customer-offers',
        builder: (context, state) => const OffersScreen(),
      ),
      GoRoute(
        path: '/customer/my-salons',
        name: 'my-salons',
        builder: (context, state) => const FollowedSalonsScreen(),
      ),
      GoRoute(
        path: '/customer/search-salons',
        name: 'search-salons',
        builder: (context, state) => const SearchSalonsScreen(),
      ),
      GoRoute(
        path: '/customer/history',
        name: 'customer-history',
        builder: (context, state) => const CustomerHistoryScreen(),
      ),

      // ============================================
      // BABER ROUTES
      // ============================================
      GoRoute(
        path: '/barber/appointments',
        name: 'barber-appointments',
        builder: (context, state) => const BarberAppointmentsScreen(),
      ),
      GoRoute(
        path: '/barber/revenue',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return RevenueScreen(salonId: salonId, role: 'barber');
        },
      ),
      GoRoute(
        path: '/barber/reports',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return ReportsScreen(salonId: salonId, role: 'barber');
        },
      ),
      GoRoute(
        path: '/barber/analytics',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return AnalyticsScreen(salonId: salonId, role: 'barber');
        },
      ),
      GoRoute(
        path: '/barber/schedule',
        name: 'barber-schedule',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return BarberScheduleViewScreen(salonId: salonId);
        },
      ),
      GoRoute(
        path: '/barber/reviews',
        builder: (context, state) {
          final salonId = state.uri.queryParameters['salonId'];
          return BarberReviewsScreen(salonId: salonId, barberId: null);
        },
      ),
    ],
  );
}

// ====================
// MAIN APP - UPDATED WITH CONTEXT EXTENSIONS
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

  bool _restoreDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _initNetworkMonitoring();
    appState.addListener(_onAppStateChanged);
    themeNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    setState(() {});
  }

  void _initNetworkMonitoring() {
    _networkService = NetworkService();
    _networkSub = _networkService.onStatusChange.listen((online) {
      if (mounted) setState(() => _offline = !online);
    });
  }

  void _onAppStateChanged() {
    if (appState.pendingDeletionRestore && !_restoreDialogShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRestoreDialog();
      });
    } else if (appState.pendingReactivation && !_restoreDialogShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showReactivateDialog();
      });
    }
  }

  // ============================================================
  // ✅ RESTORE DIALOG - AppTheme based
  // ============================================================
  Future<void> _showRestoreDialog() async {
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || _restoreDialogShowing) return;

    _restoreDialogShowing = true;

    final daysRemaining = appState.deletionRestoreDaysRemaining;
    final isDark = dialogContext.isDarkMode;
    final primaryColor = dialogContext.primaryColor;
    final textColor = dialogContext.textColor;
    final secondaryTextColor = dialogContext.secondaryTextColor;

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          // ✅ Use isDark for theme-aware dialog
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.restore, color: primaryColor),
              const SizedBox(width: 8),
              Text('Restore Your Account?', style: TextStyle(color: textColor)),
            ],
          ),
          content: Text(
            daysRemaining != null
                ? 'Your account is scheduled for deletion in $daysRemaining '
                      'days. Would you like to restore it and continue using '
                      'the app, or log out and let the deletion proceed?'
                : 'Your account is scheduled for deletion. Would you like '
                      'to restore it and continue using the app, or log out '
                      'and let the deletion proceed?',
            style: TextStyle(color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                _restoreDialogShowing = false;
                await appState.declineRestoreAndLogout();
                if (navigatorKey.currentContext != null) {
                  router.go('/login');
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : Colors.grey[700],
              ),
              child: const Text('Log Out'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                _restoreDialogShowing = false;
                await appState.confirmRestoreScheduledProfile();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Restore My Account'),
            ),
          ],
        ),
      ),
    );

    _restoreDialogShowing = false;
  }

  // ============================================================
  // ✅ REACTIVATE DIALOG - AppTheme based
  // ============================================================
  Future<void> _showReactivateDialog() async {
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || _restoreDialogShowing) return;

    _restoreDialogShowing = true;
    final primaryColor = dialogContext.primaryColor;

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.restore, color: primaryColor),
              const SizedBox(width: 8),
              const Text('Reactivate Your Account?'),
            ],
          ),
          content: const Text(
            'Your account is currently deactivated. Would you like to '
            'reactivate it and continue using the app, or log out and '
            'keep it deactivated?',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                _restoreDialogShowing = false;
                await appState.declineReactivationAndLogout();
                if (navigatorKey.currentContext != null) {
                  router.go('/login');
                }
              },
              child: const Text('Log Out'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                _restoreDialogShowing = false;
                await appState.confirmReactivateProfile();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reactivate My Account'),
            ),
          ],
        ),
      ),
    );

    _restoreDialogShowing = false;
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _networkService.dispose();
    _linkSubscription?.cancel();
    appState.removeListener(_onAppStateChanged);
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Salon Management',

      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeNotifier.currentTheme,

      builder: (context, child) {
        return Stack(
          children: [
            // ✅ EDGE-TO-EDGE: SafeArea for Android 16
            SafeArea(
              bottom: false,
              child: AbsorbPointer(
                absorbing: _offline,
                child: child ?? const SizedBox(),
              ),
            ),
            if (_offline)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: NetworkBanner(offline: _offline),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ====================
// PENDING RESTORE SCREEN - AppTheme based
// ====================
class _PendingRestoreScreen extends StatelessWidget {
  const _PendingRestoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Center(
        child: CircularProgressIndicator(color: context.primaryColor),
      ),
    );
  }
}

// ====================
// ERROR APP - AppTheme based
// ====================
class _ErrorApp extends StatelessWidget {
  final String error;
  const _ErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: context.backgroundColor,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(context.responsivePadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: context.errorColor),
                const SizedBox(height: 20),
                Text(
                  'Unable to Start App',
                  style: context.headlineSmall.copyWith(
                    color: context.textColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: context.bodyMedium.copyWith(
                    color: context.secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => main(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primaryColor,
                    foregroundColor: Colors.white,
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
    if (kDebugMode) debugPrint('🚀 Pushed: ${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) debugPrint('🔙 Popped: ${route.settings.name}');
  }
}
