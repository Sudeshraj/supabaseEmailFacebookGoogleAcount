import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_svg/svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

final supabase = Supabase.instance.client;

class ContinueScreen extends StatefulWidget {
  const ContinueScreen({super.key});

  @override
  State<ContinueScreen> createState() => _ContinueScreenState();
}

class _ContinueScreenState extends State<ContinueScreen> {
  final EnvironmentManager _env = EnvironmentManager();
  List<Map<String, dynamic>> profiles = [];
  bool _loading = true;
  String? _selectedEmail;
  final Map<String, bool> _profileLoadingStates = {};
  bool _isGoogleImageRateLimited = false;
  DateTime? _lastGoogleImageError;
  bool _selectionMode = false;
  final Set<String> _selectedProfiles = {};
  int _selectedCount = 0;

  @override
  void initState() {
    super.initState();
    _profileLoadingStates.clear();
    _loadProfiles();
    _checkCompliance();
  }

  // ============================================================
  // 🔥 GET DISPLAY NAME FROM PROFILE
  // ============================================================
  String _getDisplayName(Map<String, dynamic> profile) {
    final email = profile['email'] as String? ?? 'User';

    if (profile['full_name'] != null &&
        profile['full_name'].toString().isNotEmpty) {
      return profile['full_name'].toString();
    }

    if (profile['name'] != null && profile['name'].toString().isNotEmpty) {
      return profile['name'].toString();
    }

    if (profile['extra_data'] != null) {
      final extraData = profile['extra_data'] as Map<String, dynamic>;
      if (extraData['full_name'] != null &&
          extraData['full_name'].toString().isNotEmpty) {
        return extraData['full_name'].toString();
      }
      if (extraData['company_name'] != null &&
          extraData['company_name'].toString().isNotEmpty) {
        return extraData['company_name'].toString();
      }
      if (extraData['name'] != null &&
          extraData['name'].toString().isNotEmpty) {
        return extraData['name'].toString();
      }
    }

    if (profile['user_metadata'] != null) {
      final metadata = profile['user_metadata'] as Map<String, dynamic>;
      if (metadata['full_name'] != null &&
          metadata['full_name'].toString().isNotEmpty) {
        return metadata['full_name'].toString();
      }
      if (metadata['name'] != null && metadata['name'].toString().isNotEmpty) {
        return metadata['name'].toString();
      }
    }

    return email.split('@').first;
  }

  /// session validation add
  bool _hasValidSession() {
    try {
      final session = supabase.auth.currentSession;
      if (session == null) return false;

      if (session.expiresAt != null) {
        final expiryTime = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt!,
        );
        return DateTime.now().isBefore(expiryTime);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 🔥 CHECK IF PROFILE HAS ACTIVE ROLES (SAFE VERSION)
  // ============================================================
  /// ✅ Check if profile has active roles - HYBRID VERSION
  /// (informational filter for which profile cards to show in
  /// this quick-access list - not an auth gate)
  Future<bool> _hasActiveRoles(String email, List<String> roles) async {
    try {
      if (roles.isEmpty) return false;

      // ✅ Step 1: Check SessionManager (Fast - No network call)
      final availableProfiles = await SessionManager.getAvailableProfiles();
      debugPrint(
        '📊 Available profiles from SessionManager: $availableProfiles',
      );

      // Check if any role exists in available profiles
      for (String role in roles) {
        final exists = availableProfiles.any(
          (p) => p['email'] == email && p['role'] == role,
        );
        if (exists) {
          debugPrint('✅ Role $role found in available profiles');
          return true;
        }
      }

      // Check from SessionManager profiles
      final allProfiles = await SessionManager.getProfiles();
      for (var profile in allProfiles) {
        if (profile['email'] == email) {
          final profileRoles = profile['roles'] as List? ?? [];
          if (profileRoles.isNotEmpty) {
            debugPrint('✅ Profile has roles in SessionManager: $profileRoles');
            return true;
          }
        }
      }

      // ✅ Step 2: If not found in SessionManager, check DB (Only if session is valid)
      final currentUser = supabase.auth.currentUser;
      final session = supabase.auth.currentSession;

      if (currentUser != null && session != null) {
        // Check if session is valid
        bool sessionValid = true;
        if (session.expiresAt != null) {
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt!,
          );
          sessionValid = DateTime.now().isBefore(expiryTime);
        }

        if (sessionValid) {
          debugPrint('🔄 Valid session found, checking DB for roles...');
          int activeCount = 0;
          for (String role in roles) {
            try {
              final response = await supabase.rpc(
                'get_role_status',
                params: {'p_user_id': currentUser.id, 'p_role': role},
              );

              if (response != null) {
                final status = response['status'] as String? ?? 'active';
                debugPrint('📊 Role $role status from DB: $status');
                if (status == 'active' || status == 'scheduled_for_deletion') {
                  activeCount++;
                }
              }
            } catch (e) {
              debugPrint('⚠️ Error checking role $role in DB: $e');
              // On error, count as active (safe fallback)
              activeCount++;
            }
          }
          return activeCount > 0;
        } else {
          debugPrint('⏭️ Session expired, skipping DB check');
        }
      } else {
        debugPrint('⏭️ No valid session, skipping DB check');
      }

      debugPrint('⚠️ No active roles found for $email');
      return false;
    } catch (e) {
      debugPrint('❌ Error checking active roles: $e');
      // Safe fallback - show profile
      return true;
    }
  }

  // ============================================================
  // 🔥 GET PROFILE STATUS FROM DB (SAFE VERSION)
  // ============================================================
  /// ✅ Get profile status - HYBRID VERSION
  /// (informational only - drives the "Inactive"/"Deleting" badge
  /// on the card. The actual restore/reactivate decision and
  /// blocking/dialog logic lives centrally in AppState + the
  /// GoRouter redirect in main.dart, not here.)
  Future<Map<String, dynamic>?> _getProfileStatus(
    String email,
    String role,
  ) async {
    try {
      // ✅ Step 1: Check SessionManager first (Fast)
      final availableProfiles = await SessionManager.getAvailableProfiles();

      Map<String, dynamic>? cachedProfile = availableProfiles.firstWhere(
        (p) => p['email'] == email && p['role'] == role,
        orElse: () => {},
      );

      // Step 2: If found in available profiles, use it
      if (cachedProfile.isNotEmpty) {
        final status = cachedProfile['status'] as String? ?? 'active';

        // ✅ Step 3: If status is not 'active', check DB for latest
        if (status != 'active') {
          final currentUser = supabase.auth.currentUser;
          final session = supabase.auth.currentSession;

          if (currentUser != null && session != null) {
            // Check if session is valid
            bool sessionValid = true;
            if (session.expiresAt != null) {
              final expiryTime = DateTime.fromMillisecondsSinceEpoch(
                session.expiresAt!,
              );
              sessionValid = DateTime.now().isBefore(expiryTime);
            }

            if (sessionValid) {
              debugPrint(
                '🔄 Valid session found, checking DB for latest status...',
              );
              try {
                final response = await supabase.rpc(
                  'get_role_status',
                  params: {'p_user_id': currentUser.id, 'p_role': role},
                );

                if (response != null) {
                  debugPrint('✅ Got latest status from DB: $response');
                  return response as Map<String, dynamic>?;
                }
              } catch (e) {
                debugPrint('⚠️ RPC failed, using cached status: $e');
              }
            } else {
              debugPrint('⏭️ Session expired, using cached status');
            }
          } else {
            debugPrint('⏭️ No valid session, using cached status');
          }
        }

        // Return cached status (with extra data)
        return {
          'status': status,
          'days_remaining': cachedProfile['days_remaining'],
          'deletion_due_date': cachedProfile['deletion_due_date'],
          'source': 'cache',
        };
      }

      // ✅ Step 4: Not in available profiles, check all profiles
      final allProfiles = await SessionManager.getProfiles();
      for (var profile in allProfiles) {
        if (profile['email'] == email) {
          final extraData =
              profile['extra_data'] as Map<String, dynamic>? ?? {};
          final roleKey = 'profile_$role';

          if (extraData.containsKey(roleKey)) {
            final roleData = extraData[roleKey] as Map<String, dynamic>? ?? {};
            final status = roleData['status'] as String? ?? 'active';

            return {
              'status': status,
              'days_remaining': roleData['days_remaining'],
              'deletion_due_date': roleData['deletion_due_date'],
              'source': 'extra_data',
            };
          }
        }
      }

      // ✅ Step 5: If not found anywhere, try DB (Only if session is valid)
      final currentUser = supabase.auth.currentUser;
      final session = supabase.auth.currentSession;

      if (currentUser != null && session != null) {
        bool sessionValid = true;
        if (session.expiresAt != null) {
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt!,
          );
          sessionValid = DateTime.now().isBefore(expiryTime);
        }

        if (sessionValid) {
          debugPrint('🔄 Checking DB for status (not found in cache)...');
          try {
            final response = await supabase.rpc(
              'get_role_status',
              params: {'p_user_id': currentUser.id, 'p_role': role},
            );

            if (response != null) {
              debugPrint('✅ Got status from DB: $response');
              return response as Map<String, dynamic>?;
            }
          } catch (e) {
            debugPrint('⚠️ RPC failed: $e');
          }
        }
      }

      // ✅ Final fallback
      return {'status': 'active', 'source': 'fallback'};
    } catch (e) {
      debugPrint('⚠️ Error getting profile status: $e');
      return {'status': 'active', 'source': 'error_fallback'};
    }
  }

  // ============================================================
  // 🔥 LOAD PROFILES (UPDATED - PRODUCTION READY)
  // ============================================================
  Future<void> _loadProfiles() async {
    try {
      setState(() => _loading = true);

      // ✅ Check if session is valid
      final bool hasValidSession = _hasValidSession();
      debugPrint('📊 Has valid session: $hasValidSession');

      final allProfiles = await SessionManager.getProfiles();
      debugPrint('📥 All profiles loaded: ${allProfiles.length}');

      if (allProfiles.isEmpty) {
        debugPrint('⚠️ No profiles found');
        setState(() {
          profiles = [];
          _loading = false;
        });
        return;
      }

      final List<Map<String, dynamic>> expandedProfiles = [];

      for (var profile in allProfiles.where((p) => p['rememberMe'] == true)) {
        final dynamic rolesDynamic = profile['roles'];
        final List<String> roles = rolesDynamic is List
            ? rolesDynamic.map((e) => e.toString()).toList()
            : [];

        final email = profile['email'] as String? ?? 'unknown';
        final profileLastLogin = profile['lastLogin'] as String?;

        final displayName = _getDisplayName(profile);
        profile['display_name'] = displayName;

        debugPrint(
          '📋 Processing profile: $email, name: $displayName, roles: $roles',
        );

        if (roles.isEmpty) {
          debugPrint('  → Skipping profile with no roles: $email');
          continue;
        }

        // ✅ Only call _hasActiveRoles if session is valid
        bool hasActiveRoles = true;
        if (hasValidSession) {
          try {
            hasActiveRoles = await _hasActiveRoles(email, roles);
          } catch (e) {
            debugPrint('⚠️ _hasActiveRoles error for $email: $e');
            hasActiveRoles = true; // Safe fallback
          }
        } else {
          debugPrint(
            '⏭️ Skipping _hasActiveRoles (no valid session) for $email',
          );
        }

        if (!hasActiveRoles) {
          debugPrint('  → Skipping profile with no active roles: $email');
          continue;
        }

        debugPrint('  → Profile has active roles: $roles');

        if (roles.length == 1) {
          final newProfile = Map<String, dynamic>.from(profile);
          newProfile['lastLogin'] = profileLastLogin;
          newProfile['display_name'] = displayName;
          newProfile['roles'] = [roles.first];

          // ✅ Only call _getProfileStatus if session is valid
          Map<String, dynamic>? statusInfo;
          if (hasValidSession) {
            try {
              statusInfo = await _getProfileStatus(email, roles.first);
            } catch (e) {
              debugPrint('⚠️ _getProfileStatus error for $email: $e');
              statusInfo = {'status': 'active'};
            }
          } else {
            debugPrint(
              '⏭️ Skipping _getProfileStatus (no valid session) for $email',
            );
            statusInfo = {'status': 'active'};
          }

          if (statusInfo != null) {
            newProfile['status'] = statusInfo['status'] ?? 'active';
            newProfile['days_remaining'] = statusInfo['days_remaining'];
            newProfile['deletion_due_date'] = statusInfo['deletion_due_date'];
          } else {
            newProfile['status'] = 'active';
          }

          expandedProfiles.add(newProfile);
          debugPrint(
            '  → Added profile with single role: ${roles.first}, name: $displayName, status: ${newProfile['status']}',
          );
        } else {
          debugPrint('  → Splitting into ${roles.length} profiles');

          for (var role in roles) {
            final roleProfile = Map<String, dynamic>.from(profile);
            roleProfile['roles'] = [role];
            roleProfile['lastLogin'] = profileLastLogin;
            roleProfile['display_name'] = displayName;

            // ✅ Only call _getProfileStatus if session is valid
            Map<String, dynamic>? statusInfo;
            if (hasValidSession) {
              try {
                statusInfo = await _getProfileStatus(email, role);
              } catch (e) {
                debugPrint('⚠️ _getProfileStatus error for $email - $role: $e');
                statusInfo = {'status': 'active'};
              }
            } else {
              debugPrint(
                '⏭️ Skipping _getProfileStatus (no valid session) for $email - $role',
              );
              statusInfo = {'status': 'active'};
            }

            if (statusInfo != null) {
              roleProfile['status'] = statusInfo['status'] ?? 'active';
              roleProfile['days_remaining'] = statusInfo['days_remaining'];
              roleProfile['deletion_due_date'] =
                  statusInfo['deletion_due_date'];
            } else {
              roleProfile['status'] = 'active';
            }

            expandedProfiles.add(roleProfile);
            debugPrint(
              '    → Created profile for role: $role, name: $displayName, status: ${roleProfile['status']}',
            );
          }
        }
      }

      // Sort profiles (OAuth first)
      expandedProfiles.sort((a, b) {
        final aProvider = a['provider'] as String? ?? 'email';
        final bProvider = b['provider'] as String? ?? 'email';
        if (aProvider != 'email' && bProvider == 'email') return -1;
        if (aProvider == 'email' && bProvider != 'email') return 1;
        return 0;
      });

      // Optimize images
      for (var profile in expandedProfiles) {
        await _optimizeProfileImage(profile);
      }

      if (!mounted) return;
      setState(() {
        profiles = expandedProfiles;
        _loading = false;
        debugPrint('✅ Final profiles count: ${expandedProfiles.length}');
        for (var i = 0; i < expandedProfiles.length; i++) {
          debugPrint(
            '  Profile $i: ${expandedProfiles[i]['email']} - Name: ${expandedProfiles[i]['display_name']} - Role: ${expandedProfiles[i]['roles']?.first} - Status: ${expandedProfiles[i]['status']}',
          );
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading profiles: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _optimizeProfileImage(Map<String, dynamic> profile) async {
    try {
      String? photoUrl;
      if (profile['photo'] != null && (profile['photo'] as String).isNotEmpty) {
        photoUrl = profile['photo'] as String;
      } else if (profile['avatar_url'] != null &&
          (profile['avatar_url'] as String).isNotEmpty) {
        photoUrl = profile['avatar_url'] as String;
      } else if (profile['picture'] != null &&
          (profile['picture'] as String).isNotEmpty) {
        photoUrl = profile['picture'] as String;
      } else if (profile['image'] != null &&
          (profile['image'] as String).isNotEmpty) {
        photoUrl = profile['image'] as String;
      }

      if (photoUrl != null && photoUrl.isNotEmpty) {
        photoUrl = photoUrl.replaceAll('"', '').trim();
        if (!photoUrl.startsWith('http')) {
          photoUrl = 'https:$photoUrl';
        }
        if (photoUrl.contains('googleusercontent.com')) {
          photoUrl = _optimizeGoogleProfileUrl(photoUrl) ?? photoUrl;
        }
        profile['photo'] = photoUrl;
      }
    } catch (e) {
      debugPrint('Error optimizing profile image: $e');
    }
  }

  String? _optimizeGoogleProfileUrl(String? photoUrl) {
    if (photoUrl == null || !photoUrl.contains('googleusercontent.com')) {
      return photoUrl;
    }
    try {
      if (photoUrl.startsWith('//')) photoUrl = 'https:$photoUrl';
      final hasSizeParam =
          photoUrl.contains('=s96') ||
          photoUrl.contains('=s') ||
          photoUrl.contains('?sz=') ||
          photoUrl.contains('/s96-c/');
      if (hasSizeParam) {
        if (photoUrl.contains('=s96')) {
          photoUrl = photoUrl.replaceAll('=s96', '=s200');
        }
        return photoUrl;
      }
      if (!photoUrl.contains('=s') && !photoUrl.contains('?sz=')) {
        if (photoUrl.contains('?')) {
          return '$photoUrl&sz=200';
        } else {
          return '$photoUrl?sz=200';
        }
      }
      return photoUrl;
    } catch (e) {
      debugPrint('Error optimizing Google URL: $e');
      return photoUrl;
    }
  }

  void _handleGoogleImageError() {
    final now = DateTime.now();
    if (_lastGoogleImageError != null) {
      final difference = now.difference(_lastGoogleImageError!);
      if (difference.inMinutes < 5) {
        _isGoogleImageRateLimited = true;
        Future.delayed(const Duration(minutes: 5), () {
          if (mounted) setState(() => _isGoogleImageRateLimited = false);
        });
      }
    }
    _lastGoogleImageError = now;
  }

  Future<void> _checkCompliance() async {
    final rememberMe = await SessionManager.isRememberMeEnabled();
    if (!rememberMe) setState(() {});
  }

  // ============================================================
  // 🔥 HANDLE PROFILE LOGIN
  // ✅ SIMPLIFIED: Removed the role-level "scheduled for deletion"
  // restore dialog + cancelScheduledDeletion() call, and the
  // "Profile Inactive - contact support" hard block. Those
  // duplicated (and could conflict with / double-show alongside)
  // the profile-level restore/reactivate confirmation dialogs now
  // owned centrally by AppState + the GoRouter redirect in
  // main.dart. This screen's job is just: authenticate, then hand
  // off to the router. Status badges on the cards remain purely
  // informational (see _buildProfileCard).
  // ============================================================
  Future<void> _handleProfileLogin(
    Map<String, dynamic> profile,
    String role,
    String uniqueId,
  ) async {
    // ✅ Guard first - before any await points - to prevent double-tap
    // triggering the OAuth flow twice (PKCE code_verifier overwrite bug).
    if (_profileLoadingStates[uniqueId] == true) {
      debugPrint('⏭️ Already processing login for $uniqueId, ignoring tap');
      return;
    }

    setState(() {
      _profileLoadingStates[uniqueId] = true;
    });

    debugPrint('🔐 ===== _handleProfileLogin START =====');
    debugPrint('🔐 Role: $role, UniqueId: $uniqueId');
    debugPrint('📧 Email: ${profile['email']}');
    debugPrint('🔑 Provider: ${profile['provider']}');

    final email = profile['email'] as String?;
    final provider = profile['provider'] as String?;

    if (email == null) {
      debugPrint('❌ No email found');
      setState(() => _profileLoadingStates[uniqueId] = false);
      return;
    }

    setState(() {
      _selectedEmail = email;
    });

    try {
      bool loginSuccess = false;

      debugPrint('🔄 Attempting auto login for: $email');
      final autoSuccess = await SessionManager.tryAutoLogin(email);

      if (autoSuccess) {
        debugPrint('✅ Auto login successful!');
        loginSuccess = true;
      } else if (provider == 'email') {
        debugPrint('🔐 Email login flow started (auto-login failed)');
        SessionManager.setLocationContinuesc(true);
        final password = await _showPasswordDialog(email);
        if (password != null) {
          final response = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
          loginSuccess = response.user != null;
          debugPrint('📊 Email login success: $loginSuccess');
        }
      } else {
        debugPrint(
          '🔐 OAuth login flow started for $provider (auto-login failed)',
        );
        loginSuccess = await _handleOAuthLoginForProfile(profile);
        debugPrint('📊 OAuth login success: $loginSuccess');
      }

      if (loginSuccess && mounted) {
        debugPrint('✅ Login successful for role: $role');

        // ✅ Correct email set as current user before saving role
        // (fixes stale-email validation clearing the role in
        // getCurrentRole()).
        await SessionManager.setCurrentUser(email);
        await SessionManager.saveCurrentRole(role);
        debugPrint('💾 Saved role: $role to SessionManager');

        final currentUser = supabase.auth.currentUser;
        if (currentUser != null) {
          await supabase.auth.updateUser(
            UserAttributes(
              data: {...currentUser.userMetadata ?? {}, 'current_role': role},
            ),
          );
          debugPrint('📝 Updated user metadata with role: $role');
        }

        // ✅ SIMPLIFIED: hand off entirely to AppState + GoRouter.
        // The redirect() logic in main.dart owns all of: blocked/
        // inactive/scheduled-for-deletion handling, the restore/
        // reactivate confirmation dialogs, role-selector vs single-
        // role vs no-active-roles routing, and the "recoverable
        // roles" smart redirect. No manual dashboard switch needed
        // here - context.go('/') lets the router decide.
        await appState.refreshState();
        if (!mounted) return;
        context.go('/');
      } else {
        debugPrint('❌ Login failed for role: $role');
        if (mounted) {
          await showCustomAlert(
            context: context,
            title: "Login Failed",
            message: "Could not log in with this profile. Please try again.",
            isError: true,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Login error: $e');
      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "Login Failed",
          message: e.toString(),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _profileLoadingStates[uniqueId] = false;
          _selectedEmail = null;
        });
      }
      debugPrint('🔐 ===== _handleProfileLogin END =====');
    }
  }

  Future<bool> _handleOAuthLoginForProfile(Map<String, dynamic> profile) async {
    final email = profile['email'] as String?;
    final provider = profile['provider'] as String?;
    if (email == null || provider == null) return false;
    final roles = profile['roles'] as List? ?? [];
    final role = roles.isNotEmpty ? roles.first.toString() : 'customer';
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) return true;

      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) return true;

      await SessionManager.setPendingRoleSelection(email: email, role: role);
      switch (provider) {
        case 'google':
          await supabase.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: _env.getRedirectUrl(),
            scopes: 'email profile',
          );
          SessionManager.setLocationContinuesc(true);
          break;
        case 'facebook':
          await supabase.auth.signInWithOAuth(
            OAuthProvider.facebook,
            redirectTo: _env.getRedirectUrl(),
            scopes: 'email',
          );
          SessionManager.setLocationContinuesc(true);
          break;
        case 'apple':
          await supabase.auth.signInWithOAuth(
            OAuthProvider.apple,
            redirectTo: _env.getRedirectUrl(),
            scopes: 'email name',
          );
          SessionManager.setLocationContinuesc(true);
          break;
        default:
          return false;
      }

      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final user = supabase.auth.currentUser;
        if (user?.email == email) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('OAuth error: $e');
      return false;
    }
  }

  Future<String?> _showPasswordDialog(String email) async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SecurityCompliantPasswordDialog(email: email),
    );
  }

  // ============================================================
  // 🔥 HELPER METHODS
  // ============================================================
  Color _getProviderColor(String? provider) {
    return const Color.fromARGB(255, 242, 241, 241);
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return Colors.blueAccent;
      case 'barber':
        return Colors.orangeAccent;
      case 'customer':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return Icons.work_outline;
      case 'barber':
        return Icons.content_cut;
      case 'customer':
        return Icons.person_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'barber':
        return 'Barber';
      case 'customer':
        return 'Customer';
      default:
        return role;
    }
  }

  String _formatLastLogin(String? lastLogin) {
    if (lastLogin == null || lastLogin.isEmpty) return 'Never';
    try {
      final loginTime = DateTime.parse(lastLogin);
      final now = DateTime.now();
      final difference = now.difference(loginTime);
      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return '${difference.inDays ~/ 7}w ago';
    } catch (e) {
      return 'Recently';
    }
  }

  Widget _buildProviderIcon(String provider) {
    switch (provider.toLowerCase()) {
      case 'google':
        return SvgPicture.asset('icons/google.svg', width: 18, height: 18);
      case 'facebook':
        return SvgPicture.asset('icons/facebook.svg', width: 18, height: 18);
      case 'apple':
        return SvgPicture.asset('icons/apple.svg', width: 20, height: 20);
      case 'email':
        return Icon(
          Icons.email_rounded,
          size: 18,
          color: _getButtonColor(provider.toLowerCase()),
        );
      default:
        return const SizedBox();
    }
  }

  Color _getButtonColor(String provider) {
    switch (provider) {
      case 'google':
        return const Color.fromARGB(255, 227, 44, 8);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'apple':
        return const Color.fromARGB(255, 227, 227, 227);
      case 'email':
        return const Color.fromARGB(255, 30, 30, 31);
      default:
        return const Color.fromARGB(255, 228, 230, 234);
    }
  }

  // ============================================================
  // 🔥 PROFILE CARD (Status badge remains informational-only)
  // ============================================================
  Widget _buildProfileCard(Map<String, dynamic> profile, int index) {
    final email = profile['email'] as String? ?? 'Unknown';
    final provider = profile['provider'] as String? ?? 'email';
    final roles = profile['roles'] as List? ?? [];
    final profileRole = roles.isNotEmpty ? roles.first.toString() : 'customer';
    final uniqueId = '$email-$index-$profileRole';
    final isLoading = _profileLoadingStates[uniqueId] == true;
    final isSelected = _selectedProfiles.contains(uniqueId);
    final photoUrl = profile['photo'] as String?;
    final displayName =
        profile['display_name'] as String? ?? email.split('@').first;

    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final lastLogin = profile['lastLogin'] as String?;
    final roleColor = _getRoleColor(profileRole);
    final roleIcon = _getRoleIcon(profileRole);
    final roleDisplayName = _getRoleDisplayName(profileRole);
    final providerColor = _getProviderColor(provider);

    // ✅ Status badge is informational only - actual gating happens
    // centrally after login (AppState + router), not here.
    final status = profile['status'] as String? ?? 'active';
    final isActive = status == 'active';
    final isScheduledForDeletion = status == 'scheduled_for_deletion';
    final isInactive = status == 'inactive';
    final daysRemaining = profile['days_remaining'] as int?;

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleProfileSelection(profile, uniqueId);
        } else if (isLoading) {
          return;
        } else {
          _handleProfileLogin(profile, profileRole, uniqueId);
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          _startSelectionMode();
          _toggleProfileSelection(profile, uniqueId);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? roleColor.withValues(alpha: 0.15)
              : isLoading
              ? roleColor.withValues(alpha: 0.1)
              : isInactive
              ? Colors.grey.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLoading
                ? roleColor
                : isSelected
                ? roleColor.withValues(alpha: 0.5)
                : isScheduledForDeletion
                ? Colors.orange.withValues(alpha: 0.3)
                : isInactive
                ? Colors.grey.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.1),
            width: isLoading ? 2 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Profile Image with Icons
              SizedBox(
                width: 70,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isScheduledForDeletion
                              ? Colors.orange.withValues(alpha: 0.5)
                              : isInactive
                              ? Colors.grey.withValues(alpha: 0.3)
                              : roleColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (isScheduledForDeletion
                                        ? Colors.orange
                                        : isInactive
                                        ? Colors.grey
                                        : roleColor)
                                    .withValues(alpha: 0.2),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: _buildLargeProfileImage(
                        profile,
                        provider,
                        photoUrl,
                        hasPhoto,
                      ),
                    ),

                    // Provider Icon Badge
                    if (!isLoading && !_selectionMode)
                      Positioned(
                        top: -4,
                        left: -4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: providerColor,
                            border: Border.all(
                              color: const Color(0xFF0F1820),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: providerColor.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Center(child: _buildProviderIcon(provider)),
                        ),
                      ),

                    // Role Icon Badge
                    if (!isLoading && !_selectionMode)
                      Positioned(
                        bottom: -4,
                        right: -4,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isScheduledForDeletion
                                ? Colors.orange
                                : isInactive
                                ? Colors.grey
                                : roleColor,
                            border: Border.all(
                              color: const Color(0xFF0F1820),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isScheduledForDeletion
                                            ? Colors.orange
                                            : isInactive
                                            ? Colors.grey
                                            : roleColor)
                                        .withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              roleIcon,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),

                    // Selection check badge
                    if (isSelected && _selectionMode)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: roleColor,
                            border: Border.all(
                              color: const Color(0xFF0F1820),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),

                    // Loading indicator
                    if (isLoading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  roleColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Profile Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              color: isInactive ? Colors.grey : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Status Badge (informational only)
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isScheduledForDeletion
                                  ? Colors.orange.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isScheduledForDeletion
                                    ? Colors.orange.withValues(alpha: 0.3)
                                    : Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              isScheduledForDeletion
                                  ? '⚠️ Deleting'
                                  : '⏸ Inactive',
                              style: TextStyle(
                                color: isScheduledForDeletion
                                    ? Colors.orange
                                    : Colors.grey,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (isScheduledForDeletion
                                        ? Colors.orange
                                        : isInactive
                                        ? Colors.grey
                                        : roleColor)
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            roleDisplayName,
                            style: TextStyle(
                              color: isScheduledForDeletion
                                  ? Colors.orange
                                  : isInactive
                                  ? Colors.grey
                                  : roleColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (lastLogin != null && !isLoading)
                          Text(
                            _formatLastLogin(lastLogin),
                            style: TextStyle(
                              color: isInactive
                                  ? Colors.grey.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        if (isScheduledForDeletion && daysRemaining != null)
                          Text(
                            '${daysRemaining}d left',
                            style: TextStyle(
                              color: Colors.orange.withValues(alpha: 0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow indicator
              if (!isLoading && !_selectionMode)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        (isScheduledForDeletion
                                ? Colors.orange
                                : isInactive
                                ? Colors.grey
                                : roleColor)
                            .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color:
                        (isScheduledForDeletion
                                ? Colors.orange
                                : isInactive
                                ? Colors.grey
                                : roleColor)
                            .withValues(alpha: 0.7),
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeProfileImage(
    Map<String, dynamic> profile,
    String? provider,
    String? photoUrl,
    bool hasPhoto,
  ) {
    final isGoogle = provider == 'google';
    if (isGoogle && _isGoogleImageRateLimited && hasPhoto) {
      return _getFallbackAvatar(profile, provider);
    }
    if (hasPhoto) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: Image.network(
            photoUrl!,
            width: 70,
            height: 70,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getProviderColor(provider).withValues(alpha: 0.2),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _getProviderColor(provider),
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Image error: $error');
              if (photoUrl.contains('googleusercontent.com')) {
                _handleGoogleImageError();
              }
              return _getFallbackAvatar(profile, provider);
            },
          ),
        );
      } catch (e) {
        debugPrint('Error loading image: $e');
        return _getFallbackAvatar(profile, provider);
      }
    } else {
      return _getFallbackAvatar(profile, provider);
    }
  }

  Widget _getFallbackAvatar(Map<String, dynamic> profile, String? provider) {
    final email = profile['email'] as String? ?? 'Unknown';
    final displayName =
        profile['display_name'] as String? ?? email.split('@').first;
    final isOAuth = provider != 'email';

    if (isOAuth) {
      return Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _getProviderColor(provider),
        ),
        child: Center(
          child: provider == 'google'
              ? const Text(
                  'G',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : provider == 'facebook'
              ? const Text(
                  'f',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : provider == 'apple'
              ? const Icon(Icons.apple, color: Colors.white, size: 28)
              : const Icon(Icons.email, color: Colors.white, size: 24),
        ),
      );
    }

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blueAccent.withValues(alpha: 0.2),
      ),
      child: Center(
        child: Text(
          displayName[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🔥 SELECTION METHODS
  // ============================================================
  void _toggleProfileSelection(Map<String, dynamic> profile, String uniqueId) {
    setState(() {
      if (_selectedProfiles.contains(uniqueId)) {
        _selectedProfiles.remove(uniqueId);
      } else {
        _selectedProfiles.add(uniqueId);
      }
      _selectedCount = _selectedProfiles.length;
      if (_selectedCount == 0) _selectionMode = false;
    });
  }

  void _selectAllProfiles() {
    setState(() {
      _selectedProfiles.clear();
      for (int i = 0; i < profiles.length; i++) {
        final email = profiles[i]['email'] as String? ?? '';
        final role = profiles[i]['roles']?.isNotEmpty == true
            ? profiles[i]['roles'].first
            : 'customer';
        if (email.isNotEmpty) {
          _selectedProfiles.add('$email-$i-$role');
        }
      }
      _selectedCount = _selectedProfiles.length;
    });
  }

  void _deselectAllProfiles() {
    setState(() {
      _selectedProfiles.clear();
      _selectedCount = 0;
      _selectionMode = false;
    });
  }

  Future<void> _removeSelectedProfiles() async {
    if (_selectedProfiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Remove Selected Profiles?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove $_selectedCount profile${_selectedCount == 1 ? '' : 's'} from this device?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will not delete your accounts, only remove them from this device.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final Set<String> emailsToRemove = {};
      for (final uniqueId in _selectedProfiles) {
        final parts = uniqueId.split('-');
        if (parts.isNotEmpty) emailsToRemove.add(parts[0]);
      }

      for (final email in emailsToRemove) {
        await SessionManager.removeProfile(email);
      }

      await _loadProfiles();
      _deselectAllProfiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${emailsToRemove.length} profile${emailsToRemove.length == 1 ? '' : 's'} removed',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _startSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedProfiles.clear();
      _selectedCount = 0;
    });
  }

  // ============================================================
  // 🔥 UI BUILD METHODS
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    final double maxWidth = isWeb ? 450 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              height: screenSize.height,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  // Logo
                  Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 25),
                        child: Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white24,
                                width: 2,
                              ),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1877F2), Color(0xFF0A58CA)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1877F2,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Image.asset(
                                'logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(
                                      Icons.account_circle,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (profiles.isNotEmpty && !_selectionMode)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            child: PopupMenuButton<String>(
                              color: const Color(0xFF1C1F26),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Manage Profiles',
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'select',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Remove Selected',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.manage_accounts,
                                        color: Colors.blueAccent,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Manage Account Data',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'select') {
                                  _startSelectionMode();
                                } else if (value == 'remove') {
                                  context.go('/clear-data');
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Profiles list
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          if (_selectionMode)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                                border: const Border(
                                  bottom: BorderSide(color: Colors.white10),
                                ),
                              ),
                              child: _buildSelectionModeHeader(),
                            ),
                          Expanded(
                            child: _loading && _selectedEmail != null
                                ? _buildLoadingState()
                                : profiles.isEmpty
                                ? _buildEmptyState()
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: profiles.length,
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: _buildProfileCard(
                                          profiles[index],
                                          index,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!_selectionMode) _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
          ),
          const SizedBox(height: 15),
          const Text(
            'Logging in...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (_selectedEmail != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _selectedEmail!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_add_disabled,
            size: 60,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 15),
          const Text(
            'No Saved Profiles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enable "Remember Me" during login\nto save your profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionModeHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: _deselectAllProfiles,
          tooltip: 'Cancel Selection',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$_selectedCount selected',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Tap to select/deselect',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                _selectedCount == profiles.length
                    ? Icons.deselect
                    : Icons.select_all,
                color: Colors.blueAccent,
                size: 24,
              ),
              onPressed: _selectedCount == profiles.length
                  ? _deselectAllProfiles
                  : _selectAllProfiles,
              tooltip: _selectedCount == profiles.length
                  ? 'Deselect All'
                  : 'Select All',
            ),
            if (_selectedCount > 0)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 24,
                ),
                onPressed: _removeSelectedProfiles,
                tooltip: 'Remove Selected',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Add Another Account',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/signup'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF1877F2)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Create New Account',
                style: TextStyle(
                  color: Color(0xFF1877F2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.go('/privacy'),
                child: const Text(
                  'Privacy',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Container(width: 1, height: 12, color: Colors.white30),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/terms'),
                child: const Text(
                  'Terms',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Container(width: 1, height: 12, color: Colors.white30),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/help'),
                child: const Text(
                  'Help',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🔥 PASSWORD DIALOG
// ============================================================
class SecurityCompliantPasswordDialog extends StatefulWidget {
  final String email;
  const SecurityCompliantPasswordDialog({super.key, required this.email});
  @override
  State<SecurityCompliantPasswordDialog> createState() =>
      _SecurityCompliantPasswordDialogState();
}

class _SecurityCompliantPasswordDialogState
    extends State<SecurityCompliantPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscurePassword = true;
  bool _isValid = false;
  bool _isSubmitting = false;
  Timer? _typingTimer;
  int _typedCharacters = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final newLength = _controller.text.length;
    if (newLength > _typedCharacters) _typedCharacters = newLength;
    setState(() => _isValid = newLength >= 6);
    _handleAutoSubmit();
  }

  void _handleAutoSubmit() {
    _typingTimer?.cancel();
    if (_controller.text.length >= 6 && !_isSubmitting && mounted) {
      _typingTimer = Timer(const Duration(milliseconds: 2000), () {
        if (!_isSubmitting && mounted) _submitPassword();
      });
    }
  }

  Future<void> _submitPassword() async {
    if (_isSubmitting || !_isValid) return;
    setState(() => _isSubmitting = true);
    _typingTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final enteredPassword = _controller.text.trim();
    Navigator.pop(context, enteredPassword);
  }

  void _clearPassword() {
    _controller.clear();
    _typedCharacters = 0;
    setState(() => _isValid = false);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    double dialogWidth = isWeb
        ? screenSize.width * 0.25
        : screenSize.width * 0.85;
    final double calculatedWidth = dialogWidth.clamp(300.0, 400.0).toDouble();

    return Dialog(
      backgroundColor: const Color(0xFF1C1F26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWeb ? (screenSize.width - calculatedWidth) / 2 : 20,
        vertical: isWeb ? 100 : 20,
      ),
      child: Container(
        width: calculatedWidth,
        padding: EdgeInsets.all(isWeb ? 24 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.email,
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_controller.text.isNotEmpty && !_isSubmitting)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    color: Colors.white70,
                    onPressed: _clearPassword,
                    tooltip: 'Clear',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    TextField(
                      controller: _controller,
                      obscureText: _obscurePassword,
                      autofocus: true,
                      enabled: !_isSubmitting,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'Type at least 6 characters',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_controller.text.isNotEmpty)
                              IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: _isSubmitting
                                    ? null
                                    : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                              ),
                            if (_isValid && !_isSubmitting)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.greenAccent,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.black,
                                  size: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (value) => _submitPassword(),
                    ),
                    if (_isSubmitting)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueAccent,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_controller.text.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _controller.text.length / 6,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _controller.text.length >= 6
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_controller.text.length}/6',
                          style: TextStyle(
                            color: _controller.text.length >= 6
                                ? Colors.greenAccent
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (_isValid && !_isSubmitting)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.flash_auto,
                      color: Colors.greenAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Auto-login enabled',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isValid && !_isSubmitting
                      ? _submitPassword
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.blueAccent.withValues(
                      alpha: 0.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}