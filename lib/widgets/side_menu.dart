import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SideMenu extends StatefulWidget {
  final String userRole;
  final String userName;
  final String? userEmail;
  final String? profileImageUrl;
  final VoidCallback? onMenuItemSelected;

  const SideMenu({
    super.key,
    required this.userRole,
    required this.userName,
    this.userEmail,
    this.profileImageUrl,
    this.onMenuItemSelected,
  });

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  bool _showProfileSwitcher = false;
  List<Map<String, dynamic>> _availableProfiles = [];
  List<String> _allUserRoles = [];
  bool _isLoading = false;
  
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadUserRolesFromDatabase();
      }
    });
  }

  @override
  void didUpdateWidget(SideMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userRole != oldWidget.userRole) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadUserRolesFromDatabase();
        }
      });
    }
  }

  // ============================================================
  // 🔥 LOAD USER ROLES FROM DATABASE (UPDATED - uses user_roles)
  // ============================================================
  Future<void> _loadUserRolesFromDatabase() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('📋 Loading roles for user: ${currentUser.id}');

      // 🔥 NEW: Get user roles from user_roles table
      final userRolesResponse = await supabase
          .from('user_roles')
          .select('''
            role_id,
            roles!inner (
              id,
              name,
              description
            )
          ''')
          .eq('user_id', currentUser.id);

      // Extract role names
      final List<String> roleNames = [];
      for (var roleEntry in userRolesResponse) {
        final role = roleEntry['roles'] as Map?;
        if (role != null && role['name'] != null) {
          roleNames.add(role['name'].toString());
        }
      }
      
      _allUserRoles = roleNames.toSet().toList(); // Remove duplicates
      
      debugPrint('📋 User roles from database: $_allUserRoles');

      // 🔥 Get profile data for each role
      final List<Map<String, dynamic>> profiles = [];

      for (var roleName in _allUserRoles) {
        // Get role ID
        final roleResponse = await supabase
            .from('roles')
            .select('id')
            .eq('name', roleName)
            .single();
        
        final roleId = roleResponse['id'];

        // Get profile for this user (profiles table doesn't have role_id anymore)
        // We just get the main profile
        final profileResponse = await supabase
            .from('profiles')
            .select('''
              id,
              full_name,
              avatar_url,
              email,
              extra_data,
              is_active,
              is_blocked
            ''')
            .eq('id', currentUser.id)
            .maybeSingle();

        if (profileResponse != null) {
          final isCurrent = roleName == widget.userRole;
          
          String displayName = profileResponse['full_name'] ?? widget.userName;
          if (displayName.isEmpty) {
            displayName = profileResponse['extra_data']?['full_name'] ?? 
                         profileResponse['extra_data']?['company_name'] ?? 
                         widget.userName;
          }
          
          profiles.add({
            'id': profileResponse['id'],
            'email': profileResponse['email'] ?? widget.userEmail ?? currentUser.email,
            'role': roleName,
            'role_id': roleId,
            'name': displayName,
            'photo': profileResponse['avatar_url'] ?? widget.profileImageUrl,
            'is_current': isCurrent,
            'is_active': profileResponse['is_active'] ?? true,
            'is_blocked': profileResponse['is_blocked'] ?? false,
            'extra_data': profileResponse['extra_data'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _availableProfiles = profiles;
        });

        // Save to SessionManager
        await SessionManager.saveUserRoles(
          email: widget.userEmail ?? currentUser.email ?? '',
          roles: _allUserRoles,
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading user roles: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🔥 SWITCH PROFILE (UPDATED)
  // ============================================================
  Future<void> _switchProfile(Map<String, dynamic> profile) async {
    if (!mounted) return;
    
    if (profile['is_current'] == true) {
      setState(() => _showProfileSwitcher = false);
      return;
    }

    // Check if profile is active
    if (profile['is_active'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('This profile is inactive'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Check if profile is blocked
    if (profile['is_blocked'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('This profile is blocked'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔄 Switching to profile: ${profile['role']}');
      
      final currentUser = supabase.auth.currentUser;
      final email = widget.userEmail ?? currentUser?.email;
      
      if (email == null) throw Exception('No email found');
      
      // 🔥 Update current role in SessionManager
      await SessionManager.updateUserRole(profile['role']);
      
      // Update user metadata
      if (currentUser != null) {
        final currentMetadata = currentUser.userMetadata ?? {};
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              ...currentMetadata,
              'current_role': profile['role'],
            },
          ),
        );
      }
      
      if (!mounted) return;
      
      // Close drawer
      Navigator.pop(context);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${_getRoleDisplayName(profile['role'])} profile'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // Refresh app state
      await appState.refreshState();
      
      if (!mounted) return;
      
      // Navigate to appropriate dashboard
      _navigateToDashboard(profile['role']);
    } catch (e) {
      debugPrint('❌ Error switching profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🔥 CREATE NEW PROFILE (FIXED NAVIGATION)
  // ============================================================
  Future<void> _createNewProfile() async {
    if (!mounted) return;
    
    setState(() => _showProfileSwitcher = false);
    
    // Get available roles (roles user doesn't have yet)
    final allRoles = ['owner', 'barber', 'customer'];
    final availableRoles = allRoles
        .where((role) => !_allUserRoles.contains(role))
        .toList();

    if (availableRoles.isEmpty) {
      // User already has all roles
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have all profile types'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    final selectedRole = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create New Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What type of profile would you like to create?'),
            const SizedBox(height: 20),
            ...availableRoles.map((role) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildProfileTypeOption(
                icon: _getRoleIcon(role),
                color: _getRoleColor(role),
                title: _getRoleDisplayName(role),
                description: _getRoleDescription(role),
                role: role,
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedRole == null || !mounted) return;

    debugPrint('🔄 Selected role for new profile: $selectedRole');

    // Close drawer
    Navigator.pop(context);
    
    // Small delay
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;

    debugPrint('➡️ Navigating to registration flow for role: $selectedRole');
    
    // Navigate to registration with query parameters
    context.push('/reg?role=$selectedRole&new=true');
  }

  // ============================================================
  // 🔥 HELPER: Get role icon
  // ============================================================
  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'owner': return Icons.work_outline;
      case 'barber': return Icons.content_cut;
      case 'customer': return Icons.person_outline;
      default: return Icons.error_outline;
    }
  }

  // ============================================================
  // 🔥 HELPER: Get role color
  // ============================================================
  Color _getRoleColor(String role) {
    switch (role) {
      case 'owner': return Colors.blue;
      case 'barber': return Colors.orange;
      case 'customer': return Colors.green;
      default: return Colors.grey;
    }
  }

  // ============================================================
  // 🔥 HELPER: Get role description
  // ============================================================
  String _getRoleDescription(String role) {
    switch (role) {
      case 'owner': return 'Manage your salon';
      case 'barber': return 'Work as a barber';
      case 'customer': return 'Book appointments';
      default: return '';
    }
  }

  // ============================================================
  // 🔥 PROFILE TYPE OPTION WIDGET
  // ============================================================
  Widget _buildProfileTypeOption({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required String role,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, role),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 🔥 NAVIGATE TO DASHBOARD
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

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF6B8B),
              ),
            )
          : Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildProfileHeader(),
                  if (_showProfileSwitcher) _buildProfileSwitcher(),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _buildMenuItems(context),
                    ),
                  ),
                  _buildBottomSection(),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // 🔥 PROFILE HEADER (UPDATED)
  // ============================================================
  Widget _buildProfileHeader() {
    // Count available profiles (excluding current)
    final otherProfilesCount = _availableProfiles
        .where((p) => p['is_current'] != true)
        .length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B8B), Color(0xFFFF8A9F)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (mounted) {
                        setState(() {
                          _showProfileSwitcher = !_showProfileSwitcher;
                        });
                      }
                    },
                    child: Stack(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            image: (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty)
                                ? DecorationImage(
                                    image: NetworkImage(widget.profileImageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (widget.profileImageUrl == null || widget.profileImageUrl!.isEmpty)
                              ? CircleAvatar(
                                  backgroundColor: Colors.white,
                                  child: Text(
                                    widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF6B8B),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        if (otherProfilesCount > 0)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Text(
                                '+$otherProfilesCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.userName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (otherProfilesCount > 0)
                              GestureDetector(
                                onTap: () {
                                  if (mounted) {
                                    setState(() {
                                      _showProfileSwitcher = !_showProfileSwitcher;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.swap_horiz,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Switch',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (widget.userEmail != null && widget.userEmail!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.userEmail!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getRoleDisplayName(widget.userRole),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

  // ============================================================
  // 🔥 PROFILE SWITCHER (UPDATED)
  // ============================================================
  Widget _buildProfileSwitcher() {
    // Filter out current profile
    final otherProfiles = _availableProfiles
        .where((p) => p['is_current'] != true)
        .toList();

    if (otherProfiles.isEmpty) {
      return Container(
        color: Colors.grey[50],
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('No other profiles found'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _createNewProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
              ),
              child: const Text('Create New Profile'),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.grey[50],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Switch Profile',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                Text(
                  '${otherProfiles.length} available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          ...otherProfiles.map((profile) => ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundImage: profile['photo'] != null
                  ? NetworkImage(profile['photo'])
                  : null,
              child: profile['photo'] == null
                  ? Text(
                      profile['name'][0].toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    )
                  : null,
            ),
            title: Row(
              children: [
                Text(
                  _getRoleDisplayName(profile['role']),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (profile['is_active'] == false) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Inactive',
                      style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                if (profile['is_blocked'] == true) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Blocked',
                      style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(profile['email'] ?? ''),
            enabled: profile['is_active'] == true && profile['is_blocked'] == false,
            onTap: () => _switchProfile(profile),
          )),
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _createNewProfile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 16,
                      color: const Color(0xFFFF6B8B),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Create New Profile',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFFF6B8B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 BOTTOM SECTION
  // ============================================================
  Widget _buildBottomSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings_outlined, color: Colors.grey, size: 22),
            ),
            title: const Text('Settings', style: TextStyle(fontSize: 15)),
            onTap: () {
              Navigator.pop(context);
              _navigateToSettings(context);
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, color: Colors.red, size: 22),
            ),
            title: const Text(
              'Logout',
              style: TextStyle(fontSize: 15, color: Colors.red),
            ),
            onTap: () => _logout(context),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Version 1.0.0',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 GET ROLE DISPLAY NAME
  // ============================================================
  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'owner': return '👑 Owner';
      case 'barber': return '💇 Barber';
      case 'customer': return '👤 Customer';
      default: return role;
    }
  }

  // ============================================================
  // 🔥 BUILD MENU ITEMS
  // ============================================================
  List<Widget> _buildMenuItems(BuildContext context) {
    final List<Map<String, dynamic>> items = [];

    switch (widget.userRole) {
      case 'owner':
        items.addAll(_getOwnerMenuItems());
        break;
      case 'barber':
        items.addAll(_getBarberMenuItems());
        break;
      case 'customer':
        items.addAll(_getCustomerMenuItems());
        break;
    }

    items.addAll(_getCommonMenuItems());

    return items.map((item) {
      Color itemColor = Colors.grey;
      if (item['color'] != null) {
        itemColor = item['color'] as Color;
      }
      
      return Column(
        children: [
          if (item['divider'] == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                color: Colors.grey.withValues(alpha: 0.2),
                height: 1,
              ),
            ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: itemColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                item['icon'] as IconData? ?? Icons.error,
                color: itemColor,
                size: 22,
              ),
            ),
            title: Text(
              item['title'] as String? ?? 'Unknown',
              style: const TextStyle(fontSize: 15),
            ),
            trailing: item['badge'] != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item['badge'].toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            onTap: () {
              Navigator.pop(context);
              if (widget.onMenuItemSelected != null) {
                widget.onMenuItemSelected!();
              }
              if (item['route'] != null) {
                _navigateToScreen(context, item['route'] as String);
              }
            },
          ),
        ],
      );
    }).toList();
  }

  List<Map<String, dynamic>> _getOwnerMenuItems() {
    return [
      {'icon': Icons.dashboard_outlined, 'title': 'Dashboard', 'route': '/owner', 'color': Colors.blue},
      {'icon': Icons.calendar_month_outlined, 'title': 'Appointments', 'route': '/owner/appointments', 'color': Colors.green, 'badge': 5},
      {'icon': Icons.people_outline, 'title': 'Customers', 'route': '/owner/customers', 'color': Colors.purple},
      {'icon': Icons.content_cut_outlined, 'title': 'Barbers', 'route': '/owner/barbers', 'color': Colors.orange},
      {'icon': Icons.inventory_2_outlined, 'title': 'Services', 'route': '/owner/services', 'color': Colors.teal},
      {'icon': Icons.attach_money_outlined, 'title': 'Revenue', 'route': '/owner/revenue', 'color': Colors.green},
      {'divider': true},
    ];
  }

  List<Map<String, dynamic>> _getBarberMenuItems() {
    return [
      {'icon': Icons.dashboard_outlined, 'title': 'My Dashboard', 'route': '/barber', 'color': Colors.blue},
      {'icon': Icons.calendar_month_outlined, 'title': 'My Schedule', 'route': '/barber/schedule', 'color': Colors.green},
      {'icon': Icons.pending_actions_outlined, 'title': 'Pending Jobs', 'route': '/barber/pending', 'color': Colors.orange, 'badge': 3},
      {'icon': Icons.history_outlined, 'title': 'Completed', 'route': '/barber/completed', 'color': Colors.purple},
      {'icon': Icons.star_outline, 'title': 'My Reviews', 'route': '/barber/reviews', 'color': Colors.amber, 'badge': '4.8'},
      {'divider': true},
    ];
  }

  List<Map<String, dynamic>> _getCustomerMenuItems() {
    return [
      {'icon': Icons.home_outlined, 'title': 'Home', 'route': '/customer', 'color': Colors.blue},
      {'icon': Icons.calendar_month_outlined, 'title': 'My Bookings', 'route': '/customer/bookings', 'color': Colors.green, 'badge': 2},
      {'icon': Icons.history_outlined, 'title': 'History', 'route': '/customer/history', 'color': Colors.orange},
      {'icon': Icons.favorite_outline, 'title': 'Favorite Barbers', 'route': '/customer/favorites', 'color': Colors.red},
      {'icon': Icons.notifications_outlined, 'title': 'Notifications', 'route': '/customer/notifications', 'color': Colors.purple, 'badge': 3},
      {'divider': true},
    ];
  }

  List<Map<String, dynamic>> _getCommonMenuItems() {
    return [
      {'icon': Icons.info_outline, 'title': 'About Us', 'route': '/about', 'color': Colors.blueGrey},
      {'icon': Icons.help_outline, 'title': 'Help & Support', 'route': '/support', 'color': Colors.grey},
      {'icon': Icons.privacy_tip_outlined, 'title': 'Privacy Policy', 'route': '/privacy', 'color': Colors.grey},
      {'icon': Icons.description_outlined, 'title': 'Terms & Conditions', 'route': '/terms', 'color': Colors.grey},
    ];
  }

  void _navigateToScreen(BuildContext context, String route) {
    try {
      context.push(route);
    } catch (e) {
      debugPrint('Navigation error: $e');
    }
  }

  void _navigateToSettings(BuildContext context) {
    try {
      switch (widget.userRole) {
        case 'owner': context.push('/owner/settings'); break;
        case 'barber': context.push('/barber/settings'); break;
        case 'customer': context.push('/customer/settings'); break;
        default: context.push('/settings');
      }
    } catch (e) {
      debugPrint('Settings navigation error: $e');
    }
  }

  Future<void> _logout(BuildContext context) async {
    showLogoutConfirmation(
      context,
      onLogoutConfirmed: () async {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.all(0),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        );

        try {
          // Call your logout function
          await SessionManager.logoutForContinue();

          // Close loading dialog safely
          if (context.mounted) {
            // Check if we can pop before trying
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }

          // Update app state
          await appState.refreshState();

          // Navigate to login/splash screen using post frame callback
          if (context.mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                // Clear all routes and go to login
                context.go('/');
              }
            });
          }
        } catch (e) {
          // Close loading dialog safely
          if (context.mounted) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }

          // Show error message
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Logout failed: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }
}