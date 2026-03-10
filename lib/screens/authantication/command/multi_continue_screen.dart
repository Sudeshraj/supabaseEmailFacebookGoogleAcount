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
  final bool _loading = false;
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

  Future<void> _loadProfiles() async {
    try {
      final allProfiles = await SessionManager.getProfiles();
      debugPrint('📥 All profiles loaded: ${allProfiles.length}');

      final List<Map<String, dynamic>> expandedProfiles = [];

      for (var profile in allProfiles.where((p) => p['rememberMe'] == true)) {
        final roles = profile['roles'] as List? ?? [];
        final email = profile['email'] as String? ?? 'unknown';

        // 🔥 එක් එක් profile එකට අදාළ last login time එක දැනටමත් profile එකේ තියෙනවා
        // අපිට ආයෙත් _getLastLoginForProfile() call කරන්න ඕනේ නැහැ
        final profileLastLogin = profile['lastLogin'] as String?;

        debugPrint(
          '📋 Processing profile: $email, roles: $roles, original lastLogin: $profileLastLogin',
        );

        if (roles.isEmpty) {
          final newProfile = Map<String, dynamic>.from(profile);
          newProfile['lastLogin'] =
              profileLastLogin; // Ensure lastLogin is copied
          expandedProfiles.add(newProfile);
          debugPrint(
            '  → Added profile with no roles, lastLogin: $profileLastLogin',
          );
        } else if (roles.length == 1) {
          final newProfile = Map<String, dynamic>.from(profile);
          newProfile['lastLogin'] =
              profileLastLogin; // Ensure lastLogin is copied
          expandedProfiles.add(newProfile);
          debugPrint(
            '  → Added profile with single role: ${roles.first}, lastLogin: $profileLastLogin',
          );
        } else {
          debugPrint('  → Splitting into ${roles.length} profiles');

          // 🔥 IMPORTANT FIX: එක් එක් role profile එක සෑදීමේදී,
          // අපි එකම lastLogin value එක copy කරනවා නම් හැම role profile එකටම එකම time එක පෙන්වයි.
          // නමුත් මෙතන තියෙන problem එක තමයි - අපිට එක් එක් role එකට වෙනම lastLogin time එකක් නැහැ.
          // එකම user එකේ විවිධ roles වලට වෙනම lastLogin times තියෙන්නේ නැහැ.
          // ඒක නිසා අපිට කරන්න පුළුවන් හොඳම දේ තමයි එකම user එකේ හැම role එකටම එකම lastLogin time එක පෙන්වීම.
          // එහෙමත් නැත්නම්, අපිට role-specific lastLogin times තියාගන්න වෙනම storage system එකක් හදන්න වෙනවා.

          for (var role in roles) {
            final roleProfile = Map<String, dynamic>.from(profile);
            roleProfile['roles'] = [role.toString()];
            roleProfile['lastLogin'] =
                profileLastLogin; // Copy the same lastLogin for all roles of this user
            expandedProfiles.add(roleProfile);
            debugPrint(
              '    → Created profile for role: $role, lastLogin: $profileLastLogin',
            );
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
        debugPrint('✅ Final profiles count: ${expandedProfiles.length}');
        for (var i = 0; i < expandedProfiles.length; i++) {
          debugPrint(
            '  Profile $i: ${expandedProfiles[i]['email']} - Role: ${expandedProfiles[i]['roles']?.first} - LastLogin: ${expandedProfiles[i]['lastLogin']}',
          );
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading profiles: $e');
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
  // 🔥 HANDLE PROFILE LOGIN - FIXED WITH AUTO-LOGIN
  // ============================================================
  Future<void> _handleProfileLogin(
    Map<String, dynamic> profile,
    String role,
    String uniqueId,
  ) async {
    debugPrint('🔐 _handleProfileLogin - Role: $role, UniqueId: $uniqueId');
    debugPrint('📧 Email: ${profile['email']}');
    debugPrint('🔑 Provider: ${profile['provider']}');

    final email = profile['email'] as String?;
    final provider = profile['provider'] as String?;

    if (email == null) {
      debugPrint('❌ No email found');
      return;
    }

    setState(() {
      _profileLoadingStates[uniqueId] = true;
      _selectedEmail = email;
    });

    try {
      bool loginSuccess = false;

      // 🔥 TRY AUTO-LOGIN FIRST - FIXED
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

        // 🔥 Check current user after login
        final currentUser = supabase.auth.currentUser;
        debugPrint('👤 Current user after login: ${currentUser?.email}');

        // Check if profile completed
        final hasProfile = await SessionManager.hasProfile();
        debugPrint('📋 Has local profile: $hasProfile');

        // Save this role
        await SessionManager.saveCurrentRole(role);
        debugPrint('💾 Saved role: $role');

        final savedRole = await SessionManager.getCurrentRole();
        debugPrint('✅ Verified saved role: $savedRole');

        if (currentUser != null) {
          await supabase.auth.updateUser(
            UserAttributes(
              data: {...currentUser.userMetadata ?? {}, 'current_role': role},
            ),
          );
          debugPrint('📝 Updated user metadata with role: $role');
        }

        // Refresh app state
        await appState.refreshState();
        debugPrint(
          '🔄 AppState refreshed - currentRole: ${appState.currentRole}',
        );

        // Redirect based on role
        String dashboardRoute;
        switch (role) {
          case 'owner':
            dashboardRoute = '/owner';
            break;
          case 'barber':
            dashboardRoute = '/barber';
            break;
          default:
            dashboardRoute = '/customer';
        }

        debugPrint('📍 Redirecting to: $dashboardRoute');
        if (mounted) {
          context.go(dashboardRoute);
        }
      } else {
        debugPrint('❌ Login failed for role: $role');
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
    }
  }

  Future<bool> _handleOAuthLoginForProfile(Map<String, dynamic> profile) async {
    final email = profile['email'] as String?;
    final provider = profile['provider'] as String?;
    if (email == null || provider == null) return false;

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser?.email == email) return true;

      // 🔥 Try auto-login first for OAuth too
      final autoSuccess = await SessionManager.tryAutoLogin(email);
      if (autoSuccess) return true;

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

      await Future.delayed(const Duration(seconds: 2));
      final user = supabase.auth.currentUser;
      return user?.email == email;
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

  // ... (ඉතිරි කොටස් සියල්ලම පෙර පරිදිම තබන්න - _buildProfileCard, _buildFooter, SecurityCompliantPasswordDialog ආදිය)

  Color _getProviderColor(String? provider) {
     return const Color.fromARGB(255, 242, 241, 241);
    // switch (provider?.toLowerCase()) {
    //   case 'google':
    //     return const Color.fromARGB(255, 242, 241, 241);
    //   case 'facebook':
    //     return const Color(0xFF1877F2);
    //   case 'apple':
    //     return Colors.black;
    //   default:
    //     return Colors.blueAccent;
    // }
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

  // ============================================================
  // 🔥 PROFILE CARD - WITH PROVIDER & ROLE ICONS ON PHOTO
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
    final name = profile['name'] as String? ?? email.split('@').first;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final lastLogin = profile['lastLogin'] as String?;

    final roleColor = _getRoleColor(profileRole);
    final roleIcon = _getRoleIcon(profileRole);
    final roleDisplayName = _getRoleDisplayName(profileRole);
    final providerColor = _getProviderColor(provider);

    // 🔥 All users get a provider icon now (email users get email icon)

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleProfileSelection(profile, uniqueId);
        } else if (isLoading) {
          return;
        } else {
          SessionManager.saveCurrentRole(profileRole);
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
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLoading
                ? roleColor
                : isSelected
                ? roleColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
            width: isLoading ? 2 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Profile Image with Provider and Role Icons
              Stack(
                clipBehavior: Clip.none, // Allow icons to extend outside
                children: [
                  // Main Profile Photo
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: roleColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: roleColor.withValues(alpha: 0.2),
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

                  // 🔥 Provider Icon Badge (Top Left) - NOW FOR ALL USERS
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

                  // Role Icon Badge (Bottom Right) - Always show for all users
                  if (!isLoading && !_selectionMode)
                    Positioned(
                      bottom: -4,
                      right: -4,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: roleColor,
                          border: Border.all(
                            color: const Color(0xFF0F1820),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: roleColor.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(roleIcon, color: Colors.white, size: 16),
                        ),
                      ),
                    ),

                  // Selection check badge (only in selection mode)
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

                  // Loading indicator (overlay)
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

              const SizedBox(width: 16),

              // Profile Info - Simple
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name only - NO email label
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // Role and Last Login in one line
                    Row(
                      children: [
                        // Role name
                        Text(
                          roleDisplayName,
                          style: TextStyle(
                            color: roleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Dot separator
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Last login time
                        if (lastLogin != null && !isLoading)
                          Text(
                            _formatLastLogin(lastLogin),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Simple arrow indicator (only when not loading and not selection mode)
              if (!isLoading && !_selectionMode)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: roleColor.withValues(alpha: 0.7),
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderIcon(String provider) {
    switch (provider.toLowerCase()) {
      case 'google':
        return SvgPicture.asset('icons/google.svg', width: 18, height: 18);
      case 'facebook':
        return SvgPicture.asset('icons/facebook.svg', width: 18, height: 18);
      case 'apple':
        // return const Icon(Icons.apple, size: 18);
        return SvgPicture.asset('icons/apple.svg', width: 20, height: 20);
      case 'email':
        return Icon(
          Icons.email_rounded,
          size: 18,
          color: _getButtonColor(provider.toLowerCase()),
        );
      default:
        return const SizedBox();

      // case 'google':
      //   return const Text(
      //     'G',
      //     style: TextStyle(
      //       color: Colors.white,
      //       fontSize: 12,
      //       fontWeight: FontWeight.bold,
      //     ),
      //   );
      // case 'facebook':
      //   return const Text(
      //     'f',
      //     style: TextStyle(
      //       color: Colors.white,
      //       fontSize: 14,
      //       fontWeight: FontWeight.bold,
      //     ),
      //   );
      //  case 'apple':
      //   return const Icon(
      //     Icons.apple,
      //     color: Colors.white,
      //     size: 14,
      //   );
      // case 'email':
      //   return const Text(
      //     'E',  // 🔥 Email users get 'E'
      //     style: TextStyle(
      //       color: Colors.white,
      //       fontSize: 12,
      //       fontWeight: FontWeight.bold,
      //     ),
      //   );
      // default:
      //   return const Text(
      //     '?',
      //     style: TextStyle(
      //       color: Colors.white,
      //       fontSize: 12,
      //       fontWeight: FontWeight.bold,
      //     ),
      //   );
    }
  }

  Color _getButtonColor(provider) {
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
    final name = profile['name'] as String? ?? email.split('@').first;
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
              ? Text(
                  'G',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : provider == 'facebook'
              ? Text(
                  'f',
                  style: const TextStyle(
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
          name[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
    );
  }

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
                                PopupMenuItem<String>(
                                  value: 'select',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Remove Selected',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.manage_accounts,
                                        color: Colors.blueAccent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
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
                                : _buildProfilesList(),
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

  Widget _buildProfilesList() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildProfileCard(profiles[index], index),
        );
      },
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
