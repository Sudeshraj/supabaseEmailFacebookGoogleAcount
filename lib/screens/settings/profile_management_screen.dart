import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileManagementScreen extends StatefulWidget {
  const ProfileManagementScreen({super.key});

  @override
  State<ProfileManagementScreen> createState() =>
      _ProfileManagementScreenState();
}

class _ProfileManagementScreenState extends State<ProfileManagementScreen> {
  List<ProfileData> _profiles = [];
  bool _isLoading = true;
  String? _currentRole;
  String? currentUserId;
  bool _isProfileLevelStatus = false;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  // ============================================================
  // 🔥 LOAD PROFILES FROM DATABASE
  // ============================================================
  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      currentUserId = user.id;
      _currentRole = await SessionManager.getCurrentRole();

      debugPrint('📋 Loading profiles for user: ${user.id}');
      debugPrint('📋 Current role: $_currentRole');

      // ✅ Get user roles with status from user_roles table
      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (
              id,
              name,
              description
            ),
            status,
            created_at,
            updated_at
          ''')
          .eq('user_id', user.id);

      debugPrint('📋 User roles response: $userRolesResponse');

      // ✅ Get profile data
      final profileResponse = await supabase
          .from('profiles')
          .select('''
            id,
            full_name,
            avatar_url,
            email,
            extra_data,
            is_active,
            is_blocked,
            created_at,
            updated_at
          ''')
          .eq('id', user.id)
          .maybeSingle();

      if (profileResponse == null) {
        debugPrint('⚠️ No profile found for user');
        setState(() {
          _profiles = [];
          _isLoading = false;
        });
        return;
      }

      final extraData =
          profileResponse['extra_data'] as Map<String, dynamic>? ?? {};
      debugPrint('📋 Extra data: $extraData');

      // ✅ Check if profile level status exists
      _isProfileLevelStatus = extraData.containsKey('profile_status');

      // ✅ Build profile list from user_roles
      final List<ProfileData> profileList = [];

      // ✅ Check profile level status first
      String profileLevelStatus = 'active';
      DateTime? profileDeletionDueDate;
      int profileGracePeriodDays = 90;

      if (_isProfileLevelStatus) {
        final profileStatus =
            extraData['profile_status'] as Map<String, dynamic>? ?? {};
        profileLevelStatus = profileStatus['status'] as String? ?? 'active';

        if (profileLevelStatus == 'scheduled_for_deletion') {
          final dueDateStr = profileStatus['deletion_due_date'] as String?;
          if (dueDateStr != null) {
            profileDeletionDueDate = DateTime.parse(dueDateStr);
          }
          profileGracePeriodDays =
              profileStatus['grace_period_days'] as int? ?? 90;
        }
      }

      // ✅ Build profile data for each role
      for (var roleEntry in userRolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role == null) continue;

        final roleName = role['name'] as String;
        String roleStatus = roleEntry['status'] as String? ?? 'active';
        final roleKey = 'profile_$roleName';

        // ✅ If profile level status exists, use it instead of role status
        if (_isProfileLevelStatus) {
          roleStatus = profileLevelStatus;
        }

        // ✅ Get display name
        String displayName =
            profileResponse['full_name'] ??
            extraData['full_name'] ??
            user.email?.split('@').first ??
            'User';

        // ✅ Get role-specific data from extra_data
        DateTime? deletionDueDate;
        DateTime? scheduledAt;
        int gracePeriodDays = 90;

        if (extraData.containsKey(roleKey)) {
          final roleData = extraData[roleKey] as Map<String, dynamic>? ?? {};

          if (roleStatus == 'scheduled_for_deletion') {
            final dueDateStr = roleData['deletion_due_date'] as String?;
            if (dueDateStr != null) {
              deletionDueDate = DateTime.parse(dueDateStr);
            }
            final scheduledAtStr = roleData['deletion_scheduled_at'] as String?;
            if (scheduledAtStr != null) {
              scheduledAt = DateTime.parse(scheduledAtStr);
            }
            gracePeriodDays = roleData['grace_period_days'] as int? ?? 90;
          }
        }

        // ✅ Use profile level deletion date if available
        if (_isProfileLevelStatus &&
            profileLevelStatus == 'scheduled_for_deletion') {
          deletionDueDate = profileDeletionDueDate;
          gracePeriodDays = profileGracePeriodDays;
        }

        final isCurrent = roleName == _currentRole;
        final isActive = roleStatus == 'active';
        final isBlocked = profileResponse['is_blocked'] ?? false;

        profileList.add(
          ProfileData(
            role: roleName,
            roleId: roleEntry['role_id'],
            displayName: displayName,
            email: profileResponse['email'] ?? user.email ?? '',
            avatarUrl: profileResponse['avatar_url'],
            status: roleStatus,
            isCurrent: isCurrent,
            isActive: isActive,
            isBlocked: isBlocked,
            deletionDueDate: deletionDueDate,
            scheduledAt: scheduledAt,
            gracePeriodDays: gracePeriodDays,
            extraData: extraData,
            isProfileLevel: _isProfileLevelStatus,
            profileLevelStatus: profileLevelStatus,
          ),
        );
      }

      debugPrint('📋 Loaded ${profileList.length} profiles');

      setState(() {
        _profiles = profileList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading profiles: $e');
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 🔥 UPDATE ROLE STATUS
  // ============================================================
  Future<void> _updateRoleStatus(ProfileData profile, String status) async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📝 Updating role status: ${profile.role} -> $status');

      // ✅ Check if profile level status exists
      if (profile.isProfileLevel) {
        // ✅ Update profile level status
        final success = await SessionManager.updateProfileLevelStatus(
          email: profile.email,
          status: status,
          gracePeriodDays: 90,
        );

        if (!success) {
          throw Exception('Failed to update profile status');
        }
      } else {
        // ✅ Update individual role status
        final success = await SessionManager.updateRoleStatus(
          email: profile.email,
          role: profile.role,
          status: status,
          gracePeriodDays: 90,
        );

        if (!success) {
          throw Exception('Failed to update role status');
        }
      }

      debugPrint('✅ Status updated successfully');

      // ✅ Refresh local profiles
      await _loadProfiles();

      // ✅ Refresh app state
      await appState.refreshState();

      // ✅ Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getStatusMessage(profile.role, status)),
            backgroundColor: status == 'active' ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 🔥 PROFILE LEVEL ACTIONS
  // ============================================================

  /// ✅ Deactivate entire profile
  Future<void> _deactivateCompleteProfile(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deactivate Complete Profile?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to deactivate your entire profile?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All your roles will be deactivated. You can reactivate anytime.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Deactivate All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // ✅ Update profile level status to inactive
      await _updateProfileLevelStatus(profile, 'inactive');
    }
  }

  /// ✅ Reactivate entire profile
  Future<void> _reactivateCompleteProfile(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reactivate Complete Profile?'),
        content: const Text(
          'Your entire profile will be reactivated immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reactivate All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // ✅ Update profile level status to active
      await _updateProfileLevelStatus(profile, 'active');
    }
  }

  /// ✅ Schedule complete profile deletion (3 months grace period)
  Future<void> _scheduleCompleteProfileDeletion(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Complete Profile?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your entire profile?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '📌 What happens next? (Facebook style)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Your entire profile will be deactivated immediately\n'
                    '• All your roles will be deactivated\n'
                    '• You have 90 days to reactivate it\n'
                    '• After 90 days, it will be permanently deleted\n',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.restore, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can restore your profile at any time within 90 days by logging in or clicking "Reactivate".',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Schedule Deletion'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // ✅ Schedule profile level deletion
      await _updateProfileLevelStatus(profile, 'scheduled_for_deletion');
    }
  }

  /// ✅ Update profile level status
  Future<void> _updateProfileLevelStatus(
    ProfileData profile,
    String status,
  ) async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📝 Updating profile level status: $status');

      // ✅ Use SessionManager to update profile level status
      final success = await SessionManager.updateProfileLevelStatus(
        email: profile.email,
        status: status,
        gracePeriodDays: 90,
      );

      if (!success) {
        throw Exception('Failed to update profile status');
      }

      debugPrint('✅ Profile level status updated successfully');

      // ✅ Refresh
      await _loadProfiles();
      await appState.refreshState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getProfileStatusMessage(status)),
            backgroundColor: status == 'active' ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating profile level status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 🔥 COMPLETE PROFILE DELETE (Immediate - Admin only)
  // ============================================================
  // Future<void> _deleteCompleteProfileImmediate(ProfileData profile) async {
  //   // ✅ Show warning dialog
  //   final confirm = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //       title: const Text(
  //         '⚠️ Permanently Delete Profile?',
  //         style: TextStyle(color: Colors.red),
  //       ),
  //       content: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: const [
  //           Text(
  //             'This will permanently delete your entire profile immediately.',
  //             style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  //           ),
  //           SizedBox(height: 12),
  //           Text('• All your roles will be removed'),
  //           Text('• All your data will be deleted'),
  //           Text('• This action cannot be undone'),
  //           SizedBox(height: 12),
  //           Text(
  //             'Are you sure you want to proceed?',
  //             style: TextStyle(fontWeight: FontWeight.bold),
  //           ),
  //         ],
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: const Text('Cancel'),
  //         ),
  //         ElevatedButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.red,
  //             foregroundColor: Colors.white,
  //           ),
  //           child: const Text('Delete Permanently'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirm != true) return;

  //   setState(() => _isLoading = true);

  //   try {
  //     final supabase = Supabase.instance.client;
  //     final user = supabase.auth.currentUser;

  //     if (user == null) throw Exception('User not found');

  //     debugPrint('🗑️ Deleting complete profile immediately: ${profile.email}');

  //     // ✅ Use SessionManager to delete complete profile
  //     final success = await SessionManager.deleteCompleteProfile(
  //       email: profile.email,
  //       userId: user.id,
  //     );

  //     if (!success) {
  //       throw Exception('Failed to delete profile');
  //     }

  //     debugPrint('✅ Complete profile deleted successfully');

  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('✅ Profile deleted permanently'),
  //           backgroundColor: Colors.green,
  //           duration: Duration(seconds: 3),
  //         ),
  //       );
  //     }

  //     // ✅ Check remaining profiles
  //     final remainingProfiles = await SessionManager.getRemainingProfiles(
  //       profile.email,
  //     );

  //     if (remainingProfiles.isEmpty) {
  //       if (mounted) {
  //         await supabase.auth.signOut();
  //         await appState.refreshState();
  //         if (!mounted) return;
  //         context.go('/login');
  //       }
  //     } else {
  //       await _loadProfiles();
  //       await appState.refreshState();
  //     }
  //   } catch (e) {
  //     debugPrint('❌ Error deleting profile: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
  //       );
  //     }
  //   } finally {
  //     if (mounted) setState(() => _isLoading = false);
  //   }
  // }

  // ============================================================
  // 🔥 PROFILE ACTIONS
  // ============================================================

  Future<void> _switchProfile(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Switch to ${_getRoleDisplayName(profile.role)}?'),
        content: Text(
          'You are switching to your ${_getRoleDisplayName(profile.role)} profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await SessionManager.updateUserRole(profile.role);

        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;
        if (user != null) {
          await supabase.auth.updateUser(
            UserAttributes(
              data: {...?user.userMetadata, 'current_role': profile.role},
            ),
          );
        }

        await appState.refreshState();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Switched to ${_getRoleDisplayName(profile.role)} profile',
              ),
              backgroundColor: Colors.green,
            ),
          );
          await _loadProfiles();
          _navigateToDashboard(profile.role);
        }
      } catch (e) {
        debugPrint('❌ Error switching profile: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deactivateProfile(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deactivate Role?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to deactivate your ${_getRoleDisplayName(profile.role)} role?',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can reactivate this role anytime from settings.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateRoleStatus(profile, 'inactive');
    }
  }

  Future<void> _scheduleDeletion(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Role?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your ${_getRoleDisplayName(profile.role)} role?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '📌 What happens next?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Your role will be deactivated immediately\n'
                    '• You have 90 days to reactivate it\n'
                    '• After 90 days, it will be permanently deleted\n'
                    '• Your other roles will not be affected',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.restore, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can restore this role at any time within 90 days by logging in or clicking "Reactivate".',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Schedule Deletion'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateRoleStatus(profile, 'scheduled_for_deletion');
    }
  }

  Future<void> _reactivateProfile(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reactivate ${_getRoleDisplayName(profile.role)}?'),
        content: const Text('Your role will be reactivated immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateRoleStatus(profile, 'active');
    }
  }

  Future<void> _cancelDeletion(ProfileData profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Deletion?'),
        content: const Text(
          'Your role will be reactivated and will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Deletion'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateRoleStatus(profile, 'active');
    }
  }

  // ============================================================
  // 🔥 NAVIGATION
  // ============================================================

  void _navigateToDashboard(String role) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      switch (role) {
        case 'owner':
          context.go('/owner');
          break;
        case 'barber':
          context.go('/barber');
          break;
        case 'customer':
          context.go('/customer');
          break;
        default:
          context.go('/');
      }
    });
  }

  // ============================================================
  // 🔥 HELPER METHODS
  // ============================================================

  String _getStatusMessage(String role, String status) {
    final roleName = _getRoleDisplayName(role);
    switch (status) {
      case 'active':
        return '$roleName role reactivated successfully';
      case 'inactive':
        return '$roleName role deactivated';
      case 'scheduled_for_deletion':
        return '$roleName role will be deleted in 90 days';
      default:
        return 'Role updated';
    }
  }

  String _getProfileStatusMessage(String status) {
    switch (status) {
      case 'active':
        return '✅ Profile reactivated successfully';
      case 'inactive':
        return '⏸️ Profile deactivated';
      case 'scheduled_for_deletion':
        return '🗑️ Profile will be deleted in 90 days';
      default:
        return 'Profile updated';
    }
  }

  String _getDeletionStatusText(DateTime dueDate) {
    final now = DateTime.now();
    final daysRemaining = dueDate.difference(now).inDays;

    if (daysRemaining > 0) {
      return 'Will be permanently deleted in $daysRemaining days';
    } else {
      return 'Pending deletion...';
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.work_outline;
      case 'barber':
        return Icons.content_cut;
      case 'customer':
        return Icons.person_outline;
      default:
        return Icons.error_outline;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.blue;
      case 'barber':
        return Colors.orange;
      case 'customer':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
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

  // ============================================================
  // 🔥 UI BUILDERS
  // ============================================================

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isDestructive = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProfileCard(ProfileData profile) {
    final isCurrent = profile.isCurrent;
    final isActive = profile.isActive;
    final isScheduledForDeletion = profile.status == 'scheduled_for_deletion';
    final isInactive = profile.status == 'inactive';
    final isBlocked = profile.isBlocked;
    final isProfileLevel = profile.isProfileLevel;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isBlocked) {
      statusColor = Colors.red;
      statusText = 'Blocked';
      statusIcon = Icons.block;
    } else if (isActive) {
      statusColor = Colors.green;
      statusText = 'Active';
      statusIcon = Icons.check_circle_outline;
    } else if (isScheduledForDeletion) {
      statusColor = Colors.orange;
      statusText = 'Scheduled for Deletion';
      statusIcon = Icons.schedule;
    } else if (isInactive) {
      statusColor = Colors.grey;
      statusText = 'Inactive';
      statusIcon = Icons.pause_circle_outline;
    } else {
      statusColor = Colors.red;
      statusText = profile.status;
      statusIcon = Icons.error_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCurrent
            ? BorderSide(color: const Color(0xFFFF6B8B), width: 2)
            : BorderSide.none,
      ),
      elevation: isCurrent ? 4 : 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getRoleColor(profile.role).withValues(alpha: 0.1),
                    image:
                        profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(profile.avatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
                      ? Center(
                          child: Text(
                            profile.displayName.isNotEmpty
                                ? profile.displayName[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _getRoleColor(profile.role),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Name and Role
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B8B),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _getRoleIcon(profile.role),
                            size: 14,
                            color: _getRoleColor(profile.role),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getRoleDisplayName(profile.role),
                            style: TextStyle(
                              fontSize: 14,
                              color: _getRoleColor(profile.role),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 12, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: statusColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isProfileLevel)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.purple.withValues(alpha: 0.2),
                                ),
                              ),
                              child: const Text(
                                'Profile Level',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.purple,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.email,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Status Info
            if (isScheduledForDeletion && profile.deletionDueDate != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isProfileLevel
                                ? 'Complete profile scheduled for deletion'
                                : 'Role scheduled for deletion',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[700],
                            ),
                          ),
                          Text(
                            _getDeletionStatusText(profile.deletionDueDate!),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (isInactive) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isProfileLevel
                            ? 'Complete profile is inactive. You can reactivate it anytime.'
                            : 'This role is inactive. You can reactivate it anytime.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Switch to this profile
                if (!isCurrent && isActive && !isBlocked)
                  _buildActionButton(
                    icon: Icons.swap_horiz,
                    label: 'Switch',
                    color: Colors.blue,
                    onPressed: () => _switchProfile(profile),
                  ),

                // Reactivate - for inactive profiles
                if (isInactive && !isBlocked)
                  _buildActionButton(
                    icon: Icons.restore,
                    label: 'Reactivate',
                    color: Colors.green,
                    onPressed: () => _reactivateProfile(profile),
                  ),

                // Reactivate - for scheduled deletion (within grace period)
                if (isScheduledForDeletion &&
                    profile.deletionDueDate != null &&
                    profile.deletionDueDate!.isAfter(DateTime.now()) &&
                    !isBlocked)
                  _buildActionButton(
                    icon: Icons.restore,
                    label: 'Reactivate',
                    color: Colors.green,
                    onPressed: () => _reactivateProfile(profile),
                  ),

                // Deactivate
                if (isActive && !isCurrent && !isBlocked)
                  _buildActionButton(
                    icon: Icons.pause_circle_outline,
                    label: 'Deactivate',
                    color: Colors.orange,
                    onPressed: () => _deactivateProfile(profile),
                  ),

                // Delete (Schedule Deletion)
                if ((isActive || isInactive) && !isCurrent && !isBlocked)
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    label: 'Delete Role',
                    color: Colors.red,
                    isDestructive: true,
                    onPressed: () => _scheduleDeletion(profile),
                  ),

                // Cancel Deletion
                if (isScheduledForDeletion &&
                    profile.deletionDueDate != null &&
                    profile.deletionDueDate!.isAfter(DateTime.now()) &&
                    !isBlocked)
                  _buildActionButton(
                    icon: Icons.cancel_outlined,
                    label: 'Cancel Deletion',
                    color: Colors.grey,
                    onPressed: () => _cancelDeletion(profile),
                  ),

                // ✅ Profile Level Actions (Only show if profile level exists)
                if (isProfileLevel) ...[
                  // Deactivate Complete Profile
                  if (isActive && !isBlocked)
                    _buildActionButton(
                      icon: Icons.pause_circle_filled,
                      label: 'Deactivate All',
                      color: Colors.deepOrange,
                      onPressed: () => _deactivateCompleteProfile(profile),
                    ),

                  // Reactivate Complete Profile
                  if ((isInactive || isScheduledForDeletion) && !isBlocked)
                    _buildActionButton(
                      icon: Icons.restore,
                      label: 'Reactivate All',
                      color: Colors.green,
                      onPressed: () => _reactivateCompleteProfile(profile),
                    ),

                  // Schedule Complete Profile Deletion
                  if ((isActive || isInactive) && !isBlocked)
                    _buildActionButton(
                      icon: Icons.delete_forever,
                      label: 'Delete All',
                      color: Colors.red,
                      isDestructive: true,
                      onPressed: () =>
                          _scheduleCompleteProfileDeletion(profile),
                    ),
                ],

                // ✅ Immediate Delete (Hidden - Admin only)
                // Uncomment if needed for admin
                // if (!isBlocked)
                //   _buildActionButton(
                //     icon: Icons.delete_sweep,
                //     label: 'Delete Permanently',
                //     color: Colors.red.shade900,
                //     isDestructive: true,
                //     onPressed: () => _deleteCompleteProfileImmediate(profile),
                //   ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Management'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProfiles),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : _profiles.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No profiles found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _profiles.length,
              itemBuilder: (context, index) {
                return _buildProfileCard(_profiles[index]);
              },
            ),
    );
  }
}

// ============================================================
// 🔥 PROFILE DATA MODEL
// ============================================================
class ProfileData {
  final String role;
  final int roleId;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final String status;
  final bool isCurrent;
  final bool isActive;
  final bool isBlocked;
  final DateTime? deletionDueDate;
  final DateTime? scheduledAt;
  final int gracePeriodDays;
  final Map<String, dynamic> extraData;
  final bool isProfileLevel;
  final String? profileLevelStatus;

  ProfileData({
    required this.role,
    required this.roleId,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    required this.status,
    required this.isCurrent,
    this.isActive = false,
    this.isBlocked = false,
    this.deletionDueDate,
    this.scheduledAt,
    this.gracePeriodDays = 90,
    this.extraData = const {},
    this.isProfileLevel = false,
    this.profileLevelStatus,
  });
}
