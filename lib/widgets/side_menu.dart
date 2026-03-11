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
  bool _isLoading = false;
  
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadProfilesFromDatabase();
      }
    });
  }

  @override
  void didUpdateWidget(SideMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userRole != oldWidget.userRole) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadProfilesFromDatabase();
        }
      });
    }
  }

  // ============================================================
  // 🔥 LOAD PROFILES FROM DATABASE
  // ============================================================
  Future<void> _loadProfilesFromDatabase() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('📋 Loading profiles for user: ${currentUser.id}');

      final response = await supabase
          .from('profiles')
          .select('''
            id,
            role_id,
            full_name,
            avatar_url,
            extra_data,
            is_active,
            roles!inner (
              id,
              name,
              description
            )
          ''')
          .eq('id', currentUser.id)
          .eq('is_active', true);

      if (response.isNotEmpty && mounted) {
        setState(() {
          _availableProfiles = response.map((profile) {
            final roleName = profile['roles']?['name'] ?? 'customer';
            final isCurrent = roleName == widget.userRole;
            
            String displayName = profile['full_name'] ?? '';
            if (displayName.isEmpty) {
              displayName = profile['extra_data']?['full_name'] ?? 
                           profile['extra_data']?['company_name'] ?? 
                           widget.userName;
            }
            
            return {
              'id': profile['id'],
              'email': profile['extra_data']?['email'] ?? widget.userEmail ?? currentUser.email,
              'role': roleName,
              'role_id': profile['role_id'],
              'name': displayName,
              'photo': profile['avatar_url'] ?? widget.profileImageUrl,
              'is_current': isCurrent,
              'extra_data': profile['extra_data'],
            };
          }).toList();
        });

        final allRoles = _availableProfiles.map((p) => p['role'] as String).toList();
        await SessionManager.saveUserRoles(
          email: widget.userEmail ?? currentUser.email ?? '',
          roles: allRoles,
        );
      } else {
        await _createDefaultProfile();
      }
    } catch (e) {
      debugPrint('❌ Error loading profiles from database: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // 🔥 CREATE DEFAULT PROFILE
  // ============================================================
  Future<void> _createDefaultProfile() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final roleResponse = await supabase
          .from('roles')
          .select('id')
          .eq('name', widget.userRole)
          .single();

      final roleId = roleResponse['id'];

      final newProfile = {
        'id': currentUser.id,
        'role_id': roleId,
        'full_name': widget.userName,
        'avatar_url': widget.profileImageUrl,
        'extra_data': {
          'email': widget.userEmail ?? currentUser.email,
          'created_at': DateTime.now().toIso8601String(),
        },
        'is_active': true,
      };

      await supabase.from('profiles').insert(newProfile);
      
      await SessionManager.saveUserProfile(
        email: widget.userEmail ?? currentUser.email ?? '',
        userId: currentUser.id,
        name: widget.userName,
        photo: widget.profileImageUrl,
        roles: [widget.userRole],
        rememberMe: true,
        provider: await _getUserProvider(),
      );
      
      await _loadProfilesFromDatabase();
    } catch (e) {
      debugPrint('❌ Error creating default profile: $e');
    }
  }

  // ============================================================
  // 🔥 GET USER PROVIDER
  // ============================================================
  Future<String> _getUserProvider() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return 'email';
    
    final photo = widget.profileImageUrl;
    if (photo != null && photo.isNotEmpty) {
      if (photo.contains('googleusercontent.com')) return 'google';
      if (photo.contains('fbcdn.net') || 
          photo.contains('facebook.com') ||
          photo.contains('platform-lookaside.fbsbx.com')) {
        return 'facebook';
      }
      if (photo.contains('apple.com')) return 'apple';
    }
    
    final provider = currentUser.appMetadata['provider'];
    if (provider != null) return provider.toString();
    
    return 'email';
  }

  // ============================================================
  // 🔥 SWITCH PROFILE
  // ============================================================
  Future<void> _switchProfile(Map<String, dynamic> profile) async {
    if (!mounted) return;
    
    if (profile['is_current'] == true) {
      setState(() => _showProfileSwitcher = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔄 Switching to profile: ${profile['role']}');
      
      final currentUser = supabase.auth.currentUser;
      final email = widget.userEmail ?? currentUser?.email;
      
      if (email == null) throw Exception('No email found');
      
      await SessionManager.updateUserRole(profile['role']);
      
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
      
      Navigator.pop(context);
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${_getRoleDisplayName(profile['role'])} profile'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      
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
  // 🔥 CREATE NEW PROFILE - FIXED NAVIGATION
  // ============================================================
Future<void> _createNewProfile() async {
  if (!mounted) return;
  
  setState(() => _showProfileSwitcher = false);
  
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
          _buildProfileTypeOption(
            icon: Icons.work_outline,
            color: Colors.blue,
            title: 'Owner',
            description: 'Manage your salon',
            role: 'owner',
          ),
          const SizedBox(height: 12),
          _buildProfileTypeOption(
            icon: Icons.content_cut,
            color: Colors.orange,
            title: 'Barber',
            description: 'Work as a barber',
            role: 'barber',
          ),
          const SizedBox(height: 12),
          _buildProfileTypeOption(
            icon: Icons.person_outline,
            color: Colors.green,
            title: 'Customer',
            description: 'Book appointments',
            role: 'customer',
          ),
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
  
  // 🔥 SIMPLE FIX: Use query parameters instead of extra data
  context.push('/reg?role=$selectedRole&new=true');
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
          context.go('/owner/dashboard');
          break;
        case 'barber':
          context.go('/barber/dashboard');
          break;
        case 'customer':
          context.go('/customer/home');
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
  // 🔥 PROFILE HEADER
  // ============================================================
  Widget _buildProfileHeader() {
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
                        if (_showProfileSwitcher)
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
                              child: const Icon(
                                Icons.swap_horiz,
                                color: Colors.white,
                                size: 12,
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
  // 🔥 PROFILE SWITCHER
  // ============================================================
  Widget _buildProfileSwitcher() {
    if (_availableProfiles.isEmpty) {
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
              ],
            ),
          ),
          ..._availableProfiles.map((profile) => ListTile(
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
                  style: TextStyle(
                    fontWeight: profile['is_current'] ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (profile['is_current']) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(profile['email'] ?? ''),
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
      {'icon': Icons.dashboard_outlined, 'title': 'Dashboard', 'route': '/owner/dashboard', 'color': Colors.blue},
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
      {'icon': Icons.dashboard_outlined, 'title': 'My Dashboard', 'route': '/barber/dashboard', 'color': Colors.blue},
      {'icon': Icons.calendar_month_outlined, 'title': 'My Schedule', 'route': '/barber/schedule', 'color': Colors.green},
      {'icon': Icons.pending_actions_outlined, 'title': 'Pending Jobs', 'route': '/barber/pending', 'color': Colors.orange, 'badge': 3},
      {'icon': Icons.history_outlined, 'title': 'Completed', 'route': '/barber/completed', 'color': Colors.purple},
      {'icon': Icons.star_outline, 'title': 'My Reviews', 'route': '/barber/reviews', 'color': Colors.amber, 'badge': '4.8'},
      {'divider': true},
    ];
  }

  List<Map<String, dynamic>> _getCustomerMenuItems() {
    return [
      {'icon': Icons.home_outlined, 'title': 'Home', 'route': '/customer/home', 'color': Colors.blue},
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