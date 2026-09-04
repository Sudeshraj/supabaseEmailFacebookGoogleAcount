import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/environment_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/google_sign_in_service.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_svg/svg.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

final supabase = Supabase.instance.client;
final GoogleSignInService _googleSignInService = GoogleSignInService();

enum _OAuthAttemptResult { success, cancelled, failed }

class ContinueScreen extends StatefulWidget {
  const ContinueScreen({super.key});

  @override
  State<ContinueScreen> createState() => _ContinueScreenState();
}

class _ContinueScreenState extends State<ContinueScreen> {
  final EnvironmentManager _env = EnvironmentManager();
  final FacebookAuth _facebookAuth = FacebookAuth.instance;
  List<Map<String, dynamic>> profiles = [];
  bool _loading = true;
  String? _selectedEmail;
  final Map<String, bool> _profileLoadingStates = {};
  bool _isGoogleImageRateLimited = false;
  DateTime? _lastGoogleImageError;
  bool _selectionMode = false;
  final Set<String> _selectedProfiles = {};
  int _selectedCount = 0;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    _profileLoadingStates.clear();
    _loadProfiles();
    _checkCompliance();
    _googleSignInService.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

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

  Future<bool> _hasActiveRoles(String email, List<String> roles) async {
    try {
      if (roles.isEmpty) return false;

      final availableProfiles = await SessionManager.getAvailableProfiles();
      debugPrint('📊 Available profiles from SessionManager: $availableProfiles');

      for (String role in roles) {
        final exists = availableProfiles.any(
          (p) => p['email'] == email && p['role'] == role,
        );
        if (exists) {
          debugPrint('✅ Role $role found in available profiles');
          return true;
        }
      }

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
      return true;
    }
  }

  Future<Map<String, dynamic>?> _getProfileStatus(
    String email,
    String role,
  ) async {
    try {
      final availableProfiles = await SessionManager.getAvailableProfiles();

      Map<String, dynamic>? cachedProfile = availableProfiles.firstWhere(
        (p) => p['email'] == email && p['role'] == role,
        orElse: () => {},
      );

      if (cachedProfile.isNotEmpty) {
        final status = cachedProfile['status'] as String? ?? 'active';

        if (status != 'active') {
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
              debugPrint('🔄 Valid session found, checking DB for latest status...');
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

        return {
          'status': status,
          'days_remaining': cachedProfile['days_remaining'],
          'deletion_due_date': cachedProfile['deletion_due_date'],
          'source': 'cache',
        };
      }

      final allProfiles = await SessionManager.getProfiles();
      for (var profile in allProfiles) {
        if (profile['email'] == email) {
          final extraData = profile['extra_data'] as Map<String, dynamic>? ?? {};
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
      return {'status': 'active', 'source': 'fallback'};
    } catch (e) {
      debugPrint('⚠️ Error getting profile status: $e');
      return {'status': 'active', 'source': 'error_fallback'};
    }
  }

  Future<void> _loadProfiles() async {
    try {
      setState(() => _loading = true);

      await SessionManager.forceSyncAvailableProfiles();

      final bool hasValidSession = _hasValidSession();

      final allProfiles = await SessionManager.getProfiles();
      final availableProfiles = await SessionManager.getAvailableProfiles();

      final Map<String, String> photoMap = {};
      for (var profile in availableProfiles) {
        final email = profile['email'] as String?;
        final role = profile['role'] as String?;
        final photo = profile['photo'] as String?;
        if (email != null &&
            role != null &&
            photo != null &&
            photo.isNotEmpty) {
          final key = '$email-$role';
          photoMap[key] = photo;
          debugPrint('📸 Photo map: $key -> $photo');
        }
        if (email != null && photo != null && photo.isNotEmpty) {
          photoMap[email] = photo;
        }
      }

      final Map<String, String> savedPhotoMap = {};
      for (var profile in allProfiles) {
        final email = profile['email'] as String?;
        final photo = profile['photo'] as String?;
        if (email != null && photo != null && photo.isNotEmpty) {
          savedPhotoMap[email] = photo;
          debugPrint('📸 Saved photo map: $email -> $photo');
        }
      }

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

        if (roles.isEmpty) {
          debugPrint('  → Skipping profile with no roles: $email');
          continue;
        }

        bool hasActiveRoles = true;
        if (hasValidSession) {
          try {
            hasActiveRoles = await _hasActiveRoles(email, roles);
          } catch (e) {
            debugPrint('⚠️ _hasActiveRoles error for $email: $e');
            hasActiveRoles = true;
          }
        } else {
          debugPrint('⏭️ Skipping _hasActiveRoles (no valid session) for $email');
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

          String? syncedPhoto = photoMap[email];
          if (syncedPhoto == null || syncedPhoto.isEmpty) {
            syncedPhoto = savedPhotoMap[email];
          }
          if (syncedPhoto == null || syncedPhoto.isEmpty) {
            syncedPhoto = newProfile['photo'] as String?;
          }

          if (syncedPhoto != null && syncedPhoto.isNotEmpty) {
            newProfile['photo'] = syncedPhoto;
            debugPrint('📸 Using photo: $syncedPhoto for $email');
          }

          Map<String, dynamic>? statusInfo;
          if (hasValidSession) {
            try {
              statusInfo = await _getProfileStatus(email, roles.first);
            } catch (e) {
              debugPrint('⚠️ _getProfileStatus error for $email: $e');
              statusInfo = {'status': 'active'};
            }
          } else {
            debugPrint('⏭️ Skipping _getProfileStatus (no valid session) for $email');
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
            '  → Added profile with single role: ${roles.first}, name: $displayName, status: ${newProfile['status']}, photo: ${newProfile['photo']}',
          );
        } else {
          debugPrint('  → Splitting into ${roles.length} profiles');

          for (var role in roles) {
            final roleProfile = Map<String, dynamic>.from(profile);
            roleProfile['roles'] = [role];
            roleProfile['lastLogin'] = profileLastLogin;
            roleProfile['display_name'] = displayName;

            String? syncedPhoto = photoMap[email];
            if (syncedPhoto == null || syncedPhoto.isEmpty) {
              syncedPhoto = savedPhotoMap[email];
            }
            if (syncedPhoto == null || syncedPhoto.isEmpty) {
              syncedPhoto = roleProfile['photo'] as String?;
            }

            if (syncedPhoto != null && syncedPhoto.isNotEmpty) {
              roleProfile['photo'] = syncedPhoto;
              debugPrint('📸 Using photo: $syncedPhoto for $email - $role');
            }

            Map<String, dynamic>? statusInfo;
            if (hasValidSession) {
              try {
                statusInfo = await _getProfileStatus(email, role);
              } catch (e) {
                debugPrint('⚠️ _getProfileStatus error for $email - $role: $e');
                statusInfo = {'status': 'active'};
              }
            } else {
              statusInfo = {'status': 'active'};
            }

            if (statusInfo != null) {
              roleProfile['status'] = statusInfo['status'] ?? 'active';
              roleProfile['days_remaining'] = statusInfo['days_remaining'];
              roleProfile['deletion_due_date'] = statusInfo['deletion_due_date'];
            } else {
              roleProfile['status'] = 'active';
            }

            expandedProfiles.add(roleProfile);
          }
        }
      }

      expandedProfiles.sort((a, b) {
        final aProvider = a['provider'] as String? ?? 'email';
        final bProvider = b['provider'] as String? ?? 'email';
        if (aProvider != 'email' && bProvider == 'email') return -1;
        if (aProvider == 'email' && bProvider != 'email') return 1;
        return 0;
      });

      for (var profile in expandedProfiles) {
        await _optimizeProfileImage(profile);
      }

      if (!mounted) return;
      setState(() {
        profiles = expandedProfiles;
        _loading = false;
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
      final hasSizeParam = photoUrl.contains('=s96') ||
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

  Future<void> _handleProfileLogin(
    Map<String, dynamic> profile,
    String role,
    String uniqueId,
  ) async {
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
      bool userCancelled = false;

      debugPrint('🔄 Attempting auto login for: $email');
      loginSuccess = await SessionManager.tryAutoLogin(email);

      if (loginSuccess) {
        debugPrint('✅ Auto login successful! (NO POPUP)');
        await SessionManager.setCurrentUser(email);
        await SessionManager.saveCurrentRole(role);
      } else {
        debugPrint('❌ Auto-login failed');

        debugPrint('🔄 Trying direct session restore...');
        loginSuccess = await SessionManager.restoreSessionDirectly(email);

        if (loginSuccess) {
          debugPrint('✅ Direct session restore successful! (NO POPUP)');
          await SessionManager.setCurrentUser(email);
          await SessionManager.saveCurrentRole(role);
        } else {
          debugPrint('❌ Direct session restore failed');

          if (provider == 'email') {
            debugPrint('🔐 Email login flow started');
            SessionManager.setLocationContinuesc(true);
            final password = await _showPasswordDialog(email);

            if (password == null) {
              debugPrint('⏭️ User cancelled password dialog');
              userCancelled = true;
            } else {
              final response = await supabase.auth.signInWithPassword(
                email: email,
                password: password,
              );
              loginSuccess = response.user != null;
              debugPrint('📊 Email login success: $loginSuccess');

              if (loginSuccess && response.user != null) {
                await SessionManager.saveUserProfile(
                  email: email,
                  userId: response.user!.id,
                  name: response.user!.userMetadata?['full_name'] ??
                      email.split('@').first,
                  photo: response.user!.userMetadata?['avatar_url'],
                  roles: [role],
                  rememberMe: true,
                  provider: 'email',
                  refreshToken: response.session?.refreshToken,
                  accessToken: response.session?.accessToken,
                );
              }
            }
          } else {
            debugPrint('🔐 OAuth login flow started for $provider (popup will show)');
            final oauthResult = await _handleOAuthLoginForProfile(profile);
            loginSuccess = oauthResult == _OAuthAttemptResult.success;
            userCancelled = oauthResult == _OAuthAttemptResult.cancelled;
            debugPrint('📊 OAuth login result: $oauthResult');
          }
        }
      }

      if (loginSuccess && mounted) {
        debugPrint('✅ Login successful for role: $role');

        final savedToken = await SessionManager.getRefreshToken(email);
        debugPrint('🔑 Refresh token saved: ${savedToken != null ? "✅ YES" : "❌ NO"}');

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

        appState.clearPendingQuickLogout();
        await appState.refreshState();
        if (!mounted) return;
        context.go('/');
      } else if (userCancelled) {
        debugPrint('⏭️ Login cancelled by user - no error shown');
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

  Future<_OAuthAttemptResult> _handleOAuthLoginForProfile(
    Map<String, dynamic> profile,
  ) async {
    final email = profile['email'] as String?;
    final provider = profile['provider'] as String?;
    if (email == null || provider == null) return _OAuthAttemptResult.failed;
    final roles = profile['roles'] as List? ?? [];
    final role = roles.isNotEmpty ? roles.first.toString() : 'customer';

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) return _OAuthAttemptResult.success;

      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) {
        debugPrint('✅ Auto-login successful from Continue screen!');
        return _OAuthAttemptResult.success;
      }

      final restored = await SessionManager.restoreSessionDirectly(email);
      if (restored) {
        debugPrint('✅ Direct session restore successful from Continue screen!');
        return _OAuthAttemptResult.success;
      }

      await SessionManager.setPendingRoleSelection(email: email, role: role);

      switch (provider) {
        case 'google':
          if (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS) {
            debugPrint('🔐 Continue screen - using native Google Sign-In (MOBILE)');

            final authData = await _googleSignInService.authenticateAndGetDetails();

            if (authData != null && authData['idToken'] != null) {
              try {
                final response = await supabase.auth.signInWithIdToken(
                  provider: OAuthProvider.google,
                  idToken: authData['idToken']!,
                  accessToken: authData['accessToken'],
                );

                if (response.user != null) {
                  debugPrint('✅ Native Google sign-in successful (Continue screen)');

                  await SessionManager.saveUserProfile(
                    email: email,
                    userId: response.user!.id,
                    name: response.user!.userMetadata?['full_name'] ??
                        authData['displayName'] ??
                        email.split('@').first,
                    photo: response.user!.userMetadata?['avatar_url'] ??
                        authData['photoUrl'],
                    roles: [role],
                    rememberMe: true,
                    provider: 'google',
                    refreshToken: response.session?.refreshToken,
                    accessToken: response.session?.accessToken,
                  );

                  await _addToAvailableProfiles(
                    email: email,
                    role: role,
                    userId: response.user!.id,
                    photo: authData['photoUrl'],
                  );

                  await SessionManager.setCurrentUser(email);
                  await SessionManager.saveCurrentRole(role);

                  debugPrint('✅ Continue screen: Profile saved with refresh token');
                  return _OAuthAttemptResult.success;
                }
              } catch (e) {
                debugPrint('❌ Native Google sign-in failed (Continue screen): $e');
                return _OAuthAttemptResult.failed;
              }
            }

            debugPrint('⏭️ Native Google authentication cancelled');
            return _OAuthAttemptResult.cancelled;
          }

          debugPrint('🔐 Continue screen - using browser OAuth (WEB)');
          await supabase.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: _env.getRedirectUrl(),
            scopes: 'email profile',
          );
          SessionManager.setLocationContinuesc(true);
          break;

        case 'facebook':
          if (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS) {
            debugPrint('🔐 Continue screen - using native Facebook Sign-In (MOBILE)');

            try {
              final fbResult = await _facebookAuth.login(
                permissions: ['email', 'public_profile'],
              );

              if (fbResult.status == LoginStatus.success) {
                final accessToken = fbResult.accessToken!;
                final response = await supabase.auth.signInWithIdToken(
                  provider: OAuthProvider.facebook,
                  idToken: accessToken.tokenString,
                );

                if (response.user != null) {
                  debugPrint('✅ Native Facebook sign-in successful (Continue screen)');

                  await SessionManager.saveUserProfile(
                    email: email,
                    userId: response.user!.id,
                    name: response.user!.userMetadata?['full_name'] ??
                        email.split('@').first,
                    photo: response.user!.userMetadata?['avatar_url'],
                    roles: [role],
                    rememberMe: true,
                    provider: 'facebook',
                    refreshToken: response.session?.refreshToken,
                    accessToken: response.session?.accessToken,
                  );

                  await _addToAvailableProfiles(
                    email: email,
                    role: role,
                    userId: response.user!.id,
                    photo: response.user!.userMetadata?['avatar_url'],
                  );

                  await SessionManager.setCurrentUser(email);
                  await SessionManager.saveCurrentRole(role);

                  return _OAuthAttemptResult.success;
                }
              } else if (fbResult.status == LoginStatus.cancelled) {
                debugPrint('⏭️ User cancelled native Facebook login');
                return _OAuthAttemptResult.cancelled;
              }
              debugPrint(
                '⚠️ Native Facebook login failed (status: ${fbResult.status}), falling back to web',
              );
            } catch (e) {
              debugPrint('⚠️ Native Facebook login threw exception: $e');
            }
          }

          debugPrint('🔐 Continue screen - using browser OAuth for Facebook');
          await supabase.auth.signInWithOAuth(
            OAuthProvider.facebook,
            redirectTo: _env.getRedirectUrl(),
            scopes: 'email',
          );
          SessionManager.setLocationContinuesc(true);
          break;

        case 'apple':
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            debugPrint('🔐 Continue screen - using native Apple Sign-In (iOS)');

            try {
              final credential = await SignInWithApple.getAppleIDCredential(
                scopes: [
                  AppleIDAuthorizationScopes.email,
                  AppleIDAuthorizationScopes.fullName,
                ],
              );

              if (credential.identityToken != null) {
                final response = await supabase.auth.signInWithIdToken(
                  provider: OAuthProvider.apple,
                  idToken: credential.identityToken!,
                );

                if (response.user != null) {
                  debugPrint('✅ Native Apple sign-in successful (Continue screen)');

                  if (credential.authorizationCode.isNotEmpty) {
                    try {
                      await supabase.functions.invoke(
                        'save-apple-auth-code',
                        body: {
                          'authorizationCode': credential.authorizationCode,
                        },
                      );
                    } catch (e) {
                      debugPrint('⚠️ Failed to save Apple authorization code: $e');
                    }
                  }

                  await SessionManager.saveUserProfile(
                    email: email,
                    userId: response.user!.id,
                    name: response.user!.userMetadata?['full_name'] ??
                        email.split('@').first,
                    photo: response.user!.userMetadata?['avatar_url'],
                    roles: [role],
                    rememberMe: true,
                    provider: 'apple',
                    refreshToken: response.session?.refreshToken,
                    accessToken: response.session?.accessToken,
                  );

                  await _addToAvailableProfiles(
                    email: email,
                    role: role,
                    userId: response.user!.id,
                    photo: response.user!.userMetadata?['avatar_url'],
                  );

                  await SessionManager.setCurrentUser(email);
                  await SessionManager.saveCurrentRole(role);

                  return _OAuthAttemptResult.success;
                }
              }
            } on SignInWithAppleAuthorizationException catch (e) {
              if (e.code == AuthorizationErrorCode.canceled) {
                debugPrint('⏭️ User cancelled native Apple Sign-In');
                return _OAuthAttemptResult.cancelled;
              }
              debugPrint(
                '⚠️ Native Apple authorization error: ${e.code} - ${e.message}',
              );
            } catch (e) {
              debugPrint('⚠️ Native Apple Sign-In failed: $e');
            }
          }

          debugPrint('🔐 Continue screen - using browser OAuth for Apple');
          await supabase.auth.signInWithOAuth(
            OAuthProvider.apple,
            redirectTo: _env.getRedirectUrl(),
            scopes: 'email name',
          );
          SessionManager.setLocationContinuesc(true);
          break;

        default:
          return _OAuthAttemptResult.failed;
      }

      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final user = supabase.auth.currentUser;
        if (user?.email == email) {
          final session = supabase.auth.currentSession;
          if (session != null) {
            await SessionManager.saveUserProfile(
              email: email,
              userId: user!.id,
              name: user.userMetadata?['full_name'] ?? email.split('@').first,
              photo: user.userMetadata?['avatar_url'],
              roles: [role],
              rememberMe: true,
              provider: provider,
              refreshToken: session.refreshToken,
              accessToken: session.accessToken,
            );
          }
          await SessionManager.setCurrentUser(email);
          await SessionManager.saveCurrentRole(role);
          return _OAuthAttemptResult.success;
        }
      }

      return _OAuthAttemptResult.failed;
    } catch (e) {
      debugPrint('OAuth error: $e');
      return _OAuthAttemptResult.failed;
    }
  }

  Future<void> _addToAvailableProfiles({
    required String email,
    required String role,
    required String userId,
    String? photo,
  }) async {
    final availableProfiles = await SessionManager.getAvailableProfiles();
    final exists = availableProfiles.any(
      (p) => p['email'] == email && p['role'] == role,
    );
    if (!exists) {
      availableProfiles.add({
        'id': userId,
        'email': email,
        'role': role,
        'photo': photo,
        'is_active': true,
        'last_used': DateTime.now().toIso8601String(),
      });
      await SessionManager.saveAvailableProfiles(availableProfiles);
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
  // ✅ HELPER METHODS - AppTheme based
  // ============================================================

  Color _getProviderColor(String? provider) {
    final isDark = context.isDarkMode;
    if (isDark) {
      return Colors.white.withValues(alpha: 0.2);
    }
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
    final isDark = context.isDarkMode;
    final color = isDark
        ? Colors.white
        : _getButtonColor(provider.toLowerCase());

    switch (provider.toLowerCase()) {
      case 'google':
        return SvgPicture.asset(
          'assets/icons/google.svg',
          width: 18,
          height: 18,
        );
      case 'facebook':
        return SvgPicture.asset(
          'assets/icons/facebook.svg',
          width: 18,
          height: 18,
        );
      case 'apple':
        return SvgPicture.asset(
          'assets/icons/apple.svg',
          width: 20,
          height: 20,
        );
      case 'email':
        return Icon(Icons.email_rounded, size: 18, color: color);
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
  // ✅ PROFILE CARD - AppTheme based
  // ============================================================

  Widget _buildProfileCard(Map<String, dynamic> profile, int index) {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final backgroundColor = context.backgroundColor;

    final email = profile['email'] as String? ?? 'Unknown';
    final provider = profile['provider'] as String? ?? 'email';
    final roles = profile['roles'] as List? ?? [];
    final profileRole = roles.isNotEmpty ? roles.first.toString() : 'customer';
    final uniqueId = '$email-$index-$profileRole';
    final isLoading = _profileLoadingStates[uniqueId] == true;
    final isSelected = _selectedProfiles.contains(uniqueId);
    final photoUrl = profile['photo'] as String?;
    final displayName = profile['display_name'] as String? ?? email.split('@').first;

    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final lastLogin = profile['lastLogin'] as String?;
    final roleColor = _getRoleColor(profileRole);
    final roleIcon = _getRoleIcon(profileRole);
    final roleDisplayName = _getRoleDisplayName(profileRole);
    final providerColor = _getProviderColor(provider);

    final status = profile['status'] as String? ?? 'active';
    final isActive = status == 'active';
    final isScheduledForDeletion = status == 'scheduled_for_deletion';
    final isInactive = status == 'inactive';
    final daysRemaining = profile['days_remaining'] as int?;

    final cardBgColor = isDark
        ? (isSelected
            ? roleColor.withValues(alpha: 0.2)
            : backgroundColor.withValues(alpha: 0.05))
        : (isSelected ? roleColor.withValues(alpha: 0.1) : Colors.grey.shade50);

    final borderColor = isSelected
        ? primaryColor.withValues(alpha: 0.3)
        : isScheduledForDeletion
        ? Colors.orange.withValues(alpha: 0.3)
        : isInactive
        ? Colors.grey.withValues(alpha: 0.2)
        : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200);

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
          color: cardBgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: isLoading ? 2 : 1.5),
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
                            color: (isScheduledForDeletion
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

                    // Provider Icon Badge - Using backgroundColor
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
                              color: isDark ? Colors.grey[800]! : backgroundColor,
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

                    // Role Icon Badge - Using backgroundColor
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
                              color: isDark ? Colors.grey[800]! : backgroundColor,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isScheduledForDeletion
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

                    // Selection check badge - Using primaryColor
                    if (isSelected && _selectionMode)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor,
                            border: Border.all(
                              color: isDark ? Colors.grey[800]! : backgroundColor,
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

              // Profile Info - Using textColor
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
                              color: isInactive ? Colors.grey : textColor,
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
                            color: (isScheduledForDeletion
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
                                  : textColor.withValues(alpha: 0.5),
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

              // Arrow indicator - Using primaryColor
              if (!isLoading && !_selectionMode)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: (isScheduledForDeletion
                            ? Colors.orange
                            : isInactive
                            ? Colors.grey
                            : roleColor)
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: (isScheduledForDeletion
                            ? Colors.orange
                            : isInactive
                            ? Colors.grey
                            : primaryColor)
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
    final isDark = context.isDarkMode;
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
                    color: isDark
                        ? Colors.grey[800]!.withValues(alpha: 0.3)
                        : _getProviderColor(provider).withValues(alpha: 0.2),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark
                          ? Colors.white54
                          : _getProviderColor(provider),
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
    final displayName = profile['display_name'] as String? ?? email.split('@').first;
    final isOAuth = provider != 'email';
    final isDark = context.isDarkMode;

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
        color: isDark ? Colors.grey[800] : Colors.blueAccent.withValues(alpha: 0.2),
      ),
      child: Center(
        child: Text(
          displayName[0].toUpperCase(),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.white,
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
        backgroundColor: context.isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFF1C1F26),
        title: Text(
          "Remove Selected Profiles?",
          style: TextStyle(color: context.textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove $_selectedCount profile${_selectedCount == 1 ? '' : 's'} from this device?",
              style: TextStyle(color: context.secondaryTextColor),
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
            child: Text(
              "Cancel",
              style: TextStyle(color: context.secondaryTextColor),
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
  // ✅ UI BUILD - AppTheme based, Edge-to-Edge, API 36
  // 🔧 OVERFLOW FIX: the card's inner Column (logo + list + footer)
  // used to get an UNBOUNDED height (ConstrainedBox only capped
  // maxWidth), so on any screen where the fixed-size logo + footer
  // widgets needed slightly more room than was actually available,
  // Flutter had nowhere to "give" — hence the 2px (or 55/19/27px on
  // other screens) RenderFlex overflow.
  //
  // Fix: (1) LayoutBuilder now gives the card a REAL, finite max
  // height. (2) That whole card is wrapped in SingleChildScrollView
  // as a safety net — if content still doesn't fit (tiny window /
  // large text scale / many profiles), it scrolls instead of
  // overflowing. (3) The profile-list's `Expanded` (which required a
  // bounded ancestor to work) is replaced with a `ConstrainedBox` +
  // internal `ListView.builder(shrinkWrap: true)`, so it caps its own
  // height and scrolls internally instead of fighting its siblings
  // for space.
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final cardColor = context.cardColor;
    final textColor = context.textColor;
    final primaryColor = context.primaryColor;

    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    final double maxWidth = isWeb ? 450 : double.infinity;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // ✅ A real, finite height for the card — this is the
                  // actual fix. Falls back to 85% of screen height if the
                  // parent somehow still hands us an unbounded height.
                  final double maxCardHeight = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : screenSize.height * 0.85;

                  // Reserve rough space for logo (~140) + footer (~230)
                  // so the profile-list section gets a sane cap instead
                  // of trying to consume 100% and overflowing by a few px.
                  final double listMaxHeight =
                      (maxCardHeight - 370).clamp(140.0, 480.0);

                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxCardHeight),
                    child: SingleChildScrollView(
                      // ✅ Safety net: absorbs any remaining overflow
                      // instead of showing the yellow/black stripes.
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey.shade200,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cardColor,
                              isDark
                                  ? const Color.fromARGB(255, 25, 25, 25).withValues(alpha: 0.03)
                                  : const Color.fromARGB(255, 32, 31, 31),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min, // ✅ size to content, not force-fill
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
                                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                                          width: 2,
                                        ),
                                        gradient: LinearGradient(
                                          colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: primaryColor.withValues(alpha: 0.4),
                                            blurRadius: 20,
                                            spreadRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(40),
                                        child: Image.asset(
                                          'assets/images/logo.png',
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
                                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
                                      ),
                                      child: PopupMenuButton<String>(
                                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300,
                                          ),
                                        ),
                                        icon: Icon(
                                          Icons.more_vert,
                                          color: textColor,
                                          size: 20,
                                        ),
                                        tooltip: 'Manage Profiles',
                                        itemBuilder: (context) => [
                                          PopupMenuItem<String>(
                                            value: 'select',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Remove Selected',
                                                  style: TextStyle(
                                                    color: isDark ? Colors.white : Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'remove',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.manage_accounts,
                                                  color: Colors.blueAccent,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Manage Account Data',
                                                  style: TextStyle(
                                                    color: isDark ? Colors.white : Colors.black87,
                                                  ),
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

                            // Profiles list — bounded height, internal scroll.
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: listMaxHeight),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark ? cardColor.withValues(alpha: 0.5) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_selectionMode)
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade100,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            topRight: Radius.circular(16),
                                          ),
                                          border: Border(
                                            bottom: BorderSide(
                                              color: isDark ? Colors.white10 : Colors.grey.shade200,
                                            ),
                                          ),
                                        ),
                                        child: _buildSelectionModeHeader(),
                                      ),
                                    Flexible(
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
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final textColor = context.textColor;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
          ),
          const SizedBox(height: 15),
          Text(
            'Logging in...',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          if (_selectedEmail != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _selectedEmail!,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.6),
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
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final primaryColor = context.primaryColor;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_add_disabled,
            size: 60,
            color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.grey.shade400,
          ),
          const SizedBox(height: 15),
          Text(
            'No Saved Profiles',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enable "Remember Me" during login\nto save your profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.go('/login'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: primaryColor),
              foregroundColor: primaryColor,
            ),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionModeHeader() {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final primaryColor = context.primaryColor;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back, color: textColor, size: 24),
          onPressed: _deselectAllProfiles,
          tooltip: 'Cancel Selection',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$_selectedCount selected',
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Tap to select/deselect',
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                _selectedCount == profiles.length ? Icons.deselect : Icons.select_all,
                color: primaryColor,
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
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
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
                side: BorderSide(color: primaryColor),
                foregroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Create New Account',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.go('/privacy'),
                child: Text(
                  'Privacy',
                  style: TextStyle(color: secondaryTextColor),
                ),
              ),
              Container(
                width: 1,
                height: 12,
                color: isDark ? Colors.white30 : Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/terms'),
                child: Text(
                  'Terms',
                  style: TextStyle(color: secondaryTextColor),
                ),
              ),
              Container(
                width: 1,
                height: 12,
                color: isDark ? Colors.white30 : Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/help'),
                child: Text(
                  'Help',
                  style: TextStyle(color: secondaryTextColor),
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
// 🔥 PASSWORD DIALOG - AppTheme based
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
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;

    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    double dialogWidth = isWeb ? screenSize.width * 0.25 : screenSize.width * 0.85;
    final double calculatedWidth = dialogWidth.clamp(300.0, 400.0).toDouble();

    return Dialog(
      backgroundColor: isDark ? backgroundColor : backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWeb ? (screenSize.width - calculatedWidth) / 2 : 20,
        vertical: isWeb ? 100 : 20,
      ),
      child: Container(
        width: calculatedWidth,
        padding: EdgeInsets.all(isWeb ? 24 : 20),
        decoration: BoxDecoration(
          color: isDark ? backgroundColor : backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
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
                        Text(
                          'Enter Password',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.email,
                          style: TextStyle(
                            color: primaryColor,
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
                      icon: Icon(
                        Icons.clear,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
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
                        style: TextStyle(color: textColor, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey.shade600,
                          ),
                          hintText: 'Type at least 6 characters',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade50,
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
                                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                                    size: 20,
                                  ),
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => setState(
                                          () => _obscurePassword = !_obscurePassword,
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
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
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
                                  : isDark ? Colors.white70 : Colors.grey.shade600,
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
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context, null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      foregroundColor: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isValid && !_isSubmitting ? _submitPassword : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.blueAccent.withValues(alpha: 0.5),
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
      ),
    );
  }
}